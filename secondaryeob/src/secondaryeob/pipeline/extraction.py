"""Text extraction from the source PDF (Zone A).

Extraction runs from bytes held in memory — the decrypted PDF is never
written to a temporary file, because a temp file is plaintext PHI on disk
and master prompt §1.1 forbids that.

A page with no text layer is reported as image-only rather than as an
empty page. Treating "no text found" as "no text present" is how a
scanned patient section would silently survive redaction: the classifier
would see nothing to attribute to a patient, redaction would find nothing
to remove, and the PHI would ship. So image-only pages halt the MVP
pipeline (OCR-for-extraction is deferred per plan §E).
"""

from __future__ import annotations

import pymupdf

from ..errors import CorruptDocumentError, ExtractionError
from .documents import ExtractedPage, TextLine


def open_document(pdf_bytes: bytes) -> pymupdf.Document:
    """Open a PDF from memory, or raise :class:`CorruptDocumentError`."""
    try:
        document = pymupdf.open(stream=pdf_bytes, filetype="pdf")
    except Exception as exc:
        raise CorruptDocumentError(f"could not open the PDF: {type(exc).__name__}") from exc

    if document.is_encrypted and not document.authenticate(""):
        document.close()
        raise CorruptDocumentError(
            "the PDF is password-protected; it cannot be processed without the password"
        )
    if document.page_count == 0:
        document.close()
        raise CorruptDocumentError("the PDF has no pages")
    return document


def extract_pages(document: pymupdf.Document) -> tuple[ExtractedPage, ...]:
    """Extract every page's text lines with positions.

    Raises:
        ExtractionError: a page could not be read at all.
    """
    pages: list[ExtractedPage] = []

    for page_index in range(document.page_count):
        page_number = page_index + 1
        try:
            page = document.load_page(page_index)
            raw = page.get_text("dict")
        except Exception as exc:
            raise ExtractionError(
                f"page {page_number} could not be read: {type(exc).__name__}"
            ) from exc

        lines: list[TextLine] = []
        for block in raw.get("blocks", []):
            # type 0 is a text block; type 1 is an image.
            if block.get("type") != 0:
                continue
            for line in block.get("lines", []):
                text = "".join(span.get("text", "") for span in line.get("spans", []))
                if not text.strip():
                    continue
                x0, y0, x1, y1 = line["bbox"]
                lines.append(
                    TextLine(
                        page_number=page_number,
                        text=text,
                        x0=float(x0),
                        y0=float(y0),
                        x1=float(x1),
                        y1=float(y1),
                    )
                )

        pages.append(
            ExtractedPage(
                page_number=page_number,
                lines=tuple(lines),
                is_image_only=not lines,
            )
        )

    return tuple(pages)


def assert_text_layer_present(pages: tuple[ExtractedPage, ...]) -> None:
    """Halt if any page lacks a text layer.

    See the module docstring: an image-only page is not safe to process
    without OCR, and OCR-for-extraction is out of MVP scope.
    """
    image_only = [page.page_number for page in pages if page.is_image_only]
    if image_only:
        raise ExtractionError(
            f"pages {image_only} have no text layer. This build processes "
            "text-layer PDFs only; a scanned page cannot be classified or "
            "redacted reliably without OCR, so processing stops rather than "
            "producing a document whose PHI was never seen."
        )
