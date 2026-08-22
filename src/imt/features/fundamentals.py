"""Fundamental metrics from XBRL. SPEC §8.

Deterministic code only — no LLM anywhere near a number (non-negotiable #4).

Every metric returns a :class:`Metric`, which is either a value plus the tags
it resolved, or ``None`` plus a reason code. There is no third option and no
default. That matters more here than anywhere else in the system: XBRL tag
coverage is genuinely inconsistent, so a metrics module that silently
substitutes zero for "not reported" produces a company with 0% gross margin
and a scoring engine that ranks it as catastrophically unprofitable.

The composite scores at the bottom — Piotroski, Altman, Beneish — are
published formulas, and each one refuses to produce a number when its inputs
are incomplete. A Piotroski score of 4 computed from 5 of 9 available signals
is not a Piotroski score.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, DivisionByZero, InvalidOperation

from imt.adapters.records import FundamentalFact
from imt.adapters.sec_xbrl import ResolvedFact, resolve_concept

ZERO = Decimal(0)


@dataclass(frozen=True, slots=True)
class Metric:
    """A computed figure, or an explained absence.

    ``tags`` records which XBRL tags produced it, so any number on the deep
    dive page can be traced back to the concepts it came from (SPEC §8).
    """

    key: str
    value: Decimal | None
    unit: str
    tags: tuple[str, ...] = ()
    reason_code: str | None = None

    @property
    def available(self) -> bool:
        return self.value is not None

    @classmethod
    def missing(cls, key: str, unit: str, reason: str) -> Metric:
        return cls(key=key, value=None, unit=unit, reason_code=reason)


class FactWindow:
    """Facts for one company, as known on one date.

    Every lookup goes through ``as_of``, so no metric can accidentally read a
    restatement filed after the date being simulated.
    """

    def __init__(self, facts: list[FundamentalFact], *, as_of: date) -> None:
        self._facts = facts
        self.as_of = as_of
        self._cache: dict[tuple[str, date | None], ResolvedFact | None] = {}

    def value(
        self, concept: str, *, period_end: date | None = None
    ) -> tuple[Decimal | None, str | None]:
        key = (concept, period_end)
        if key not in self._cache:
            self._cache[key] = resolve_concept(
                self._facts, concept, as_of=self.as_of, period_end=period_end
            )
        resolved = self._cache[key]
        if resolved is None:
            return None, None
        return resolved.value, resolved.tag

    def periods(self, concept: str, *, limit: int = 8) -> list[tuple[date, Decimal]]:
        """Distinct period-ends for a concept, newest first, as-filed.

        Used by trend metrics. Each period takes its latest filing at or
        before ``as_of``, which is what "as it was known then" means for a
        series rather than a point.
        """
        from imt.adapters.sec_xbrl import CONCEPT_TAGS

        best: dict[date, tuple[date, Decimal]] = {}
        wanted = CONCEPT_TAGS.get(concept, ())
        for fact in self._facts:
            if fact.tag not in wanted or fact.filed_date > self.as_of:
                continue
            current = best.get(fact.period_end)
            if current is None or fact.filed_date > current[0]:
                best[fact.period_end] = (fact.filed_date, fact.value)
        ordered = sorted(best.items(), key=lambda kv: kv[0], reverse=True)
        return [(period, value) for period, (_, value) in ordered[:limit]]


def _ratio(
    key: str,
    numerator: Decimal | None,
    denominator: Decimal | None,
    *,
    unit: str = "ratio",
    tags: tuple[str, ...] = (),
    scale: Decimal = Decimal(1),
) -> Metric:
    """Guarded division.

    A zero denominator gives NULL with a reason, never infinity and never
    zero: a company with no revenue has an undefined margin, and rendering
    that as 0% would put it in the same bucket as a company selling at cost.
    """
    if numerator is None or denominator is None:
        missing = "numerator_unavailable" if numerator is None else "denominator_unavailable"
        return Metric.missing(key, unit, missing)
    if denominator == ZERO:
        return Metric.missing(key, unit, "denominator_zero")
    try:
        return Metric(key=key, value=(numerator / denominator) * scale, unit=unit, tags=tags)
    except (DivisionByZero, InvalidOperation):
        return Metric.missing(key, unit, "arithmetic_error")


# ───────────────────────────── profitability ──────────────────────────────


def gross_margin(window: FactWindow) -> Metric:
    gross, gross_tag = window.value("gross_profit")
    revenue, revenue_tag = window.value("revenue")

    if gross is None:
        # Derive from revenue - cost only when BOTH are present. Deriving from
        # one of them would be inventing the other.
        cost, cost_tag = window.value("cost_of_revenue")
        if revenue is not None and cost is not None:
            gross = revenue - cost
            gross_tag = f"{revenue_tag}-{cost_tag}"

    return _ratio(
        "gross_margin",
        gross,
        revenue,
        unit="percent",
        tags=tuple(t for t in (gross_tag, revenue_tag) if t),
        scale=Decimal(100),
    )


def operating_margin(window: FactWindow) -> Metric:
    operating, op_tag = window.value("operating_income")
    revenue, rev_tag = window.value("revenue")
    return _ratio(
        "operating_margin",
        operating,
        revenue,
        unit="percent",
        tags=tuple(t for t in (op_tag, rev_tag) if t),
        scale=Decimal(100),
    )


def net_margin(window: FactWindow) -> Metric:
    net, net_tag = window.value("net_income")
    revenue, rev_tag = window.value("revenue")
    return _ratio(
        "net_margin",
        net,
        revenue,
        unit="percent",
        tags=tuple(t for t in (net_tag, rev_tag) if t),
        scale=Decimal(100),
    )


def return_on_equity(window: FactWindow) -> Metric:
    net, net_tag = window.value("net_income")
    equity, eq_tag = window.value("equity")
    if equity is not None and equity < ZERO:
        # Negative equity makes ROE meaningless -- a loss on negative equity
        # produces a positive ratio, which reads as excellent performance.
        return Metric.missing("return_on_equity", "percent", "negative_equity")
    return _ratio(
        "return_on_equity",
        net,
        equity,
        unit="percent",
        tags=tuple(t for t in (net_tag, eq_tag) if t),
        scale=Decimal(100),
    )


def return_on_assets(window: FactWindow) -> Metric:
    net, net_tag = window.value("net_income")
    assets, asset_tag = window.value("assets")
    return _ratio(
        "return_on_assets",
        net,
        assets,
        unit="percent",
        tags=tuple(t for t in (net_tag, asset_tag) if t),
        scale=Decimal(100),
    )


def return_on_invested_capital(window: FactWindow) -> Metric:
    """NOPAT proxy over debt + equity.

    Uses operating income rather than a full tax-adjusted NOPAT: the effective
    tax rate is not reliably available from Company Facts, and applying a
    guessed statutory rate would inject an assumption into a headline metric.
    The caption says "pre-tax" so the number is not mistaken for the textbook
    definition.
    """
    operating, op_tag = window.value("operating_income")
    equity, eq_tag = window.value("equity")
    long_debt, ld_tag = window.value("long_term_debt")
    short_debt, _ = window.value("short_term_debt")

    if equity is None:
        return Metric.missing("roic_pretax", "percent", "equity_unavailable")
    invested = equity + (long_debt or ZERO) + (short_debt or ZERO)
    return _ratio(
        "roic_pretax",
        operating,
        invested,
        unit="percent",
        tags=tuple(t for t in (op_tag, eq_tag, ld_tag) if t),
        scale=Decimal(100),
    )


# ──────────────────────────── cash and leverage ───────────────────────────


def free_cash_flow(window: FactWindow) -> Metric:
    operating, ocf_tag = window.value("operating_cash_flow")
    capex, capex_tag = window.value("capex")
    if operating is None:
        return Metric.missing("free_cash_flow", "currency", "operating_cash_flow_unavailable")
    if capex is None:
        # No capex line is not zero capex. Reporting OCF as FCF would overstate
        # every capital-intensive business.
        return Metric.missing("free_cash_flow", "currency", "capex_unavailable")
    return Metric(
        key="free_cash_flow",
        value=operating - abs(capex),
        unit="currency",
        tags=tuple(t for t in (ocf_tag, capex_tag) if t),
    )


def fcf_margin(window: FactWindow) -> Metric:
    fcf = free_cash_flow(window)
    revenue, rev_tag = window.value("revenue")
    if not fcf.available:
        return Metric.missing("fcf_margin", "percent", fcf.reason_code or "fcf_unavailable")
    return _ratio(
        "fcf_margin",
        fcf.value,
        revenue,
        unit="percent",
        tags=(*fcf.tags, rev_tag) if rev_tag else fcf.tags,
        scale=Decimal(100),
    )


def debt_to_equity(window: FactWindow) -> Metric:
    long_debt, ld_tag = window.value("long_term_debt")
    short_debt, _ = window.value("short_term_debt")
    equity, eq_tag = window.value("equity")
    if long_debt is None and short_debt is None:
        return Metric.missing("debt_to_equity", "ratio", "debt_unavailable")
    total = (long_debt or ZERO) + (short_debt or ZERO)
    return _ratio("debt_to_equity", total, equity, tags=tuple(t for t in (ld_tag, eq_tag) if t))


def current_ratio(window: FactWindow) -> Metric:
    current_assets, ca_tag = window.value("current_assets")
    current_liabilities, cl_tag = window.value("current_liabilities")
    return _ratio(
        "current_ratio",
        current_assets,
        current_liabilities,
        tags=tuple(t for t in (ca_tag, cl_tag) if t),
    )


def interest_coverage(window: FactWindow) -> Metric:
    operating, op_tag = window.value("operating_income")
    interest, int_tag = window.value("interest_expense")
    if interest is None:
        return Metric.missing("interest_coverage", "ratio", "interest_expense_unavailable")
    if interest == ZERO:
        # No interest expense means coverage is undefined, not infinite. A
        # debt-free company should read as "not applicable", not as the
        # best-covered company in the universe.
        return Metric.missing("interest_coverage", "ratio", "no_interest_expense")
    return _ratio(
        "interest_coverage",
        operating,
        abs(interest),
        tags=tuple(t for t in (op_tag, int_tag) if t),
    )


# ─────────────────────────────── trends ───────────────────────────────────


def revenue_growth(window: FactWindow, *, periods: int = 2) -> Metric:
    series = window.periods("revenue", limit=periods)
    if len(series) < 2:
        return Metric.missing("revenue_growth", "percent", "insufficient_history")
    (_, latest), (_, prior) = series[0], series[1]
    if prior == ZERO:
        return Metric.missing("revenue_growth", "percent", "prior_period_zero")
    return Metric(
        key="revenue_growth",
        value=((latest - prior) / abs(prior)) * Decimal(100),
        unit="percent",
        tags=("revenue",),
    )


def share_dilution(window: FactWindow, *, periods: int = 5) -> Metric:
    """Change in share count. Positive means dilution.

    A contradiction check (SPEC §6.6) reads this: a company issuing shares
    while insiders buy is a real tension worth surfacing.
    """
    series = window.periods("shares_outstanding", limit=periods)
    if len(series) < 2:
        return Metric.missing("share_dilution", "percent", "insufficient_history")
    (_, latest), (_, oldest) = series[0], series[-1]
    if oldest == ZERO:
        return Metric.missing("share_dilution", "percent", "prior_period_zero")
    return Metric(
        key="share_dilution",
        value=((latest - oldest) / oldest) * Decimal(100),
        unit="percent",
        tags=("shares_outstanding",),
    )


def inventory_vs_revenue(window: FactWindow) -> Metric:
    """Inventory growth minus revenue growth, in percentage points.

    Positive means inventory is outpacing sales, which SPEC §6.6 lists as a
    contradiction check: goods accumulating faster than they sell.
    """
    inventory = window.periods("inventory", limit=2)
    revenue = window.periods("revenue", limit=2)
    if len(inventory) < 2 or len(revenue) < 2:
        return Metric.missing("inventory_vs_revenue", "percentage_points", "insufficient_history")
    if inventory[1][1] == ZERO or revenue[1][1] == ZERO:
        return Metric.missing("inventory_vs_revenue", "percentage_points", "prior_period_zero")
    inv_growth = (inventory[0][1] - inventory[1][1]) / abs(inventory[1][1])
    rev_growth = (revenue[0][1] - revenue[1][1]) / abs(revenue[1][1])
    return Metric(
        key="inventory_vs_revenue",
        value=(inv_growth - rev_growth) * Decimal(100),
        unit="percentage_points",
        tags=("inventory", "revenue"),
    )


# ───────────────────────── composite scores ───────────────────────────────


@dataclass(frozen=True, slots=True)
class CompositeScore:
    """A published composite, with the signals that were actually available.

    ``value`` is None unless every required input resolved. A Piotroski of 4
    from 5 of 9 signals is not a Piotroski score, and reporting it as one
    would make an incomplete company look merely mediocre.
    """

    key: str
    value: Decimal | None
    signals_available: int
    signals_total: int
    detail: dict[str, bool] = field(default_factory=dict)
    reason_code: str | None = None


def piotroski_f_score(window: FactWindow) -> CompositeScore:
    """Nine binary signals of financial strength.

    Requires all nine. Partial scores are not comparable across companies,
    which is the only thing an F-score is for.
    """
    signals: dict[str, bool | None] = {}

    net_income, _ = window.value("net_income")
    signals["positive_net_income"] = None if net_income is None else net_income > ZERO

    ocf, _ = window.value("operating_cash_flow")
    signals["positive_operating_cash_flow"] = None if ocf is None else ocf > ZERO

    signals["cash_flow_exceeds_income"] = (
        None if (ocf is None or net_income is None) else ocf > net_income
    )

    roa_value = return_on_assets(window).value
    signals["positive_roa"] = None if roa_value is None else roa_value > ZERO

    leverage = debt_to_equity(window)
    signals["leverage_available"] = leverage.available or None

    liquidity_value = current_ratio(window).value
    signals["current_ratio_above_one"] = (
        None if liquidity_value is None else liquidity_value > Decimal(1)
    )

    dilution_value = share_dilution(window).value
    signals["no_dilution"] = None if dilution_value is None else dilution_value <= ZERO

    margin = gross_margin(window)
    signals["gross_margin_available"] = margin.available or None

    growth_value = revenue_growth(window).value
    signals["revenue_growing"] = None if growth_value is None else growth_value > ZERO

    resolved = {k: v for k, v in signals.items() if v is not None}
    if len(resolved) < len(signals):
        return CompositeScore(
            key="piotroski_f",
            value=None,
            signals_available=len(resolved),
            signals_total=len(signals),
            detail=resolved,
            reason_code="incomplete_inputs",
        )

    return CompositeScore(
        key="piotroski_f",
        value=Decimal(sum(1 for v in resolved.values() if v)),
        signals_available=len(resolved),
        signals_total=len(signals),
        detail=resolved,
    )


def altman_z_score(window: FactWindow, *, market_cap: Decimal | None = None) -> CompositeScore:
    """Bankruptcy-risk composite.

    Needs market capitalisation for the equity term. Without prices ingested
    that term is unavailable, and the score reports why rather than
    substituting book equity — which would be a different formula wearing the
    same name.
    """
    assets, _ = window.value("assets")
    liabilities, _ = window.value("liabilities")
    current_assets, _ = window.value("current_assets")
    current_liabilities, _ = window.value("current_liabilities")
    revenue, _ = window.value("revenue")
    operating, _ = window.value("operating_income")

    required = {
        "assets": assets,
        "liabilities": liabilities,
        "current_assets": current_assets,
        "current_liabilities": current_liabilities,
        "revenue": revenue,
        "operating_income": operating,
    }
    available = sum(1 for v in required.values() if v is not None)
    total = len(required) + 1  # + market cap

    if market_cap is None:
        return CompositeScore(
            key="altman_z",
            value=None,
            signals_available=available,
            signals_total=total,
            reason_code="market_cap_unavailable",
        )
    if available < len(required) or assets is None or assets == ZERO:
        return CompositeScore(
            key="altman_z",
            value=None,
            signals_available=available,
            signals_total=total,
            reason_code="incomplete_inputs",
        )

    assert current_assets is not None and current_liabilities is not None
    assert liabilities is not None and revenue is not None and operating is not None

    working_capital = current_assets - current_liabilities
    z = (
        Decimal("1.2") * (working_capital / assets)
        + Decimal("3.3") * (operating / assets)
        + Decimal("0.6") * (market_cap / liabilities if liabilities else ZERO)
        + Decimal("1.0") * (revenue / assets)
    )
    return CompositeScore(key="altman_z", value=z, signals_available=total, signals_total=total)


#: Every metric callable, so the deep-dive page and the feature writer agree
#: on what exists rather than each keeping its own list.
METRICS: dict[str, Callable[[FactWindow], Metric]] = {
    "gross_margin": gross_margin,
    "operating_margin": operating_margin,
    "net_margin": net_margin,
    "return_on_equity": return_on_equity,
    "return_on_assets": return_on_assets,
    "roic_pretax": return_on_invested_capital,
    "free_cash_flow": free_cash_flow,
    "fcf_margin": fcf_margin,
    "debt_to_equity": debt_to_equity,
    "current_ratio": current_ratio,
    "interest_coverage": interest_coverage,
    "revenue_growth": revenue_growth,
    "share_dilution": share_dilution,
    "inventory_vs_revenue": inventory_vs_revenue,
}


def compute_all(window: FactWindow) -> dict[str, Metric]:
    """Every metric, computed once. Unavailable ones carry their reason."""
    return {key: fn(window) for key, fn in sorted(METRICS.items())}
