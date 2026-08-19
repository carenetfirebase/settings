"""Zone B data structures.

These hold PHI in memory during processing and are never serialized to
disk in the clear (master prompt §1.3). ``__repr__`` is suppressed on the
PHI-bearing fields so that an accidental log, traceback, or debugger dump
does not print a patient's name — master prompt §14, "never expose PHI in
debug output", applies to the objects themselves, not only to the code
that handles them.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from decimal import Decimal


@dataclass(frozen=True)
class TextLine:
    """One extracted line of text with its position on the page.

    The bounding box is what redaction acts on: to remove a line
    permanently you have to know where it sits, not just what it says.
    """

    page_number: int
    text: str = field(repr=False)
    x0: float
    y0: float
    x1: float
    y1: float

    @property
    def bbox(self) -> tuple[float, float, float, float]:
        return (self.x0, self.y0, self.x1, self.y1)


@dataclass(frozen=True)
class ExtractedPage:
    """The text layer of one page."""

    page_number: int
    lines: tuple[TextLine, ...] = field(repr=False)
    #: True when the page carried no extractable text layer, which for a
    #: scanned EOB means OCR would be required. The MVP does not OCR for
    #: extraction (plan §E defers it), so such a page is a halt, not a
    #: silently-empty page.
    is_image_only: bool = False

    @property
    def text(self) -> str:
        return "\n".join(line.text for line in self.lines)


@dataclass(frozen=True)
class ClaimLine:
    """One claim/service line parsed deterministically from an EOB.

    Every monetary field is a :class:`~decimal.Decimal` parsed from the
    document, or ``None``. Nothing is inferred, defaulted to zero, or
    computed to fill a gap: master prompt §8.4 forbids the LLM from
    calculating financial values, and the deterministic path holds itself
    to the same standard — a number this system reports is a number that
    was printed on the EOB.
    """

    procedure_code: str | None = None
    service_date: str | None = None
    billed: Decimal | None = None
    allowed: Decimal | None = None
    paid: Decimal | None = None
    patient_responsibility: Decimal | None = None
    #: Set when a field was present but could not be parsed unambiguously.
    needs_review: bool = False
    review_reason: str | None = None


@dataclass
class PatientRecord:
    """One patient's section within a bulk multi-patient EOB.

    ``identifiers`` are the strings that mark this patient in the
    document — name as printed, member ID, subscriber ID. Redaction uses
    *other* records' identifiers as search terms to remove, and validation
    uses them again as the terms it tries to recover. They are PHI and are
    excluded from ``repr``.
    """

    #: Index of this record within the source document, 0-based.
    index: int
    #: Pages this record spans, 1-based, in document order.
    page_numbers: tuple[int, ...]
    #: Lines belonging to this record, across all its pages.
    lines: tuple[TextLine, ...] = field(repr=False)
    #: PHI strings identifying this patient.
    identifiers: frozenset[str] = field(default_factory=frozenset, repr=False)
    claims: tuple[ClaimLine, ...] = field(default_factory=tuple, repr=False)

    @property
    def pseudonym(self) -> str:
        """A stable, non-reversing handle for logs and filenames.

        Derived from the identifiers, so the same patient in the same
        document always gets the same handle, but the handle does not
        reveal who they are. Used wherever a name would otherwise end up
        in a log line or an output filename.

        This is a pseudonym, not de-identification: it is stable and
        derived from PHI, so anyone holding both this value and the source
        document can correlate them. It keeps PHI out of logs and
        filenames; it is not a Safe Harbor de-identification method.
        """
        material = "".join(sorted(self.identifiers)) or f"index:{self.index}"
        return "pt-" + hashlib.sha256(material.encode("utf-8")).hexdigest()[:12]

    @property
    def needs_review(self) -> bool:
        return any(claim.needs_review for claim in self.claims)
