"""The Phase 0 deliverables (§3.6): the report, and the constants file.

Two artefacts come out of here and they are governed by different rules.

`ablation_report.md` is written from any run, synthetic or real, because a
report of a synthetic run is a useful record of what the harness did. It
carries its provenance in the first screen, so it cannot be mistaken for a
measurement of gold.

`calibrated_constants.json` is written **only** when every series in the run's
provenance came from a real feed. §4 is unambiguous that Phase 1 does not start
until this file exists and that every threshold in v2 comes from it; if a
synthetic dry run could produce it, that rule would protect nothing. A
non-real run writes `calibrated_constants.SYNTHETIC.json` instead, whose
`calibrated` flag is false and which `verify_constants` refuses.

The report is also where negative results are given equal billing (§5). Filters
that failed are listed before filters that passed, with the v1 claim each one
was making, because "the pullback filter did not beat the control" is a more
valuable output than a tuned equity curve.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

from .ablation import (
    DELETE,
    KEEP,
    AblationRow,
    AtrBasisPoint,
    Baseline,
    BetaRegimeTable,
    CostPoint,
    Sweep,
    WalkForward,
)
from .control import ControlSpec
from .filters import SCORE_COMPONENTS_TO_DROP
from .panel import (
    BREAKOUT_LOOKBACK_BARS,
    IMPULSE_MINUTES,
    PULLBACK_SEARCH_MINUTES,
    SURPRISE_LOOKBACK,
    EventRow,
)
from .sources import Provenance
from .stats import sample_health


class NotCalibrated(RuntimeError):
    """Refusal to treat a synthetic or partial run as calibrated output."""


@dataclass
class Phase0Results:
    """Everything a report needs, gathered in one object."""

    provenance: Provenance
    spec: ControlSpec
    rows: list[EventRow]
    baseline: Baseline
    ablations: list[AblationRow]
    sweeps: list[Sweep]
    regime: BetaRegimeTable
    costs: list[CostPoint]
    walk: WalkForward
    atr_bases: list[AtrBasisPoint]


def _fmt(value: float, places: int = 3) -> str:
    return "n/a" if value is None or (isinstance(value, float) and math.isnan(value)) else f"{value:+.{places}f}"


def _pct(value: float) -> str:
    return "n/a" if value is None or math.isnan(value) else f"{value * 100:.1f}%"


def structural_choices(spec: ControlSpec) -> list[tuple[str, object, str]]:
    """Choices the handoff left open, which the harness had to make.

    Listed separately from anything the sweeps produced, and never written to
    the constants file as if they had been measured. Each one is a place where
    a different reasonable choice would change the numbers, so each is named.
    """
    return [
        (
            "ATR basis",
            f"{spec.atr_timeframe_minutes}-minute bars, {spec.atr_periods} periods",
            (
                "§3.3 fixes the stop at 1.0 ATR but not the timeframe. It dominates the "
                "control's results — see the ATR basis table — and must be settled first."
            ),
        ),
        (
            "Intrabar ambiguity",
            "resolves as a stop",
            (
                "1-minute OHLC cannot say whether the stop or the target came first. The "
                "conservative reading is the one that does not flatter the strategy."
            ),
        ),
        (
            "Cost model",
            "round-trip, deducted in R at exit",
            (
                "First-order: ignores that a worse entry fill also moves the stop. The cost "
                "curve is reported across the whole ladder because the level matters more "
                "than the model."
            ),
        ),
        (
            "Impulse window",
            f"T+0 to T+{IMPULSE_MINUTES}, against the last close before the release",
            "Matches v1's three-minute window so the ablation tests v1's actual filter.",
        ),
        (
            "Pullback and breakout search",
            f"{PULLBACK_SEARCH_MINUTES} minutes after the impulse, {BREAKOUT_LOOKBACK_BARS}-bar extreme",
            "v1 implies a timeout without fixing one.",
        ),
        (
            "Surprise z-score lookback",
            f"{SURPRISE_LOOKBACK} prior releases of the same type",
            "§3.2's '~20'. Fewer than five prior releases yields NaN, not a guess.",
        ),
    ]


def render_report(results: Phase0Results) -> str:
    provenance = results.provenance
    baseline = results.baseline
    lines: list[str] = []
    add = lines.append

    add("# HERMICANE v2 — Phase 0 ablation report")
    add("")

    if not provenance.is_real:
        add("> ## ⚠ THIS RUN IS NOT CALIBRATED OUTPUT")
        add(">")
        add("> One or more series did not come from a real feed. Every number below is")
        add("> a property of the inputs listed under Provenance, **not a measurement of")
        add("> gold**. No constant here may be ported to Pine, and no")
        add("> `calibrated_constants.json` has been written.")
        add("")

    # --- provenance -------------------------------------------------------
    add("## Provenance")
    add("")
    add(f"Generated {provenance.generated_utc}. Quality: **{provenance.as_dict()['quality']}**.")
    add("")
    add("| Series | Origin | Detail | Proxy for |")
    add("| --- | --- | --- | --- |")
    for entry in provenance.entries:
        add(f"| `{entry['series']}` | {entry['origin']} | {entry['detail'] or '—'} | {entry['proxy_for'] or '—'} |")
    add("")
    for note in provenance.notes:
        add(f"> {note}")
        add("")

    # --- control ----------------------------------------------------------
    estimate = baseline.estimate
    add("## 1. The control (§3.3)")
    add("")
    add("Enter at T+3 in the direction of `-sign(Δ2Y)`, stop 1.0 ATR, target 2.0 ATR,")
    add("time exit 120 minutes. No filtering whatsoever. **This interval is the bar")
    add("every filter below has to clear.**")
    add("")
    add(f"- Events in panel: **{baseline.events_total}**")
    add(f"- Events the control could trade: **{baseline.events_traded}**")
    add(f"- Mean R: **{_fmt(estimate.mean)}**, 95% CI **{estimate.ci}**")
    add(f"- Median R {_fmt(estimate.median)} · win rate {_pct(estimate.win_rate)} · sd {_fmt(estimate.stdev)}")
    add(f"- Share of bootstrap resamples above zero: {_pct(estimate.prob_positive)}")
    add(f"- Sample health: **{baseline.health}** ({sample_health(estimate.n)} at n={estimate.n})")
    add("")
    if baseline.rejections:
        add("Events the control could not trade:")
        add("")
        for reason, count in sorted(baseline.rejections.items(), key=lambda kv: -kv[1]):
            add(f"- `{reason}`: {count}")
        add("")
    if baseline.by_event_type:
        add("### Control by event type")
        add("")
        add("| Event | n | Mean R | 95% CI | Win rate | Health |")
        add("| --- | ---: | ---: | :---: | ---: | :---: |")
        for name, per_type in baseline.by_event_type.items():
            add(
                f"| {name} | {per_type.n} | {_fmt(per_type.mean)} | {per_type.ci} | "
                f"{_pct(per_type.win_rate)} | {sample_health(per_type.n)} |"
            )
        add("")

    # --- ablation, failures first ----------------------------------------
    add("## 2. Filter ablation (§3.4)")
    add("")
    add("Each filter applied **alone** on top of the control. A filter passes only if")
    add("its lower confidence bound clears the control's upper bound — anything weaker")
    add("cannot be told from a coincidence at this sample size. Failures are listed")
    add("first, deliberately (§5).")
    add("")
    failures = [row for row in results.ablations if row.recommendation == DELETE]
    passes = [row for row in results.ablations if row.recommendation == KEEP]

    def table(rows: list[AblationRow]) -> None:
        add("| Filter | Threshold | n | Retained | Mean R | 95% CI | Δ vs control | Verdict |")
        add("| --- | ---: | ---: | ---: | ---: | :---: | ---: | :---: |")
        for row in rows:
            add(
                f"| {row.label} | {_fmt(row.threshold, 2) if row.estimate.n != 0 else '—'} | "
                f"{row.estimate.n} | {_pct(row.retained_share)} | {_fmt(row.estimate.mean)} | "
                f"{row.estimate.ci} | {_fmt(row.delta_mean)} | **{row.verdict}** |"
            )
        add("")

    add(f"### Deleted — {len(failures)} filter(s) did not clear the control")
    add("")
    if failures:
        table(failures)
        add("The claim each deleted filter was making, now unsupported by this panel:")
        add("")
        for row in failures:
            add(f"- **{row.label}** — “{row.v1_claim}”")
        add("")
    else:
        add("None.")
        add("")

    add(f"### Retained — {len(passes)} filter(s) cleared the control")
    add("")
    if passes:
        table(passes)
    else:
        add("**None.** No filter in v1 beat the unfiltered control on this panel. If this")
        add("holds on real data it is the single most important result of Phase 0: the")
        add("filter stack is shrinking the sample, not adding edge, and v2 should ship")
        add("with the control rule and the beta gate alone.")
        add("")

    # --- sweeps -----------------------------------------------------------
    add("## 3. Threshold sweeps (§3.4)")
    add("")
    add("A real effect shows a broad plateau; a curve-fit shows a lonely spike. The")
    add("recommendation is always the midpoint of the widest qualifying run, never the")
    add("peak of the curve.")
    add("")
    for sweep in results.sweeps:
        add(f"### {sweep.label} (`{sweep.filter_key}`)")
        add("")
        add(f"Shape: **{sweep.shape}**. {sweep.note}")
        add("")
        add(f"| Threshold ({sweep.units}) | n | Mean R | 95% CI |")
        add("| ---: | ---: | ---: | :---: |")
        for point in sweep.points:
            marker = " ◀" if sweep.plateau and sweep.plateau[0] <= point.threshold <= sweep.plateau[1] else ""
            add(
                f"| {point.threshold:g}{marker} | {point.n} | {_fmt(point.mean_r)} | "
                f"[{_fmt(point.ci_low)}, {_fmt(point.ci_high)}] |"
            )
        add("")

    # --- beta regime ------------------------------------------------------
    add("## 4. The beta regime test (§3.5)")
    add("")
    add("Is the model's directional accuracy conditional on beta regime? This is the")
    add("central thesis of v2, and it is allowed to fail.")
    add("")
    add(f"**Verdict: {results.regime.verdict}.** {results.regime.note}")
    add("")
    if results.regime.buckets:
        cuts = results.regime.r2_cuts
        add(f"{results.regime.window}-day window; R² tercile cuts at {cuts[0]:.3f} / {cuts[1]:.3f}.")
        add("")
        add("| Bucket | n | Mean R | 95% CI | Win rate | Directional accuracy |")
        add("| --- | ---: | ---: | :---: | ---: | ---: |")
        for bucket in results.regime.buckets:
            add(
                f"| {bucket.name} | {bucket.estimate.n} | {_fmt(bucket.estimate.mean)} | "
                f"{bucket.estimate.ci} | {_pct(bucket.estimate.win_rate)} | "
                f"{_pct(bucket.directional_accuracy)} |"
            )
        add("")

    # --- structural sensitivities ----------------------------------------
    add("## 5. Structural choices and sensitivities")
    add("")
    add("These are **not calibrated constants**. They are decisions the handoff left")
    add("open that the harness had to make in order to run at all. Each is a place")
    add("where a different reasonable choice would move the numbers above.")
    add("")
    add("| Choice | Value | Why it matters |")
    add("| --- | --- | --- |")
    for name, value, why in structural_choices(results.spec):
        add(f"| {name} | `{value}` | {why} |")
    add("")
    add("### ATR basis sensitivity")
    add("")
    add("The control's stop is \"1.0 ATR\". What ATR means changes the rule completely.")
    add("")
    add("| Timeframe | Periods | Median ATR | n | Mean R | 95% CI |")
    add("| ---: | ---: | ---: | ---: | ---: | :---: |")
    for point in results.atr_bases:
        add(
            f"| {point.timeframe_minutes}m | {point.periods} | {point.median_atr:.2f} | "
            f"{point.estimate.n} | {_fmt(point.estimate.mean)} | {point.estimate.ci} |"
        )
    add("")

    # --- costs and walk-forward ------------------------------------------
    add("## 6. Cost sensitivity (§4.3)")
    add("")
    add("v1 assumed 20 ticks of slippage — twenty cents on gold — and zero commission.")
    add("Real CPI-minute spreads are dollars wide. If the edge dies by 200 ticks it is")
    add("not tradable through a news print.")
    add("")
    add("| Slippage (ticks) | $ per round trip | n | Mean R | 95% CI | Above zero |")
    add("| ---: | ---: | ---: | ---: | :---: | ---: |")
    for point in results.costs:
        add(
            f"| {point.cost_ticks} | {point.cost_dollars:.2f} | {point.estimate.n} | "
            f"{_fmt(point.estimate.mean)} | {point.estimate.ci} | {_pct(point.estimate.prob_positive)} |"
        )
    add("")

    add("## 7. Walk-forward (§4.3)")
    add("")
    walk = results.walk
    add(f"Chronological 60/40 split at {walk.split_at}. Never shuffled.")
    add("")
    add(f"- Calibration: n={walk.calibration.n}, mean R {_fmt(walk.calibration.mean)}, CI {walk.calibration.ci}")
    add(f"- Test: n={walk.test.n}, mean R {_fmt(walk.test.mean)}, CI {walk.test.ci}")
    add(f"- Gap: {_fmt(walk.gap)}")
    add("")
    add(f"> {walk.note}")
    add("")

    # --- design findings --------------------------------------------------
    add("## 8. Findings that do not depend on the data")
    add("")
    add("These are statements about v1's design rather than about gold, so no sample")
    add("size changes them.")
    add("")
    add(
        "- **Score components that are constant at entry.** v1's entry condition already "
        f"requires the breakout and the 5-minute confirmation, so `{'`, `'.join(SCORE_COMPONENTS_TO_DROP)}` "
        "are pinned at 10 on every trade that happens — a fixed +0.8 on every score that "
        "looks variable. With the 5-minute filter switched off, `fiveScore` stays 10, so "
        "*disabling* a filter raises the score. A hard gate must never also contribute a "
        "score term."
    )
    add(
        "- **Macro confirmation is not independent confirmation.** Gold, DXY and the 2Y "
        "reprice off the same headline in the same second. Requiring agreement inside a "
        "three-minute window counts one piece of information several times, and in v1 it "
        "is 25% of the score plus part of the price score."
    )
    add(
        "- **The global surprise unit is a bug, not a tuning choice.** A single divisor "
        "of 0.20 saturates instantly for Jobless Claims, GDP, ISM, Retail Sales and JOLTS, "
        "pinning them at 10/10 on every release. The z-score against the same event type's "
        "own recent dispersion removes the input entirely."
    )
    add("")

    return "\n".join(lines) + "\n"


def constants_payload(results: Phase0Results) -> dict[str, object]:
    """The machine-readable half of §3.6, ready for the Pine port."""
    retained = [row for row in results.ablations if row.recommendation == KEEP]
    sweeps = {sweep.filter_key: sweep for sweep in results.sweeps}
    return {
        "schema": "hermicane/calibrated_constants/1",
        "calibrated": results.provenance.is_real,
        "generated_utc": results.provenance.generated_utc,
        "provenance": results.provenance.as_dict(),
        "panel": {
            "events_total": results.baseline.events_total,
            "events_traded": results.baseline.events_traded,
            "sample_health": results.baseline.health,
        },
        "control": results.spec.as_dict(),
        "control_baseline": results.baseline.estimate.as_dict(),
        "beta_regime": results.regime.as_dict(),
        "surviving_filters": [
            {
                **row.as_dict(),
                "sweep_shape": sweeps[row.filter_key].shape if row.filter_key in sweeps else "boolean",
                "plateau": (
                    list(sweeps[row.filter_key].plateau)
                    if row.filter_key in sweeps and sweeps[row.filter_key].plateau
                    else None
                ),
            }
            for row in retained
        ],
        "deleted_filters": [
            {"filter": row.filter_key, "v1_claim": row.v1_claim, "verdict": row.verdict}
            for row in results.ablations
            if row.recommendation != KEEP
        ],
        "structural_choices": [
            {"choice": name, "value": str(value), "why": why}
            for name, value, why in structural_choices(results.spec)
        ],
        "cost_curve": [
            {"cost_ticks": p.cost_ticks, **p.estimate.as_dict()} for p in results.costs
        ],
        "atr_basis_sensitivity": [
            {
                "timeframe_minutes": p.timeframe_minutes,
                "periods": p.periods,
                "median_atr": p.median_atr,
                **p.estimate.as_dict(),
            }
            for p in results.atr_bases
        ],
        "walk_forward": {
            "split_at": results.walk.split_at,
            "calibration": results.walk.calibration.as_dict(),
            "test": results.walk.test.as_dict(),
            "gap": results.walk.gap,
            "note": results.walk.note,
        },
    }


def write_outputs(results: Phase0Results, out_dir: Path) -> dict[str, Path]:
    """Write the report, the provenance and — only if earned — the constants.

    Returns the paths written, so the CLI can say plainly which artefacts exist
    and which were withheld.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    written: dict[str, Path] = {}

    report_path = out_dir / "ablation_report.md"
    report_path.write_text(render_report(results), encoding="utf-8")
    written["report"] = report_path

    provenance_path = out_dir / "provenance.json"
    results.provenance.write(provenance_path)
    written["provenance"] = provenance_path

    payload = constants_payload(results)
    if results.provenance.is_real:
        constants_path = out_dir / "calibrated_constants.json"
    else:
        constants_path = out_dir / "calibrated_constants.SYNTHETIC.json"
    constants_path.write_text(json.dumps(payload, indent=2, default=str) + "\n", encoding="utf-8")
    written["constants"] = constants_path

    return written


def verify_constants(path: Path) -> dict[str, object]:
    """Load a constants file, refusing anything that is not calibrated.

    This is the gate §4 describes: Phase 1 does not begin until a real
    `calibrated_constants.json` exists, and every threshold in v2 comes from
    it. Any Pine-generation step should call this first and let it raise.
    """
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if payload.get("schema") != "hermicane/calibrated_constants/1":
        raise NotCalibrated(f"{path}: not a HERMICANE constants file")
    if not payload.get("calibrated"):
        raise NotCalibrated(
            f"{path}: this file was produced from data that was not entirely real. "
            "Phase 1 must not start from it. Obtain the series listed under "
            "provenance and re-run the harness."
        )
    return payload


def write_panel_csv(rows: list[EventRow], path: Path) -> Path:
    """The panel itself (§3.6), as CSV.

    §3.6 asks for `panel.parquet`. CSV is written unconditionally because this
    package is standard-library only; `write_panel_parquet` upgrades it when
    pyarrow happens to be installed.
    """
    import csv

    path.parent.mkdir(parents=True, exist_ok=True)
    records = [row.as_dict() for row in rows]
    if not records:
        path.write_text("", encoding="utf-8")
        return path
    columns: list[str] = []
    for record in records:
        for key in record:
            if key not in columns:
                columns.append(key)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for record in records:
            writer.writerow(record)
    return path


def write_panel_parquet(rows: list[EventRow], path: Path) -> Path | None:
    """Write `panel.parquet` when pyarrow is available, else return None.

    Deliberately optional. The analysis never reads the parquet — it is an
    interchange artefact for whatever the operator wants to do next — so a
    missing pyarrow degrades the deliverable rather than the result.
    """
    try:
        import pyarrow as pa
        import pyarrow.parquet as pq
    except ImportError:
        return None
    records = [row.as_dict() for row in rows]
    if not records:
        return None
    columns: list[str] = []
    for record in records:
        for key in record:
            if key not in columns:
                columns.append(key)
    table = pa.table({name: [record.get(name) for record in records] for name in columns})
    path.parent.mkdir(parents=True, exist_ok=True)
    pq.write_table(table, path)
    return path
