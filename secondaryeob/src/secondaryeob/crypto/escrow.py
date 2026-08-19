"""Key escrow — surviving the loss of the Windows profile.

DPAPI ties the data encryption key to a Windows user profile. That is the
right binding for day-to-day confidentiality — another account on the same
machine cannot unwrap the DEK — but it creates an availability failure
mode that is easy to overlook: if the profile is lost (machine dies, user
account is deleted, OS is reinstalled), every encrypted record becomes
permanently unreadable. Data nobody can read is data that is gone, and a
practice that cannot produce a patient's records has a problem whether or
not those records were ever disclosed.

Escrow adds a *second, independent* way to recover the DEK, using public
key cryptography so that the machine does not have to store anything
capable of performing the recovery:

* A recovery keypair is generated once. The **public** key stays on the
  machine and seals a copy of the DEK into ``dek.escrow``.
* The **private** key is written out once and must be moved to offline
  storage — a safe, a sealed envelope, an offline password manager. The
  application never keeps it and cannot recover without it.

So a machine compromise yields the sealed blob and no way to open it,
while a lost machine is recoverable from the offline key. This mirrors how
BitLocker recovery keys and LUKS key slots work, and for the same reason.

The sealing is X25519 ECDH → HKDF-SHA256 → AES-256-GCM, with a fresh
ephemeral keypair per seal.

**The escrow is only as good as where the private key ends up.** Left
beside the working root it is not escrow at all — it is a second copy of
the key on the same disk, which turns a confidentiality control into a
liability. :func:`generate_recovery_keypair` therefore returns the private
key rather than filing it anywhere, and the CLI writes it to a path the
operator names and then tells them to move it off the machine.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass
from pathlib import Path

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey,
    X25519PublicKey,
)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from ..errors import EncryptionError

_MAGIC = b"SEOBESC1"
_NONCE_BYTES = 12
_PUBLIC_KEY_BYTES = 32
_HKDF_INFO = b"secondaryeob-dek-escrow-v1"
_AAD = b"secondaryeob-escrow"


@dataclass(frozen=True)
class RecoveryKeypair:
    """A freshly generated escrow keypair.

    ``private_key_bytes`` is returned to the caller and deliberately not
    persisted by this module — see the module docstring.
    """

    public_key_bytes: bytes
    private_key_bytes: bytes


def generate_recovery_keypair() -> RecoveryKeypair:
    """Generate an X25519 recovery keypair."""
    private = X25519PrivateKey.generate()
    return RecoveryKeypair(
        public_key_bytes=private.public_key().public_bytes_raw(),
        private_key_bytes=private.private_bytes_raw(),
    )


def _derive(shared_secret: bytes, ephemeral_public: bytes, recipient_public: bytes) -> bytes:
    """Derive the wrapping key, binding it to both public keys."""
    return HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=_HKDF_INFO + ephemeral_public + recipient_public,
    ).derive(shared_secret)


def seal(recipient_public_key: bytes, plaintext: bytes) -> bytes:
    """Seal ``plaintext`` to the holder of the matching private key."""
    if len(recipient_public_key) != _PUBLIC_KEY_BYTES:
        raise EncryptionError("recovery public key must be 32 bytes")

    try:
        recipient = X25519PublicKey.from_public_bytes(recipient_public_key)
    except Exception as exc:
        raise EncryptionError("recovery public key is malformed") from exc

    ephemeral = X25519PrivateKey.generate()
    ephemeral_public = ephemeral.public_key().public_bytes_raw()
    key = _derive(ephemeral.exchange(recipient), ephemeral_public, recipient_public_key)

    nonce = secrets.token_bytes(_NONCE_BYTES)
    ciphertext = AESGCM(key).encrypt(nonce, plaintext, _AAD)
    return _MAGIC + ephemeral_public + nonce + ciphertext


def unseal(recovery_private_key: bytes, blob: bytes) -> bytes:
    """Recover plaintext from an escrow blob using the offline private key."""
    if len(recovery_private_key) != 32:
        raise EncryptionError("recovery private key must be 32 bytes")

    header = len(_MAGIC) + _PUBLIC_KEY_BYTES + _NONCE_BYTES
    if len(blob) < header or not blob.startswith(_MAGIC):
        raise EncryptionError("not a SecondaryEOB escrow blob")

    ephemeral_public = blob[len(_MAGIC) : len(_MAGIC) + _PUBLIC_KEY_BYTES]
    nonce = blob[len(_MAGIC) + _PUBLIC_KEY_BYTES : header]
    ciphertext = blob[header:]

    try:
        private = X25519PrivateKey.from_private_bytes(recovery_private_key)
    except Exception as exc:
        raise EncryptionError("recovery private key is malformed") from exc

    recipient_public = private.public_key().public_bytes_raw()
    key = _derive(private.exchange(X25519PublicKey.from_public_bytes(ephemeral_public)),
                  ephemeral_public, recipient_public)

    try:
        return AESGCM(key).decrypt(nonce, ciphertext, _AAD)
    except InvalidTag as exc:
        raise EncryptionError(
            "escrow recovery failed: this is not the matching recovery key, or the "
            "escrow blob has been altered"
        ) from exc


def verify_restore(recovery_private_key: bytes, blob: bytes, expected: bytes) -> None:
    """Prove the escrow actually restores ``expected``.

    Plan §4 requires *restore verification tests*, not merely backups. An
    escrow blob nobody has ever opened is an assumption, and the moment it
    matters is the worst time to discover it was written under the wrong
    key. This runs the full recovery path and compares the result.

    Raises:
        EncryptionError: recovery failed or returned different bytes.
    """
    recovered = unseal(recovery_private_key, blob)
    if recovered != expected:
        raise EncryptionError(
            "escrow verification failed: recovery succeeded but returned different "
            "key material than the key in use"
        )


def read_key_file(path: Path, *, expected_length: int = 32) -> bytes:
    """Read a raw key from ``path``, accepting hex or binary.

    Operators move these around by hand, so a file that arrives as hex text
    (copied out of a password manager) is accepted alongside raw bytes.
    """
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise EncryptionError(f"could not read key file at {path}") from exc

    stripped = data.strip()
    if len(stripped) == expected_length * 2:
        try:
            return bytes.fromhex(stripped.decode("ascii"))
        except (ValueError, UnicodeDecodeError):
            pass
    if len(data) == expected_length:
        return data
    if len(stripped) == expected_length:
        return stripped

    raise EncryptionError(
        f"key file at {path} is {len(data)} bytes; expected {expected_length} raw "
        f"bytes or {expected_length * 2} hex characters"
    )
