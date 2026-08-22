"""Feature → 0-100. SPEC §6.2.

Two methods, and which one produced a score is stamped on the row and shown in
the UI, because they are different kinds of claim:

* **percentile** — where this feature sits against its own trailing 36-month
  cross-sectional distribution. An *observation*.
* **fallback_threshold** — a piecewise-linear curve someone wrote down in
  ``weights.yaml``. A *hypothesis*.

For the whole of V1 it is the fallback, because percentile needs ≥500 prior
observations of that feature and the project has none. That is why Confidence
carries a ×0.7 penalty and every score on screen renders with the dotted
underline meaning "unvalidated — weights not yet backtested".

Nothing here reads the clock. The as-of date is an argument and the
distribution is passed in, so a rerun of a historical date produces the same
answer today as it did last week (SPEC §7.5).
"""

from __future__ import annotations

from bisect import bisect_left
from dataclasses import dataclass

from imt.db.enums import NormalizationMethod
from imt.scoring.categories import SCORE_PRECISION
from imt.scoring.weights import Weights


@dataclass(frozen=True, slots=True)
class NormalizedValue:
    score: float
    method: NormalizationMethod
    #: How many historical observations backed a percentile, for the tooltip.
    sample_size: int = 0


def interpolate(points: list[tuple[float, float]], raw: float) -> float:
    """Piecewise-linear interpolation, clamped at both ends.

    Clamped rather than extrapolated: a $500M insider purchase should score
    100, not 400. Extrapolating past the last point would let one enormous
    outlier dominate every other signal in the system.
    """
    if not points:
        raise ValueError("threshold curve is empty")
    if raw <= points[0][0]:
        return points[0][1]
    if raw >= points[-1][0]:
        return points[-1][1]

    for i in range(1, len(points)):
        x1, y1 = points[i - 1]
        x2, y2 = points[i]
        if raw <= x2:
            if x2 == x1:
                return y2
            fraction = (raw - x1) / (x2 - x1)
            return y1 + fraction * (y2 - y1)
    return points[-1][1]


def percentile_rank(distribution: list[float], raw: float) -> float:
    """Percentage of the distribution at or below ``raw``.

    The distribution must be pre-sorted; sorting here would hide an O(n log n)
    inside a function called once per feature per company.
    """
    if not distribution:
        return 0.0
    return 100.0 * bisect_left(distribution, raw) / len(distribution)


def normalize(
    feature_key: str,
    raw: float | None,
    weights: Weights,
    *,
    distribution: list[float] | None = None,
) -> NormalizedValue | None:
    """Normalize one feature. Returns None when the input is missing.

    A missing feature is not a zero. Returning 0.0 here would make "no insider
    purchases" indistinguishable from "insider purchases worth nothing", and
    the first should remove the category from convergence while the second
    should score it low.
    """
    if raw is None:
        return None

    if distribution is not None and len(distribution) >= weights.min_observations:
        return NormalizedValue(
            score=round(percentile_rank(distribution, raw), SCORE_PRECISION),
            method=NormalizationMethod.PERCENTILE,
            sample_size=len(distribution),
        )

    curve = weights.thresholds.get(feature_key)
    if curve is None:
        raise KeyError(
            f"No threshold curve for feature {feature_key!r} in config/weights.yaml, and "
            f"too few observations for a percentile. Add the curve rather than letting "
            f"the feature default to a score."
        )

    return NormalizedValue(
        score=round(max(0.0, min(100.0, interpolate(curve, raw))), SCORE_PRECISION),
        method=NormalizationMethod.FALLBACK_THRESHOLD,
        sample_size=len(distribution) if distribution else 0,
    )


def dominant_method(methods: list[NormalizationMethod]) -> NormalizationMethod:
    """The method stamped on the score row.

    If any input fell back to a threshold, the composite is threshold-based —
    a score is only as validated as its least validated input, and rounding
    that up would overstate the whole row.
    """
    return (
        NormalizationMethod.PERCENTILE
        if methods and all(m is NormalizationMethod.PERCENTILE for m in methods)
        else NormalizationMethod.FALLBACK_THRESHOLD
    )
