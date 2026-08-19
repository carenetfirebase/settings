"""AES-256-GCM encryption at rest, with zone-bound authenticated data.

Every encrypted file commits to the zone it was written into and its
logical name via GCM's additional authenticated data. Moving a Zone A
ciphertext into ``Ready/`` and decrypting it as sanitized output fails the
tag check rather than silently succeeding — so the zone model (§9) is
enforced by cryptography, not only by the guard's path checks.

Plaintext PHI never touches disk here: decryption returns bytes to the
caller, and the only writer is :meth:`Vault.encrypt_bytes`. The pipeline
holds plaintext in memory for the duration of one document and no longer
(master prompt §1.3).
"""

from __future__ import annotations

import os
import secrets
import tempfile
from pathlib import Path

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from ..errors import EncryptionError
from ..zones import Zone

_MAGIC = b"SEOB1"
_VERSION = 1
_NONCE_BYTES = 12
_HEADER_LEN = len(_MAGIC) + 1 + _NONCE_BYTES


def _aad(zone: Zone, logical_name: str) -> bytes:
    """Build the additional authenticated data binding a blob to its zone."""
    return f"secondaryeob:v{_VERSION}:zone={zone.value}:name={logical_name}".encode("utf-8")


class Vault:
    """Encrypts and decrypts PHI-bearing bytes under the run's DEK."""

    def __init__(self, dek: bytes, *, enabled: bool = True) -> None:
        if enabled and len(dek) != 32:
            raise EncryptionError("vault requires a 256-bit key")
        self._aesgcm = AESGCM(dek) if enabled else None
        self._enabled = enabled

    @property
    def enabled(self) -> bool:
        return self._enabled

    def encrypt_bytes(self, plaintext: bytes, *, zone: Zone, logical_name: str) -> bytes:
        """Encrypt ``plaintext``, binding the result to ``zone``/``logical_name``."""
        if self._aesgcm is None:
            # Development mode only; load_settings refuses this combination
            # unless SECONDARYEOB_DEV_MODE is set on a non-PHI instance.
            return plaintext
        nonce = secrets.token_bytes(_NONCE_BYTES)
        ciphertext = self._aesgcm.encrypt(nonce, plaintext, _aad(zone, logical_name))
        return _MAGIC + bytes([_VERSION]) + nonce + ciphertext

    def decrypt_bytes(self, blob: bytes, *, zone: Zone, logical_name: str) -> bytes:
        """Decrypt ``blob``, requiring it to have been written for this zone/name.

        Raises:
            EncryptionError: wrong zone, wrong name, wrong key, or the
                ciphertext was altered.
        """
        if self._aesgcm is None:
            return blob
        if len(blob) < _HEADER_LEN or not blob.startswith(_MAGIC):
            raise EncryptionError("not a SecondaryEOB encrypted file")
        version = blob[len(_MAGIC)]
        if version != _VERSION:
            raise EncryptionError(f"unsupported vault format version {version}")
        nonce = blob[len(_MAGIC) + 1 : _HEADER_LEN]
        try:
            return self._aesgcm.decrypt(nonce, blob[_HEADER_LEN:], _aad(zone, logical_name))
        except InvalidTag as exc:
            raise EncryptionError(
                f"decryption failed for {logical_name!r} in {zone}: the file was "
                "written for a different zone or name, encrypted under a different "
                "key, or has been modified"
            ) from exc

    def write(self, path: Path, plaintext: bytes, *, zone: Zone) -> None:
        """Atomically write ``plaintext`` encrypted to ``path``.

        The logical name is the file's own name, so a ciphertext renamed on
        disk will not decrypt — renaming is how a file would be smuggled
        between zones without going through the pipeline.
        """
        blob = self.encrypt_bytes(plaintext, zone=zone, logical_name=path.name)
        path.parent.mkdir(parents=True, exist_ok=True)

        # Write to a temp file in the same directory, fsync, then replace.
        # A partial ciphertext left behind by a crash would be indis-
        # tinguishable from tampering at the next read.
        fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-", suffix=".enc")
        tmp = Path(tmp_name)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(blob)
                handle.flush()
                os.fsync(handle.fileno())
            try:
                tmp.chmod(0o600)
            except OSError:  # pragma: no cover - platform dependent
                pass
            os.replace(tmp, path)
        except BaseException:
            tmp.unlink(missing_ok=True)
            raise

    def read(self, path: Path, *, zone: Zone) -> bytes:
        """Read and decrypt ``path``, requiring it to belong to ``zone``."""
        try:
            blob = path.read_bytes()
        except OSError as exc:
            raise EncryptionError(f"could not read encrypted file at {path}") from exc
        return self.decrypt_bytes(blob, zone=zone, logical_name=path.name)
