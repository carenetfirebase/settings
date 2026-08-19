"""Post-redaction validation by attempted PHI recovery (master prompt §10).

The system does not trust its own redaction. After redacting, it attacks
the output the way an adversary would and checks whether any of the PHI it
just removed comes back:

* **text extraction** — the fastest real attack. If ``apply_redactions``
  silently failed, or a rectangle was drawn instead of removing content,
  the text is still in the content stream and this finds it.
* **OCR re-scan** — renders each page to an image and reads it back.
  Catches PHI that is visually present but absent from the text layer:
  redaction that removed the glyphs but left a flattened image behind, or
  content that was always an image.
* **metadata inspection** — the info dictionary, XMP packet, outline,
  annotations, form fields, and attachments. None of these are page
  content, so page redaction never touches them.
* **raw object scan** — searches the serialized PDF bytes for the tokens.
  Catches PHI in places the structured APIs do not surface at all: an
  orphaned object left by an incremental save, an unreferenced stream, a
  named destination.

If any technique recovers any token, export is blocked.

**A technique that cannot run is a failure, not a pass.** If OCR is
unavailable, validation is incomplete, and incomplete validation blocks
export — because "we did not look" and "we looked and found nothing" are
not the same result, and only one of them is safe to ship on.
"""

from __future__ import annotations

import re
import shutil
from dataclasses import dataclass, field

import pymupdf

from ..errors import RedactionValidationError

#: Render resolution for the OCR pass. 200 dpi reads 8-9pt EOB body text
#: reliably; lower starts dropping characters, which would make the OCR
#: check pass by failing to read rather than by finding nothing.
_OCR_DPI = 200

#: OCR misreads characters, so exact matching under-detects. How much
#: slack to allow depends on what kind of token it is, and the two kinds
#: pull in opposite directions:
#:
#: *Names* are high-entropy. Two patients' names differ in most of their
#: characters, so a coincidental match is very unlikely and the comparison
#: can afford to be loose — which it needs to be, because OCR garbles
#: several characters of a long name (``Thornwhistle`` -> ``Thomwhist1e``
#: is three edits).
#:
#: *Structured identifiers* — member IDs, dates — are the opposite. They
#: are low-entropy and, worse, siblings by construction: two IDs issued by
#: one payer differ in a couple of characters (``ZZQ-100001`` vs
#: ``ZZQ-200002``), and two dates in a single digit. Any edit budget large
#: enough to absorb an OCR error is also large enough to turn one member
#: into another, so these get no budget at all. They are matched exactly,
#: after both sides are canonicalized through the confusable map below —
#: which handles the OCR errors that actually occur on digit strings
#: (``0``/``O``, ``1``/``l``) deterministically, rather than by allowing
#: an edit that could equally well swap one patient for the next.
_NAME_FUZZY_THRESHOLD = 0.75

#: A token counts as name-like when at least this fraction of it is
#: alphabetic.
_NAME_ALPHA_RATIO = 0.5

#: Glyph pairs OCR routinely confuses, collapsed to a single canonical
#: form so that a misread identifier still matches the one it came from.
_CONFUSABLE_MAP = str.maketrans(
    {
        "o": "0",
        "i": "1",
        "l": "1",
        "|": "1",
        "s": "5",
        "b": "8",
        "z": "2",
        "g": "6",
    }
)

#: Separators that OCR drops, doubles, or invents inside identifiers.
_SEPARATORS = str.maketrans({c: "" for c in " -/.#,"})


@dataclass
class TechniqueResult:
    """Outcome of one recovery technique."""

    name: str
    ran: bool
    #: Redacted tokens this technique recovered. PHI — never logged.
    recovered: frozenset[str] = field(default_factory=frozenset, repr=False)
    #: Why the technique could not run, when ``ran`` is False.
    unavailable_reason: str | None = None

    @property
    def clean(self) -> bool:
        return self.ran and not self.recovered


@dataclass
class ValidationReport:
    """The result of validating one redacted document."""

    techniques: tuple[TechniqueResult, ...]

    @property
    def recovered_count(self) -> int:
        return len({token for t in self.techniques for token in t.recovered})

    @property
    def techniques_that_did_not_run(self) -> tuple[str, ...]:
        return tuple(t.name for t in self.techniques if not t.ran)

    @property
    def passed(self) -> bool:
        """True only if every technique ran and none recovered anything."""
        return all(t.clean for t in self.techniques)

    def failure_summary(self) -> str:
        """A PHI-free explanation of why validation failed."""
        parts = []
        for technique in self.techniques:
            if technique.recovered:
                parts.append(f"{technique.name} recovered {len(technique.recovered)} token(s)")
            elif not technique.ran:
                parts.append(f"{technique.name} could not run ({technique.unavailable_reason})")
        return "; ".join(parts) or "unknown"


def _normalize(text: str) -> str:
    """Lowercase and collapse whitespace for comparison."""
    return re.sub(r"\s+", " ", text).strip().lower()


def _find_exact(haystack: str, tokens: frozenset[str]) -> frozenset[str]:
    normalized = _normalize(haystack)
    return frozenset(token for token in tokens if _normalize(token) in normalized)


def _is_name_like(token: str) -> bool:
    """True when ``token`` is mostly letters, i.e. a name rather than an ID."""
    if not token:
        return False
    letters = sum(1 for ch in token if ch.isalpha())
    return letters / len(token) >= _NAME_ALPHA_RATIO


def _canonicalize(text: str) -> str:
    """Collapse OCR-confusable glyphs and drop separators."""
    return text.translate(_CONFUSABLE_MAP).translate(_SEPARATORS)


def _edit_distance(a: str, b: str, ceiling: int) -> int:
    """Levenshtein distance, abandoned once it provably exceeds ``ceiling``.

    Edit distance rather than positional comparison because OCR inserts
    and drops characters as well as substituting them, and a single
    dropped character misaligns every position after it — which a
    positional comparison reports as a string of mismatches.
    """
    if abs(len(a) - len(b)) > ceiling:
        return ceiling + 1

    previous = list(range(len(b) + 1))
    for i, ch_a in enumerate(a, start=1):
        current = [i]
        for j, ch_b in enumerate(b, start=1):
            current.append(
                min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (ch_a != ch_b),
                )
            )
        if min(current) > ceiling:
            return ceiling + 1
        previous = current
    return previous[-1]


def _find_fuzzy(
    haystack: str, tokens: frozenset[str], retained: frozenset[str]
) -> frozenset[str]:
    """Find redacted tokens in OCR text, allowing for OCR character errors.

    ``retained`` holds the identifiers that legitimately belong in this
    document — the target patient's own. They answer the question a
    similarity score alone cannot: is this window an OCR-garbled copy of a
    token that should be gone, or a clean read of one that should be
    there? A window explained at least as well by a retained identifier is
    not reported as a recovery. Without that check the validator reports
    the target's own member ID as a neighbouring patient's and blocks
    every legitimate export.
    """
    normalized = _normalize(haystack)
    retained_normalized = {_normalize(value) for value in retained if value}
    canonical_haystack = _canonicalize(normalized)
    recovered: set[str] = set()

    for token in tokens:
        needle = _normalize(token)
        if len(needle) < 4:
            continue
        if needle in normalized:
            recovered.add(token)
            continue

        if not _is_name_like(needle):
            # Structured identifier: canonical exact match, no edit budget.
            # See the threshold constants above for why.
            canonical_needle = _canonicalize(needle)
            if len(canonical_needle) >= 4 and canonical_needle in canonical_haystack:
                # Unless a retained identifier canonicalizes the same way,
                # in which case the retained one explains it.
                if not any(
                    _canonicalize(candidate) == canonical_needle
                    for candidate in retained_normalized
                ):
                    recovered.add(token)
            continue

        budget = int(len(needle) * (1.0 - _NAME_FUZZY_THRESHOLD))
        if budget < 1:
            # Too short to allow any error; the exact check above stands.
            continue

        needle_chars = set(needle)
        found = False
        # Window lengths around the token's own length cover substitutions
        # (same length) as well as insertions and deletions.
        for window_len in range(len(needle) - budget, len(needle) + budget + 1):
            if window_len < 4 or window_len > len(normalized):
                continue
            for start in range(len(normalized) - window_len + 1):
                window = normalized[start : start + window_len]
                # Cheap prefilter: a window sharing too few characters with
                # the token cannot be within the edit budget, and skipping
                # it avoids the quadratic distance computation.
                if len(needle_chars & set(window)) < len(needle_chars) - budget:
                    continue
                distance = _edit_distance(needle, window, budget)
                if distance > budget:
                    continue
                # Is a retained identifier at least as good an explanation?
                if any(
                    _edit_distance(candidate, window, distance) <= distance
                    for candidate in retained_normalized
                ):
                    continue
                recovered.add(token)
                found = True
                break
            if found:
                break

    return frozenset(recovered)


def _technique_text_extraction(
    document: pymupdf.Document, tokens: frozenset[str]
) -> TechniqueResult:
    text = "\n".join(
        document.load_page(i).get_text("text") for i in range(document.page_count)
    )
    return TechniqueResult(
        name="text_extraction", ran=True, recovered=_find_exact(text, tokens)
    )


def _technique_ocr(
    document: pymupdf.Document, tokens: frozenset[str], retained: frozenset[str]
) -> TechniqueResult:
    if shutil.which("tesseract") is None:
        return TechniqueResult(
            name="ocr_rescan",
            ran=False,
            unavailable_reason=(
                "tesseract is not installed or not on PATH — install Tesseract-OCR "
                "(see the README); every export stays blocked until it is available"
            ),
        )
    try:
        chunks = []
        for page_index in range(document.page_count):
            page = document.load_page(page_index)
            textpage = page.get_textpage_ocr(dpi=_OCR_DPI, full=True)
            chunks.append(page.get_text("text", textpage=textpage))
        return TechniqueResult(
            name="ocr_rescan",
            ran=True,
            recovered=_find_fuzzy("\n".join(chunks), tokens, retained),
        )
    except Exception as exc:
        # An OCR error is "we did not look", which blocks export.
        return TechniqueResult(
            name="ocr_rescan",
            ran=False,
            unavailable_reason=f"OCR failed: {type(exc).__name__}",
        )


def _technique_metadata(document: pymupdf.Document, tokens: frozenset[str]) -> TechniqueResult:
    fragments: list[str] = []

    fragments.extend(str(value) for value in (document.metadata or {}).values() if value)

    try:
        xml_meta = document.get_xml_metadata()
        if xml_meta:
            fragments.append(xml_meta)
    except Exception:  # pragma: no cover - absent on some documents
        pass

    try:
        fragments.extend(str(entry[1]) for entry in document.get_toc() or [])
    except Exception:  # pragma: no cover - absent on some documents
        pass

    for page_index in range(document.page_count):
        page = document.load_page(page_index)
        for annot in page.annots() or []:
            info = annot.info or {}
            fragments.extend(str(value) for value in info.values() if value)
        for widget in page.widgets() or []:
            fragments.extend(
                str(value)
                for value in (widget.field_name, widget.field_value, widget.field_label)
                if value
            )

    try:
        for i in range(document.embfile_count()):
            info = document.embfile_info(i)
            fragments.extend(str(value) for value in info.values() if value)
    except Exception:  # pragma: no cover - no embedded files
        pass

    return TechniqueResult(
        name="metadata_inspection", ran=True, recovered=_find_exact("\n".join(fragments), tokens)
    )


def _technique_raw_scan(pdf_bytes: bytes, tokens: frozenset[str]) -> TechniqueResult:
    """Search the serialized bytes, including decompressed streams."""
    fragments = [pdf_bytes.decode("latin-1", errors="ignore")]

    # Decompress every stream so PHI inside a Flate-encoded object is
    # visible to the scan.
    try:
        document = pymupdf.open(stream=pdf_bytes, filetype="pdf")
        try:
            for xref in range(1, document.xref_length()):
                try:
                    if document.xref_is_stream(xref):
                        fragments.append(
                            document.xref_stream(xref).decode("latin-1", errors="ignore")
                        )
                    fragments.append(document.xref_object(xref, compressed=False) or "")
                except Exception:
                    continue
        finally:
            document.close()
    except Exception:  # pragma: no cover - unreadable document
        pass

    return TechniqueResult(
        name="raw_object_scan", ran=True, recovered=_find_exact("\n".join(fragments), tokens)
    )


def validate_redaction(
    redacted_pdf: bytes,
    removed_tokens: frozenset[str],
    retained_tokens: frozenset[str] = frozenset(),
    *,
    require_ocr: bool = True,
) -> ValidationReport:
    """Attempt to recover ``removed_tokens`` from ``redacted_pdf``.

    Args:
        redacted_pdf: The output of the redaction engine.
        removed_tokens: The PHI strings that must no longer be present.
        retained_tokens: The identifiers that legitimately remain — the
            target patient's own. Used only by the fuzzy OCR comparison,
            to avoid reporting the target's own identifier as a
            neighbour's near-match. Exact-match techniques do not need it
            and do not use it.
        require_ocr: When False, the OCR technique is omitted entirely
            rather than counted as a failure. Only for environments where
            OCR is genuinely out of scope; it weakens the guarantee, so
            the caller has to ask for it.

    Returns:
        A :class:`ValidationReport`. Callers must check ``passed``.
    """
    if not removed_tokens:
        # Nothing was supposed to be removed, so there is nothing to
        # recover. Still run the techniques so the report is uniform.
        removed_tokens = frozenset()

    try:
        document = pymupdf.open(stream=redacted_pdf, filetype="pdf")
    except Exception as exc:
        raise RedactionValidationError(
            f"the redacted document could not be reopened for validation: "
            f"{type(exc).__name__}"
        ) from exc

    try:
        techniques = [
            _technique_text_extraction(document, removed_tokens),
            _technique_metadata(document, removed_tokens),
        ]
        if require_ocr:
            techniques.append(_technique_ocr(document, removed_tokens, retained_tokens))
    finally:
        document.close()

    techniques.append(_technique_raw_scan(redacted_pdf, removed_tokens))
    return ValidationReport(techniques=tuple(techniques))


def assert_safe_to_export(report: ValidationReport) -> None:
    """Halt unless every technique ran clean (master prompt §10).

    Raises:
        RedactionValidationError: PHI was recovered, or a technique could
            not run.
    """
    if not report.passed:
        raise RedactionValidationError(
            f"BLOCKED: post-redaction validation did not pass — {report.failure_summary()}. "
            "The document has not been exported."
        )
