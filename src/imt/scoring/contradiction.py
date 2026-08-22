"""Contradiction. SPEC §6.6, and docs/ARCHITECTURE.md §E.

Every thesis searches for its own disconfirmation:

    Contradiction = 100 * (1 - Π_k (1 - c_k/100))

Contradiction **reduces** Research Priority multiplicatively and is never
netted into it. It is displayed as its own column, always, even at zero
(UI_SPEC correction #8).

## Why this is a registry

SPEC §6.6 lists thirteen checks. Only three of them can be computed from Phase
2 data — CEO/CFO selling, executive departure, and immaterial insider
purchase. The rest need fundamentals (Phase 5), prices and short interest
(Phase 7), or government awards (Phase 6).

Built naively, the engine would report Contradiction 0 for a company whose
balance sheet it has never looked at. That is worse than reporting nothing: a
zero in a column headed "Contradiction" is a claim that the system searched
and found no disconfirming evidence, and it would push exactly the companies
with the least scrutiny to the top of the ranking.

So a check resolves to one of three states, and **unavailable is not clear**:

* ``FIRED``       — the check ran and found disconfirming evidence
* ``CLEAR``       — the check ran and found none
* ``UNAVAILABLE`` — the data it needs has not been ingested

Unavailable checks are excluded from the product (they cannot contribute
severity they did not measure) and reduce ``DataQuality``, which multiplies
Research Priority. A company most of whose checks could not run therefore
cannot rank highly — which is the mechanism SPEC §10 already specifies,
applied to contradiction coverage.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import date
from typing import Any

from imt.db.enums import ContradictionStatus
from imt.scoring.categories import SCORE_PRECISION
from imt.scoring.weights import Weights


@dataclass(frozen=True, slots=True)
class CheckOutcome:
    check_id: str
    status: ContradictionStatus
    severity: float
    detail: str | None = None
    source_url: str | None = None

    @property
    def contributes(self) -> bool:
        return self.status is ContradictionStatus.FIRED


@dataclass(frozen=True, slots=True)
class ContradictionResult:
    score: float
    outcomes: tuple[CheckOutcome, ...]
    checks_available: int
    checks_total: int

    @property
    def coverage(self) -> float:
        """Share of declared checks that could actually run.

        Feeds DataQuality. A contradiction score computed from 3 of 13 checks
        is not the same claim as one computed from 13 of 13, and the difference
        has to reach the score rather than only the tooltip.
        """
        if self.checks_total == 0:
            return 0.0
        return round(self.checks_available / self.checks_total, SCORE_PRECISION)

    @property
    def fired(self) -> tuple[CheckOutcome, ...]:
        return tuple(o for o in self.outcomes if o.contributes)


#: A check receives the fact set and the as-of date, and returns either a
#: (fired, detail, source_url) triple or None for "ran, found nothing".
CheckFn = Callable[[Mapping[str, Any], date], tuple[bool, str, str | None] | None]

_REGISTRY: dict[str, CheckFn] = {}


def register(check_id: str) -> Callable[[CheckFn], CheckFn]:
    def decorator(fn: CheckFn) -> CheckFn:
        _REGISTRY[check_id] = fn
        return fn

    return decorator


def registered_checks() -> frozenset[str]:
    return frozenset(_REGISTRY)


def evaluate(
    facts: Mapping[str, Any],
    as_of: date,
    weights: Weights,
    *,
    available_data: frozenset[str],
) -> ContradictionResult:
    """Run every declared check against the facts available.

    ``available_data`` names the datasets that have actually been ingested. A
    check whose ``requires`` list is not satisfied returns UNAVAILABLE without
    running — it is not asked to guess from absent data.
    """
    outcomes: list[CheckOutcome] = []

    # Sorted: the product below is floating-point, and order changes the last
    # bits. Phase 3 criterion 1 requires byte-identical reruns.
    for check_id in sorted(weights.contradiction_checks):
        config = weights.contradiction_checks[check_id]
        severity = float(config.get("severity", 0))
        requires = frozenset(config.get("requires", []))

        missing = requires - available_data
        implementation = _REGISTRY.get(check_id)

        if missing or implementation is None:
            reason = (
                f"requires {', '.join(sorted(missing))}" if missing else "check not implemented yet"
            )
            outcomes.append(
                CheckOutcome(
                    check_id=check_id,
                    status=ContradictionStatus.UNAVAILABLE,
                    severity=0.0,
                    detail=reason,
                )
            )
            continue

        verdict = implementation(facts, as_of)
        if verdict is None:
            outcomes.append(CheckOutcome(check_id, ContradictionStatus.CLEAR, 0.0))
            continue

        fired, detail, source_url = verdict
        outcomes.append(
            CheckOutcome(
                check_id=check_id,
                status=ContradictionStatus.FIRED if fired else ContradictionStatus.CLEAR,
                severity=severity if fired else 0.0,
                detail=detail,
                source_url=source_url,
            )
        )

    remaining = 1.0
    for outcome in outcomes:
        if outcome.contributes:
            remaining *= 1.0 - (outcome.severity / 100.0)

    available = sum(1 for o in outcomes if o.status is not ContradictionStatus.UNAVAILABLE)

    return ContradictionResult(
        score=round(100.0 * (1.0 - remaining), SCORE_PRECISION),
        outcomes=tuple(outcomes),
        checks_available=available,
        checks_total=len(weights.contradiction_checks),
    )


# ─────────────────────────── the Phase 2 checks ───────────────────────────
#
# Only these three are computable from insider and 8-K data. The other ten are
# declared in weights.yaml and report UNAVAILABLE until their phase lands.


@register("ceo_cfo_selling")
def _ceo_cfo_selling(facts: Mapping[str, Any], as_of: date) -> tuple[bool, str, str | None] | None:
    """The most direct disconfirmation: the people who know are selling.

    Open-market sales only. A code F disposition is tax withholding on a
    vesting grant — mechanical, not a decision — and treating it as bearish
    would fire this check on every routine vesting event.
    """
    sales = [
        s
        for s in facts.get("insider_sales", [])
        if s.get("role_rank", 0) >= 3 and s.get("transaction_code") == "S"
    ]
    if not sales:
        return None
    largest = max(sales, key=lambda s: (s.get("value_minor") or 0, s.get("date", "")))
    amount = (largest.get("value_minor") or 0) / 100
    return (
        True,
        f"{largest.get('role', 'Senior officer')} sold ${amount:,.0f} on {largest.get('date')}",
        largest.get("source_url"),
    )


@register("executive_departure")
def _executive_departure(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """8-K item 5.02. A departure alongside insider buying is a real tension."""
    departures = facts.get("executive_departures", [])
    if not departures:
        return None
    first = departures[0]
    return (
        True,
        f"Executive change disclosed {first.get('date')} (8-K item 5.02)",
        first.get("source_url"),
    )


@register("immaterial_insider_purchase")
def _immaterial_insider_purchase(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """A purchase too small to mean anything, relative to what they hold.

    A director buying $8,000 of a company where they already hold $40M is a
    gesture, not conviction, and without this check it scores the same as a
    material purchase. Fires when every purchase in the window moves the
    holder's position by less than 1%.
    """
    purchases = facts.get("insider_purchases", [])
    if not purchases:
        return None
    material = [
        p
        for p in purchases
        if (p.get("pct_of_existing_holding") or 0) >= 1.0
        or (p.get("value_minor") or 0) >= 25_000_00
    ]
    if material:
        return None
    largest = max(purchases, key=lambda p: p.get("value_minor") or 0)
    amount = (largest.get("value_minor") or 0) / 100
    return (
        True,
        f"Largest purchase ${amount:,.0f} is immaterial against existing holdings",
        largest.get("source_url"),
    )


# ───────────────────── the Phase 4 check (congressional) ──────────────────


@register("stale_congressional_disclosure")
def _stale_congressional_disclosure(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """A PTR whose transaction is old enough that the edge is likely gone.

    This is the check that argues against the political category from inside
    the political category. The STOCK Act allows 30-45 days and late filings
    are routine, so a disclosure covering a trade from two months ago is
    weaker evidence than its freshness score alone suggests -- and the
    contradiction column is where that gets said out loud.
    """
    lags = facts.get("congressional_lag_days") or []
    if not lags:
        return None
    worst = max(lags)
    if worst <= 45:
        return False, f"Longest disclosure lag {worst}d", None
    return (
        True,
        f"Disclosure lagged the transaction by {worst}d; the edge is likely priced in",
        facts.get("ptr_url"),
    )


# ─────────────────────── the Phase 5 checks (XBRL) ────────────────────────
#
# These become available once `xbrl_facts` is ingested. Until then they report
# UNAVAILABLE, which is why contradiction coverage rises phase by phase and
# DataQuality rises with it.


@register("share_dilution")
def _share_dilution(facts: Mapping[str, Any], as_of: date) -> tuple[bool, str, str | None] | None:
    """Issuing shares while insiders buy is a real tension.

    Fires above 5% over the trailing window: below that is ordinary
    compensation-plan issuance, and firing on it would flag nearly every
    company that grants equity.
    """
    value = facts.get("share_dilution_pct")
    if value is None:
        return None
    if value <= 5.0:
        return False, f"Share count changed {value:+.1f}%", None
    return True, f"Share count up {value:.1f}% over the trailing window", facts.get("filing_url")


@register("rising_debt")
def _rising_debt(facts: Mapping[str, Any], as_of: date) -> tuple[bool, str, str | None] | None:
    value = facts.get("debt_to_equity")
    if value is None:
        return None
    if value <= 2.0:
        return False, f"Debt/equity {value:.2f}", None
    return True, f"Debt/equity at {value:.2f}", facts.get("filing_url")


@register("falling_interest_coverage")
def _falling_interest_coverage(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """Below 3x, debt service starts constraining the business."""
    value = facts.get("interest_coverage")
    if value is None:
        return None
    if value >= 3.0:
        return False, f"Interest coverage {value:.1f}x", None
    return True, f"Interest coverage only {value:.1f}x", facts.get("filing_url")


@register("deteriorating_gross_margin")
def _deteriorating_gross_margin(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    value = facts.get("gross_margin_change_pp")
    if value is None:
        return None
    if value >= -2.0:
        return False, f"Gross margin {value:+.1f}pp", None
    return True, f"Gross margin down {abs(value):.1f}pp", facts.get("filing_url")


@register("inventory_outpacing_revenue")
def _inventory_outpacing_revenue(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """Goods accumulating faster than they sell."""
    value = facts.get("inventory_vs_revenue_pp")
    if value is None:
        return None
    if value <= 10.0:
        return False, f"Inventory vs revenue {value:+.1f}pp", None
    return True, f"Inventory growing {value:.1f}pp faster than revenue", facts.get("filing_url")


@register("negative_fcf_trend")
def _negative_fcf_trend(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    value = facts.get("fcf_margin")
    if value is None:
        return None
    if value >= 0:
        return False, f"FCF margin {value:+.1f}%", None
    return True, f"Free cash flow negative at {value:.1f}% of revenue", facts.get("filing_url")


# ────────────────────── the Phase 7 check (prices) ────────────────────────


@register("price_already_ran")
def _price_already_ran(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """SPEC §6.6: stock already up >50% in 90 days.

    Not a claim the move is unjustified -- only that the evidence arrived after
    the price did, which is worth seeing next to a high score.
    """
    value = facts.get("price_run_90d_pct")
    if value is None:
        return None
    if value <= 50.0:
        return False, f"90-day move {value:+.1f}%", None
    return True, f"Already up {value:.1f}% over 90 days", None


# ────────────── the Phase 6 and Phase 7 checks (last two) ─────────────────


@register("declining_government_awards")
def _declining_government_awards(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """Contract momentum turning down.

    Reads the same gated momentum the government category scores from, so a
    company whose awards were never resolved reports None here rather than
    firing on an absence it mistook for a decline.
    """
    value = facts.get("contract_yoy_pct")
    if value is None:
        return None
    if value >= -20.0:
        return False, f"Awards {value:+.0f}% year over year", None
    return True, f"Federal awards down {abs(value):.0f}% year over year", None


@register("rising_short_interest")
def _rising_short_interest(
    facts: Mapping[str, Any], as_of: date
) -> tuple[bool, str, str | None] | None:
    """Short interest building against the thesis.

    Measured in percentage points of shares outstanding, never of float
    (SPEC §4). Fires above +2pp, which is a real change rather than the noise
    of a bi-monthly snapshot.
    """
    change = facts.get("short_interest_change_pp")
    if change is None:
        return None
    if change <= 2.0:
        return False, f"Short interest {change:+.1f}pp", None
    level = facts.get("short_interest_pct_shares_outstanding")
    suffix = f", now {level:.1f}% of shares outstanding" if level is not None else ""
    return True, f"Short interest up {change:.1f}pp{suffix}", None
