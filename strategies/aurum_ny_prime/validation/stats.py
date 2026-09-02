"""Performance statistics and uncertainty (S62, S63, S64).

A win rate without an interval is a number pretending to be evidence. 70% from
30 trades and 70% from 400 trades are not the same claim, and every function
here that reports a proportion reports its uncertainty alongside.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass


@dataclass(frozen=True)
class Interval:
    low: float
    high: float

    def __str__(self) -> str:
        return f"[{self.low:.4f}, {self.high:.4f}]"


def wilson_interval(wins: int, n: int, z: float = 1.96) -> Interval:
    """Wilson score interval for a binomial proportion.

    Preferred over the normal approximation because it does not fall off the
    end of the [0, 1] interval on small samples, which is exactly the regime
    this project will be in for a long time.
    """
    if n <= 0:
        return Interval(float("nan"), float("nan"))
    p = wins / n
    denominator = 1 + z * z / n
    centre = p + z * z / (2 * n)
    spread = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return Interval((centre - spread) / denominator, (centre + spread) / denominator)


@dataclass(frozen=True)
class Summary:
    """Core performance statistics, all in R unless the name says otherwise."""

    n: int
    wins: int
    losses: int
    win_rate: float
    win_rate_ci: Interval
    avg_win_r: float
    avg_loss_r: float
    expectancy_r: float
    profit_factor: float
    net_r: float
    max_drawdown_r: float
    avg_drawdown_r: float
    calmar_like: float
    max_consecutive_losses: int
    max_consecutive_wins: int
    avg_mae_r: float
    avg_mfe_r: float
    avg_winner_mae_r: float
    avg_loser_mfe_r: float
    realized_reward_risk: float
    sample_label: str

    def as_dict(self) -> dict[str, object]:
        data = dict(self.__dict__)
        data["win_rate_ci"] = [self.win_rate_ci.low, self.win_rate_ci.high]
        return data


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else float("nan")


def drawdown_curve(r_values: list[float]) -> list[float]:
    """Drawdown in R at each trade, measured from the running peak."""
    equity = 0.0
    peak = 0.0
    out: list[float] = []
    for r in r_values:
        equity += r
        peak = max(peak, equity)
        out.append(peak - equity)
    return out


def summarize(
    r_values: list[float],
    mae_r: list[float] | None = None,
    mfe_r: list[float] | None = None,
) -> Summary:
    n = len(r_values)
    if n == 0:
        nan = float("nan")
        return Summary(
            0, 0, 0, nan, Interval(nan, nan), nan, nan, nan, nan, 0.0, 0.0, 0.0, nan,
            0, 0, nan, nan, nan, nan, nan, "EMPTY",
        )
    wins = [r for r in r_values if r > 0]
    losses = [r for r in r_values if r <= 0]
    gross_win = sum(wins)
    gross_loss = -sum(losses)

    streak_l = streak_w = max_l = max_w = 0
    for r in r_values:
        if r > 0:
            streak_w += 1
            streak_l = 0
        else:
            streak_l += 1
            streak_w = 0
        max_l = max(max_l, streak_l)
        max_w = max(max_w, streak_w)

    curve = drawdown_curve(r_values)
    in_dd = [d for d in curve if d > 0]
    max_dd = max(curve) if curve else 0.0
    net_r = sum(r_values)

    mae = mae_r or []
    mfe = mfe_r or []
    winner_mae = [m for m, r in zip(mae, r_values, strict=False) if r > 0]
    loser_mfe = [m for m, r in zip(mfe, r_values, strict=False) if r <= 0]

    avg_win = _mean(wins)
    avg_loss = _mean([-r for r in losses])

    return Summary(
        n=n,
        wins=len(wins),
        losses=len(losses),
        win_rate=len(wins) / n,
        win_rate_ci=wilson_interval(len(wins), n),
        avg_win_r=avg_win,
        avg_loss_r=avg_loss,
        expectancy_r=net_r / n,
        profit_factor=gross_win / gross_loss if gross_loss > 0 else float("inf"),
        net_r=net_r,
        max_drawdown_r=max_dd,
        avg_drawdown_r=_mean(in_dd) if in_dd else 0.0,
        calmar_like=net_r / max_dd if max_dd > 0 else float("inf"),
        max_consecutive_losses=max_l,
        max_consecutive_wins=max_w,
        avg_mae_r=_mean(mae),
        avg_mfe_r=_mean(mfe),
        avg_winner_mae_r=_mean(winner_mae),
        avg_loser_mfe_r=_mean(loser_mfe),
        realized_reward_risk=avg_win / avg_loss if avg_loss and avg_loss > 0 else float("nan"),
        sample_label="VALIDATED" if n >= 200 else "ADEQUATE" if n >= 100 else "PRELIMINARY",
    )


@dataclass(frozen=True)
class BootstrapResult:
    """S64. `prob_positive` is the number the specification insists on
    reporting: the share of resamples whose mean expectancy is above zero."""

    samples: int
    mean: float
    median: float
    p5: float
    p95: float
    prob_positive: float

    def as_dict(self) -> dict[str, float]:
        return dict(self.__dict__)


def percentile(sorted_values: list[float], q: float) -> float:
    """Linear-interpolated percentile of an already sorted list."""
    if not sorted_values:
        return float("nan")
    if len(sorted_values) == 1:
        return sorted_values[0]
    pos = q * (len(sorted_values) - 1)
    lower = math.floor(pos)
    upper = math.ceil(pos)
    if lower == upper:
        return sorted_values[int(pos)]
    weight = pos - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def bootstrap_expectancy(
    r_values: list[float],
    samples: int = 10_000,
    seed: int = 20260825,
) -> BootstrapResult:
    """IID bootstrap of mean expectancy.

    This deliberately ignores loss clustering — use `montecarlo.block_bootstrap`
    for anything that has to respect it. Reported side by side, the gap between
    the two is itself informative: if the IID interval is much tighter, the
    trades are not independent and the IID interval was never the right one.
    """
    if not r_values:
        nan = float("nan")
        return BootstrapResult(0, nan, nan, nan, nan, nan)
    rng = random.Random(seed)
    n = len(r_values)
    means = [
        sum(r_values[rng.randrange(n)] for _ in range(n)) / n
        for _ in range(samples)
    ]
    means.sort()
    positive = sum(1 for m in means if m > 0)
    return BootstrapResult(
        samples=samples,
        mean=sum(means) / len(means),
        median=percentile(means, 0.50),
        p5=percentile(means, 0.05),
        p95=percentile(means, 0.95),
        prob_positive=positive / len(means),
    )
