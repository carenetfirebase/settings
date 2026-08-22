"""The only sanctioned source of "now".

SPEC §7.5 forbids any scoring function from calling ``datetime.now()``: an
as-of date is always an argument, so a rerun of a historical date produces the
same answer today as it did last week. A test walks the AST of everything under
``imt.scoring`` and fails on a call to ``datetime.now``, ``date.today`` or
``time.time``.

Ingestion legitimately needs the wall clock — ``retrieved_at`` is a real
observation about when we fetched something — so it goes through here, where it
is greppable and mockable, instead of being scattered across adapters.
"""

from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

MARKET_TZ = ZoneInfo("America/New_York")


def utc_now() -> datetime:
    """Wall clock, UTC, timezone-aware. Never call this from scoring."""
    return datetime.now(UTC)


def market_now() -> datetime:
    """Wall clock in US market time, for the top bar's market clock only."""
    return datetime.now(MARKET_TZ)
