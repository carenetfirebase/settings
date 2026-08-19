"""End-to-end pipeline tests (master prompt §11, §13).

Asserts the whole chain: an encrypted bulk EOB in, per-patient sanitized
PDFs out, with an authorization check and an audit entry at every
transition, and a hard stop on every failure mode.
"""

from __future__ import annotations

import pymupdf
import pytest

from conftest import SYNTHETIC_PATIENTS, build_eob_pdf
from secondaryeob.audit import AuditLog
from secondaryeob.errors import (
    AuthorizationError,
    ClassificationError,
    CorruptDocumentError,
    ExtractionError,
)
from secondaryeob.pipeline import process_document
from secondaryeob.zones import Zone


def _stage(pdf_bytes: bytes, settings, vault, name: str = "bulk.pdf"):
    """Place an encrypted bulk EOB in Incoming/."""
    path = settings.path_for("Incoming") / name
    vault.write(path, pdf_bytes, zone=Zone.A_RAW_PHI)
    return path


def test_end_to_end_exports_one_pdf_per_patient(eob_pdf, settings, vault, biller_guard):
    source = _stage(eob_pdf, settings, vault)
    result = process_document(source, biller_guard, settings)

    assert result.patient_count == len(SYNTHETIC_PATIENTS)
    assert result.exported_count == len(SYNTHETIC_PATIENTS)
    assert result.blocked_count == 0

    ready = sorted(settings.path_for("Ready").glob("*.pdf"))
    assert len(ready) == len(SYNTHETIC_PATIENTS)


def test_exported_files_are_encrypted_at_rest(eob_pdf, settings, vault, biller_guard):
    source = _stage(eob_pdf, settings, vault)
    result = process_document(source, biller_guard, settings)

    for outcome in result.outcomes:
        raw = outcome.exported_path.read_bytes()
        assert raw.startswith(b"SEOB1"), "output must be encrypted, not a bare PDF"
        assert b"%PDF" not in raw
        for patient in SYNTHETIC_PATIENTS:
            assert patient["name"].encode() not in raw


def test_each_export_contains_only_its_own_patient(eob_pdf, settings, vault, biller_guard):
    source = _stage(eob_pdf, settings, vault)
    result = process_document(source, biller_guard, settings)

    seen_names = []
    for outcome in result.outcomes:
        decrypted = biller_guard.read(outcome.exported_path)
        document = pymupdf.open(stream=decrypted, filetype="pdf")
        try:
            text = "\n".join(
                document.load_page(i).get_text("text") for i in range(document.page_count)
            )
        finally:
            document.close()

        present = [p["name"] for p in SYNTHETIC_PATIENTS if p["name"] in text]
        assert len(present) == 1, f"expected exactly one patient, found {len(present)}"
        seen_names.append(present[0])

    assert sorted(seen_names) == sorted(p["name"] for p in SYNTHETIC_PATIENTS)


def test_output_filenames_carry_no_phi(eob_pdf, settings, vault, biller_guard):
    source = _stage(eob_pdf, settings, vault)
    result = process_document(source, biller_guard, settings)

    for outcome in result.outcomes:
        name = outcome.exported_path.name
        for patient in SYNTHETIC_PATIENTS:
            assert patient["name"] not in name
            assert patient["member_id"] not in name
            assert patient["dob"] not in name
        assert outcome.pseudonym.startswith("pt-")


def test_shared_page_document_processes_end_to_end(
    shared_page_eob_pdf, settings, vault, biller_guard
):
    source = _stage(shared_page_eob_pdf, settings, vault)
    result = process_document(source, biller_guard, settings)
    assert result.exported_count == len(SYNTHETIC_PATIENTS)


# --- audit coverage ----------------------------------------------------


def test_every_stage_is_audited(eob_pdf, settings, vault, biller_guard, audit_log):
    source = _stage(eob_pdf, settings, vault)
    process_document(source, biller_guard, settings)

    actions = {entry.action for entry in audit_log.verify_chain()}
    for expected in ("INTAKE", "EXTRACT", "CLASSIFY", "PARSE", "REDACT", "VALIDATE", "EXPORT"):
        assert expected in actions, f"{expected} was not audited"


def test_audit_chain_survives_a_full_run(eob_pdf, settings, vault, biller_guard, audit_log):
    source = _stage(eob_pdf, settings, vault)
    process_document(source, biller_guard, settings)

    reopened = AuditLog.open(audit_log.path)
    assert reopened.entry_count > 0


def test_audit_entries_contain_no_phi(eob_pdf, settings, vault, biller_guard, audit_log):
    source = _stage(eob_pdf, settings, vault)
    process_document(source, biller_guard, settings)

    blob = audit_log.path.read_text()
    for patient in SYNTHETIC_PATIENTS:
        assert patient["name"] not in blob
        assert patient["member_id"] not in blob
        assert patient["dob"] not in blob


def test_all_entries_share_one_job_id(eob_pdf, settings, vault, biller_guard, audit_log):
    source = _stage(eob_pdf, settings, vault)
    result = process_document(source, biller_guard, settings)

    job_ids = {
        entry.job_id for entry in audit_log.verify_chain() if entry.action != "AUTH"
    }
    assert result.job_id in job_ids


# --- failure modes (master prompt §13) ---------------------------------


def test_reviewer_cannot_run_the_pipeline(eob_pdf, settings, vault, reviewer_guard):
    source = _stage(eob_pdf, settings, vault)
    with pytest.raises(AuthorizationError):
        process_document(source, reviewer_guard, settings)


def test_corrupt_pdf_halts_and_quarantines(settings, vault, biller_guard):
    source = _stage(b"this is not a pdf at all", settings, vault)

    with pytest.raises(CorruptDocumentError):
        process_document(source, biller_guard, settings)

    assert list(settings.path_for("Quarantine").iterdir()), "should be quarantined"
    assert not source.exists(), "should be removed from Incoming"
    assert not list(settings.path_for("Ready").iterdir()), "nothing may be exported"


def test_document_with_no_patient_anchor_halts(settings, vault, biller_guard):
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((50, 50), "An unrelated invoice with no patient header", fontsize=10)
    data = document.tobytes()
    document.close()

    source = _stage(data, settings, vault)
    with pytest.raises(ClassificationError):
        process_document(source, biller_guard, settings)

    assert not list(settings.path_for("Ready").iterdir())


def test_image_only_pdf_halts_rather_than_seeing_nothing(settings, vault, biller_guard):
    """A scanned page must stop the pipeline, not process as an empty page."""
    source_doc = pymupdf.open(stream=build_eob_pdf(SYNTHETIC_PATIENTS), filetype="pdf")
    flattened = pymupdf.open()
    try:
        for page_index in range(source_doc.page_count):
            pixmap = source_doc.load_page(page_index).get_pixmap(dpi=100)
            page = flattened.new_page(width=pixmap.width, height=pixmap.height)
            page.insert_image(page.rect, pixmap=pixmap)
        data = flattened.tobytes()
    finally:
        source_doc.close()
        flattened.close()

    source = _stage(data, settings, vault)
    with pytest.raises(ExtractionError, match="no text layer"):
        process_document(source, biller_guard, settings)

    assert not list(settings.path_for("Ready").iterdir())


def test_quarantined_document_stays_encrypted(settings, vault, biller_guard):
    source = _stage(b"not a pdf", settings, vault)
    with pytest.raises(CorruptDocumentError):
        process_document(source, biller_guard, settings)

    quarantined = next(iter(settings.path_for("Quarantine").iterdir()))
    assert quarantined.read_bytes().startswith(b"SEOB1")


# --- review gating -----------------------------------------------------


def test_unparseable_claim_is_held_for_review(settings, vault, biller_guard):
    """A record whose figures could not be parsed must not reach Ready/."""
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((50, 50), "Patient Name: Solo Testcase", fontsize=10)
    page.insert_text((50, 68), "Member ID: ZZQ-900009", fontsize=10)
    # No ADA procedure code, so the parser cannot identify a claim line.
    page.insert_text((50, 86), "Total charges applied to account", fontsize=10)
    data = document.tobytes()
    document.close()

    source = _stage(data, settings, vault)
    result = process_document(source, biller_guard, settings)

    assert result.exported_count == 0
    assert result.blocked_count == 1
    assert "REVIEW REQUIRED" in result.outcomes[0].blocked_reason
    assert not list(settings.path_for("Ready").iterdir())
