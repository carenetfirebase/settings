"""Backtest statistics and the walk-forward split.

Two disciplines the spec is explicit about, both of which exist to stop this
system fooling the person who built it:

**Confidence intervals, not point estimates.** The 24-month backfill supports
roughly twelve months of signals at the 250-day horizon (SPEC §2), and insider
clusters are not common. A median excess return of +3.1% from n=14 is not a
finding, and reporting it without an interval invites reading it as one.

**Publish the result even when it is null or negative.** That is Phase 8
criterion 5. If congressional signals carry no excess return, the honest
outcome is to say so and set the weight toward zero — not to quietly retune
until the number looks better. Retuning weights against a backtest until it
flatters the system is exactly how a project like this ends up lying to its
author.
"""

from __future__ import annotations

import math
import statistics
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date

from imt.backtest.engine import EntryResult, Outcome

#: Below this, a horizon reports "insufficient sample" rather than a number.
#: SPEC §8 uses the same floor for actor histories.
MIN_SAMPLE = 20


@dataclass(frozen=True, slots=True)
class HorizonStats:
    horizon_days: int
    n: int
    hit_rate: float | None
    median: float | None
    mean: float | None
    ci_low: float | None
    ci_high: float | None
    max_drawdown: float | None
    #: Set when n < MIN_SAMPLE. The UI prints this instead of the numbers.
    insufficient_sample: bool

    def describe(self) -> str:
        if self.insufficient_sample:
            return f"{self.horizon_days}d: n={self.n} — insufficient sample"
        assert self.median is not None and self.ci_low is not None
        return (
            f"{self.horizon_days}d: n={self.n} hit={self.hit_rate:.1%} "
            f"median={self.median:+.2%} "
            f"95% CI [{self.ci_low:+.2%}, {self.ci_high:+.2%}]"
        )


@dataclass(frozen=True, slots=True)
class BacktestReport:
    signal: str
    measure: str
    horizons: tuple[HorizonStats, ...]
    entries_total: int
    entries_excluded: int
    outcome_counts: dict[str, int]

    def render(self) -> str:
        lines = [
            f"Signal: {self.signal}   measure: {self.measure}",
            f"Entries: {self.entries_total} ({self.entries_excluded} without usable prices)",
            "Outcomes: " + ", ".join(f"{k}={v}" for k, v in sorted(self.outcome_counts.items())),
            "",
        ]
        lines.extend(f"  {h.describe()}" for h in self.horizons)
        if all(h.insufficient_sample for h in self.horizons):
            lines.append("")
            lines.append(
                "  NO CONCLUSION SUPPORTED. Every horizon is below the minimum sample. "
                "This is a real result and is published as one."
            )
        return "\n".join(lines)


def mean_confidence_interval(
    values: Sequence[float], confidence: float = 0.95
) -> tuple[float, float] | None:
    """Normal-approximation interval on the mean.

    Deliberately not a bootstrap: the sample sizes here are small enough that a
    bootstrap's extra precision would be false comfort, and the point of the
    interval is to show how wide the uncertainty is, not to narrow it.
    """
    n = len(values)
    if n < 2:
        return None
    mean = statistics.fmean(values)
    stdev = statistics.stdev(values)
    if stdev == 0:
        return mean, mean
    # 1.96 for 95%; the small-sample t correction is immaterial next to how
    # wide these intervals already are.
    z = 1.96 if confidence >= 0.95 else 1.645
    margin = z * stdev / math.sqrt(n)
    return mean - margin, mean + margin


def summarize_horizon(
    results: Sequence[EntryResult], *, horizon: int, measure: str = "benchmark_excess"
) -> HorizonStats:
    """Statistics for one horizon.

    Only ``COMPLETE`` entries contribute: an open horizon has no return yet,
    and treating it as zero would drag every estimate toward nothing.
    """
    values: list[float] = []
    for result in results:
        entry = result.returns.get(horizon)
        if entry is None or entry.outcome is not Outcome.COMPLETE:
            continue
        value = getattr(entry, measure)
        if value is not None:
            values.append(float(value))

    n = len(values)
    if n < MIN_SAMPLE:
        return HorizonStats(
            horizon_days=horizon,
            n=n,
            hit_rate=None,
            median=None,
            mean=None,
            ci_low=None,
            ci_high=None,
            max_drawdown=None,
            insufficient_sample=True,
        )

    interval = mean_confidence_interval(values)
    return HorizonStats(
        horizon_days=horizon,
        n=n,
        hit_rate=sum(1 for v in values if v > 0) / n,
        median=statistics.median(values),
        mean=statistics.fmean(values),
        ci_low=interval[0] if interval else None,
        ci_high=interval[1] if interval else None,
        max_drawdown=min(values),
        insufficient_sample=False,
    )


def build_report(
    results: Sequence[EntryResult],
    *,
    signal: str,
    horizons: Sequence[int],
    measure: str = "benchmark_excess",
) -> BacktestReport:
    counts: dict[str, int] = {}
    for result in results:
        counts[result.outcome.value] = counts.get(result.outcome.value, 0) + 1

    return BacktestReport(
        signal=signal,
        measure=measure,
        horizons=tuple(
            summarize_horizon(results, horizon=h, measure=measure) for h in sorted(horizons)
        ),
        entries_total=len(results),
        entries_excluded=sum(1 for r in results if r.outcome is Outcome.NO_PRICE_DATA),
        outcome_counts=counts,
    )


@dataclass(frozen=True, slots=True)
class WalkForwardSplit:
    train_start: date
    train_end: date
    validation_start: date
    validation_end: date

    def is_chronological(self) -> bool:
        """Phase 8 criterion 6: no validation date precedes any training date."""
        return self.train_end < self.validation_start


def walk_forward_splits(
    *, start: date, end: date, train_months: int, validation_months: int
) -> list[WalkForwardSplit]:
    """Expanding-window splits, strictly ordered in time.

    Training always ends before validation begins, with no overlap: a single
    shared day would let the weights see the period they are scored on, and
    every result after that is unfalsifiable.
    """
    from datetime import timedelta

    def add_months(anchor: date, months: int) -> date:
        month = anchor.month - 1 + months
        year = anchor.year + month // 12
        month = month % 12 + 1
        day = min(
            anchor.day,
            [
                31,
                29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28,
                31,
                30,
                31,
                30,
                31,
                31,
                30,
                31,
                30,
                31,
            ][month - 1],
        )
        return date(year, month, day)

    splits: list[WalkForwardSplit] = []
    train_end = add_months(start, train_months)

    while True:
        validation_start = train_end + timedelta(days=1)
        validation_end = add_months(validation_start, validation_months)
        if validation_end > end:
            break
        splits.append(
            WalkForwardSplit(
                train_start=start,
                train_end=train_end,
                validation_start=validation_start,
                validation_end=validation_end,
            )
        )
        train_end = validation_end

    return splits
