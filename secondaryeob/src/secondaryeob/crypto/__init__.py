"""Encryption at rest (master prompt §1.1).

``keyring`` manages the data-encryption key and how it is wrapped;
``vault`` performs AES-256-GCM file encryption with zone-bound
authenticated data.
"""

from __future__ import annotations

from .keyring import DPAPIKeyProvider, Keyring, KeyProvider, PassphraseKeyProvider
from .vault import Vault

__all__ = [
    "DPAPIKeyProvider",
    "KeyProvider",
    "Keyring",
    "PassphraseKeyProvider",
    "Vault",
]
