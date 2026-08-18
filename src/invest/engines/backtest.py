"""Point-in-time backtesting engine.

## The refusal comes first

Most signals in this platform **cannot be honestly backtested on free data**,
and the engine says so rather than producing a plausible equity curve. The
spec requires the message; this module decides when to print it, and the
decision is made *before* any simulation runs.

Reasons a signal fails the testability gate:

* **No survivorship-bias-free universe history.** The security master holds
  today's companies. Backtesting a screen over a universe that excludes
  everything that went bankrupt or got acquired is the single most common way
  to manufacture a fake track record, and no free source provides
  point-in-time index membership.
* **Insufficient point-in-time depth.** A signal needs enough independent
  observations to say anything. Twelve quarterly rebalances is not a sample.
* **Disclosure-lagged inputs.** Political trades are 30-45 days stale by
  publication and firewalled anyway.
* **Premium-dependent inputs.** Anything needing analyst revisions, options
  data or intraday liquidity cannot be tested because the data does not exist
  here at any point in history.

## What CAN be tested

Price-and-fundamentals signals on a fixed, explicitly-declared universe, over
a period where EDGAR filing dates give real point-in-time discipline. That is
a genuine but narrow claim, and the report states the survivorship caveat every
time rather than burying it.

## Execution model

Signals are computed on bar `t` and filled on bar `t+1`. Filling on the same
bar you generated the signal from is look-ahead: the close is not knowable
until the close. A test asserts a perfect-foresight strategy cannot profit.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import date
from enum import StrEnum

import pandas as pd

from invest.engines.costs import DEFAULT_COSTS, CostModel, CostReport
from invest.engines.quant import (
    TRADING_DAYS_PER_YEAR,
    cagr_from_series,
    max_drawdown,
    sharpe_ratio,
    simple_returns,
    sortino_ratio,
    volatility,
)

logger = logging.getLogger(__name__)

#: The exact wording the spec asks for.
CANNOT_BACKTEST_MESSAGE = (
    "THIS SIGNAL CANNOT YET BE RELIABLY BACKTESTED WITH THE AVAILABLE FREE DATA."
)

#: Minimum usable bars before a result means anything.
MIN_BARS_FOR_BACKTEST = 250

#: Minimum round-trip trades before performance statistics are reported.
MIN_TRADES_FOR_STATISTICS = 20


class SignalKind(StrEnum):
    """What a signal depends on determines whether it can be tested."""

    PRICE_ONLY = "price_only"
    FUNDAMENTAL = "fundamental"
    INSIDER = "insider"
    POLITICAL = "political"
    ANALYST_ESTIMATES = "analyst_estimates"
    OPTIONS = "options"
    CROSS_SECTIONAL = "cross_sectional"


#: Why each kind cannot be tested, or None when it can.
UNTESTABLE_REASONS: dict[SignalKind, str | None] = {
    SignalKind.PRICE_ONLY: None,
    SignalKind.FUNDAMENTAL: None,
    SignalKind.INSIDER: (
        "Form 4 history is only as deep as what has been ingested, and insider "
        "signals need many independent events across many companies before a "
        "result is distinguishable from noise."
    ),
    SignalKind.POLITICAL: (
        "Political disclosures are firewalled and arrive 30-45 days after the "
        "trade. The lag alone makes a historical simulation meaningless."
    ),
    SignalKind.ANALYST_ESTIMATES: (
        "PREMIUM-DATA DEPENDENT: no free source provides point-in-time analyst "
        "estimates or revision history."
    ),
    SignalKind.OPTIONS: (
        "PREMIUM-DATA DEPENDENT: no free source provides historical options "
        "chains or implied volatility surfaces."
    ),
    SignalKind.CROSS_SECTIONAL: (
        "Cross-sectional ranking requires point-in-time universe membership. "
        "The security master holds today's companies, so any ranked backtest "
        "would be survivorship-biased: everything that went bankrupt or was "
        "acquired is silently absent."
    ),
}


@dataclass
class TestabilityVerdict:
    """Whether a backtest may run at all, decided before any simulation."""

    can_backtest: bool
    reasons: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def render(self) -> str:
        lines: list[str] = []
        if not self.can_backtest:
            lines.append(CANNOT_BACKTEST_MESSAGE)
            lines.append("")
            for reason in self.reasons:
                lines.append(f"  - {reason}")
        for warning in self.warnings:
            lines.append(f"  ! {warning}")
        return "\n".join(lines)

    def as_dict(self) -> dict:
        return {
            "can_backtest": self.can_backtest,
            "reasons": self.reasons,
            "warnings": self.warnings,
        }


def assess_testability(
    *,
    kind: SignalKind,
    bar_count: int,
    universe_is_point_in_time: bool = False,
    universe_size: int = 1,
) -> TestabilityVerdict:
    """Decide whether this signal can be honestly tested on the data we have.

    Called before simulating, so an untestable signal never produces an equity
    curve that someone could screenshot.
    """
    reasons: list[str] = []
    warnings: list[str] = []

    kind_reason = UNTESTABLE_REASONS.get(kind)
    if kind_reason:
        reasons.append(kind_reason)

    if bar_count < MIN_BARS_FOR_BACKTEST:
        reasons.append(
            f"Only {bar_count} usable bars available; at least "
            f"{MIN_BARS_FOR_BACKTEST} (roughly one year) are needed before a "
            f"result is worth reading."
        )

    if universe_size > 1 and not universe_is_point_in_time:
        reasons.append(
            f"A {universe_size}-name universe was supplied without point-in-time "
            f"membership history. Results would be survivorship-biased."
        )

    if universe_size == 1 and not universe_is_point_in_time:
        # A single-name test is not survivorship-biased in the portfolio sense,
        # but it IS conditioned on the company still existing today.
        warnings.append(
            "Single-security backtest: the result is conditioned on this company "
            "still existing and still being in the universe today. It says "
            "nothing about a strategy applied across a real universe."
        )

    return TestabilityVerdict(can_backtest=not reasons, reasons=reasons, warnings=warnings)


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------


@dataclass
class Trade:
    entry_date: date
    exit_date: date | None
    entry_price: float
    exit_price: float | None
    shares: float
    cost: float = 0.0

    @property
    def is_open(self) -> bool:
        return self.exit_date is None

    @property
    def pnl(self) -> float | None:
        if self.exit_price is None:
            return None
        return (self.exit_price - self.entry_price) * self.shares - self.cost

    @property
    def return_pct(self) -> float | None:
        if self.exit_price is None or self.entry_price == 0:
            return None
        return self.exit_price / self.entry_price - 1.0

    def as_dict(self) -> dict:
        return {
            "entry_date": self.entry_date.isoformat(),
            "exit_date": self.exit_date.isoformat() if self.exit_date else None,
            "entry_price": self.entry_price,
            "exit_price": self.exit_price,
            "shares": self.shares,
            "cost": self.cost,
            "pnl": self.pnl,
            "return_pct": self.return_pct,
        }


@dataclass
class BacktestResult:
    """A backtest outcome, or an honest refusal to produce one."""

    verdict: TestabilityVerdict
    equity_curve: pd.Series = field(default_factory=lambda: pd.Series(dtype=float))
    trades: list[Trade] = field(default_factory=list)
    costs: CostReport = field(default_factory=CostReport)
    cost_model: CostModel = field(default_factory=lambda: DEFAULT_COSTS)
    benchmark_curve: pd.Series = field(default_factory=lambda: pd.Series(dtype=float))
    initial_capital: float = 100_000.0

    @property
    def ran(self) -> bool:
        return self.verdict.can_backtest and not self.equity_curve.empty

    @property
    def closed_trades(self) -> list[Trade]:
        return [t for t in self.trades if not t.is_open]

    @property
    def has_enough_trades(self) -> bool:
        return len(self.closed_trades) >= MIN_TRADES_FOR_STATISTICS

    # -- statistics ------------------------------------------------------

    @property
    def total_return(self) -> float | None:
        if not self.ran or len(self.equity_curve) < 2:
            return None
        return float(self.equity_curve.iloc[-1] / self.equity_curve.iloc[0] - 1.0)

    @property
    def cagr(self) -> float | None:
        return cagr_from_series(self.equity_curve) if self.ran else None

    @property
    def volatility(self) -> float | None:
        return volatility(simple_returns(self.equity_curve)) if self.ran else None

    @property
    def sharpe(self) -> float | None:
        return sharpe_ratio(simple_returns(self.equity_curve)) if self.ran else None

    @property
    def sortino(self) -> float | None:
        return sortino_ratio(simple_returns(self.equity_curve)) if self.ran else None

    @property
    def max_drawdown(self) -> float | None:
        return max_drawdown(self.equity_curve) if self.ran else None

    @property
    def win_rate(self) -> float | None:
        """None below the minimum trade count — a win rate over five trades
        is not a statistic.
        """
        closed = self.closed_trades
        if len(closed) < MIN_TRADES_FOR_STATISTICS:
            return None
        wins = sum(1 for t in closed if (t.pnl or 0) > 0)
        return wins / len(closed)

    @property
    def gross_return(self) -> float | None:
        """Return before costs — shown only next to the net figure, so the
        size of the cost drag is visible.
        """
        if self.total_return is None:
            return None
        return self.total_return + self.costs.total_cost / self.initial_capital

    @property
    def benchmark_return(self) -> float | None:
        if self.benchmark_curve.empty or len(self.benchmark_curve) < 2:
            return None
        return float(self.benchmark_curve.iloc[-1] / self.benchmark_curve.iloc[0] - 1.0)

    @property
    def excess_return(self) -> float | None:
        own = self.total_return
        bench = self.benchmark_return
        if own is None or bench is None:
            return None
        return own - bench

    def as_dict(self) -> dict:
        return {
            "ran": self.ran,
            "verdict": self.verdict.as_dict(),
            "initial_capital": self.initial_capital,
            "total_return": self.total_return,
            "gross_return": self.gross_return,
            "cagr": self.cagr,
            "volatility": self.volatility,
            "sharpe": self.sharpe,
            "sortino": self.sortino,
            "max_drawdown": self.max_drawdown,
            "win_rate": self.win_rate,
            "trade_count": len(self.closed_trades),
            "has_enough_trades": self.has_enough_trades,
            "benchmark_return": self.benchmark_return,
            "excess_return": self.excess_return,
            "costs": self.costs.as_dict(),
            "cost_model": self.cost_model.as_dict(),
            "value_type": "calculated",
        }


#: A signal function takes the history available UP TO AND INCLUDING bar t and
#: returns a target position in [0, 1]. It is never handed future bars.
SignalFn = Callable[[pd.Series], float]


def run_backtest(
    prices: pd.Series,
    signal_fn: SignalFn,
    *,
    kind: SignalKind = SignalKind.PRICE_ONLY,
    cost_model: CostModel | None = None,
    initial_capital: float = 100_000.0,
    warmup: int = 200,
    universe_is_point_in_time: bool = False,
    universe_size: int = 1,
    benchmark: pd.Series | None = None,
) -> BacktestResult:
    """Simulate a single-security long/flat strategy.

    Execution: the signal is computed from bars up to and including `t`, and
    the resulting position change is filled at bar `t+1`'s price. Filling at
    bar `t` would be look-ahead — you cannot trade on a close you have not
    seen yet.

    The testability gate runs first. When it refuses, no simulation happens and
    the caller gets the refusal message rather than an equity curve.
    """
    prices = prices.dropna().sort_index()
    cost_model = cost_model or DEFAULT_COSTS

    verdict = assess_testability(
        kind=kind,
        bar_count=len(prices),
        universe_is_point_in_time=universe_is_point_in_time,
        universe_size=universe_size,
    )
    result = BacktestResult(
        verdict=verdict, cost_model=cost_model, initial_capital=initial_capital
    )
    if not verdict.can_backtest:
        return result

    cash = initial_capital
    shares_held = 0.0
    costs = CostReport()
    trades: list[Trade] = []
    open_trade: Trade | None = None
    equity_dates: list = []
    equity_values: list[float] = []

    # Stop one short: the final bar has no t+1 to fill against.
    for i in range(warmup, len(prices) - 1):
        history = prices.iloc[: i + 1]
        target = signal_fn(history)
        target = max(0.0, min(1.0, float(target)))

        fill_date = prices.index[i + 1]
        fill_mid = float(prices.iloc[i + 1])

        equity = cash + shares_held * float(prices.iloc[i])
        desired_value = equity * target
        desired_shares = desired_value / fill_mid if fill_mid > 0 else 0.0
        delta = desired_shares - shares_held

        if abs(delta * fill_mid) > 1e-9:
            is_buy = delta > 0
            fill_price = cost_model.fill_price(fill_mid, is_buy=is_buy)
            notional = abs(delta) * fill_mid
            commission = cost_model.commission(notional)
            spread = abs(fill_price - fill_mid) * abs(delta)

            cash -= delta * fill_price
            cash -= commission
            shares_held += delta
            costs.record(commission=commission, spread=spread, notional=notional)

            if is_buy and open_trade is None:
                open_trade = Trade(
                    entry_date=fill_date,
                    exit_date=None,
                    entry_price=fill_price,
                    exit_price=None,
                    shares=delta,
                    cost=commission + spread,
                )
            elif not is_buy and open_trade is not None and shares_held <= 1e-9:
                open_trade.exit_date = fill_date
                open_trade.exit_price = fill_price
                open_trade.cost += commission + spread
                trades.append(open_trade)
                open_trade = None

        equity_dates.append(fill_date)
        equity_values.append(cash + shares_held * fill_mid)

    if open_trade is not None:
        trades.append(open_trade)

    result.equity_curve = pd.Series(equity_values, index=equity_dates, dtype=float)
    result.trades = trades
    result.costs = costs

    if benchmark is not None and not benchmark.empty:
        aligned = benchmark.reindex(result.equity_curve.index).dropna()
        if len(aligned) >= 2:
            result.benchmark_curve = aligned / aligned.iloc[0] * initial_capital

    return result


# --------------------------------------------------------------------------
# Example signals
# --------------------------------------------------------------------------


def sma_crossover_signal(fast: int = 50, slow: int = 200) -> SignalFn:
    """Long when the fast SMA is above the slow one.

    Only ever sees history up to the current bar, by construction.
    """

    def signal(history: pd.Series) -> float:
        if len(history) < slow:
            return 0.0
        fast_ma = history.iloc[-fast:].mean()
        slow_ma = history.iloc[-slow:].mean()
        return 1.0 if fast_ma > slow_ma else 0.0

    return signal


def buy_and_hold_signal() -> SignalFn:
    """The benchmark every strategy has to beat after costs."""

    def signal(history: pd.Series) -> float:
        return 1.0

    return signal


def render_backtest(result: BacktestResult, *, name: str = "Strategy") -> str:
    """Render a backtest, or the refusal, as text."""
    from invest.reports.research_report import (
        INSUFFICIENT,
        _rule,
        fmt_money,
        fmt_number,
        fmt_pct,
    )

    lines = [_rule(), f"BACKTEST — {name}", _rule()]

    if not result.verdict.can_backtest:
        lines.append("")
        lines.append(result.verdict.render())
        lines.append("")
        lines.append(_rule())
        return "\n".join(lines)

    if not result.ran:
        lines.append("")
        lines.append(f"{INSUFFICIENT}: the simulation produced no equity curve.")
        lines.append(_rule())
        return "\n".join(lines)

    lines.append(f"  Initial capital     {fmt_money(result.initial_capital)}")
    lines.append(f"  Final equity        {fmt_money(float(result.equity_curve.iloc[-1]))}")
    lines.append("")
    lines.append(f"  Total return, net   {fmt_pct(result.total_return, signed=True)}")
    lines.append(f"  Total return, gross {fmt_pct(result.gross_return, signed=True)}")
    lines.append(f"  CAGR                {fmt_pct(result.cagr, signed=True)}")
    lines.append(f"  Volatility          {fmt_pct(result.volatility)}")
    lines.append(f"  Sharpe              {fmt_number(result.sharpe)}")
    lines.append(f"  Sortino             {fmt_number(result.sortino)}")
    lines.append(f"  Max drawdown        {fmt_pct(result.max_drawdown)}")

    if result.benchmark_return is not None:
        lines.append("")
        lines.append(f"  Buy-and-hold        {fmt_pct(result.benchmark_return, signed=True)}")
        lines.append(f"  Excess              {fmt_pct(result.excess_return, signed=True)}")

    lines.append("")
    lines.append(f"  Round trips         {len(result.closed_trades)}")
    if result.has_enough_trades:
        lines.append(f"  Win rate            {fmt_pct(result.win_rate)}")
    else:
        lines.append(
            f"  Win rate            {INSUFFICIENT} "
            f"(need {MIN_TRADES_FOR_STATISTICS}+ round trips)"
        )

    lines.append("")
    lines.append("  COSTS  [ESTIMATED — no quote or fill data exists in V1]")
    lines.append(f"    Total             {fmt_money(result.costs.total_cost)}")
    lines.append(f"    Commission        {fmt_money(result.costs.commission_paid)}")
    lines.append(f"    Spread + slippage {fmt_money(result.costs.spread_paid)}")
    lines.append(
        f"    Round-trip assumption {result.cost_model.round_trip_bps:.1f}bp"
    )
    if result.costs.cost_as_bps_of_notional is not None:
        lines.append(
            f"    Cost / notional   {result.costs.cost_as_bps_of_notional:.1f}bp"
        )

    if result.verdict.warnings:
        lines.append("")
        lines.append("  CAVEATS")
        for warning in result.verdict.warnings:
            lines.append(f"    ! {warning}")

    lines.append("")
    lines.append(
        "  Signals are computed on bar t and filled at bar t+1. Past performance\n"
        "  of a simulation is not evidence about the future, and this simulation\n"
        "  is not evidence that the strategy was tradable."
    )
    lines.append(_rule())
    return "\n".join(lines)


def annualization_note() -> str:
    return f"Statistics annualised at {TRADING_DAYS_PER_YEAR} trading days per year."
