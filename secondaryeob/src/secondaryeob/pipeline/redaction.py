"""The redaction engine (master prompt §10).

Redaction here is **permanent content removal**, not a black rectangle
drawn over text that remains in the content stream. PyMuPDF's
``apply_redactions`` rewrites the page's content stream with the covered
glyphs deleted, which is what makes the result non-reversible. A drawn
rectangle would look identical on screen and would still yield the
patient's name to ``Ctrl+A, Ctrl+C`` — the exact failure this product
exists to prevent.

Two independent mechanisms remove other patients' PHI, because either one
alone has a gap:

1. **Structural** — every line the classifier attributed to a different
   patient is redacted by its bounding box. Catches PHI regardless of
   whether it matches any pattern.
2. **Token search** — every identifier belonging to another patient is
   searched for across the retained pages and redacted wherever it
   appears. Catches an identifier that leaked into a shared header,
   footer, or summary table that the structural pass attributed to the
   target's own section.

Pages belonging to no retained record are dropped entirely, which is
stronger than redacting them: a page that is not in the output cannot leak
from the output.

Finally the document is rebuilt with metadata stripped and without
incremental save. An incremental save appends a new revision while leaving
the previous one intact inside the same file, so the un-redacted original
would still be recoverable from the "redacted" PDF.
"""

from __future__ import annotations

import pymupdf

from ..errors import RedactionError
from .classification import identifiers_of_others
from .documents import PatientRecord

#: Redaction boxes are expanded slightly so that glyph antialiasing and
#: bbox rounding cannot leave a readable sliver of a character behind.
_BBOX_PADDING = 1.0

#: Tokens shorter than this are not searched for: a 3-character string
#: matches inside unrelated words and would redact legitimate content.
#: Structural redaction still covers such an identifier within its own
#: patient's section.
_MIN_SEARCHABLE_TOKEN = 4


def redact_to_single_patient(
    pdf_bytes: bytes,
    records: tuple[PatientRecord, ...],
    target: PatientRecord,
) -> bytes:
    """Produce a PDF containing only ``target``'s record, PHI-free of others.

    Args:
        pdf_bytes: The source multi-patient PDF.
        records: Every record the classifier found.
        target: The record to keep.

    Returns:
        The redacted PDF as bytes. Never written to disk here — the caller
        encrypts it into Zone C.

    Raises:
        RedactionError: redaction could not be applied.
    """
    keep_pages = set(target.page_numbers)
    if not keep_pages:
        raise RedactionError(f"record {target.index} spans no pages")

    others = identifiers_of_others(records, target)

    try:
        document = pymupdf.open(stream=pdf_bytes, filetype="pdf")
    except Exception as exc:
        raise RedactionError(f"could not open the source PDF: {type(exc).__name__}") from exc

    try:
        # Drop non-target pages first so later passes do less work and so
        # the page indices below refer only to retained pages.
        drop = [i for i in range(document.page_count) if (i + 1) not in keep_pages]
        if drop:
            document.delete_pages(drop)
        if document.page_count == 0:
            raise RedactionError("every page was dropped; nothing to export")

        # Map original page numbers to their new indices.
        retained = sorted(keep_pages)
        page_index_of = {page_no: idx for idx, page_no in enumerate(retained)}

        # Pass 1: structural. Redact lines attributed to other patients.
        foreign_lines = [
            line
            for record in records
            if record.index != target.index
            for line in record.lines
            if line.page_number in keep_pages
        ]
        for line in foreign_lines:
            page = document.load_page(page_index_of[line.page_number])
            rect = pymupdf.Rect(line.bbox) + (
                -_BBOX_PADDING,
                -_BBOX_PADDING,
                _BBOX_PADDING,
                _BBOX_PADDING,
            )
            page.add_redact_annot(rect)

        # Pass 2: token search across every retained page.
        searchable = [token for token in others if len(token) >= _MIN_SEARCHABLE_TOKEN]
        for page_index in range(document.page_count):
            page = document.load_page(page_index)
            for token in searchable:
                for rect in page.search_for(token, quads=False):
                    page.add_redact_annot(
                        rect + (-_BBOX_PADDING, -_BBOX_PADDING, _BBOX_PADDING, _BBOX_PADDING)
                    )

        # Apply. images=REDACT_IMAGE_PIXELS removes covered image pixels
        # too, so PHI inside a scanned region under a redaction box is
        # destroyed rather than merely covered.
        for page_index in range(document.page_count):
            page = document.load_page(page_index)
            page.apply_redactions(images=pymupdf.PDF_REDACT_IMAGE_PIXELS)

        _scrub_document(document)

        # garbage=4 + clean rewrites the file and discards unreferenced
        # objects, so no orphaned copy of a redacted stream survives.
        # deflate keeps the output small. This is a full save, never
        # incremental — see the module docstring.
        return document.tobytes(garbage=4, clean=True, deflate=True, incremental=False)
    except RedactionError:
        raise
    except Exception as exc:
        raise RedactionError(f"redaction failed: {type(exc).__name__}: {exc}") from exc
    finally:
        document.close()


def _scrub_document(document: pymupdf.Document) -> None:
    """Remove metadata and non-content structures that can carry PHI.

    A redacted page body is not enough: the source filename in
    ``/Title``, a bookmark named after a patient, or an XMP packet
    retained from the payer's generator all carry PHI that no amount of
    page redaction touches.
    """
    # Document information dictionary.
    document.set_metadata({})

    # XMP metadata stream, which is separate from the info dictionary and
    # survives set_metadata.
    try:
        document.del_xml_metadata()
    except Exception:  # pragma: no cover - absent on some documents
        pass

    # Outline entries are frequently generated from patient names in
    # payer batch exports.
    try:
        document.set_toc([])
    except Exception:  # pragma: no cover - absent on some documents
        pass

    # Remaining annotations and form fields. Redaction annotations are
    # consumed by apply_redactions, but link annotations, comments, and
    # widget values are not.
    for page_index in range(document.page_count):
        page = document.load_page(page_index)
        for annot in list(page.annots() or []):
            try:
                page.delete_annot(annot)
            except Exception:  # pragma: no cover - malformed annotation
                pass
        for widget in list(page.widgets() or []):
            try:
                page.delete_widget(widget)
            except Exception:  # pragma: no cover - malformed widget
                pass
