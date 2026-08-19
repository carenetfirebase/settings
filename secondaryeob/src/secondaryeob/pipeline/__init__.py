"""The deterministic processing pipeline (master prompt §11).

    Intake -> Extraction -> Classification -> Parsing -> Redaction -> Validation -> Export

Every stage transition is gated by an authorization check and produces an
audit entry. No stage guesses: a stage that cannot determine its answer
deterministically raises rather than returning a plausible value.
"""

from __future__ import annotations

from .documents import ClaimLine, ExtractedPage, PatientRecord, TextLine
from .runner import JobResult, process_document

__all__ = [
    "ClaimLine",
    "ExtractedPage",
    "JobResult",
    "PatientRecord",
    "TextLine",
    "process_document",
]
