"""Data-encryption-key management and key wrapping.

The system encrypts files with a single AES-256 data encryption key (DEK)
held in memory. The DEK itself is never stored in the clear: it is
*wrapped* by a platform key provider and the wrapped blob is what lands on
disk.

Two providers:

``DPAPIKeyProvider``
    Windows. Wraps via ``CryptProtectData`` in user scope, which ties the
    DEK to the logged-on Windows account. This is the same binding the
    auth layer uses for identity (master prompt §2.1), so a different
    Windows user on the same machine cannot unwrap the DEK even with
    filesystem access to the wrapped blob.

``PassphraseKeyProvider``
    Everything else, including development on non-Windows. Derives a
    wrapping key from a passphrase with scrypt. Present so the pipeline is
    testable off-Windows; it is *not* equivalent to DPAPI in production,
    because the passphrase has to come from somewhere and an operator who
    stores it next to the data has wrapped nothing.

Key-recovery warning (plan §F, security risks): DPAPI ties the DEK to a
Windows user profile. If that profile is lost and no escrow exists, PHI
encrypted under it is unrecoverable — an availability failure, not just a
confidentiality control. Backup/DR must escrow key material, not only
data. That escrow is deferred with the rest of §4 and is a go-live
blocker, not an MVP one.
"""

from __future__ import annotations

import os
import secrets
import sys
from pathlib import Path
from typing import Protocol

from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

from ..errors import ConfigError, EncryptionError

#: AES-256.
DEK_BYTES = 32

_WRAPPED_DEK_FILENAME = "dek.wrapped"
_SCRYPT_SALT_FILENAME = "dek.salt"

# scrypt parameters. n=2**15 keeps interactive unwrap under ~100ms on a
# typical workstation while staying expensive to brute-force offline.
_SCRYPT_N = 2**15
_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_SALT_BYTES = 16


class KeyProvider(Protocol):
    """Wraps and unwraps the data encryption key."""

    name: str

    def wrap(self, dek: bytes) -> bytes:
        """Return ``dek`` encrypted under the platform/user key."""
        ...

    def unwrap(self, wrapped: bytes) -> bytes:
        """Return the DEK recovered from ``wrapped``."""
        ...


class DPAPIKeyProvider:
    """Windows DPAPI key wrapping, scoped to the current Windows user."""

    name = "dpapi"

    def __init__(self) -> None:
        if sys.platform != "win32":
            raise ConfigError("DPAPIKeyProvider requires Windows")

    # DPAPI is reached through ctypes rather than a third-party package to
    # avoid taking a dependency for two calls.
    @staticmethod
    def _crypt(data: bytes, *, protect: bool) -> bytes:  # pragma: no cover - Windows only
        import ctypes
        from ctypes import wintypes

        class DATA_BLOB(ctypes.Structure):
            _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

        def to_blob(payload: bytes) -> DATA_BLOB:
            buffer = ctypes.create_string_buffer(payload, len(payload))
            return DATA_BLOB(len(payload), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char)))

        def from_blob(blob: DATA_BLOB) -> bytes:
            return ctypes.string_at(blob.pbData, blob.cbData)

        crypt32 = ctypes.windll.crypt32
        kernel32 = ctypes.windll.kernel32

        blob_in = to_blob(data)
        blob_out = DATA_BLOB()
        # Flag 0 = user scope. CRYPTPROTECT_LOCAL_MACHINE (4) is
        # deliberately NOT used: machine scope would let any local account
        # unwrap the DEK, defeating the per-user binding.
        func = crypt32.CryptProtectData if protect else crypt32.CryptUnprotectData
        args = (
            (ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out))
            if protect
            else (ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out))
        )
        if not func(*args):
            raise EncryptionError(
                f"DPAPI {'protect' if protect else 'unprotect'} failed "
                f"(win32 error {kernel32.GetLastError()})"
            )
        try:
            return from_blob(blob_out)
        finally:
            kernel32.LocalFree(blob_out.pbData)

    def wrap(self, dek: bytes) -> bytes:  # pragma: no cover - Windows only
        return self._crypt(dek, protect=True)

    def unwrap(self, wrapped: bytes) -> bytes:  # pragma: no cover - Windows only
        return self._crypt(wrapped, protect=False)


class PassphraseKeyProvider:
    """scrypt-derived key wrapping for non-Windows and development use."""

    name = "passphrase"

    def __init__(self, passphrase: str, salt: bytes) -> None:
        if not passphrase:
            raise ConfigError("passphrase key provider requires a non-empty passphrase")
        if len(salt) < _SCRYPT_SALT_BYTES:
            raise ConfigError("scrypt salt too short")
        self._passphrase = passphrase.encode("utf-8")
        self._salt = salt

    def _wrapping_key(self) -> bytes:
        kdf = Scrypt(salt=self._salt, length=DEK_BYTES, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P)
        return kdf.derive(self._passphrase)

    def wrap(self, dek: bytes) -> bytes:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        nonce = secrets.token_bytes(12)
        return nonce + AESGCM(self._wrapping_key()).encrypt(nonce, dek, b"secondaryeob-dek")

    def unwrap(self, wrapped: bytes) -> bytes:
        from cryptography.exceptions import InvalidTag
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        if len(wrapped) < 13:
            raise EncryptionError("wrapped DEK is truncated")
        nonce, ciphertext = wrapped[:12], wrapped[12:]
        try:
            return AESGCM(self._wrapping_key()).decrypt(nonce, ciphertext, b"secondaryeob-dek")
        except InvalidTag as exc:
            raise EncryptionError(
                "could not unwrap the DEK: wrong passphrase, or the wrapped key "
                "has been altered"
            ) from exc


class Keyring:
    """Owns the DEK for a run, and its wrapped form on disk."""

    def __init__(self, provider: KeyProvider, key_dir: Path) -> None:
        self._provider = provider
        self._key_dir = key_dir
        self._dek: bytes | None = None

    @property
    def provider_name(self) -> str:
        return self._provider.name

    @classmethod
    def for_platform(cls, key_dir: Path, *, passphrase_env_var: str) -> Keyring:
        """Select the strongest provider available on this platform."""
        key_dir.mkdir(parents=True, exist_ok=True)

        if sys.platform == "win32":  # pragma: no cover - Windows only
            return cls(DPAPIKeyProvider(), key_dir)

        passphrase = os.environ.get(passphrase_env_var)
        if not passphrase:
            raise ConfigError(
                f"{passphrase_env_var} is not set. Off Windows there is no DPAPI, "
                "so a passphrase is the only way to wrap the data encryption key. "
                "Note this configuration is for development; production deployment "
                "is Windows with DPAPI."
            )
        salt_path = key_dir / _SCRYPT_SALT_FILENAME
        if salt_path.exists():
            salt = salt_path.read_bytes()
        else:
            salt = secrets.token_bytes(_SCRYPT_SALT_BYTES)
            salt_path.write_bytes(salt)
        return cls(PassphraseKeyProvider(passphrase, salt), key_dir)

    def load_or_create(self) -> bytes:
        """Return the DEK, generating and wrapping a fresh one on first run."""
        if self._dek is not None:
            return self._dek

        wrapped_path = self._key_dir / _WRAPPED_DEK_FILENAME
        if wrapped_path.exists():
            self._dek = self._provider.unwrap(wrapped_path.read_bytes())
            if len(self._dek) != DEK_BYTES:
                raise EncryptionError("unwrapped DEK has the wrong length")
        else:
            self._dek = secrets.token_bytes(DEK_BYTES)
            wrapped_path.write_bytes(self._provider.wrap(self._dek))
            # Owner-only. On Windows this is a no-op that DPAPI already
            # covers; on POSIX dev machines it stops other local accounts
            # reading the wrapped blob.
            try:
                wrapped_path.chmod(0o600)
            except OSError:  # pragma: no cover - platform dependent
                pass
        return self._dek
