"""The rolling beta regime estimator (§1, §3.5).

This is the one input in HERMICANE v2 that is genuinely orthogonal to the
event. Gold, DXY and the 2Y all reprice off the same headline in the same
second, so requiring them to agree inside a three-minute window counts one
piece of information three times. Beta is different: it is estimated on daily
data over the sixty-to-a-hundred-and-twenty days *before* the release, and it
answers a question the event window cannot — is gold currently listening to
rates at all?

The regression is deliberately the simplest thing that can work:

    ΔlogXAU(t) = alpha + beta · ΔDGS2(t) + e(t)

with ΔDGS2 in percentage points (the units FRED publishes). A negative beta is
the classic mapping: yields up, gold down. R² says how much of gold is being
explained by rates at all, and the t-statistic says whether the sign is worth
believing.

The three regimes v2 gates on:

* ``CLASSIC``  — beta negative and R² healthy. The v1 reaction function is live.
* ``DECOUPLED``— beta near zero or R² collapsed. Gold is being driven by
  something outside the model: central bank buying, debasement flows, a
  geopolitical bid. Stand down regardless of how large the surprise is.
* ``INVERTED`` — beta positive and significant. Do **not** trade, and do not
  auto-invert the signal either: §1 is explicit that inversion is only tradable
  if Phase 0 demonstrates it, and that demonstration is `ablation.beta_regime_table`.

The thresholds that separate "healthy R²" from "collapsed" are *not* set here.
They are swept in the ablation and written to the calibrated constants. The
defaults on `classify` exist so the estimator can be unit-tested, and
`report.py` refuses to emit them as calibrated values.
"""

from __future__ import annotations

import bisect
import math
from dataclasses import dataclass
from datetime import date

#: §3.2 asks for all three. They are reported side by side rather than averaged:
#: if the sign flips between a 60-day and a 120-day window, that disagreement is
#: the finding, and averaging it away would hide exactly the transition the
#: estimator exists to catch.
WINDOWS = (60, 90, 120)

CLASSIC = "CLASSIC"
DECOUPLED = "DECOUPLED"
INVERTED = "INVERTED"
INSUFFICIENT = "INSUFFICIENT"


@dataclass(frozen=True)
class BetaFit:
    """One OLS fit of gold returns on yield changes."""

    window: int
    n: int
    beta: float
    alpha: float
    r_squared: float
    t_stat: float
    #: Last observation date used. Every fit is strictly backward-looking from
    #: the event it will be attached to; see `fit_as_of`.
    as_of: date | None = None

    @property
    def is_significant(self) -> bool:
        return not math.isnan(self.t_stat) and abs(self.t_stat) >= 2.0

    def as_dict(self) -> dict[str, object]:
        return {
            "window": self.window,
            "n": self.n,
            "beta": self.beta,
            "alpha": self.alpha,
            "r_squared": self.r_squared,
            "t_stat": self.t_stat,
            "as_of": self.as_of.isoformat() if self.as_of else None,
        }


def _nan_fit(window: int, n: int, as_of: date | None) -> BetaFit:
    nan = float("nan")
    return BetaFit(window, n, nan, nan, nan, nan, as_of)


def ols(x: list[float], y: list[float]) -> tuple[float, float, float, float]:
    """Simple OLS. Returns (beta, alpha, r_squared, t_stat).

    Written out rather than imported so the package stays standard-library
    only. Degenerate inputs — fewer than three points, or a regressor with no
    variance, which happens in a window where the 2Y did not move — return NaN
    rather than raising, so a single flat window does not abort a panel build.
    """
    n = len(x)
    if n != len(y) or n < 3:
        nan = float("nan")
        return nan, nan, nan, nan
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    sxx = sum((xi - mean_x) ** 2 for xi in x)
    if sxx <= 0.0:
        nan = float("nan")
        return nan, nan, nan, nan
    sxy = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    syy = sum((yi - mean_y) ** 2 for yi in y)
    beta = sxy / sxx
    alpha = mean_y - beta * mean_x
    r_squared = (sxy * sxy) / (sxx * syy) if syy > 0.0 else float("nan")
    residual_ss = max(syy - beta * sxy, 0.0)
    if n <= 2:
        return beta, alpha, r_squared, float("nan")
    sigma_squared = residual_ss / (n - 2)
    se_beta = math.sqrt(sigma_squared / sxx) if sigma_squared > 0.0 else 0.0
    t_stat = beta / se_beta if se_beta > 0.0 else float("inf") * (1 if beta > 0 else -1)
    return beta, alpha, r_squared, t_stat


@dataclass(frozen=True)
class DailyObservation:
    """One trading day of the two series the estimator needs."""

    day: date
    gold_close: float
    dgs2: float


def to_changes(observations: list[DailyObservation]) -> tuple[list[date], list[float], list[float]]:
    """Convert levels to the paired changes the regression consumes.

    Gold becomes a log return, the 2Y a simple difference in percentage points.
    Days where either series is missing break the pair, so the change spanning
    the gap is dropped rather than silently spanning a holiday — a three-day
    move regressed as a one-day move is the kind of thing that quietly inflates
    an R².
    """
    ordered = sorted(observations, key=lambda o: o.day)
    days: list[date] = []
    d_yield: list[float] = []
    d_gold: list[float] = []
    for previous, current in zip(ordered, ordered[1:]):
        if (current.day - previous.day).days > 5:
            continue
        if previous.gold_close <= 0 or current.gold_close <= 0:
            continue
        if any(math.isnan(v) for v in (previous.dgs2, current.dgs2)):
            continue
        days.append(current.day)
        d_yield.append(current.dgs2 - previous.dgs2)
        d_gold.append(math.log(current.gold_close / previous.gold_close))
    return days, d_yield, d_gold


@dataclass(frozen=True)
class ChangeSeries:
    """The paired daily changes, computed once and reused for every event.

    Recomputing `to_changes` per event per window is quadratic in the length of
    the daily history, which on five years and six hundred releases is the
    difference between a panel that builds in seconds and one that does not
    build. The days list is sorted, so the as-of cut is a bisection.
    """

    days: list[date]
    d_yield: list[float]
    d_gold: list[float]

    def __len__(self) -> int:
        return len(self.days)


def prepare(observations: list[DailyObservation]) -> ChangeSeries:
    return ChangeSeries(*to_changes(observations))


def fit_prepared(series: ChangeSeries, as_of: date, window: int) -> BetaFit:
    """Fit over the `window` changes dated strictly before `as_of`.

    The strictness is the point. An event at 08:30 on a Friday must not see
    that Friday's close, and `as_of` is the event's own date, so the cut is
    `bisect_left` and not `bisect_right`.
    """
    cut = bisect.bisect_left(series.days, as_of)
    if cut < window:
        return _nan_fit(window, cut, as_of)
    x = series.d_yield[cut - window:cut]
    y = series.d_gold[cut - window:cut]
    beta, alpha, r_squared, t_stat = ols(x, y)
    return BetaFit(window, window, beta, alpha, r_squared, t_stat, as_of)


def fit_as_of(observations: list[DailyObservation], as_of: date, window: int) -> BetaFit:
    """Convenience wrapper for a one-off fit. `fit_prepared` for panel builds."""
    return fit_prepared(prepare(observations), as_of, window)


def classify(
    fit: BetaFit,
    min_r_squared: float,
    min_abs_t: float = 2.0,
) -> str:
    """Bucket a fit into CLASSIC / DECOUPLED / INVERTED / INSUFFICIENT.

    `min_r_squared` has no default on purpose. It is a calibrated constant and
    must come from the threshold sweep in `ablation.sweep_threshold`; a default
    here would be exactly the invented number Phase 0 exists to eliminate.
    """
    if math.isnan(fit.beta) or math.isnan(fit.r_squared):
        return INSUFFICIENT
    if fit.r_squared < min_r_squared or abs(fit.t_stat) < min_abs_t:
        return DECOUPLED
    return CLASSIC if fit.beta < 0 else INVERTED


def sign_of_beta(fit: BetaFit) -> int:
    if math.isnan(fit.beta) or fit.beta == 0.0:
        return 0
    return 1 if fit.beta > 0 else -1
