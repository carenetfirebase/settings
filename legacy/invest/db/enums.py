"""Controlled vocabularies shared by the schema and the application.

Stored as VARCHAR + CHECK constraint rather than native PG ENUM types:
adding a value later is a one-line constraint change instead of an
`ALTER TYPE` that cannot run inside a transaction.
"""

from enum import StrEnum


class ValueType(StrEnum):
    """Ground rule 7: every stored value declares what kind of thing it is."""

    OBSERVED = "observed"  # came off a filing/feed exactly as published
    CALCULATED = "calculated"  # deterministic Python math over observed values
    ESTIMATED = "estimated"  # modelled assumption (e.g. a DCF growth input)
    AI_INTERPRETED = "ai_interpreted"  # LLM output — interpretation, never fact


class DataQualityFlag(StrEnum):
    OK = "ok"
    UNVERIFIED_BOOTSTRAP = "unverified_bootstrap"  # seeded offline, awaiting source confirmation
    MISSING = "missing"  # value could not be retrieved — stored NULL, never guessed
    QUARANTINED = "quarantined"  # failed the validation gate
    STALE = "stale"
    CONFLICTED = "conflicted"  # sources disagree beyond tolerance
    SUSPECT_UNIT = "suspect_unit"
    PREMIUM_DEPENDENT = "premium_dependent"  # needs a data source V1 does not have


class FirewallStatus(StrEnum):
    """Political trade disclosures are research/context only."""

    INVESTIGATE_ONLY = "investigate_only"
    EXCLUDED = "excluded"


class ConflictType(StrEnum):
    CROSS_SOURCE_DISAGREEMENT = "cross_source_disagreement"
    IMPOSSIBLE_VALUE = "impossible_value"
    TIMESTAMP_SANITY = "timestamp_sanity"
    UNIT_MISMATCH = "unit_mismatch"
    DUPLICATE = "duplicate"
    STALENESS = "staleness"
    ADJUSTMENT_INCONSISTENCY = "adjustment_inconsistency"


class Severity(StrEnum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


class JobStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class EntityType(StrEnum):
    COMPANY = "company"
    FUND = "fund"
    INDEX = "index"
    GOVERNMENT = "government"


def values(enum_cls: type[StrEnum]) -> list[str]:
    """Member values, for building CHECK constraints."""
    return [m.value for m in enum_cls]
