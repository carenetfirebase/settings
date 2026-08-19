"""Pipeline orchestration.

Sequences the stages, and at every transition performs the authorization
check and writes the audit entry that master prompt §11 requires. Halts
are recorded before they propagate, so the log shows *why* a document
stopped, not just that it did.

On any failure the source document is moved to Quarantine rather than
left in Incoming. A failed document that stays in the intake folder gets
picked up by the next run and fails again; a quarantined one is visible as
something a human has to look at.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from pathlib import Path

from ..audit import Action, Outcome
from ..audit.log import content_ref
from ..auth.guard import Guard
from ..auth.roles import Permission
from ..config import Settings
from ..errors import (
    ClassificationError,
    CorruptDocumentError,
    ExtractionError,
    RedactionValidationError,
    SecondaryEOBError,
)
from ..zones import Zone
from .classification import classify, identifiers_of_others
from .documents import PatientRecord
from .extraction import assert_text_layer_present, extract_pages, open_document
from .parsing import parse_claims
from .redaction import redact_to_single_patient
from .validation import ValidationReport, assert_safe_to_export, validate_redaction


@dataclass
class PatientOutcome:
    """What happened to one patient's record within a job."""

    #: Non-identifying handle. Safe for logs and filenames.
    pseudonym: str
    exported_path: Path | None = None
    blocked_reason: str | None = None
    needs_review: bool = False
    validation: ValidationReport | None = field(default=None, repr=False)

    @property
    def exported(self) -> bool:
        return self.exported_path is not None


@dataclass
class JobResult:
    """The result of processing one source document."""

    job_id: str
    source_ref: str
    patient_count: int = 0
    outcomes: list[PatientOutcome] = field(default_factory=list)
    quarantined: bool = False
    halt_reason: str | None = None

    @property
    def exported_count(self) -> int:
        return sum(1 for outcome in self.outcomes if outcome.exported)

    @property
    def blocked_count(self) -> int:
        return sum(1 for outcome in self.outcomes if outcome.blocked_reason)


def process_document(
    source_path: Path,
    guard: Guard,
    settings: Settings,
    *,
    require_ocr: bool = True,
) -> JobResult:
    """Run the full pipeline over one bulk EOB.

    Args:
        source_path: Encrypted source PDF in ``Incoming/`` (Zone A).
        guard: Authorization guard for the acting principal.
        settings: Resolved deployment settings.
        require_ocr: Passed through to validation. Leaving OCR out
            weakens the guarantee — see :func:`validate_redaction`.

    Returns:
        A :class:`JobResult`. Per-patient blocks are recorded in it rather
        than raised, because one patient's blocked export should not
        abandon the others. Document-level halts raise.
    """
    job_id = uuid.uuid4().hex[:16]
    job_guard = guard.for_job(job_id)
    result = JobResult(job_id=job_id, source_ref="-")

    # --- Intake (Zone A) ------------------------------------------------
    pdf_bytes = job_guard.read(source_path)
    source_ref = content_ref(pdf_bytes)
    result.source_ref = source_ref
    job_guard.record(
        Action.INTAKE,
        outcome=Outcome.SUCCESS,
        zone=Zone.A_RAW_PHI,
        target_ref=source_ref,
        detail={"bytes": len(pdf_bytes)},
    )

    try:
        # --- Extraction (Zone A) ----------------------------------------
        document = open_document(pdf_bytes)
        try:
            pages = extract_pages(document)
        finally:
            document.close()
        assert_text_layer_present(pages)
        job_guard.record(
            Action.EXTRACT,
            outcome=Outcome.SUCCESS,
            zone=Zone.A_RAW_PHI,
            target_ref=source_ref,
            detail={"pages": len(pages)},
        )

        # --- Classification (Zone A -> B) -------------------------------
        records = classify(pages)
        result.patient_count = len(records)
        job_guard.record(
            Action.CLASSIFY,
            outcome=Outcome.SUCCESS,
            zone=Zone.B_PROCESSING,
            target_ref=source_ref,
            detail={"patient_records": len(records)},
        )

        # --- Parsing (Zone B) -------------------------------------------
        records = tuple(
            PatientRecord(
                index=record.index,
                page_numbers=record.page_numbers,
                lines=record.lines,
                identifiers=record.identifiers,
                claims=parse_claims(record),
            )
            for record in records
        )
        job_guard.record(
            Action.PARSE,
            outcome=Outcome.SUCCESS,
            zone=Zone.B_PROCESSING,
            target_ref=source_ref,
            detail={
                "claim_lines": sum(len(r.claims) for r in records),
                "records_needing_review": sum(1 for r in records if r.needs_review),
            },
        )

    except (CorruptDocumentError, ExtractionError, ClassificationError) as exc:
        _quarantine(source_path, pdf_bytes, job_guard, settings, source_ref, exc)
        result.quarantined = True
        result.halt_reason = str(exc)
        raise

    # --- Redaction / Validation / Export, per patient -------------------
    for record in records:
        result.outcomes.append(
            _process_patient(
                pdf_bytes=pdf_bytes,
                records=records,
                record=record,
                job_guard=job_guard,
                settings=settings,
                source_ref=source_ref,
                require_ocr=require_ocr,
            )
        )

    return result


def _process_patient(
    *,
    pdf_bytes: bytes,
    records: tuple[PatientRecord, ...],
    record: PatientRecord,
    job_guard: Guard,
    settings: Settings,
    source_ref: str,
    require_ocr: bool,
) -> PatientOutcome:
    outcome = PatientOutcome(pseudonym=record.pseudonym, needs_review=record.needs_review)
    removed = identifiers_of_others(records, record)

    try:
        redacted = redact_to_single_patient(pdf_bytes, records, record)
        job_guard.record(
            Action.REDACT,
            outcome=Outcome.SUCCESS,
            zone=Zone.C_SANITIZED,
            target_ref=record.pseudonym,
            detail={"pages_kept": len(record.page_numbers), "tokens_removed": len(removed)},
        )
    except SecondaryEOBError as exc:
        outcome.blocked_reason = str(exc)
        job_guard.record(
            Action.REDACT,
            outcome=Outcome.FAILURE,
            zone=Zone.C_SANITIZED,
            target_ref=record.pseudonym,
            detail={"error": type(exc).__name__},
        )
        return outcome

    # --- Validation: try to get the PHI back ----------------------------
    report = validate_redaction(
        redacted, removed, record.identifiers, require_ocr=require_ocr
    )
    outcome.validation = report
    try:
        assert_safe_to_export(report)
    except RedactionValidationError as exc:
        outcome.blocked_reason = str(exc)
        job_guard.record(
            Action.VALIDATE,
            outcome=Outcome.BLOCKED,
            zone=Zone.C_SANITIZED,
            target_ref=record.pseudonym,
            detail={
                "recovered_tokens": report.recovered_count,
                "techniques_not_run": len(report.techniques_that_did_not_run),
            },
        )
        # Recovering PHI from a document the system believed it had
        # sanitized is a suspected exposure, not a routine validation
        # failure (master prompt §6).
        if report.recovered_count:
            job_guard.record(
                Action.BREACH_SUSPECTED,
                outcome=Outcome.BLOCKED,
                zone=Zone.C_SANITIZED,
                target_ref=record.pseudonym,
                detail={"recovered_tokens": report.recovered_count},
            )
        return outcome

    job_guard.record(
        Action.VALIDATE,
        outcome=Outcome.SUCCESS,
        zone=Zone.C_SANITIZED,
        target_ref=record.pseudonym,
        detail={"techniques": len(report.techniques)},
    )

    # --- Export (Zone C) ------------------------------------------------
    if record.needs_review:
        # Parsed with gaps. It is still safe to release — validation
        # passed — but a human confirms the figures first, so it does not
        # land in Ready/ where PAD would pick it up unattended.
        outcome.blocked_reason = "REVIEW REQUIRED: one or more claim fields could not be parsed"
        job_guard.record(
            Action.EXPORT,
            outcome=Outcome.REVIEW_REQUIRED,
            zone=Zone.C_SANITIZED,
            target_ref=record.pseudonym,
            detail={"claims_needing_review": sum(1 for c in record.claims if c.needs_review)},
        )
        return outcome

    job_guard.require(Permission.EXPORT, target_ref=record.pseudonym)
    destination = settings.path_for("Ready") / f"{source_ref[:12]}-{record.pseudonym}.pdf"
    job_guard.write(destination, redacted)
    outcome.exported_path = destination
    job_guard.record(
        Action.EXPORT,
        outcome=Outcome.SUCCESS,
        zone=Zone.C_SANITIZED,
        target_ref=record.pseudonym,
        detail={"bytes": len(redacted)},
    )
    return outcome


def _quarantine(
    source_path: Path,
    pdf_bytes: bytes,
    job_guard: Guard,
    settings: Settings,
    source_ref: str,
    error: Exception,
) -> None:
    """Move a failed document to Quarantine (still Zone A, still encrypted)."""
    destination = settings.path_for("Quarantine") / f"{source_ref[:12]}.pdf"
    try:
        job_guard.write(destination, pdf_bytes)
        source_path.unlink(missing_ok=True)
    except SecondaryEOBError:
        # Quarantine itself failed. The document stays in Incoming; the
        # audit entry below is what makes that visible.
        pass
    job_guard.record(
        Action.QUARANTINE,
        outcome=Outcome.FAILURE,
        zone=Zone.A_RAW_PHI,
        target_ref=source_ref,
        detail={"error": type(error).__name__},
    )
