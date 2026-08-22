"""Per-source decay. SPEC §6.5.

    freshness = 0.5 ^ (age_days / half_life)

Never a single shared function: a 13F is up to 45 days stale on arrival and a
Form 4 is filed within two business days, so decaying them at the same rate
would treat quarterly position reporting as though it were news.

**Congressional age is measured from the transaction date, not the disclosure
date.** This is the load-bearing decision in the whole module. A PTR disclosed
today may cover a trade made 45 days ago; measuring from disclosure would
reset the clock and present a six-week-old trade as fresh, which is exactly
the failure UI_SPEC correction #2 and CLAUDE.md non-negotiable #5 exist to
prevent. Disclosure lag is a penalty, not a reset.
"""

from __future__ import annotations

from datetime import date

from imt.scoring.categories import SCORE_PRECISION
from imt.scoring.weights import Weights

#: Event types whose age is measured from the transaction, because the
#: disclosure can lag it by weeks. Everything else is measured from when it
#: became public, which for a Form 4 is within two business days anyway.
DECAY_FROM_TRANSACTION = frozenset({"congressional_ptr", "thirteen_f"})


def freshness(
    event_type: str,
    *,
    as_of: date,
    transaction_date: date,
    disclosure_date: date | None,
    weights: Weights,
) -> float:
    """0-100 freshness for one event.

    ``as_of`` is an argument, never ``date.today()`` — an AST-level test
    asserts no module in this package calls the clock (SPEC §7.5).
    """
    half_life = weights.half_life(event_type)
    if half_life <= 0:
        raise ValueError(f"half-life for {event_type!r} must be positive, got {half_life}")

    anchor = (
        transaction_date
        if event_type in DECAY_FROM_TRANSACTION or disclosure_date is None
        else disclosure_date
    )
    age_days = max((as_of - anchor).days, 0)
    decayed: float = 100.0 * (0.5 ** (age_days / half_life))
    return round(decayed, SCORE_PRECISION)


def disclosure_lag_days(transaction_date: date, disclosure_date: date) -> int:
    """Computed in Python and returned by the API.

    The frontend formats; it never calculates (non-negotiable #8), so this
    number is not two dates the client subtracts.
    """
    return max((disclosure_date - transaction_date).days, 0)
