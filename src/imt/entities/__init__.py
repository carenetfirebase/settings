"""Entity resolution — SPEC §5, "the crux".

Everything resolves to an SEC CIK or is quarantined in the review queue.
"""

from imt.entities.identifiers import (
    InvalidCIKError,
    looks_like_ticker,
    normalize_cik,
    normalize_ticker,
)
from imt.entities.normalize import name_tokens, normalize_name
from imt.entities.resolver import (
    CONFIDENCE_THRESHOLD,
    Candidate,
    EntityMatch,
    EntityResolver,
    MatchMethod,
    TickerMap,
    load_overrides,
)

__all__ = [
    "CONFIDENCE_THRESHOLD",
    "Candidate",
    "EntityMatch",
    "EntityResolver",
    "InvalidCIKError",
    "MatchMethod",
    "TickerMap",
    "load_overrides",
    "looks_like_ticker",
    "name_tokens",
    "normalize_cik",
    "normalize_name",
    "normalize_ticker",
]
