"""Key escrow and audit anchoring tests.

These cover the two go-live blockers from the plan's §E deferred list:
recovering from a lost key binding, and detecting audit tampering the hash
chain cannot see.
"""

from __future__ import annotations

import pytest

from secondaryeob.audit import Action, AuditLog, Outcome
from secondaryeob.audit.anchor import AnchorStore
from secondaryeob.crypto import Keyring, Vault
from secondaryeob.crypto.escrow import (
    generate_recovery_keypair,
    read_key_file,
    seal,
    unseal,
    verify_restore,
)
from secondaryeob.errors import AuditIntegrityError, EncryptionError
from secondaryeob.zones import Zone

# =====================================================================
# Key escrow
# =====================================================================


def test_seal_unseal_roundtrip():
    keypair = generate_recovery_keypair()
    secret = b"\x42" * 32
    assert unseal(keypair.private_key_bytes, seal(keypair.public_key_bytes, secret)) == secret


def test_sealed_blob_does_not_contain_the_secret():
    keypair = generate_recovery_keypair()
    secret = b"\x42" * 32
    assert secret not in seal(keypair.public_key_bytes, secret)


def test_wrong_recovery_key_cannot_unseal():
    keypair = generate_recovery_keypair()
    other = generate_recovery_keypair()
    blob = seal(keypair.public_key_bytes, b"\x42" * 32)

    with pytest.raises(EncryptionError, match="not the matching recovery key"):
        unseal(other.private_key_bytes, blob)


def test_tampered_escrow_blob_is_rejected():
    keypair = generate_recovery_keypair()
    blob = bytearray(seal(keypair.public_key_bytes, b"\x42" * 32))
    blob[-1] ^= 0xFF

    with pytest.raises(EncryptionError):
        unseal(keypair.private_key_bytes, bytes(blob))


def test_verify_restore_detects_mismatched_material():
    keypair = generate_recovery_keypair()
    blob = seal(keypair.public_key_bytes, b"\x01" * 32)

    with pytest.raises(EncryptionError, match="different key material"):
        verify_restore(keypair.private_key_bytes, blob, b"\x02" * 32)


def test_enroll_escrow_verifies_restore_immediately(settings):
    """Plan §4: backups are not a control until a restore has been proven."""
    keyring = Keyring.for_platform(
        settings.working_root / "keys", passphrase_env_var="SECONDARYEOB_PASSPHRASE"
    )
    dek = keyring.load_or_create()
    private_key = keyring.enroll_escrow()

    assert keyring.has_escrow
    assert unseal(private_key, keyring.escrow_path.read_bytes()) == dek


def test_escrow_cannot_be_silently_replaced(settings):
    keyring = Keyring.for_platform(
        settings.working_root / "keys", passphrase_env_var="SECONDARYEOB_PASSPHRASE"
    )
    keyring.enroll_escrow()

    with pytest.raises(EncryptionError, match="already exists"):
        keyring.enroll_escrow()


def test_recovery_after_losing_the_key_binding(settings, monkeypatch):
    """The disaster case: the profile is gone, the escrow is not.

    Simulated by destroying the wrapped DEK and changing the passphrase,
    which is the non-Windows equivalent of losing the DPAPI binding.
    """
    key_dir = settings.working_root / "keys"
    keyring = Keyring.for_platform(key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE")
    original_dek = keyring.load_or_create()
    private_key = keyring.enroll_escrow()

    # Encrypt something under the original key.
    vault = Vault(original_dek)
    path = settings.path_for("Ready") / "record.pdf"
    vault.write(path, b"sanitized patient record", zone=Zone.C_SANITIZED)

    # Disaster: the key binding is destroyed.
    (key_dir / "dek.wrapped").unlink()
    (key_dir / "dek.salt").unlink()
    monkeypatch.setenv("SECONDARYEOB_PASSPHRASE", "a-completely-different-passphrase")

    # Without escrow this would be unrecoverable; a fresh keyring would
    # mint a new DEK that cannot read the existing ciphertext.
    recovered_keyring = Keyring.for_platform(
        key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE"
    )
    recovered_dek = recovered_keyring.recover_from_escrow(private_key)

    assert recovered_dek == original_dek
    assert Vault(recovered_dek).read(path, zone=Zone.C_SANITIZED) == b"sanitized patient record"


def test_recovery_persists_for_the_next_run(settings, monkeypatch):
    """After recovery the machine works normally, without the recovery key."""
    key_dir = settings.working_root / "keys"
    keyring = Keyring.for_platform(key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE")
    original_dek = keyring.load_or_create()
    private_key = keyring.enroll_escrow()

    (key_dir / "dek.wrapped").unlink()
    Keyring.for_platform(
        key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE"
    ).recover_from_escrow(private_key)

    # A later run, with no recovery key in sight.
    assert (
        Keyring.for_platform(
            key_dir, passphrase_env_var="SECONDARYEOB_PASSPHRASE"
        ).load_or_create()
        == original_dek
    )


def test_recovery_without_escrow_fails_loudly(settings):
    keyring = Keyring.for_platform(
        settings.working_root / "keys", passphrase_env_var="SECONDARYEOB_PASSPHRASE"
    )
    keyring.load_or_create()

    with pytest.raises(EncryptionError, match="no recovery path"):
        keyring.recover_from_escrow(generate_recovery_keypair().private_key_bytes)


def test_key_file_accepts_hex_and_raw(tmp_path):
    key = bytes(range(32))

    raw_path = tmp_path / "raw.key"
    raw_path.write_bytes(key)
    assert read_key_file(raw_path) == key

    hex_path = tmp_path / "hex.key"
    hex_path.write_text(key.hex() + "\n")
    assert read_key_file(hex_path) == key


def test_malformed_key_file_is_rejected(tmp_path):
    path = tmp_path / "bad.key"
    path.write_bytes(b"too short")
    with pytest.raises(EncryptionError, match="expected 32 raw bytes"):
        read_key_file(path)


# =====================================================================
# Audit anchoring
# =====================================================================


def _fill(log: AuditLog, n: int) -> None:
    for i in range(n):
        log.append(
            actor="test", role="BILLER", job_id="j", action=Action.EXPORT,
            zone="C", target_ref=f"r{i}", outcome=Outcome.SUCCESS,
        )


def test_truncation_is_invisible_to_the_chain_alone(audit_log: AuditLog):
    """The gap anchoring exists to close, stated as a test.

    Deleting entries from the end leaves a shorter chain that verifies
    perfectly, because a valid chain says nothing about how long it should
    be. If this ever starts failing, the chain gained a length commitment
    and the anchor rationale should be revisited.
    """
    _fill(audit_log, 10)
    path = audit_log.path

    lines = path.read_text().splitlines()
    path.write_text("\n".join(lines[:-4]) + "\n")

    reopened = AuditLog(path)
    assert len(reopened.verify_chain()) == 6, "chain still verifies after truncation"


def test_anchor_detects_truncation(settings, audit_log: AuditLog):
    _fill(audit_log, 10)
    store = AnchorStore(settings.path_for("Logs") / "anchors.jsonl")
    store.record(audit_log)

    lines = audit_log.path.read_text().splitlines()
    audit_log.path.write_text("\n".join(lines[:-4]) + "\n")

    with pytest.raises(AuditIntegrityError, match="TRUNCATED"):
        store.verify(AuditLog(audit_log.path))


def test_anchor_detects_a_rebuilt_log(settings, audit_log: AuditLog):
    """A wholesale rewrite with recomputed hashes must still be caught."""
    _fill(audit_log, 5)
    store = AnchorStore(settings.path_for("Logs") / "anchors.jsonl")
    store.record(audit_log)

    # Rebuild from scratch: internally consistent, different history.
    audit_log.path.write_text("")
    rebuilt = AuditLog(audit_log.path)
    rebuilt._opened = True
    for i in range(5):
        rebuilt.append(
            actor="attacker", role="ADMIN", job_id="j", action=Action.SYSTEM,
            zone="D", target_ref=f"x{i}", outcome=Outcome.SUCCESS,
        )

    rebuilt.verify_chain()  # the forged chain is internally valid
    with pytest.raises(AuditIntegrityError, match="REWRITTEN"):
        store.verify(AuditLog(audit_log.path))


def test_anchor_accepts_honest_growth(settings, audit_log: AuditLog):
    _fill(audit_log, 5)
    store = AnchorStore(settings.path_for("Logs") / "anchors.jsonl")
    store.record(audit_log)

    _fill(audit_log, 5)
    store.verify(AuditLog(audit_log.path))  # must not raise


def test_anchor_file_is_itself_chained(settings, audit_log: AuditLog):
    store = AnchorStore(settings.path_for("Logs") / "anchors.jsonl")
    for _ in range(3):
        _fill(audit_log, 2)
        store.record(audit_log)

    lines = store.path.read_text().splitlines()
    del lines[1]
    store.path.write_text("\n".join(lines) + "\n")

    with pytest.raises(AuditIntegrityError, match="anchor sequence gap"):
        store.read_all()


def test_modified_anchor_is_detected(settings, audit_log: AuditLog):
    _fill(audit_log, 5)
    store = AnchorStore(settings.path_for("Logs") / "anchors.jsonl")
    store.record(audit_log)

    import json

    record = json.loads(store.path.read_text().splitlines()[0])
    record["entry_count"] = 1
    store.path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")

    with pytest.raises(AuditIntegrityError, match="has been modified"):
        store.read_all()


def test_open_refuses_a_truncated_log(settings, audit_log: AuditLog):
    """Anchor verification is enforced at open, not left to a command."""
    _fill(audit_log, 8)
    AnchorStore(settings.path_for("Logs") / "anchors.jsonl").record(audit_log)

    lines = audit_log.path.read_text().splitlines()
    audit_log.path.write_text("\n".join(lines[:-3]) + "\n")

    with pytest.raises(AuditIntegrityError, match="TRUNCATED"):
        AuditLog.open(audit_log.path)


def test_external_head_hash_catches_a_fully_forged_pair(settings, audit_log: AuditLog):
    """The check that survives an attacker who controls both files.

    They rebuild the log and re-anchor it consistently, so on-disk
    verification passes — but the head hash the operator filed externally
    does not match.
    """
    _fill(audit_log, 6)
    entries = audit_log.verify_chain()
    external_head = entries[-1].entry_hash
    external_count = len(entries)

    anchor_path = settings.path_for("Logs") / "anchors.jsonl"

    # Attacker rebuilds both artifacts consistently.
    audit_log.path.write_text("")
    anchor_path.unlink(missing_ok=True)
    forged = AuditLog(audit_log.path)
    forged._opened = True
    _fill(forged, 6)
    store = AnchorStore(anchor_path)
    store.record(forged)

    store.verify(AuditLog(audit_log.path))  # on-disk story is self-consistent

    with pytest.raises(AuditIntegrityError, match="REWRITTEN"):
        store.verify_head(AuditLog(audit_log.path), external_head, external_count)


def test_external_head_hash_accepts_the_genuine_log(settings, audit_log: AuditLog):
    _fill(audit_log, 4)
    entries = audit_log.verify_chain()
    store = AnchorStore(settings.path_for("Logs") / "anchors.jsonl")
    store.verify_head(AuditLog(audit_log.path), entries[-1].entry_hash, len(entries))
