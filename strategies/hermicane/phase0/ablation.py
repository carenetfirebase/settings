"""Filter ablation, threshold sweeps and the beta regime test (§3.3–§3.5).

The shape of the argument this module makes:

1. Run the control on every event. Its bootstrapped mean-R interval is the bar.
2. Apply each filter alone on top of the control. If the filtered interval does
   not clear the control's by a visible margin, the filter is noise.
3. Sweep each surviving filter's threshold and look at the *shape* of the
   curve. A real effect shows a broad plateau; a curve-fit shows a lonely
   spike. Take the middle of the plateau, never the peak.
4. Split every event by pre-event beta sign and R² tercile and compare. This is
   the v2 thesis, and it is allowed to fail.

`verdict` is deliberately harsh. §5 says prefer deleting a filter to tuning it,
and the parameter budget — five or six free parameters against perhaps seventy
five filtered trades — is the binding constraint on the whole design. A filter
that improves the mean but whose interval still overlaps the control has not
demonstrated anything, and "it looked better" is how a strategy acquires
twelve filters and no edge.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field, replace

from .beta import CLASSIC, INVERTED
from .control import (
    ATR_BASES,
    COST_LADDER_TICKS,
    TICK_SIZE,
    ControlSpec,
    average_true_range,
    simulate,
)
from .filters import FILTERS, Filter, beta_at, beta_r2_at
from .loaders import BarSeries
from .panel import EventRow, resample
from .stats import Interval, MeanEstimate, bootstrap_mean, sample_health, terciles

KEEP = "KEEP"
DELETE = "DELETE"

PASS = "PASS"
MARGINAL = "MARGINAL"
FAIL = "FAIL"
EMPTY = "NO SAMPLE"

#: Below this many surviving events, a filter's interval is too wide to clear
#: anything and the honest verdict is "untested", not "failed". §4.3's health
#: warning uses the same scale.
MIN_EVALUABLE = 30


def evaluable(rows: list[EventRow]) -> list[EventRow]:
    """Rows the control actually traded. Everything else has no outcome."""
    return [row for row in rows if row.is_evaluable]


def control_r(rows: list[EventRow], cost_ticks: int = 0, tick_size: float = TICK_SIZE) -> list[float]:
    """Control R-multiples, optionally re-costed.

    Re-costing is analytic rather than a re-simulation: under the first-order
    cost model stated in `control`, cost enters only as a subtraction scaled by
    the trade's own risk in price terms, and the stop and target paths are
    unchanged. That makes the §4.3 cost curve cheap enough to always print.
    """
    out: list[float] = []
    for row in evaluable(rows):
        result = row.control
        adjustment = (
            (cost_ticks * tick_size) / result.risk_price
            if cost_ticks and result.risk_price > 0
            else 0.0
        )
        out.append(result.r_multiple - adjustment)
    return out


@dataclass(frozen=True)
class Baseline:
    """§3.3. The number every filter is measured against."""

    estimate: MeanEstimate
    events_total: int
    events_traded: int
    rejections: dict[str, int]
    by_event_type: dict[str, MeanEstimate] = field(default_factory=dict)

    @property
    def health(self) -> str:
        return sample_health(self.estimate.n)


def control_baseline(rows: list[EventRow], resamples: int = 10_000) -> Baseline:
    traded = evaluable(rows)
    rejections: dict[str, int] = {}
    for row in rows:
        if row.is_evaluable:
            continue
        rejections[row.control.exit_reason] = rejections.get(row.control.exit_reason, 0) + 1

    by_type: dict[str, list[float]] = {}
    for row in traded:
        by_type.setdefault(row.event_type, []).append(row.control.r_multiple)

    return Baseline(
        estimate=bootstrap_mean([r.control.r_multiple for r in traded], resamples=resamples),
        events_total=len(rows),
        events_traded=len(traded),
        rejections=rejections,
        by_event_type={
            name: bootstrap_mean(values, resamples=resamples)
            for name, values in sorted(by_type.items())
        },
    )


@dataclass(frozen=True)
class AblationRow:
    filter_key: str
    label: str
    v1_claim: str
    threshold: float
    estimate: MeanEstimate
    delta_mean: float
    verdict: str
    recommendation: str
    retained_share: float

    def as_dict(self) -> dict[str, object]:
        return {
            "filter": self.filter_key,
            "label": self.label,
            "v1_claim": self.v1_claim,
            "threshold": self.threshold,
            "n": self.estimate.n,
            "mean_r": self.estimate.mean,
            "ci_low": self.estimate.ci.low,
            "ci_high": self.estimate.ci.high,
            "win_rate": self.estimate.win_rate,
            "delta_mean_r": self.delta_mean,
            "retained_share": self.retained_share,
            "verdict": self.verdict,
            "recommendation": self.recommendation,
            "sample_health": sample_health(self.estimate.n),
        }


def verdict(estimate: MeanEstimate, control: Interval) -> str:
    """Compare a filtered interval against the control's.

    PASS requires the filtered lower bound to sit above the control's *upper*
    bound. That is a demanding test and it is meant to be: with intervals this
    wide, anything weaker cannot tell a filter from a coincidence.
    """
    if estimate.n == 0:
        return EMPTY
    if estimate.n < MIN_EVALUABLE or math.isnan(estimate.ci.low):
        return FAIL
    if estimate.ci.low > control.high:
        return PASS
    if estimate.mean > control.high:
        return MARGINAL
    return FAIL


def ablate_one(
    rows: list[EventRow],
    filt: Filter,
    threshold: float,
    baseline: Baseline,
    resamples: int = 10_000,
) -> AblationRow:
    survivors = [row for row in evaluable(rows) if filt.passes(row, threshold)]
    estimate = bootstrap_mean([r.control.r_multiple for r in survivors], resamples=resamples)
    outcome = verdict(estimate, baseline.estimate.ci)
    return AblationRow(
        filter_key=filt.key,
        label=filt.label,
        v1_claim=filt.v1_claim,
        threshold=threshold,
        estimate=estimate,
        delta_mean=estimate.mean - baseline.estimate.mean,
        verdict=outcome,
        recommendation=KEEP if outcome == PASS else DELETE,
        retained_share=estimate.n / baseline.estimate.n if baseline.estimate.n else float("nan"),
    )


@dataclass(frozen=True)
class SweepPoint:
    threshold: float
    n: int
    mean_r: float
    ci_low: float
    ci_high: float


PLATEAU = "PLATEAU"
SPIKE = "SPIKE"
NONE_FOUND = "NONE"

#: A run of at least this many adjacent thresholds must beat the control before
#: the effect is called a plateau. Three is the smallest number that can
#: distinguish a shape from a point.
MIN_PLATEAU_WIDTH = 3


@dataclass(frozen=True)
class Sweep:
    filter_key: str
    label: str
    units: str
    points: list[SweepPoint]
    shape: str
    plateau: tuple[float, float] | None
    recommended: float
    note: str

    def as_dict(self) -> dict[str, object]:
        return {
            "filter": self.filter_key,
            "units": self.units,
            "shape": self.shape,
            "plateau_low": self.plateau[0] if self.plateau else None,
            "plateau_high": self.plateau[1] if self.plateau else None,
            "recommended": self.recommended,
            "note": self.note,
            "points": [
                {
                    "threshold": p.threshold, "n": p.n, "mean_r": p.mean_r,
                    "ci_low": p.ci_low, "ci_high": p.ci_high,
                }
                for p in self.points
            ],
        }


def sweep_threshold(
    rows: list[EventRow],
    filt: Filter,
    baseline: Baseline,
    resamples: int = 2_000,
) -> Sweep:
    """Mean R against threshold, plus a verdict on the curve's shape.

    §3.4 asks for the plot; this returns the data behind it and the reading.
    The recommendation is the midpoint of the widest qualifying run, never the
    argmax — the peak of a noisy curve is the single most overfit point on it.

    Width alone is not enough, and it took a noise test to notice why. Adjacent
    thresholds select **nested** subsets of the same events: the sample at 0.25
    contains almost everything in the sample at 0.20. So one lucky small subset
    propagates rightward and manufactures a run of four or five "independent"
    thresholds that all beat the control, purely because they are mostly the
    same trades. A plateau therefore has to be wide *and* contain at least one
    threshold that clears the control on its own confidence bound — the same
    bar `verdict` applies — before the shape is believed.
    """
    usable = evaluable(rows)
    points: list[SweepPoint] = []
    for threshold in filt.sweep:
        survivors = [row for row in usable if filt.passes(row, threshold)]
        estimate = bootstrap_mean(
            [r.control.r_multiple for r in survivors], resamples=resamples
        )
        points.append(
            SweepPoint(threshold, estimate.n, estimate.mean, estimate.ci.low, estimate.ci.high)
        )

    bar = baseline.estimate.ci.high
    qualifying = [
        bool(p.n >= MIN_EVALUABLE and not math.isnan(p.mean_r) and p.mean_r > bar)
        for p in points
    ]
    #: Nested-subset guard: somewhere in the run, one threshold must clear the
    #: control on its own lower bound, not merely on its point estimate.
    significant = [
        bool(p.n >= MIN_EVALUABLE and not math.isnan(p.ci_low) and p.ci_low > bar)
        for p in points
    ]

    best_start, best_length = -1, 0
    start = -1
    for i, ok in enumerate(qualifying + [False]):
        if ok and start < 0:
            start = i
        elif not ok and start >= 0:
            if i - start > best_length:
                best_start, best_length = start, i - start
            start = -1

    if best_length == 0:
        return Sweep(
            filt.key, filt.label, filt.units, points, NONE_FOUND, None, float("nan"),
            "No threshold beat the control on a sample large enough to judge. Delete the filter.",
        )
    low = points[best_start].threshold
    high = points[best_start + best_length - 1].threshold
    if best_length < MIN_PLATEAU_WIDTH:
        return Sweep(
            filt.key, filt.label, filt.units, points, SPIKE, (low, high), float("nan"),
            f"Only {best_length} adjacent threshold(s) beat the control. That is a spike, "
            "not an effect. Delete the filter rather than taking its best point.",
        )
    if not any(significant[best_start:best_start + best_length]):
        return Sweep(
            filt.key, filt.label, filt.units, points, SPIKE, (low, high), float("nan"),
            f"{best_length} adjacent thresholds beat the control on their point estimates "
            f"across [{low:g}, {high:g}], but none of them clears it on its own confidence "
            "bound. Adjacent thresholds select nested subsets of the same events, so a run "
            "this wide can be one lucky subset seen several times. Delete the filter.",
        )
    return Sweep(
        filt.key, filt.label, filt.units, points, PLATEAU, (low, high),
        (low + high) / 2.0,
        f"{best_length} adjacent thresholds beat the control across [{low:g}, {high:g}]. "
        "Recommendation is the midpoint of that run, not its peak.",
    )


@dataclass(frozen=True)
class RegimeBucket:
    name: str
    estimate: MeanEstimate
    directional_accuracy: float


@dataclass(frozen=True)
class BetaRegimeTable:
    """§3.5. The v2 thesis, stated so it can fail."""

    window: int
    r2_cuts: tuple[float, float]
    buckets: list[RegimeBucket]
    verdict: str
    note: str

    def as_dict(self) -> dict[str, object]:
        return {
            "window": self.window,
            "r2_tercile_cuts": list(self.r2_cuts),
            "verdict": self.verdict,
            "note": self.note,
            "buckets": [
                {"bucket": b.name, "directional_accuracy": b.directional_accuracy, **b.estimate.as_dict()}
                for b in self.buckets
            ],
        }


def beta_regime_table(
    rows: list[EventRow],
    window: int = 90,
    resamples: int = 5_000,
) -> BetaRegimeTable:
    """Split events by pre-event beta sign and R² tercile; compare mean R.

    The question §3.5 poses precisely: **is the model's directional accuracy
    conditional on beta regime?** A yes makes this the highest-value feature in
    the system and it becomes a hard gate. A no is a genuinely important
    negative result that invalidates the central thesis of v2, and this
    function reports it in the same words either way.
    """
    usable = [row for row in evaluable(rows) if not math.isnan(beta_at(row, window))]
    if len(usable) < MIN_EVALUABLE:
        return BetaRegimeTable(
            window, (float("nan"), float("nan")), [], "UNTESTED",
            f"Only {len(usable)} events carry a {window}-day beta fit. "
            "The thesis is neither supported nor refuted; it is unmeasured.",
        )

    cuts = terciles([beta_r2_at(row, window) for row in usable])

    def bucket_name(row: EventRow) -> str:
        beta_value = beta_at(row, window)
        r2 = beta_r2_at(row, window)
        sign = CLASSIC if beta_value < 0 else INVERTED
        if math.isnan(r2):
            return f"{sign} / R² unknown"
        tier = "R² low" if r2 <= cuts[0] else ("R² mid" if r2 <= cuts[1] else "R² high")
        return f"{sign} / {tier}"

    grouped: dict[str, list[EventRow]] = {}
    for row in usable:
        grouped.setdefault(bucket_name(row), []).append(row)

    buckets: list[RegimeBucket] = []
    for name, members in sorted(grouped.items()):
        values = [m.control.r_multiple for m in members]
        agreed = [m for m in members if m.impulse_dir != 0]
        accuracy = (
            sum(1 for m in agreed if m.impulse_dir == m.predicted_dir) / len(agreed)
            if agreed
            else float("nan")
        )
        buckets.append(RegimeBucket(name, bootstrap_mean(values, resamples=resamples), accuracy))

    classic = [b for b in buckets if b.name.startswith(CLASSIC) and b.estimate.n >= MIN_EVALUABLE]
    inverted = [b for b in buckets if b.name.startswith(INVERTED) and b.estimate.n >= MIN_EVALUABLE]
    if not classic or not inverted:
        return BetaRegimeTable(
            window, cuts, buckets, "UNDERPOWERED",
            "One side of the beta split has too few events to compare. The thesis "
            f"needs at least {MIN_EVALUABLE} evaluable events in both the classic "
            "and inverted regimes before it can be judged.",
        )

    best_classic = max(b.estimate.ci.low for b in classic)
    worst_inverted = max(b.estimate.ci.high for b in inverted)
    if best_classic > worst_inverted:
        return BetaRegimeTable(
            window, cuts, buckets, "SUPPORTED",
            "Classic-regime events outperform inverted-regime events with "
            "non-overlapping intervals. Beta regime belongs in v2 as a hard gate.",
        )
    return BetaRegimeTable(
        window, cuts, buckets, "NOT SUPPORTED",
        "Classic and inverted regimes are not separable at this sample size. "
        "The central thesis of v2 is not supported by this panel, and building "
        "the beta gate anyway would be adding a parameter on faith.",
    )


@dataclass(frozen=True)
class CostPoint:
    cost_ticks: int
    cost_dollars: float
    estimate: MeanEstimate


def cost_curve(
    rows: list[EventRow],
    ladder: tuple[int, ...] = COST_LADDER_TICKS,
    tick_size: float = TICK_SIZE,
    resamples: int = 5_000,
) -> list[CostPoint]:
    """§4.3. If the edge dies by 200 ticks it is not tradable through a print."""
    return [
        CostPoint(ticks, ticks * tick_size, bootstrap_mean(control_r(rows, ticks, tick_size), resamples=resamples))
        for ticks in ladder
    ]


@dataclass(frozen=True)
class WalkForward:
    calibration: MeanEstimate
    test: MeanEstimate
    split_at: str
    gap: float
    note: str


def walk_forward(rows: list[EventRow], calibration_share: float = 0.60, resamples: int = 5_000) -> WalkForward:
    """Chronological 60/40 split (§4.3). Never shuffled.

    A random split of event-study rows leaks the future into the calibration
    set through nothing more exotic than an adjacent release in the same
    regime. A large gap between the two halves means the constants were fit
    rather than found.
    """
    traded = sorted(evaluable(rows), key=lambda r: r.ts_utc)
    if len(traded) < 2:
        nan_estimate = bootstrap_mean([], resamples=resamples)
        return WalkForward(nan_estimate, nan_estimate, "n/a", float("nan"), "Too few events to split.")
    cut = max(1, int(len(traded) * calibration_share))
    head, tail = traded[:cut], traded[cut:]
    first = bootstrap_mean([r.control.r_multiple for r in head], resamples=resamples)
    second = bootstrap_mean([r.control.r_multiple for r in tail], resamples=resamples)
    gap = first.mean - second.mean
    note = (
        "Out-of-sample mean R is within the calibration interval; nothing here "
        "suggests fitting."
        if not math.isnan(second.mean) and first.ci.contains(second.mean)
        else "Out-of-sample mean R falls outside the calibration interval. Treat every "
        "constant chosen on the first segment as suspect."
    )
    return WalkForward(first, second, tail[0].ts_utc.date().isoformat() if tail else "n/a", gap, note)


def run_all_ablations(
    rows: list[EventRow],
    baseline: Baseline,
    resamples: int = 5_000,
) -> tuple[list[AblationRow], list[Sweep]]:
    """Every filter, at every swept threshold, against the control.

    Boolean filters produce one ablation row and no sweep. Threshold filters
    produce a sweep and one ablation row at the sweep's recommendation, or —
    when the sweep found nothing — at its midpoint, so the table still shows
    what the filter did rather than omitting the line.
    """
    ablations: list[AblationRow] = []
    sweeps: list[Sweep] = []
    for filt in FILTERS:
        if filt.is_boolean:
            ablations.append(ablate_one(rows, filt, 0.0, baseline, resamples=resamples))
            continue
        sweep = sweep_threshold(rows, filt, baseline, resamples=max(1_000, resamples // 3))
        sweeps.append(sweep)
        threshold = (
            sweep.recommended
            if not math.isnan(sweep.recommended)
            else filt.sweep[len(filt.sweep) // 2]
        )
        ablations.append(ablate_one(rows, filt, threshold, baseline, resamples=resamples))
    return ablations, sweeps


@dataclass(frozen=True)
class AtrBasisPoint:
    timeframe_minutes: int
    periods: int
    median_atr: float
    estimate: MeanEstimate


def atr_basis_sensitivity(
    rows: list[EventRow],
    prices: BarSeries,
    bases: tuple[tuple[int, int], ...] = ATR_BASES,
    spec: ControlSpec = ControlSpec(),
    resamples: int = 3_000,
) -> list[AtrBasisPoint]:
    """Re-run the control across candidate risk units.

    The handoff fixes the control's stop at "1.0 ATR" but not what ATR means,
    and the answer turns out to dominate the rule: a risk unit taken from
    1-minute bars is a fraction of a dollar, which a release goes through
    before the entry bar has closed, while one taken from daily bars is wider
    than the whole reaction. This is a **structural sensitivity, not a
    calibrated constant** — it is reported so the basis is chosen on evidence,
    and `report.py` lists it apart from anything the sweeps produced.

    Only the risk unit is re-derived. Direction comes from Δ2Y and does not
    depend on ATR, so it is taken from the panel unchanged.
    """
    points: list[AtrBasisPoint] = []
    for timeframe, periods in bases:
        series = resample(prices, timeframe)
        basis_spec = replace(spec, atr_timeframe_minutes=timeframe, atr_periods=periods)
        values: list[float] = []
        atrs: list[float] = []
        for row in rows:
            atr = average_true_range(series, row.ts_utc, periods)
            if math.isnan(atr):
                continue
            atrs.append(atr)
            result = simulate(prices, row.ts_utc, row.predicted_dir, atr, basis_spec)
            if result.traded and not math.isnan(result.r_multiple):
                values.append(result.r_multiple)
        points.append(
            AtrBasisPoint(
                timeframe, periods,
                sorted(atrs)[len(atrs) // 2] if atrs else float("nan"),
                bootstrap_mean(values, resamples=resamples),
            )
        )
    return points
