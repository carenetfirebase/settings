"""Fail-closed error hierarchy.

Master prompt §13: FAIL = STOP PROCESSING. Every error defined here is a
halt condition, not a warning. Nothing in this package catches
``SecondaryEOBError`` and continues; the pipeline runner catches it only
to record the halt in the audit log and re-raise.

Master prompt §14: never expose PHI in debug output. Exception messages
are part of debug output, so no exception in this package may carry a
patient name, DOB, member ID, or any raw extracted text. Refer to
documents by job ID and content hash instead.
"""

from __future__ import annotations


class SecondaryEOBError(Exception):
    """Base for every halt condition in the system.

    Carries no PHI. Subclasses must keep that property: build messages
    from job IDs, hashes, page numbers, and counts — never from document
    content.
    """


# --- Configuration and deployment -------------------------------------


class ConfigError(SecondaryEOBError):
    """The deployment is misconfigured in a way that is unsafe to run."""


class UnsafeWorkingDirectoryError(ConfigError):
    """Working directory sits inside a third-party sync client's folder.

    Plan §F, security risks: a cloud-synced working directory exfiltrates
    PHI outside every control this application enforces, and the
    application cannot police a sync client running in another process.
    The only safe response is to refuse to start.
    """


# --- Encryption (§1) ---------------------------------------------------


class EncryptionError(SecondaryEOBError):
    """Encryption or decryption failed, or a key could not be unwrapped."""


class PlaintextPHIError(EncryptionError):
    """A PHI-bearing write was attempted outside the encrypted vault.

    Master prompt §1.1: no plaintext PHI storage outside active
    processing memory.
    """


# --- Authentication and authorization (§2) -----------------------------


class AuthenticationError(SecondaryEOBError):
    """The acting identity could not be established."""


class AuthorizationError(SecondaryEOBError):
    """The authenticated principal is not permitted this action.

    Raised by the guard on every denied zone access. Because enforcement
    is programmatic rather than UI-level (master prompt §2.2), this is
    raised from the data-access path itself, so there is no code route
    that reaches a file after a denial.
    """


# --- Audit (§3) --------------------------------------------------------


class AuditError(SecondaryEOBError):
    """The audit log could not be written."""


class AuditIntegrityError(AuditError):
    """The audit hash chain does not verify — possible tampering.

    Master prompt §13 lists audit log tampering as a fail-closed
    condition. A broken chain means the record of what happened to PHI is
    no longer trustworthy, so processing stops rather than appending to a
    log nobody can rely on.
    """


class PHIInAuditError(AuditError):
    """An audit entry payload looked like it carried PHI.

    Backstop for master prompt §14 ("never store PHI in logs"). See
    ``audit.log._assert_phi_free`` for what this can and cannot catch.
    """


# --- Document processing ----------------------------------------------


class CorruptDocumentError(SecondaryEOBError):
    """The PDF could not be opened or is structurally unusable."""


class ExtractionError(SecondaryEOBError):
    """Text could not be extracted from the document."""


class ClassificationError(SecondaryEOBError):
    """Patient record boundaries could not be determined deterministically.

    Not a guess-and-continue condition: an unresolved boundary means the
    system does not know which pages belong to which patient, and
    redacting on a wrong boundary is exactly the failure this product
    exists to prevent.
    """


class ParseError(SecondaryEOBError):
    """A required field could not be parsed deterministically."""


# --- Redaction and validation (§10) ------------------------------------


class RedactionError(SecondaryEOBError):
    """Redaction could not be applied."""


class RedactionValidationError(RedactionError):
    """Post-redaction validation recovered PHI that should have been removed.

    Master prompt §10: if ANY PHI is found after redaction, BLOCK EXPORT
    and FLAG FAILURE. This is the single most important halt in the
    system — it is the difference between a sanitized document and a
    breach.
    """


class PHIExposureError(SecondaryEOBError):
    """PHI exposure was detected. Export halts (master prompt §6)."""


# --- Lifecycle (§5) ----------------------------------------------------


class RetentionError(SecondaryEOBError):
    """A retention or deletion operation could not be verified."""


class DeletionVerificationError(RetentionError):
    """A file that was deleted is still recoverable or still indexed.

    Master prompt §5.2 requires deletion be *verified*, not assumed. An
    unlink that leaves the data readable is not a deletion.
    """


# --- LLM (§8) ----------------------------------------------------------


class LLMError(SecondaryEOBError):
    """Base for LLM-boundary violations.

    The MVP ships with no LLM integration (plan §E defers it), but the
    boundary errors are defined now so that any future integration has to
    fail closed against an existing contract rather than inventing its
    own more permissive one.
    """


class LLMZoneViolationError(LLMError):
    """An LLM call was attempted with data from outside Zone B.

    Master prompt §9: the LLM may ONLY access Zone B (anonymized subset).
    """


class LLMOutputError(LLMError):
    """LLM output failed strict JSON validation after the permitted retry.

    Master prompt §8.3: invalid output is rejected, retried once, and
    otherwise marked REVIEW REQUIRED.
    """
