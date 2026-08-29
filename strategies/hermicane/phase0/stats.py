"""Uncertainty around small samples (§2, §3.3).

The binding constraint on HERMICANE is not code quality, it is n. Ten years of
US macro releases across the tracked event types is on the order of a thousand
observations, and v1's filter stack passes perhaps a tenth of them. Every
number this package reports therefore arrives with an interval attached, and
the comparison that matters — "does this filter beat the control?" — is a
comparison of intervals, never of point estimates.

Standard library only, so the bootstrap is written out rather than imported.
Ten thousand resamples of a few hundred values is a fraction of a second.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass

#: Fixed so that two runs of the same analysis on the same panel agree. A
#: bootstrap CI that moves between runs invites re-rolling until the answer is
#: the desired one.
DEFAULT_SEED = 20260829

DEFAULT_RESAMPLES = 10_000


@dataclass(frozen=True)
class Interval:
    low: float
    high: float

    def __str__(self) -> str:
        if math.isnan(self.low) or math.isnan(self.high):
            return "[n/a, n/a]"
        return f"[{self.low:+.3f}, {self.high:+.3f}]"

    def contains(self, value: float) -> bool:
        return self.low <= value <= self.high

    @property
    def excludes_zero(self) -> bool:
        return not math.isnan(self.low) and (self.low > 0.0 or self.high < 0.0)


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


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else float("nan")


def median(values: list[float]) -> float:
    return percentile(sorted(values), 0.50) if values else float("nan")


def stdev(values: list[float]) -> float:
    """Sample standard deviation."""
    n = len(values)
    if n < 2:
        return float("nan")
    mu = mean(values)
    return math.sqrt(sum((v - mu) ** 2 for v in values) / (n - 1))


def standard_error(values: list[float]) -> float:
    n = len(values)
    if n < 2:
        return float("nan")
    return stdev(values) / math.sqrt(n)


@dataclass(frozen=True)
class MeanEstimate:
    """A mean with everything needed to judge whether to believe it."""

    n: int
    mean: float
    median: float
    stdev: float
    standard_error: float
    ci: Interval
    win_rate: float
    prob_positive: float

    def as_dict(self) -> dict[str, float | int]:
        return {
            "n": self.n,
            "mean_r": self.mean,
            "median_r": self.median,
            "stdev_r": self.stdev,
            "standard_error": self.standard_error,
            "ci_low": self.ci.low,
            "ci_high": self.ci.high,
            "win_rate": self.win_rate,
            "prob_positive": self.prob_positive,
        }


def bootstrap_mean(
    values: list[float],
    resamples: int = DEFAULT_RESAMPLES,
    seed: int = DEFAULT_SEED,
    alpha: float = 0.05,
) -> MeanEstimate:
    """Percentile bootstrap of the mean, plus the descriptive statistics.

    `prob_positive` is the share of resample means above zero. It is not a
    p-value and is not offered as one; it is the honest reading of "how often
    does this sample, resampled, still look profitable".

    An empty sample returns an all-NaN estimate rather than raising, because
    filters legitimately reduce n to zero and the ablation table needs to print
    that row rather than abort the report.
    """
    n = len(values)
    if n == 0:
        nan = float("nan")
        return MeanEstimate(0, nan, nan, nan, nan, Interval(nan, nan), nan, nan)
    if n == 1:
        only = values[0]
        return MeanEstimate(
            1, only, only, float("nan"), float("nan"),
            Interval(float("nan"), float("nan")),
            1.0 if only > 0 else 0.0,
            1.0 if only > 0 else 0.0,
        )
    rng = random.Random(seed)
    means: list[float] = []
    for _ in range(resamples):
        total = 0.0
        for _ in range(n):
            total += values[rng.randrange(n)]
        means.append(total / n)
    means.sort()
    return MeanEstimate(
        n=n,
        mean=mean(values),
        median=median(values),
        stdev=stdev(values),
        standard_error=standard_error(values),
        ci=Interval(percentile(means, alpha / 2), percentile(means, 1 - alpha / 2)),
        win_rate=sum(1 for v in values if v > 0) / n,
        prob_positive=sum(1 for m in means if m > 0) / len(means),
    )


def terciles(values: list[float]) -> tuple[float, float]:
    """The two cut points that split a sample into thirds."""
    ordered = sorted(values)
    return percentile(ordered, 1 / 3), percentile(ordered, 2 / 3)


def sample_health(n: int) -> str:
    """The health warning §4.3 requires on every reported result.

    The thresholds come from the standard error on a win rate, not from taste:
    at n=75 the standard error is ~5.7pp, which cannot separate a 58% system
    from a coin. Anything below that is a description of a handful of days.
    """
    if n >= 200:
        return "ADEQUATE"
    if n >= 100:
        return "THIN"
    if n >= 50:
        return "UNDERPOWERED"
    return "ANECDOTE"
