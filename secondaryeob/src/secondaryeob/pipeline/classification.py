"""Deterministic patient-boundary detection.

This is the stage that decides which pages and which lines belong to which
patient. Everything downstream trusts it: redaction removes what this
stage attributed to *other* patients, so a boundary error here is a PHI
leak or a destroyed record.

That is why it is rule-based and why it refuses rather than guesses. The
rules are anchor patterns — the header lines payers print above each
patient's section. When the anchors do not produce a coherent structure,
the stage raises :class:`ClassificationError` and the document goes to
Quarantine for human handling.

Master prompt: patient identity resolution is never the LLM's to decide.
When the LLM fallback is eventually added (deferred, plan §E), it may
propose an anchor for a layout these rules do not cover, but a human
confirms it before it is used — the proposal is not the decision.
"""

from __future__ import annotations

import re

from ..errors import ClassificationError
from .documents import ExtractedPage, PatientRecord, TextLine

#: Anchor patterns marking the start of a patient section. Ordered by
#: specificity; the first that matches a line wins.
#:
#: Each pattern must capture the patient's name in group "name". Adding a
#: payer layout means adding a pattern here and a fixture that exercises
#: it — never loosening an existing pattern until it happens to match,
#: which is how a pattern starts matching things it should not.
_PATIENT_ANCHORS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^\s*patient\s+name\s*[:\-]\s*(?P<name>.+?)\s*$", re.IGNORECASE),
    re.compile(r"^\s*patient\s*[:\-]\s*(?P<name>.+?)\s*$", re.IGNORECASE),
    re.compile(r"^\s*name\s+of\s+patient\s*[:\-]\s*(?P<name>.+?)\s*$", re.IGNORECASE),
)

#: Secondary identifiers to collect within a section. These are additional
#: PHI strings that redaction must remove from other patients' outputs.
_IDENTIFIER_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"member\s*(?:id|#|no\.?)\s*[:\-]?\s*(?P<value>[A-Za-z0-9\-]{4,})", re.IGNORECASE),
    re.compile(r"subscriber\s*(?:id|#|no\.?)\s*[:\-]?\s*(?P<value>[A-Za-z0-9\-]{4,})", re.IGNORECASE),
    re.compile(r"\bID\s*[:\-]\s*(?P<value>[A-Za-z0-9\-]{4,})", re.IGNORECASE),
    re.compile(r"(?:date\s+of\s+birth|dob)\s*[:\-]?\s*(?P<value>[0-9]{1,2}[/-][0-9]{1,2}[/-][0-9]{2,4})", re.IGNORECASE),
)

#: A captured name shorter than this is more likely a stray label than a
#: real name, and a boundary built on it would be wrong.
_MIN_NAME_LENGTH = 2


def _match_anchor(line: TextLine) -> str | None:
    """Return the patient name if ``line`` starts a patient section."""
    for pattern in _PATIENT_ANCHORS:
        match = pattern.match(line.text)
        if match:
            name = match.group("name").strip()
            # Strip trailing field labels that ran onto the same line,
            # e.g. "Patient: Jane Doe    Member ID: X123".
            name = re.split(
                r"\s{2,}|\s+(?:member|subscriber|id|dob|date)\b",
                name,
                maxsplit=1,
                flags=re.IGNORECASE,
            )[0].strip()
            if len(name) >= _MIN_NAME_LENGTH:
                return name
    return None


def _collect_identifiers(lines: tuple[TextLine, ...], name: str) -> frozenset[str]:
    """Gather the PHI strings that identify this patient in the document."""
    identifiers = {name}
    for line in lines:
        for pattern in _IDENTIFIER_PATTERNS:
            for match in pattern.finditer(line.text):
                value = match.group("value").strip()
                if len(value) >= 4:
                    identifiers.add(value)
    return frozenset(identifiers)


def classify(pages: tuple[ExtractedPage, ...]) -> tuple[PatientRecord, ...]:
    """Split a bulk EOB into per-patient records.

    Returns:
        One :class:`PatientRecord` per patient section, in document order.

    Raises:
        ClassificationError: no patient anchor was found, or the document
            structure is not coherent enough to attribute lines safely.
    """
    all_lines: list[TextLine] = []
    for page in pages:
        all_lines.extend(page.lines)

    if not all_lines:
        raise ClassificationError("no text lines to classify")

    # Find the anchor positions first, then slice. Two passes keeps the
    # boundary logic explicit rather than hidden in accumulator state.
    anchors: list[tuple[int, str]] = []
    for position, line in enumerate(all_lines):
        name = _match_anchor(line)
        if name is not None:
            anchors.append((position, name))

    if not anchors:
        raise ClassificationError(
            "no patient anchor line was found. This document does not match any "
            "known payer layout, so patient boundaries cannot be determined. "
            "Routed to Quarantine for human review rather than processed on a "
            "guessed boundary."
        )

    records: list[PatientRecord] = []
    for record_index, (start, name) in enumerate(anchors):
        end = anchors[record_index + 1][0] if record_index + 1 < len(anchors) else len(all_lines)
        section = tuple(all_lines[start:end])
        page_numbers = tuple(sorted({line.page_number for line in section}))
        records.append(
            PatientRecord(
                index=record_index,
                page_numbers=page_numbers,
                lines=section,
                identifiers=_collect_identifiers(section, name),
            )
        )

    _assert_coherent(records)
    return tuple(records)


def _assert_coherent(records: list[PatientRecord]) -> None:
    """Sanity-check the boundary structure before anything relies on it."""
    if not records:
        raise ClassificationError("classification produced no records")

    for record in records:
        if not record.page_numbers:
            raise ClassificationError(
                f"record {record.index} spans no pages, which means its lines "
                "could not be attributed to a page"
            )
        # A section whose pages are not contiguous suggests the anchors
        # matched something that is not a section header — a table
        # heading repeated in a footer, say. Redacting on that structure
        # would remove the wrong content.
        span = record.page_numbers
        if span[-1] - span[0] + 1 != len(span):
            raise ClassificationError(
                f"record {record.index} spans non-contiguous pages {span}. The "
                "anchor pattern likely matched a repeated header rather than a "
                "patient section; refusing to redact on this structure."
            )


def identifiers_of_others(
    records: tuple[PatientRecord, ...], target: PatientRecord
) -> frozenset[str]:
    """Return every identifier belonging to a patient other than ``target``.

    These are the strings redaction must remove and validation must fail
    to recover. Identifiers the target shares (a subscriber ID common to a
    family, for instance) are excluded — removing the target's own
    identifier from the target's own EOB would corrupt the record.
    """
    others: set[str] = set()
    for record in records:
        if record.index == target.index:
            continue
        others.update(record.identifiers)
    return frozenset(others - target.identifiers)
