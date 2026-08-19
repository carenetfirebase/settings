"""Audit immutability and tamper-evidence tests (master prompt §3)."""

from __future__ import annotations

import json

import pytest

from secondaryeob.audit import Action, AuditLog, Outcome
from secondaryeob.errors import AuditIntegrityError, PHIInAuditError


def _append(log: AuditLog, n: int = 3) -> None:
    for i in range(n):
        log.append(
            actor="test-biller",
            role="BILLER",
            job_id="job-1",
            action=Action.INTAKE,
            zone="A",
            target_ref=f"ref{i}",
            outcome=Outcome.SUCCESS,
            detail={"pages": i},
        )


def test_chain_verifies(audit_log: AuditLog):
    _append(audit_log)
    assert len(audit_log.verify_chain()) == 3


def test_entries_are_chained(audit_log: AuditLog):
    _append(audit_log)
    entries = audit_log.verify_chain()
    for previous, current in zip(entries, entries[1:]):
        assert current.prev_hash == previous.entry_hash


def test_modified_entry_is_detected(audit_log: AuditLog):
    _append(audit_log)
    path = audit_log.path

    lines = path.read_text().splitlines()
    record = json.loads(lines[1])
    record["detail"] = {"pages": 999}
    lines[1] = json.dumps(record, sort_keys=True, separators=(",", ":"))
    path.write_text("\n".join(lines) + "\n")

    with pytest.raises(AuditIntegrityError, match="modified"):
        AuditLog.open(path)


def test_deleted_entry_is_detected(audit_log: AuditLog):
    _append(audit_log)
    path = audit_log.path

    lines = path.read_text().splitlines()
    del lines[1]
    path.write_text("\n".join(lines) + "\n")

    with pytest.raises(AuditIntegrityError):
        AuditLog.open(path)


def test_reordered_entries_are_detected(audit_log: AuditLog):
    _append(audit_log)
    path = audit_log.path

    lines = path.read_text().splitlines()
    lines[0], lines[1] = lines[1], lines[0]
    path.write_text("\n".join(lines) + "\n")

    with pytest.raises(AuditIntegrityError):
        AuditLog.open(path)


def test_appended_forged_entry_is_detected(audit_log: AuditLog):
    """An entry appended outside the API must not verify."""
    _append(audit_log)
    path = audit_log.path

    forged = {
        "seq": 3,
        "timestamp": "2026-01-01T00:00:00.000000+00:00",
        "actor": "attacker",
        "role": "ADMIN",
        "job_id": "job-x",
        "action": "EXPORT",
        "zone": "C",
        "target_ref": "ref",
        "outcome": "SUCCESS",
        "detail": {},
        "prev_hash": "0" * 64,
        "entry_hash": "f" * 64,
    }
    with path.open("a") as handle:
        handle.write(json.dumps(forged, sort_keys=True, separators=(",", ":")) + "\n")

    with pytest.raises(AuditIntegrityError):
        AuditLog.open(path)


def test_reopening_continues_the_chain(audit_log: AuditLog):
    _append(audit_log, 2)
    head = audit_log.head_hash

    reopened = AuditLog.open(audit_log.path)
    assert reopened.head_hash == head
    assert reopened.entry_count == 2

    reopened.append(
        actor="a", role="BILLER", job_id="j", action=Action.EXPORT,
        zone="C", target_ref="r", outcome=Outcome.SUCCESS,
    )
    entries = reopened.verify_chain()
    assert len(entries) == 3
    assert entries[2].prev_hash == head


@pytest.mark.parametrize(
    "detail",
    [
        {"patient_name": "Alder Quillfeather"},
        {"dob": "03/14/1982"},
        {"member_id": "ZZQ-100001"},
        {"filename": "bulk-eob.pdf"},
        {"extracted_text": "some text"},
    ],
)
def test_phi_carrying_detail_keys_are_rejected(audit_log: AuditLog, detail):
    with pytest.raises(PHIInAuditError):
        audit_log.append(
            actor="a", role="BILLER", job_id="j", action=Action.PARSE,
            zone="B", target_ref="r", outcome=Outcome.SUCCESS, detail=detail,
        )


def test_ssn_pattern_in_detail_is_rejected(audit_log: AuditLog):
    with pytest.raises(PHIInAuditError):
        audit_log.append(
            actor="a", role="BILLER", job_id="j", action=Action.PARSE,
            zone="B", target_ref="r", outcome=Outcome.SUCCESS,
            detail={"note": "123-45-6789"},
        )


def test_long_detail_value_is_rejected(audit_log: AuditLog):
    with pytest.raises(PHIInAuditError):
        audit_log.append(
            actor="a", role="BILLER", job_id="j", action=Action.PARSE,
            zone="B", target_ref="r", outcome=Outcome.SUCCESS,
            detail={"note": "x" * 200},
        )
