"""Attach manifest tests.

The manifest is what makes sanitized output usable: filenames are
PHI-free pseudonyms by design, so without it nothing — human or
automation — can tell which chart a document belongs to.
"""

from __future__ import annotations

from decimal import Decimal

import pytest

from conftest import SYNTHETIC_PATIENTS
from secondaryeob.errors import AuthorizationError, SecondaryEOBError
from secondaryeob.manifest import (
    MANIFEST_FILENAME,
    Manifest,
    ManifestEntry,
    summarize_claims,
)
from secondaryeob.pipeline import process_document
from secondaryeob.pipeline.documents import ClaimLine
from secondaryeob.zones import Zone


def _manifest(settings, guard) -> Manifest:
    return Manifest(settings.path_for("Ready") / MANIFEST_FILENAME, guard)


def _run(eob_pdf, settings, vault, guard):
    source = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(source, eob_pdf, zone=Zone.A_RAW_PHI)
    return process_document(source, guard, settings)


# --- populated by the pipeline -----------------------------------------


def test_export_records_every_patient(eob_pdf, settings, vault, biller_guard):
    _run(eob_pdf, settings, vault, biller_guard)
    entries = _manifest(settings, biller_guard).read()
    assert len(entries) == len(SYNTHETIC_PATIENTS)


def test_manifest_identifies_the_right_patient(eob_pdf, settings, vault, biller_guard):
    """The whole point: pseudonym -> the patient whose chart this goes in."""
    _run(eob_pdf, settings, vault, biller_guard)

    by_name = {e.patient_name: e for e in _manifest(settings, biller_guard).read()}
    for patient in SYNTHETIC_PATIENTS:
        assert patient["name"] in by_name, f"{patient['name']} missing from manifest"
        entry = by_name[patient["name"]]
        assert entry.member_id == patient["member_id"]
        assert entry.date_of_birth == patient["dob"]
        assert patient["procedure"] in entry.procedure_codes


def test_manifest_filename_matches_the_exported_file(eob_pdf, settings, vault, biller_guard):
    result = _run(eob_pdf, settings, vault, biller_guard)
    entries = {e.pseudonym: e for e in _manifest(settings, biller_guard).read()}

    for outcome in result.outcomes:
        assert entries[outcome.pseudonym].filename == outcome.exported_path.name
        assert (settings.path_for("Ready") / entries[outcome.pseudonym].filename).exists()


# --- encryption and leakage --------------------------------------------


def test_manifest_is_encrypted_at_rest(eob_pdf, settings, vault, biller_guard):
    _run(eob_pdf, settings, vault, biller_guard)

    raw = (settings.path_for("Ready") / MANIFEST_FILENAME).read_bytes()
    assert raw.startswith(b"SEOB1")
    for patient in SYNTHETIC_PATIENTS:
        assert patient["name"].encode() not in raw
        assert patient["member_id"].encode() not in raw


def test_manifest_does_not_leak_into_the_audit_log(eob_pdf, settings, vault, biller_guard, audit_log):
    _run(eob_pdf, settings, vault, biller_guard)

    blob = audit_log.path.read_text()
    for patient in SYNTHETIC_PATIENTS:
        assert patient["name"] not in blob
        assert patient["member_id"] not in blob


def test_reviewer_can_read_but_not_write(eob_pdf, settings, vault, biller_guard, reviewer_guard):
    """REVIEWER approves documents, so must be able to see whose they are."""
    _run(eob_pdf, settings, vault, biller_guard)

    assert len(_manifest(settings, reviewer_guard).read()) == len(SYNTHETIC_PATIENTS)

    with pytest.raises(AuthorizationError):
        _manifest(settings, reviewer_guard).mark_attached(
            _manifest(settings, biller_guard).read()[0].pseudonym, by="reviewer"
        )


# --- attach tracking ---------------------------------------------------


def test_mark_attached_moves_it_off_the_pending_list(eob_pdf, settings, vault, biller_guard):
    _run(eob_pdf, settings, vault, biller_guard)
    manifest = _manifest(settings, biller_guard)

    target = manifest.pending()[0].pseudonym
    manifest.mark_attached(target, by="tester")

    assert target not in {e.pseudonym for e in manifest.pending()}
    assert len(manifest.pending()) == len(SYNTHETIC_PATIENTS) - 1

    entry = next(e for e in manifest.read() if e.pseudonym == target)
    assert entry.attached
    assert entry.attached_by == "tester"
    assert entry.attached_at


def test_mark_attached_is_recorded_in_the_audit_log(eob_pdf, settings, vault, biller_guard, audit_log):
    _run(eob_pdf, settings, vault, biller_guard)
    manifest = _manifest(settings, biller_guard)
    manifest.mark_attached(manifest.pending()[0].pseudonym, by="tester")

    events = [
        e for e in audit_log.verify_chain() if e.detail.get("event") == "marked_attached"
    ]
    assert len(events) == 1


def test_unknown_pseudonym_is_rejected(eob_pdf, settings, vault, biller_guard):
    _run(eob_pdf, settings, vault, biller_guard)
    with pytest.raises(SecondaryEOBError, match="no manifest entry"):
        _manifest(settings, biller_guard).mark_attached("pt-doesnotexist", by="t")


def test_reprocessing_replaces_rather_than_duplicates(eob_pdf, settings, vault, biller_guard):
    _run(eob_pdf, settings, vault, biller_guard)
    _run(eob_pdf, settings, vault, biller_guard)

    entries = _manifest(settings, biller_guard).read()
    assert len(entries) == len(SYNTHETIC_PATIENTS)
    assert len({e.pseudonym for e in entries}) == len(entries)


def test_empty_manifest_reads_as_empty(settings, biller_guard):
    assert _manifest(settings, biller_guard).read() == []


# --- claim summary -----------------------------------------------------


def test_summarize_totals_patient_responsibility():
    claims = (
        ClaimLine(procedure_code="D0120", patient_responsibility=Decimal("14.40")),
        ClaimLine(procedure_code="D1110", patient_responsibility=Decimal("20.80")),
    )
    codes, total = summarize_claims(claims)
    assert codes == ("D0120", "D1110")
    assert total == "35.20"


def test_summarize_refuses_a_partial_total():
    """A number beside a patient's name gets read as authoritative.

    If one line's figure could not be parsed, a total that silently omits
    it is worse than no total at all.
    """
    claims = (
        ClaimLine(procedure_code="D0120", patient_responsibility=Decimal("14.40")),
        ClaimLine(procedure_code="D1110", patient_responsibility=None, needs_review=True),
    )
    codes, total = summarize_claims(claims)
    assert codes == ("D0120", "D1110")
    assert total is None


def test_entry_repr_hides_phi():
    entry = ManifestEntry(
        pseudonym="pt-abc",
        filename="x.pdf",
        source_ref="ref",
        exported_at="now",
        patient_name="Alder Quillfeather",
        member_id="ZZQ-100001",
    )
    text = repr(entry)
    assert "Quillfeather" not in text
    assert "ZZQ-100001" not in text
    assert "pt-abc" in text
