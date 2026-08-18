"""Valuation: DCF, reverse DCF, comparables, and sensitivity tables.

Everything a DCF produces is an *estimate*, built on assumptions that are
inputs rather than observations. That is not a caveat bolted on at the end —
it is why `DcfAssumptions` is a separate, explicit, serialized object stored in
the research snapshot. A valuation whose assumptions are not recorded cannot
be argued with, and a valuation that cannot be argued with is worthless.

The reverse DCF is arguably the more useful direction: instead of asking "what
is it worth?", it asks "what growth rate does today's price already assume?"
That question has a defensible answer, because the price is an observation.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import StrEnum

from invest.engines.quant import safe_divide


class Scenario(StrEnum):
    BEAR = "bear"
    BASE = "base"
    BULL = "bull"


@dataclass(frozen=True)
class DcfAssumptions:
    """Explicit, recorded, arguable.

    Stored verbatim in `research_snapshots.inputs_json` so any valuation can be
    reproduced or challenged months later.
    """

    growth_rate: float  # annual FCF growth during the forecast period
    terminal_growth_rate: float  # perpetual growth after it
    discount_rate: float  # WACC or required return
    forecast_years: int = 10
    margin_of_safety: float = 0.0

    def __post_init__(self) -> None:
        if self.forecast_years <= 0:
            raise ValueError("forecast_years must be positive")
        if self.discount_rate <= self.terminal_growth_rate:
            # The Gordon denominator (r - g) goes zero or negative, and the
            # model returns a huge or negative "value" that looks like a
            # result. Refuse instead.
            raise ValueError(
                f"discount_rate ({self.discount_rate:.4f}) must exceed terminal_growth_rate "
                f"({self.terminal_growth_rate:.4f}); otherwise the terminal value is infinite"
            )
        if self.terminal_growth_rate > 0.05:
            raise ValueError(
                "terminal_growth_rate above 5% implies the company eventually "
                "outgrows the whole economy"
            )
        if not 0.0 <= self.margin_of_safety < 1.0:
            raise ValueError("margin_of_safety must be in [0, 1)")


@dataclass
class DcfResult:
    """A DCF valuation with every intermediate exposed."""

    assumptions: DcfAssumptions
    projected_cash_flows: list[float] = field(default_factory=list)
    discounted_cash_flows: list[float] = field(default_factory=list)
    terminal_value: float | None = None
    discounted_terminal_value: float | None = None
    enterprise_value: float | None = None
    equity_value: float | None = None
    fair_value_per_share: float | None = None
    fair_value_with_margin: float | None = None
    upside: float | None = None  # vs current price
    insufficient_data_reason: str | None = None

    @property
    def is_valid(self) -> bool:
        return self.fair_value_per_share is not None

    @property
    def terminal_value_share(self) -> float | None:
        """Fraction of enterprise value coming from the terminal value.

        Reported because it is the single most important honesty check on a
        DCF: when 85% of the value sits in a perpetuity growth assumption,
        the "valuation" is mostly that one assumption.
        """
        if self.enterprise_value is None or self.discounted_terminal_value is None:
            return None
        if self.enterprise_value == 0:
            return None
        return self.discounted_terminal_value / self.enterprise_value

    def as_dict(self) -> dict:
        return {
            "assumptions": asdict(self.assumptions),
            "fair_value_per_share": self.fair_value_per_share,
            "fair_value_with_margin": self.fair_value_with_margin,
            "enterprise_value": self.enterprise_value,
            "equity_value": self.equity_value,
            "terminal_value": self.terminal_value,
            "discounted_terminal_value": self.discounted_terminal_value,
            "terminal_value_share": self.terminal_value_share,
            "upside": self.upside,
            "projected_cash_flows": self.projected_cash_flows,
            "discounted_cash_flows": self.discounted_cash_flows,
            "insufficient_data_reason": self.insufficient_data_reason,
            "value_type": "estimated",
        }


def discounted_cash_flow(
    *,
    base_free_cash_flow: float | None,
    assumptions: DcfAssumptions,
    shares_outstanding: float | None = None,
    net_debt: float | None = None,
    current_price: float | None = None,
) -> DcfResult:
    """Standard two-stage DCF.

    Stage 1 grows FCF at `growth_rate` for `forecast_years`.
    Stage 2 applies a Gordon terminal value at `terminal_growth_rate`.

    A negative base FCF returns INSUFFICIENT DATA rather than a negative fair
    value: growing a negative cash flow at a positive rate produces a
    confident-looking number with no economic meaning.
    """
    result = DcfResult(assumptions=assumptions)

    if base_free_cash_flow is None:
        result.insufficient_data_reason = "base free cash flow unavailable"
        return result
    if base_free_cash_flow <= 0:
        result.insufficient_data_reason = (
            "base free cash flow is not positive; a growth-based DCF cannot be "
            "applied to negative cash flows"
        )
        return result

    r = assumptions.discount_rate
    g = assumptions.growth_rate
    tg = assumptions.terminal_growth_rate

    projected: list[float] = []
    discounted: list[float] = []
    for year in range(1, assumptions.forecast_years + 1):
        cash_flow = base_free_cash_flow * ((1 + g) ** year)
        projected.append(cash_flow)
        discounted.append(cash_flow / ((1 + r) ** year))

    final_cash_flow = projected[-1]
    terminal_value = final_cash_flow * (1 + tg) / (r - tg)
    discounted_terminal = terminal_value / ((1 + r) ** assumptions.forecast_years)

    enterprise_value = sum(discounted) + discounted_terminal

    result.projected_cash_flows = projected
    result.discounted_cash_flows = discounted
    result.terminal_value = terminal_value
    result.discounted_terminal_value = discounted_terminal
    result.enterprise_value = enterprise_value

    equity_value = enterprise_value - (net_debt or 0.0)
    result.equity_value = equity_value

    if shares_outstanding is None or shares_outstanding <= 0:
        result.insufficient_data_reason = "share count unavailable; per-share value not computed"
        return result

    per_share = equity_value / shares_outstanding
    result.fair_value_per_share = per_share
    result.fair_value_with_margin = per_share * (1 - assumptions.margin_of_safety)

    if current_price is not None and current_price > 0:
        result.upside = per_share / current_price - 1.0

    return result


@dataclass
class ScenarioSet:
    """Bear / base / bull, each a full DCF with its own assumptions."""

    bear: DcfResult
    base: DcfResult
    bull: DcfResult

    def as_dict(self) -> dict:
        return {
            "bear": self.bear.as_dict(),
            "base": self.base.as_dict(),
            "bull": self.bull.as_dict(),
        }

    @property
    def fair_value_range(self) -> tuple[float, float] | None:
        values = [
            r.fair_value_per_share
            for r in (self.bear, self.base, self.bull)
            if r.fair_value_per_share is not None
        ]
        if not values:
            return None
        return min(values), max(values)


def scenario_dcf(
    *,
    base_free_cash_flow: float | None,
    base_assumptions: DcfAssumptions,
    shares_outstanding: float | None = None,
    net_debt: float | None = None,
    current_price: float | None = None,
    bear_growth_delta: float = -0.05,
    bull_growth_delta: float = 0.05,
    bear_discount_delta: float = 0.02,
    bull_discount_delta: float = -0.01,
) -> ScenarioSet:
    """Three scenarios varying growth AND discount rate together.

    Varying growth alone understates the spread: a pessimistic future usually
    arrives with a higher required return, not just slower growth.
    """

    def build(growth_delta: float, discount_delta: float) -> DcfResult:
        try:
            assumptions = DcfAssumptions(
                growth_rate=base_assumptions.growth_rate + growth_delta,
                terminal_growth_rate=base_assumptions.terminal_growth_rate,
                discount_rate=base_assumptions.discount_rate + discount_delta,
                forecast_years=base_assumptions.forecast_years,
                margin_of_safety=base_assumptions.margin_of_safety,
            )
        except ValueError as exc:
            failed = DcfResult(assumptions=base_assumptions)
            failed.insufficient_data_reason = f"scenario assumptions invalid: {exc}"
            return failed

        return discounted_cash_flow(
            base_free_cash_flow=base_free_cash_flow,
            assumptions=assumptions,
            shares_outstanding=shares_outstanding,
            net_debt=net_debt,
            current_price=current_price,
        )

    return ScenarioSet(
        bear=build(bear_growth_delta, bear_discount_delta),
        base=build(0.0, 0.0),
        bull=build(bull_growth_delta, bull_discount_delta),
    )


# --------------------------------------------------------------------------
# Reverse DCF
# --------------------------------------------------------------------------


@dataclass
class ReverseDcfResult:
    """The growth rate today's price implies."""

    implied_growth_rate: float | None
    market_price: float | None
    converged: bool = False
    iterations: int = 0
    insufficient_data_reason: str | None = None

    def as_dict(self) -> dict:
        return {
            "implied_growth_rate": self.implied_growth_rate,
            "market_price": self.market_price,
            "converged": self.converged,
            "iterations": self.iterations,
            "insufficient_data_reason": self.insufficient_data_reason,
            "value_type": "calculated",
        }

    def interpretation(self, historical_growth: float | None = None) -> str:
        if self.implied_growth_rate is None:
            return "INSUFFICIENT DATA"
        implied = f"The current price implies {self.implied_growth_rate:.1%} annual FCF growth"
        if historical_growth is None:
            return implied + "."
        if self.implied_growth_rate > historical_growth:
            return (
                f"{implied}, above the {historical_growth:.1%} actually delivered "
                f"historically — the price requires an acceleration."
            )
        return (
            f"{implied}, below the {historical_growth:.1%} delivered historically — "
            f"the price does not require growth to continue at past rates."
        )


def reverse_dcf(
    *,
    market_price: float | None,
    base_free_cash_flow: float | None,
    shares_outstanding: float | None,
    discount_rate: float,
    terminal_growth_rate: float = 0.025,
    forecast_years: int = 10,
    net_debt: float | None = None,
    tolerance: float = 1e-6,
    max_iterations: int = 200,
) -> ReverseDcfResult:
    """Solve for the growth rate that makes the DCF equal today's price.

    Bisection rather than Newton's method: the function is monotonic in growth
    over the bracket, and bisection cannot diverge. Slower, but this runs once
    per company, and a valuation engine that occasionally returns nonsense is
    worse than one that takes a millisecond longer.
    """
    if market_price is None or market_price <= 0:
        return ReverseDcfResult(None, market_price, insufficient_data_reason="no market price")
    if base_free_cash_flow is None or base_free_cash_flow <= 0:
        return ReverseDcfResult(
            None,
            market_price,
            insufficient_data_reason="base free cash flow is not positive",
        )
    if shares_outstanding is None or shares_outstanding <= 0:
        return ReverseDcfResult(
            None, market_price, insufficient_data_reason="share count unavailable"
        )

    def price_for_growth(growth: float) -> float | None:
        try:
            assumptions = DcfAssumptions(
                growth_rate=growth,
                terminal_growth_rate=terminal_growth_rate,
                discount_rate=discount_rate,
                forecast_years=forecast_years,
            )
        except ValueError:
            return None
        result = discounted_cash_flow(
            base_free_cash_flow=base_free_cash_flow,
            assumptions=assumptions,
            shares_outstanding=shares_outstanding,
            net_debt=net_debt,
        )
        return result.fair_value_per_share

    # The forecast period is finite, so stage-1 growth may legitimately exceed
    # the discount rate — only the TERMINAL growth is bounded by it, and
    # DcfAssumptions already enforces that. The bracket is therefore set by
    # what is economically sensible rather than by the discount rate: sustained
    # +100%/yr for the whole forecast is already beyond any real company, and
    # -90%/yr is effectively a wind-down.
    low, high = -0.90, 1.00

    low_price = price_for_growth(low)
    high_price = price_for_growth(high)
    if low_price is None or high_price is None:
        return ReverseDcfResult(
            None, market_price, insufficient_data_reason="could not evaluate the growth bracket"
        )

    if not (low_price <= market_price <= high_price):
        return ReverseDcfResult(
            None,
            market_price,
            insufficient_data_reason=(
                f"market price {market_price:,.2f} lies outside the achievable valuation range "
                f"[{low_price:,.2f}, {high_price:,.2f}] for growth in [{low:.0%}, {high:.0%}]"
            ),
        )

    iterations = 0
    for iterations in range(1, max_iterations + 1):
        mid = (low + high) / 2
        mid_price = price_for_growth(mid)
        if mid_price is None:
            return ReverseDcfResult(
                None, market_price, iterations=iterations,
                insufficient_data_reason="valuation failed mid-search",
            )
        if abs(mid_price - market_price) < tolerance * max(1.0, market_price):
            return ReverseDcfResult(mid, market_price, converged=True, iterations=iterations)
        if mid_price < market_price:
            low = mid
        else:
            high = mid

    return ReverseDcfResult((low + high) / 2, market_price, converged=False, iterations=iterations)


# --------------------------------------------------------------------------
# Sensitivity
# --------------------------------------------------------------------------


@dataclass
class SensitivityTable:
    """Fair value across a grid of growth and discount rates."""

    growth_rates: list[float]
    discount_rates: list[float]
    #: values[i][j] = fair value at discount_rates[i], growth_rates[j].
    values: list[list[float | None]]

    def as_dict(self) -> dict:
        return {
            "growth_rates": self.growth_rates,
            "discount_rates": self.discount_rates,
            "values": self.values,
            "value_type": "estimated",
        }

    @property
    def value_range(self) -> tuple[float, float] | None:
        flat = [v for row in self.values for v in row if v is not None]
        if not flat:
            return None
        return min(flat), max(flat)


def sensitivity_table(
    *,
    base_free_cash_flow: float | None,
    base_assumptions: DcfAssumptions,
    shares_outstanding: float | None,
    net_debt: float | None = None,
    growth_deltas: tuple[float, ...] = (-0.04, -0.02, 0.0, 0.02, 0.04),
    discount_deltas: tuple[float, ...] = (-0.02, -0.01, 0.0, 0.01, 0.02),
) -> SensitivityTable:
    """Grid the two assumptions the answer is most sensitive to.

    A single fair value invites false precision. The table shows how much of
    the "valuation" is really a choice of discount rate.
    """
    growth_rates = [base_assumptions.growth_rate + d for d in growth_deltas]
    discount_rates = [base_assumptions.discount_rate + d for d in discount_deltas]

    values: list[list[float | None]] = []
    for discount in discount_rates:
        row: list[float | None] = []
        for growth in growth_rates:
            try:
                assumptions = DcfAssumptions(
                    growth_rate=growth,
                    terminal_growth_rate=base_assumptions.terminal_growth_rate,
                    discount_rate=discount,
                    forecast_years=base_assumptions.forecast_years,
                )
            except ValueError:
                # Invalid combination (r <= g) is a hole in the grid, not a zero.
                row.append(None)
                continue
            result = discounted_cash_flow(
                base_free_cash_flow=base_free_cash_flow,
                assumptions=assumptions,
                shares_outstanding=shares_outstanding,
                net_debt=net_debt,
            )
            row.append(result.fair_value_per_share)
        values.append(row)

    return SensitivityTable(growth_rates, discount_rates, values)


# --------------------------------------------------------------------------
# Comparables
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Multiple:
    name: str
    value: float | None
    unavailable_reason: str | None = None

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "value": self.value,
            "unavailable_reason": self.unavailable_reason,
        }


@dataclass
class ComparablesResult:
    subject: dict[str, float | None]
    peer_medians: dict[str, float | None]
    premium_discount: dict[str, float | None]
    peer_count: int
    note: str | None = None

    def as_dict(self) -> dict:
        return {
            "subject": self.subject,
            "peer_medians": self.peer_medians,
            "premium_discount": self.premium_discount,
            "peer_count": self.peer_count,
            "note": self.note,
        }


def compute_multiples(
    *,
    price: float | None = None,
    market_cap: float | None = None,
    net_income: float | None = None,
    revenue: float | None = None,
    book_value: float | None = None,
    free_cash_flow: float | None = None,
    ebitda: float | None = None,
    net_debt: float | None = None,
) -> dict[str, float | None]:
    """Valuation multiples, with None where the input is missing or the
    multiple would be meaningless.

    A P/E on negative earnings is the classic trap: -15x is not "cheap", it is
    undefined, so it comes back as None rather than a negative number that
    would sort to the top of a "cheapest" ranking.
    """
    enterprise_value = None
    if market_cap is not None:
        enterprise_value = market_cap + (net_debt or 0.0)

    return {
        "pe": safe_divide(market_cap, net_income) if (net_income or 0) > 0 else None,
        "ps": safe_divide(market_cap, revenue) if (revenue or 0) > 0 else None,
        "pb": safe_divide(market_cap, book_value) if (book_value or 0) > 0 else None,
        "p_fcf": safe_divide(market_cap, free_cash_flow) if (free_cash_flow or 0) > 0 else None,
        "ev_ebitda": safe_divide(enterprise_value, ebitda) if (ebitda or 0) > 0 else None,
        "ev_sales": safe_divide(enterprise_value, revenue) if (revenue or 0) > 0 else None,
        "fcf_yield": safe_divide(free_cash_flow, market_cap),
        "earnings_yield": safe_divide(net_income, market_cap),
    }


def _median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    n = len(ordered)
    mid = n // 2
    if n % 2 == 1:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2


#: Below this many peers, a median is not a peer group, it is an anecdote.
MIN_PEERS_FOR_COMPARABLES = 3


def comparables(
    subject_multiples: dict[str, float | None],
    peer_multiples: list[dict[str, float | None]],
) -> ComparablesResult:
    """Compare a company against the median of its peers.

    Median, not mean: one peer trading at 300x earnings would drag a mean into
    uselessness, and outliers are common in small peer groups.
    """
    medians: dict[str, float | None] = {}
    premium: dict[str, float | None] = {}

    for name in subject_multiples:
        peer_values = [
            peer[name] for peer in peer_multiples if peer.get(name) is not None
        ]
        median_value = _median([v for v in peer_values if v is not None])
        medians[name] = median_value
        subject_value = subject_multiples.get(name)
        premium[name] = (
            None
            if (subject_value is None or median_value is None or median_value == 0)
            else subject_value / median_value - 1.0
        )

    note = None
    if len(peer_multiples) < MIN_PEERS_FOR_COMPARABLES:
        note = (
            f"Only {len(peer_multiples)} peer(s) supplied; a median over fewer than "
            f"{MIN_PEERS_FOR_COMPARABLES} is not a reliable peer benchmark."
        )

    return ComparablesResult(
        subject=dict(subject_multiples),
        peer_medians=medians,
        premium_discount=premium,
        peer_count=len(peer_multiples),
        note=note,
    )
