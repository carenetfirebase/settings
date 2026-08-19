"""Encryption-at-rest tests (master prompt §1.1)."""

from __future__ import annotations

import pytest

from secondaryeob.crypto import Keyring, PassphraseKeyProvider, Vault
from secondaryeob.errors import EncryptionError
from secondaryeob.zones import Zone

PLAINTEXT = b"Patient Name: Alder Quillfeather\nMember ID: ZZQ-100001"


def test_roundtrip(vault: Vault):
    blob = vault.encrypt_bytes(PLAINTEXT, zone=Zone.A_RAW_PHI, logical_name="x.pdf")
    assert vault.decrypt_bytes(blob, zone=Zone.A_RAW_PHI, logical_name="x.pdf") == PLAINTEXT


def test_no_plaintext_phi_on_disk(vault: Vault, settings):
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PLAINTEXT, zone=Zone.A_RAW_PHI)

    on_disk = path.read_bytes()
    assert PLAINTEXT not in on_disk
    assert b"Quillfeather" not in on_disk
    assert b"ZZQ-100001" not in on_disk


def test_zone_confusion_is_rejected(vault: Vault, settings):
    """A Zone A ciphertext must not decrypt as Zone C sanitized output."""
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PLAINTEXT, zone=Zone.A_RAW_PHI)

    with pytest.raises(EncryptionError):
        vault.read(path, zone=Zone.C_SANITIZED)


def test_rename_breaks_decryption(vault: Vault, settings):
    """Renaming a ciphertext must not let it decrypt under the new name."""
    original = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(original, PLAINTEXT, zone=Zone.A_RAW_PHI)

    renamed = settings.path_for("Incoming") / "innocuous.pdf"
    original.rename(renamed)

    with pytest.raises(EncryptionError):
        vault.read(renamed, zone=Zone.A_RAW_PHI)


def test_tampered_ciphertext_is_rejected(vault: Vault, settings):
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PLAINTEXT, zone=Zone.A_RAW_PHI)

    blob = bytearray(path.read_bytes())
    blob[-1] ^= 0xFF
    path.write_bytes(bytes(blob))

    with pytest.raises(EncryptionError):
        vault.read(path, zone=Zone.A_RAW_PHI)


def test_wrong_passphrase_cannot_unwrap_dek(settings, monkeypatch):
    key_dir = settings.working_root / "keys2"
    keyring = Keyring.for_platform(key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE")
    keyring.load_or_create()

    monkeypatch.setenv("SECONDARYEOB_PASSPHRASE", "the-wrong-passphrase")
    other = Keyring.for_platform(key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE")
    with pytest.raises(EncryptionError):
        other.load_or_create()


def test_dek_is_256_bit_and_stable(settings):
    key_dir = settings.working_root / "keys3"
    first = Keyring.for_platform(key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE")
    dek = first.load_or_create()
    assert len(dek) == 32

    second = Keyring.for_platform(key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE")
    assert second.load_or_create() == dek


def test_wrapped_dek_is_not_the_dek(settings):
    provider = PassphraseKeyProvider("passphrase", b"0123456789abcdef")
    dek = b"\x01" * 32
    wrapped = provider.wrap(dek)
    assert dek not in wrapped
    assert provider.unwrap(wrapped) == dek
