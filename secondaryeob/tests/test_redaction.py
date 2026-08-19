"""Redaction and validation tests (master prompt §10).

These are the tests that matter most: they assert that PHI belonging to
other patients cannot be recovered from a sanitized output by any means
the validator knows about.
"""

from __future__ import annotations

import pymupdf
import pytest

from conftest import SYNTHETIC_PATIENTS, build_eob_pdf
from secondaryeob.errors import RedactionValidationError
from secondaryeob.pipeline.classification import classify, identifiers_of_others
from secondaryeob.pipeline.extraction import extract_pages, open_document
from secondaryeob.pipeline.redaction import redact_to_single_patient
from secondaryeob.pipeline.validation import (
    assert_safe_to_export,
    validate_redaction,
)


def _records(pdf_bytes: bytes):
    document = open_document(pdf_bytes)
    try:
        pages = extract_pages(document)
    finally:
        document.close()
    return classify(pages)


def _all_text(pdf_bytes: bytes) -> str:
    document = pymupdf.open(stream=pdf_bytes, filetype="pdf")
    try:
        return "\n".join(
            document.load_page(i).get_text("text") for i in range(document.page_count)
        )
    finally:
        document.close()


# --- classification ----------------------------------------------------


def test_classification_finds_every_patient(eob_pdf):
    records = _records(eob_pdf)
    assert len(records) == len(SYNTHETIC_PATIENTS)


def test_classification_collects_identifiers(eob_pdf):
    records = _records(eob_pdf)
    first = records[0]
    assert SYNTHETIC_PATIENTS[0]["name"] in first.identifiers
    assert SYNTHETIC_PATIENTS[0]["member_id"] in first.identifiers


def test_classification_refuses_a_document_with_no_anchor():
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((50, 50), "Some unrelated invoice with no patient header", fontsize=10)
    data = document.tobytes()
    document.close()

    from secondaryeob.errors import ClassificationError

    with pytest.raises(ClassificationError, match="no patient anchor"):
        _records(data)


# --- redaction: separate pages ----------------------------------------


@pytest.mark.parametrize("target_index", range(len(SYNTHETIC_PATIENTS)))
def test_other_patients_absent_from_output(eob_pdf, target_index):
    records = _records(eob_pdf)
    target = records[target_index]

    redacted = redact_to_single_patient(eob_pdf, records, target)
    text = _all_text(redacted)

    for index, patient in enumerate(SYNTHETIC_PATIENTS):
        if index == target_index:
            continue
        assert patient["name"] not in text
        assert patient["member_id"] not in text
        assert patient["dob"] not in text


@pytest.mark.parametrize("target_index", range(len(SYNTHETIC_PATIENTS)))
def test_target_patient_survives_redaction(eob_pdf, target_index):
    """Redaction must not destroy the record it is meant to keep."""
    records = _records(eob_pdf)
    target = records[target_index]

    redacted = redact_to_single_patient(eob_pdf, records, target)
    text = _all_text(redacted)

    patient = SYNTHETIC_PATIENTS[target_index]
    assert patient["name"] in text
    assert patient["member_id"] in text
    assert patient["procedure"] in text


def test_only_target_pages_are_kept(eob_pdf):
    records = _records(eob_pdf)
    redacted = redact_to_single_patient(eob_pdf, records, records[1])

    document = pymupdf.open(stream=redacted, filetype="pdf")
    try:
        assert document.page_count == len(records[1].page_numbers)
    finally:
        document.close()


# --- redaction: shared page (the harder case) --------------------------


@pytest.mark.parametrize("target_index", range(len(SYNTHETIC_PATIENTS)))
def test_shared_page_isolates_the_target(shared_page_eob_pdf, target_index):
    """All three patients on one page: the page is kept, others removed."""
    records = _records(shared_page_eob_pdf)
    target = records[target_index]

    redacted = redact_to_single_patient(shared_page_eob_pdf, records, target)
    text = _all_text(redacted)

    patient = SYNTHETIC_PATIENTS[target_index]
    assert patient["name"] in text

    for index, other in enumerate(SYNTHETIC_PATIENTS):
        if index == target_index:
            continue
        assert other["name"] not in text
        assert other["member_id"] not in text


# --- validation --------------------------------------------------------


def test_validation_passes_on_correct_redaction(eob_pdf):
    records = _records(eob_pdf)
    target = records[0]
    redacted = redact_to_single_patient(eob_pdf, records, target)

    report = validate_redaction(redacted, identifiers_of_others(records, target))
    assert report.passed, report.failure_summary()
    assert_safe_to_export(report)


def test_validation_runs_every_technique(eob_pdf):
    records = _records(eob_pdf)
    target = records[0]
    redacted = redact_to_single_patient(eob_pdf, records, target)

    report = validate_redaction(redacted, identifiers_of_others(records, target))
    names = {technique.name for technique in report.techniques}
    assert names == {"text_extraction", "metadata_inspection", "ocr_rescan", "raw_object_scan"}


def test_validation_catches_annotation_style_fake_redaction(eob_pdf):
    """A black box drawn over text is not redaction, and must be caught.

    This is the failure the product exists to prevent: the document looks
    sanitized and still yields the PHI to text extraction.
    """
    records = _records(eob_pdf)
    target = records[0]

    # Build a "redacted" document the wrong way: keep every page, draw an
    # opaque rectangle over the other patients' lines, remove nothing.
    document = pymupdf.open(stream=eob_pdf, filetype="pdf")
    try:
        for record in records:
            if record.index == target.index:
                continue
            for line in record.lines:
                page = document.load_page(line.page_number - 1)
                page.draw_rect(pymupdf.Rect(line.bbox), color=(0, 0, 0), fill=(0, 0, 0))
        fake = document.tobytes()
    finally:
        document.close()

    report = validate_redaction(fake, identifiers_of_others(records, target))
    assert not report.passed
    assert report.recovered_count > 0
    with pytest.raises(RedactionValidationError, match="BLOCKED"):
        assert_safe_to_export(report)


def test_validation_catches_phi_left_in_metadata(eob_pdf):
    """Page redaction never touches the info dictionary."""
    records = _records(eob_pdf)
    target = records[0]
    redacted = redact_to_single_patient(eob_pdf, records, target)

    document = pymupdf.open(stream=redacted, filetype="pdf")
    try:
        document.set_metadata({"title": SYNTHETIC_PATIENTS[1]["name"]})
        leaky = document.tobytes()
    finally:
        document.close()

    report = validate_redaction(leaky, identifiers_of_others(records, target))
    assert not report.passed
    metadata_result = next(t for t in report.techniques if t.name == "metadata_inspection")
    assert metadata_result.recovered


def test_metadata_is_scrubbed_by_redaction(eob_pdf):
    document = pymupdf.open(stream=eob_pdf, filetype="pdf")
    try:
        document.set_metadata({"title": "Bulk EOB for Bexley Thornwhistle", "author": "Payer"})
        with_metadata = document.tobytes()
    finally:
        document.close()

    records = _records(with_metadata)
    redacted = redact_to_single_patient(with_metadata, records, records[0])

    document = pymupdf.open(stream=redacted, filetype="pdf")
    try:
        metadata = document.metadata or {}
        # "format" is an inherent property of the file (e.g. "PDF 1.7"),
        # not something the payer wrote, so it is not scrubbed.
        phi_bearing = {k: v for k, v in metadata.items() if k != "format"}
        assert not any(phi_bearing.values()), phi_bearing
    finally:
        document.close()


def test_unavailable_technique_blocks_export(eob_pdf, monkeypatch):
    """'We did not look' must not be reported as 'we found nothing'."""
    records = _records(eob_pdf)
    target = records[0]
    redacted = redact_to_single_patient(eob_pdf, records, target)

    monkeypatch.setattr("secondaryeob.pipeline.validation.shutil.which", lambda _: None)

    report = validate_redaction(redacted, identifiers_of_others(records, target))
    assert not report.passed
    assert "ocr_rescan" in report.techniques_that_did_not_run
    with pytest.raises(RedactionValidationError, match="could not run"):
        assert_safe_to_export(report)


def test_fuzzy_matcher_does_not_confuse_sibling_identifiers():
    """Two member IDs from one payer differ in very few characters.

    Regression: a positional comparison scored ``ZZQ-100001`` as an 80%
    match for ``ZZQ-200002`` and blocked every legitimate export. The
    retained identifier explains the window, so it is not a recovery.
    """
    from secondaryeob.pipeline.validation import _find_fuzzy

    page_text = "Patient Name: Alder Quillfeather Member ID: ZZQ-100001"
    removed = frozenset({"ZZQ-200002", "ZZQ-300003"})
    retained = frozenset({"ZZQ-100001", "Alder Quillfeather"})

    assert _find_fuzzy(page_text, removed, retained) == frozenset()


def test_fuzzy_matcher_still_catches_a_garbled_leak():
    """A real leak with OCR errors must still be found."""
    from secondaryeob.pipeline.validation import _find_fuzzy

    # "Thornwhistle" misread with rn->m and l->1.
    page_text = "Patient Name: Bexley Thomwhist1e Member ID: ZZQ-200002"
    removed = frozenset({"Bexley Thornwhistle"})
    retained = frozenset({"Alder Quillfeather", "ZZQ-100001"})

    assert _find_fuzzy(page_text, removed, retained) == frozenset({"Bexley Thornwhistle"})


def test_structured_id_matched_through_ocr_confusables():
    """A member ID misread with letter-O for zero must still be caught."""
    from secondaryeob.pipeline.validation import _find_fuzzy

    page_text = "Member ID: ZZQ-2OOOO2"  # letter O, not digit zero
    removed = frozenset({"ZZQ-200002"})
    retained = frozenset({"ZZQ-100001"})

    assert _find_fuzzy(page_text, removed, retained) == frozenset({"ZZQ-200002"})


def test_dates_are_not_confused_with_each_other():
    """A removed DOB must not match a retained service date one digit away."""
    from secondaryeob.pipeline.validation import _find_fuzzy

    page_text = "Service Date: 01/15/2026"
    removed = frozenset({"01/15/2020"})

    assert _find_fuzzy(page_text, removed, frozenset()) == frozenset()


def test_ocr_recovers_phi_from_a_flattened_page(eob_pdf):
    """PHI present as pixels but absent from the text layer must be caught.

    Text extraction alone would report this document clean, which is
    exactly why the OCR technique exists.
    """
    records = _records(eob_pdf)
    target = records[0]

    # Rasterize the whole source: every glyph becomes pixels, no text layer.
    source = pymupdf.open(stream=eob_pdf, filetype="pdf")
    flattened = pymupdf.open()
    try:
        for page_index in range(source.page_count):
            pixmap = source.load_page(page_index).get_pixmap(dpi=200)
            page = flattened.new_page(width=pixmap.width, height=pixmap.height)
            page.insert_image(page.rect, pixmap=pixmap)
        data = flattened.tobytes()
    finally:
        source.close()
        flattened.close()

    others = identifiers_of_others(records, target)
    report = validate_redaction(data, others)

    text_result = next(t for t in report.techniques if t.name == "text_extraction")
    ocr_result = next(t for t in report.techniques if t.name == "ocr_rescan")

    assert not text_result.recovered, "no text layer, so extraction alone sees nothing"
    assert ocr_result.ran
    assert ocr_result.recovered, "OCR should read the other patients' names off the pixels"
    assert not report.passed
