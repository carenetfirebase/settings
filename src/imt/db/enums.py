"""Enumerations shared by the schema and the API surface.

These are Postgres enums, not free-text columns, so a typo is a constraint
violation at write time rather than a category that quietly never matches.
"""

from __future__ import annotations

from enum import StrEnum


class DataQuality(StrEnum):
    """SPEC §10. Every panel knows the state of its feed."""

    CURRENT = "current"
    DELAYED = "delayed"
    STALE = "stale"
    UNAVAILABLE = "unavailable"
    ESTIMATED = "estimated"
    MANUALLY_IMPORTED = "manually_imported"


class SignalCategory(StrEnum):
    """SPEC §6.3 independence buckets. Convergence is measured across these."""

    CORPORATE_INSIDER = "corporate_insider"
    POLITICAL = "political"
    INSTITUTIONAL = "institutional"
    GOVERNMENT = "government"
    CORPORATE_EVENT = "corporate_event"
    FUNDAMENTAL = "fundamental"
    VALUATION = "valuation"
    POSITIONING = "positioning"
    MACRO_SECTOR = "macro_sector"
    CREDIT = "credit"


CATEGORY_LABELS: dict[SignalCategory, str] = {
    SignalCategory.CORPORATE_INSIDER: "Insider Conviction",
    SignalCategory.POLITICAL: "Political Activity",
    SignalCategory.INSTITUTIONAL: "Institutional Activity",
    SignalCategory.GOVERNMENT: "Government Business",
    SignalCategory.CORPORATE_EVENT: "Catalyst Strength",
    SignalCategory.FUNDAMENTAL: "Fundamental Quality",
    SignalCategory.VALUATION: "Valuation",
    SignalCategory.POSITIONING: "Positioning",
    SignalCategory.MACRO_SECTOR: "Macro Alignment",
    SignalCategory.CREDIT: "Credit",
}

# Categories whose events describe a transaction that happened before it became
# public. For these, both dates are mandatory -- enforced by a CHECK constraint
# on signal_events, not by convention (CLAUDE.md non-negotiable #5).
DATED_CATEGORIES: frozenset[SignalCategory] = frozenset(
    {
        SignalCategory.CORPORATE_INSIDER,
        SignalCategory.POLITICAL,
        SignalCategory.INSTITUTIONAL,
    }
)


class NormalizationMethod(StrEnum):
    """SPEC §6.2. A threshold score is a hypothesis; a percentile is an observation."""

    PERCENTILE = "percentile"
    FALLBACK_THRESHOLD = "fallback_threshold"


class CompanyStatus(StrEnum):
    ACTIVE = "active"
    DELISTED = "delisted"
    ACQUIRED = "acquired"
    MERGED = "merged"


class OwnerType(StrEnum):
    """Congressional disclosures cover more than the filer (SPEC §8).

    Collapsing these into one actor is what makes "Senator X bought" wrong when
    the filing describes a dependent child's account.
    """

    SELF = "self"
    SPOUSE = "spouse"
    DEPENDENT = "dependent"
    JOINT = "joint"
    UNKNOWN = "unknown"


class ContradictionStatus(StrEnum):
    """docs/ARCHITECTURE.md §E.

    ``UNAVAILABLE`` is the whole point: a check whose input data has not been
    ingested yet must never be recorded as ``CLEAR``, because "we looked and
    found nothing" and "we did not look" are different claims and only one of
    them justifies a high score.
    """

    FIRED = "fired"
    CLEAR = "clear"
    UNAVAILABLE = "unavailable"


class IngestionStatus(StrEnum):
    RUNNING = "running"
    SUCCESS = "success"
    PARTIAL = "partial"
    FAILED = "failed"


class ParseOutcome(StrEnum):
    """Congressional PDF pipeline (DATA_SOURCES Tier 3)."""

    TEXT_EXTRACTED = "text_extracted"
    OCR = "ocr"
    REVIEW_QUEUED = "review_queued"
    FAILED = "failed"
    MANUAL_IMPORT = "manual_import"
