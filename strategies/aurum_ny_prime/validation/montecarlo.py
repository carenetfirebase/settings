"""Regime-aware Monte Carlo and FTMO pass-path simulation (S65, S66, S67).

Two decisions here matter more than the arithmetic:

**Trades are not independent.** Losses cluster: a regime that breaks the setup
breaks it for days at a time. Resampling individual trades destroys exactly the
structure that kills evaluations, and produces a comfortable, wrong answer. So
the resampling unit is a **trading day**, drawn in **blocks** of consecutive
days (moving-block by default, stationary as an option), which keeps runs of
bad days intact.

**Floating loss counts.** FTMO measures the daily limit against intraday equity,
not against the close. Where the export carries MAE in R, each trade's worst
excursion is applied to the running equity before its realised result, so a day
that dipped 4.9% and recovered is scored on the dip. Without MAE the simulation
says so and models realised P/L only, which is optimistic — and labelled as
such in the result.
"""

from __future__ import annotations

import random
from collections import defaultdict
from dataclasses import dataclass, field

from .stats import percentile


@dataclass(frozen=True)
class TradingDay:
    """All trades of one calendar trading day, in order."""

    date: str
    r_values: tuple[float, ...]
    mae_r: tuple[float, ...] = ()

    @property
    def net_r(self) -> float:
        return sum(self.r_values)


def group_by_day(dates: list[str], r_values: list[float], mae_r: list[float] | None = None) -> list[TradingDay]:
    """Group trades into trading days, preserving chronological order."""
    buckets: dict[str, list[tuple[float, float]]] = defaultdict(list)
    order: list[str] = []
    maes = mae_r or [float("nan")] * len(r_values)
    for date, r, mae in zip(dates, r_values, maes, strict=True):
        if date not in buckets:
            order.append(date)
        buckets[date].append((r, mae))
    return [
        TradingDay(
            date=date,
            r_values=tuple(r for r, _ in buckets[date]),
            mae_r=tuple(mae for _, mae in buckets[date]),
        )
        for date in order
    ]


def block_bootstrap_days(
    days: list[TradingDay],
    length: int,
    block: int,
    rng: random.Random,
    stationary: bool = False,
) -> list[TradingDay]:
    """Draw `length` trading days in blocks of consecutive days.

    Moving-block: every block is exactly `block` days, wrapping at the end of
    the sample. Stationary: block lengths are geometric with mean `block`,
    which removes the artefacts a fixed block length can introduce.
    """
    if not days:
        return []
    out: list[TradingDay] = []
    n = len(days)
    while len(out) < length:
        start = rng.randrange(n)
        size = block
        if stationary:
            size = 1
            while rng.random() > 1.0 / block:
                size += 1
        for offset in range(size):
            out.append(days[(start + offset) % n])
            if len(out) >= length:
                break
    return out[:length]


@dataclass(frozen=True)
class FtmoRules:
    """S5. Every value is exposed because FTMO changes them."""

    account: float = 100_000.0
    target_pct: float = 10.0
    daily_loss_pct: float = 5.0
    max_loss_pct: float = 10.0
    min_trading_days: int = 4
    max_days: int = 120
    risk_std_pct: float = 0.50
    risk_abs_max_pct: float = 1.00
    risk_hard_cap: float = 1_000.0
    risk_5_8_pct: float = 0.40
    risk_8_9_pct: float = 0.25
    risk_9_10_pct: float = 0.15
    internal_daily_stop_pct: float = 1.50
    cost_per_trade: float = 0.0

    def risk_pct_for(self, gain_pct: float) -> float:
        """S8 risk schedule. Risk falls as the target approaches; it never
        rises to make back a loss."""
        if gain_pct < 5:
            pct = self.risk_std_pct
        elif gain_pct < 8:
            pct = self.risk_5_8_pct
        elif gain_pct < 9:
            pct = self.risk_8_9_pct
        else:
            pct = self.risk_9_10_pct
        return min(pct, self.risk_abs_max_pct)


@dataclass
class PathResult:
    outcome: str  # "PASS" | "DAILY_LOSS" | "MAX_LOSS" | "TIMEOUT"
    days: int
    trading_days: int
    final_equity: float
    max_drawdown: float


def simulate_path(days: list[TradingDay], rules: FtmoRules, use_mae: bool = True) -> PathResult:
    """Walk one evaluation path day by day and stop at the first terminal event.

    Order of checks inside a day matters and follows the firm's: the daily-loss
    and max-loss breaches are evaluated against intraday equity, so a breach
    that happens before the day's profit is still a breach.
    """
    equity = rules.account
    peak = equity
    max_dd = 0.0
    trading_days = 0
    target_equity = rules.account * (1 + rules.target_pct / 100)
    floor_equity = rules.account * (1 - rules.max_loss_pct / 100)

    for index, day in enumerate(days, start=1):
        day_start = equity
        daily_floor = day_start * (1 - rules.daily_loss_pct / 100)
        internal_floor = day_start * (1 - rules.internal_daily_stop_pct / 100)
        traded_today = False

        for r, mae in zip(day.r_values, day.mae_r or [float("nan")] * len(day.r_values), strict=False):
            if equity <= internal_floor:
                break  # internal daily stop: no new trading today (S6)
            gain_pct = (equity - rules.account) / rules.account * 100
            risk = min(equity * rules.risk_pct_for(gain_pct) / 100, rules.risk_hard_cap)
            traded_today = True

            # Floating excursion first: the low of the trade is reached before
            # its result is known.
            if use_mae and mae == mae:  # NaN check
                trough = equity - abs(mae) * risk
                peak = max(peak, equity)
                max_dd = max(max_dd, peak - trough)
                if trough <= floor_equity:
                    return PathResult("MAX_LOSS", index, trading_days, trough, max_dd)
                if trough <= daily_floor:
                    return PathResult("DAILY_LOSS", index, trading_days, trough, max_dd)

            equity += r * risk - rules.cost_per_trade
            peak = max(peak, equity)
            max_dd = max(max_dd, peak - equity)

            if equity <= floor_equity:
                return PathResult("MAX_LOSS", index, trading_days, equity, max_dd)
            if equity <= daily_floor:
                return PathResult("DAILY_LOSS", index, trading_days, equity, max_dd)

        if traded_today:
            trading_days += 1
        if equity >= target_equity and trading_days >= rules.min_trading_days:
            return PathResult("PASS", index, trading_days, equity, max_dd)

    return PathResult("TIMEOUT", len(days), trading_days, equity, max_dd)


@dataclass(frozen=True)
class MonteCarloResult:
    paths: int
    block: int
    stationary: bool
    used_mae: bool
    p_pass: float
    p_daily_loss: float
    p_max_loss: float
    p_timeout: float
    median_days_to_pass: float
    p95_days_to_pass: float
    median_max_drawdown: float
    p95_max_drawdown: float
    note: str = ""

    def as_dict(self) -> dict[str, object]:
        return dict(self.__dict__)


def run_monte_carlo(
    days: list[TradingDay],
    rules: FtmoRules | None = None,
    paths: int = 10_000,
    block: int = 5,
    stationary: bool = False,
    horizon_days: int | None = None,
    seed: int = 20260825,
) -> MonteCarloResult:
    """S66. Estimate P(pass before failure) and the drawdown distribution."""
    rules = rules or FtmoRules()
    if not days:
        nan = float("nan")
        return MonteCarloResult(0, block, stationary, False, nan, nan, nan, nan, nan, nan, nan, nan, "no trading days")

    has_mae = any(m == m for day in days for m in day.mae_r)
    horizon = horizon_days or rules.max_days
    rng = random.Random(seed)
    counts = {"PASS": 0, "DAILY_LOSS": 0, "MAX_LOSS": 0, "TIMEOUT": 0}
    days_to_pass: list[float] = []
    drawdowns: list[float] = []

    for _ in range(paths):
        sample = block_bootstrap_days(days, horizon, block, rng, stationary)
        result = simulate_path(sample, rules, use_mae=has_mae)
        counts[result.outcome] += 1
        drawdowns.append(result.max_drawdown)
        if result.outcome == "PASS":
            days_to_pass.append(result.days)

    days_to_pass.sort()
    drawdowns.sort()
    note = (
        "MAE present: floating loss modelled."
        if has_mae
        else "NO MAE in export: realised P/L only, so failure probability is UNDERSTATED."
    )
    return MonteCarloResult(
        paths=paths,
        block=block,
        stationary=stationary,
        used_mae=has_mae,
        p_pass=counts["PASS"] / paths,
        p_daily_loss=counts["DAILY_LOSS"] / paths,
        p_max_loss=counts["MAX_LOSS"] / paths,
        p_timeout=counts["TIMEOUT"] / paths,
        median_days_to_pass=percentile(days_to_pass, 0.50),
        p95_days_to_pass=percentile(days_to_pass, 0.95),
        median_max_drawdown=percentile(drawdowns, 0.50),
        p95_max_drawdown=percentile(drawdowns, 0.95),
        note=note,
    )


def block_bootstrap_expectancy(
    days: list[TradingDay],
    samples: int = 10_000,
    block: int = 5,
    seed: int = 20260825,
) -> dict[str, float]:
    """Expectancy interval that preserves clustering, for comparison with the
    IID bootstrap in stats.py. A large gap between the two means the IID
    interval was fiction."""
    if not days:
        return {}
    rng = random.Random(seed)
    n_trades = sum(len(day.r_values) for day in days)
    means: list[float] = []
    for _ in range(samples):
        sample = block_bootstrap_days(days, len(days), block, rng)
        values = [r for day in sample for r in day.r_values]
        if values:
            means.append(sum(values) / len(values))
    means.sort()
    return {
        "samples": len(means),
        "block": block,
        "trades_per_path": n_trades,
        "mean": sum(means) / len(means),
        "median": percentile(means, 0.50),
        "p5": percentile(means, 0.05),
        "p95": percentile(means, 0.95),
        "prob_positive": sum(1 for m in means if m > 0) / len(means),
    }
