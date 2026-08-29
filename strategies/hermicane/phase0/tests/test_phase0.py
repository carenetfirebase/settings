"""Tests for the Phase 0 computation core.

The core has to be right before real data arrives, and the only way to know it
is right is to run it against worlds whose answers are known in advance. So the
tests here plant an effect and check the machinery recovers it, plant no effect
and check the machinery says so, and — most importantly — check the guards: no
lookahead, and no path by which a synthetic run produces calibrated constants.

Standard library only, and no network.
"""

from __future__ import annotations

import json
import math
import random
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import pytest

from phase0 import beta, control, filters, loaders, panel, report, stats
from phase0.ablation import (
    KEEP,
    NONE_FOUND,
    PASS,
    PLATEAU,
    SPIKE,
    Baseline,
    ablate_one,
    beta_regime_table,
    control_baseline,
    cost_curve,
    sweep_threshold,
    walk_forward,
)
from phase0.control import ControlResult, ControlSpec
from phase0.loaders import Bar, BarSeries, MacroEvent
from phase0.sources import Provenance

T0 = datetime(2024, 3, 12, 12, 30, tzinfo=UTC)


# --- helpers -------------------------------------------------------------

def make_bars(start: datetime, closes: list[float], half_range: float = 0.5) -> list[Bar]:
    return [
        Bar(start + timedelta(minutes=i), c, c + half_range, c - half_range, c)
        for i, c in enumerate(closes)
    ]


def make_row(
    r_multiple: float,
    *,
    ts: datetime = T0,
    surprise_z: float = 1.0,
    pullback_frac: float = 0.4,
    beta_value: float = -0.05,
    r_squared: float = 0.4,
    impulse_dir: int = 1,
    predicted_dir: int = 1,
    risk_price: float = 2.0,
) -> panel.EventRow:
    """A panel row carrying a chosen outcome. Only the fields the tests read."""
    fit = beta.BetaFit(90, 90, beta_value, 0.0, r_squared, -5.0, ts.date())
    result = ControlResult(
        traded=True, direction=predicted_dir, entry_ts=ts, entry_price=100.0,
        stop_price=98.0, target_price=104.0, risk_price=risk_price, exit_ts=ts,
        exit_price=100.0, exit_reason="target", r_multiple=r_multiple,
        mae_r=0.0, mfe_r=abs(r_multiple), minutes_held=10,
    )
    return panel.EventRow(
        ts_utc=ts, ts_ny=ts.astimezone(panel.NEW_YORK), event_type="CPI",
        actual=3.0, consensus=2.8, consensus_sd=0.2,
        surprise_raw=0.2, surprise_z=surprise_z,
        beta_fits={60: fit, 90: fit, 120: fit}, realised_vol_20d=0.008, atr=2.0,
        drift_atr={"60m": 0.0, "4h": 0.0, "1d": 0.0}, trend_15m=1, trend_1h=1,
        d_yield={h: -0.01 for h in panel.REACTION_HORIZONS},
        d_dxy={h: -0.05 for h in panel.REACTION_HORIZONS},
        d_xau={h: 1.0 for h in panel.REACTION_HORIZONS},
        impulse_atr=1.2, impulse_dir=impulse_dir, pullback_frac=pullback_frac,
        origin_held=True, micro_breakout=True, breakout_minute=8.0,
        macro_aligned=1.0, five_min_dir=1, predicted_dir=predicted_dir,
        fwd_r={h: r_multiple for h in panel.REACTION_HORIZONS}, control=result,
    )


# --- stats ---------------------------------------------------------------

def test_bootstrap_interval_covers_the_true_mean():
    rng = random.Random(11)
    values = [rng.gauss(0.25, 1.0) for _ in range(400)]
    estimate = stats.bootstrap_mean(values, resamples=3000)
    assert estimate.n == 400
    assert estimate.ci.low < 0.25 < estimate.ci.high
    assert 0.0 < estimate.prob_positive <= 1.0


def test_bootstrap_handles_degenerate_samples_without_raising():
    empty = stats.bootstrap_mean([])
    assert empty.n == 0 and math.isnan(empty.mean)
    single = stats.bootstrap_mean([1.5])
    assert single.n == 1 and single.mean == 1.5


def test_sample_health_thresholds_track_the_standard_error_argument():
    assert stats.sample_health(400) == "ADEQUATE"
    assert stats.sample_health(120) == "THIN"
    assert stats.sample_health(75) == "UNDERPOWERED"
    assert stats.sample_health(20) == "ANECDOTE"


# --- beta ----------------------------------------------------------------

def test_ols_recovers_a_planted_slope():
    rng = random.Random(3)
    xs = [rng.gauss(0, 0.05) for _ in range(300)]
    ys = [-2.0 * x + rng.gauss(0, 0.002) for x in xs]
    slope, _, r_squared, t_stat = beta.ols(xs, ys)
    assert slope == pytest.approx(-2.0, abs=0.05)
    assert r_squared > 0.95
    assert t_stat < -10


def test_ols_refuses_a_regressor_with_no_variance():
    slope, _, _, _ = beta.ols([1.0] * 10, [float(i) for i in range(10)])
    assert math.isnan(slope)


def _daily(n: int, sensitivity: float, seed: int = 5) -> list[beta.DailyObservation]:
    rng = random.Random(seed)
    out, gold, yld, day = [], 2000.0, 4.0, date(2023, 1, 2)
    for _ in range(n):
        step = rng.gauss(0, 0.05)
        yld += step
        gold *= math.exp(sensitivity * step + rng.gauss(0, 0.003))
        out.append(beta.DailyObservation(day, gold, yld))
        day += timedelta(days=1)
    return out


def test_fit_is_strictly_backward_looking():
    observations = _daily(200, -2.0)
    as_of = observations[120].day
    fit = beta.fit_as_of(observations, as_of, 60)
    assert fit.as_of == as_of
    assert fit.n == 60
    # Truncating everything from `as_of` onward must not change the fit.
    truncated = [o for o in observations if o.day < as_of]
    assert beta.fit_as_of(truncated, as_of, 60).beta == pytest.approx(fit.beta)


def test_fit_reports_insufficient_history_rather_than_guessing():
    fit = beta.fit_as_of(_daily(200, -2.0), date(2023, 1, 20), 90)
    assert math.isnan(fit.beta)
    assert beta.classify(fit, 0.3) == beta.INSUFFICIENT


def test_classify_separates_the_three_regimes():
    strong_negative = beta.BetaFit(90, 90, -2.0, 0.0, 0.60, -12.0)
    strong_positive = beta.BetaFit(90, 90, +2.0, 0.0, 0.60, +12.0)
    noise = beta.BetaFit(90, 90, -0.1, 0.0, 0.01, -0.4)
    assert beta.classify(strong_negative, 0.30) == beta.CLASSIC
    assert beta.classify(strong_positive, 0.30) == beta.INVERTED
    assert beta.classify(noise, 0.30) == beta.DECOUPLED


def test_prepared_and_one_off_fits_agree():
    observations = _daily(200, -1.5)
    as_of = observations[150].day
    prepared = beta.prepare(observations)
    assert beta.fit_prepared(prepared, as_of, 90).beta == pytest.approx(
        beta.fit_as_of(observations, as_of, 90).beta
    )


# --- control -------------------------------------------------------------

def _series_with_pre_history(post: list[float], half_range: float = 0.5) -> BarSeries:
    pre = make_bars(T0 - timedelta(minutes=400), [100.0] * 400, half_range)
    return BarSeries("X", pre + make_bars(T0, post, half_range))


def test_control_takes_the_target_and_the_stop_on_the_right_paths():
    atr = 1.0
    up = _series_with_pre_history([100.0 + 0.25 * i for i in range(130)])
    won = control.simulate(up, T0, +1, atr)
    assert won.exit_reason == control.EXIT_TARGET
    assert won.r_multiple == pytest.approx(2.0)

    lost = control.simulate(up, T0, -1, atr)
    assert lost.exit_reason == control.EXIT_STOP
    assert lost.r_multiple == pytest.approx(-1.0)


def test_control_times_out_when_neither_level_is_reached():
    flat = _series_with_pre_history([100.0] * 200, half_range=0.05)
    result = control.simulate(flat, T0, +1, 10.0)
    assert result.exit_reason == control.EXIT_TIME
    assert result.minutes_held == 120


def test_a_bar_touching_both_levels_resolves_as_a_stop():
    bars = make_bars(T0, [100.0] * 14, half_range=0.1)
    # Widen the bar after entry so it spans stop and target at once.
    bars[5] = Bar(bars[5].ts, 100.0, 105.0, 95.0, 100.0)
    series = BarSeries("X", make_bars(T0 - timedelta(minutes=400), [100.0] * 400, 0.1) + bars)
    result = control.simulate(series, T0, +1, 1.0)
    assert result.exit_reason == control.EXIT_STOP


def test_costs_are_deducted_in_r_and_scale_with_the_risk_unit():
    up = _series_with_pre_history([100.0 + 0.25 * i for i in range(130)])
    free = control.simulate(up, T0, +1, 1.0, ControlSpec())
    costed = control.simulate(up, T0, +1, 1.0, ControlSpec(cost_ticks=200))
    # 200 ticks at $0.01 against a $1.00 risk unit is exactly 2R.
    assert free.r_multiple - costed.r_multiple == pytest.approx(2.0)


def test_control_declines_rather_than_guessing_when_inputs_are_missing():
    up = _series_with_pre_history([100.0 + 0.25 * i for i in range(130)])
    assert control.simulate(up, T0, 0, 1.0).exit_reason == control.EXIT_NO_DIRECTION
    assert control.simulate(up, T0, 1, float("nan")).exit_reason == control.EXIT_NO_DATA
    assert control.control_direction(0.0) == 0
    assert control.control_direction(float("nan")) == 0
    assert control.control_direction(0.02) == -1
    assert control.control_direction(-0.02) == +1


def test_atr_uses_only_bars_closed_before_the_release():
    fifteen = panel.resample(_series_with_pre_history([100.0] * 130), 15)
    value = control.average_true_range(fifteen, T0, 14)
    assert value > 0
    assert math.isnan(control.average_true_range(BarSeries("X", []), T0, 14))


# --- panel ---------------------------------------------------------------

def test_surprise_z_uses_only_prior_releases_of_the_same_type():
    rng = random.Random(9)
    history = [
        MacroEvent(T0 - timedelta(days=30 * (12 - i)), "CPI", 2.0 + rng.gauss(0, 0.2), 2.0, 0.2)
        for i in range(12)
    ]
    z = panel.rolling_surprise_z(MacroEvent(T0, "CPI", 2.6, 2.0, 0.2), history)
    assert not math.isnan(z)
    # A different event type shares no history, so there is nothing to scale by.
    assert math.isnan(panel.rolling_surprise_z(MacroEvent(T0, "ISM", 55.0, 52.0, 1.4), history))


def test_surprise_z_returns_nan_rather_than_a_guess_on_thin_history():
    history = [MacroEvent(T0 - timedelta(days=30), "CPI", 2.1, 2.0, 0.2)]
    assert math.isnan(panel.rolling_surprise_z(MacroEvent(T0, "CPI", 2.6, 2.0, 0.2), history))


def test_five_minute_direction_reads_only_closed_bars():
    rising = make_bars(T0 - timedelta(minutes=60), [100.0 + 0.1 * i for i in range(60)])
    five = panel.resample(BarSeries("X", rising), 5)
    assert panel.five_minute_direction(five, T0) == 1
    assert panel.five_minute_direction(five, T0 - timedelta(minutes=60)) == 0


def test_measure_impulse_recovers_a_planted_shape():
    # Up 6.0 over three minutes, then a ~50% retracement that holds above the
    # pre-news level, then a break to a new high.
    closes = [102.0, 104.0, 106.0] + [106.0 - 0.3 * i for i in range(1, 11)] + [
        103.0 + 0.5 * i for i in range(1, 12)
    ]
    series = BarSeries(
        "X",
        make_bars(T0 - timedelta(minutes=400), [100.0] * 400, 0.05) + make_bars(T0, closes, 0.05),
    )
    shape = panel.measure_impulse(series, T0, atr=2.0)
    assert shape.direction == 1
    assert shape.impulse_atr == pytest.approx((106.05 - 100.0) / 2.0, abs=0.1)
    assert 0.4 < shape.pullback_frac < 0.7
    assert shape.origin_held is True
    assert shape.breakout is True


def test_macro_alignment_counts_only_the_legs_that_exist():
    assert panel.macro_alignment(-0.02, -0.10, +1) == 1.0
    assert panel.macro_alignment(+0.02, -0.10, +1) == 0.5
    assert panel.macro_alignment(-0.02, float("nan"), +1) == 1.0
    assert math.isnan(panel.macro_alignment(-0.02, -0.10, 0))


# --- ablation ------------------------------------------------------------

def _baseline_from(rows: list[panel.EventRow]) -> Baseline:
    return control_baseline(rows, resamples=1500)


def test_ablation_recovers_a_filter_that_really_separates():
    """Half the events are +2R with a shallow pullback; half -1R with a deep one."""
    rows = (
        [make_row(+2.0, pullback_frac=0.10, ts=T0 + timedelta(days=i)) for i in range(120)]
        + [make_row(-1.0, pullback_frac=0.80, ts=T0 + timedelta(days=200 + i)) for i in range(120)]
    )
    baseline = _baseline_from(rows)
    assert baseline.estimate.mean == pytest.approx(0.5, abs=0.05)
    row = ablate_one(rows, filters.FILTERS_BY_KEY["pullback_max"], 0.40, baseline, resamples=1500)
    assert row.estimate.n == 120
    assert row.estimate.mean == pytest.approx(2.0)
    assert row.verdict == PASS
    assert row.recommendation == KEEP


def test_ablation_rejects_a_filter_that_only_shrinks_the_sample():
    rng = random.Random(2)
    rows = [
        make_row(rng.choice([2.0, -1.0]), pullback_frac=rng.uniform(0.0, 1.0),
                 ts=T0 + timedelta(days=i))
        for i in range(300)
    ]
    baseline = _baseline_from(rows)
    row = ablate_one(rows, filters.FILTERS_BY_KEY["pullback_max"], 0.50, baseline, resamples=1500)
    assert row.recommendation != KEEP


def test_a_filter_that_leaves_too_few_events_cannot_pass():
    rows = [make_row(+2.0, pullback_frac=0.10, ts=T0 + timedelta(days=i)) for i in range(10)]
    rows += [make_row(-1.0, pullback_frac=0.90, ts=T0 + timedelta(days=100 + i)) for i in range(200)]
    baseline = _baseline_from(rows)
    row = ablate_one(rows, filters.FILTERS_BY_KEY["pullback_max"], 0.40, baseline, resamples=1000)
    assert row.estimate.n == 10
    assert row.recommendation != KEEP


def test_sweep_calls_a_broad_effect_a_plateau_and_takes_its_middle():
    rows = [
        make_row(+2.0 if p <= 0.5 else -1.0, pullback_frac=p, ts=T0 + timedelta(days=i))
        for i, p in enumerate([0.05 * (j % 20) for j in range(400)])
    ]
    baseline = _baseline_from(rows)
    sweep = sweep_threshold(rows, filters.FILTERS_BY_KEY["pullback_max"], baseline, resamples=800)
    assert sweep.shape == PLATEAU
    assert not math.isnan(sweep.recommended)
    low, high = sweep.plateau
    assert low <= sweep.recommended <= high


def test_sweep_finds_nothing_in_noise():
    rng = random.Random(4)
    rows = [
        make_row(rng.choice([2.0, -1.0]), pullback_frac=rng.uniform(0.0, 1.0),
                 ts=T0 + timedelta(days=i))
        for i in range(400)
    ]
    baseline = _baseline_from(rows)
    sweep = sweep_threshold(rows, filters.FILTERS_BY_KEY["pullback_max"], baseline, resamples=800)
    assert sweep.shape in (NONE_FOUND, SPIKE)
    assert math.isnan(sweep.recommended)


def test_beta_regime_table_supports_a_planted_thesis():
    classic = [
        make_row(+2.0, beta_value=-0.08, r_squared=0.10 + 0.004 * i, ts=T0 + timedelta(days=i))
        for i in range(120)
    ]
    inverted = [
        make_row(-1.0, beta_value=+0.08, r_squared=0.10 + 0.004 * i,
                 impulse_dir=-1, ts=T0 + timedelta(days=300 + i))
        for i in range(120)
    ]
    table = beta_regime_table(classic + inverted, window=90, resamples=1500)
    assert table.verdict == "SUPPORTED"
    assert any(b.name.startswith(beta.CLASSIC) for b in table.buckets)
    assert any(b.name.startswith(beta.INVERTED) for b in table.buckets)


def test_beta_regime_table_reports_a_negative_result_plainly():
    rng = random.Random(6)
    rows = [
        make_row(rng.choice([2.0, -1.0]), beta_value=rng.choice([-0.08, 0.08]),
                 r_squared=rng.uniform(0.05, 0.7), ts=T0 + timedelta(days=i))
        for i in range(400)
    ]
    table = beta_regime_table(rows, window=90, resamples=1500)
    assert table.verdict == "NOT SUPPORTED"
    assert "not supported" in table.note.lower()


def test_beta_regime_table_says_untested_rather_than_failed_on_a_thin_panel():
    table = beta_regime_table([make_row(1.0) for _ in range(5)], window=90, resamples=200)
    assert table.verdict == "UNTESTED"


def test_cost_curve_is_monotonically_worse():
    rows = [make_row(+2.0, ts=T0 + timedelta(days=i), risk_price=2.0) for i in range(100)]
    points = cost_curve(rows, resamples=500)
    means = [p.estimate.mean for p in points]
    assert means == sorted(means, reverse=True)
    # (400 - 20) ticks at $0.01 against a $2.00 risk unit is 1.9R of extra cost.
    assert points[0].estimate.mean - points[-1].estimate.mean == pytest.approx(1.9, abs=0.01)


def test_walk_forward_splits_chronologically_and_never_shuffles():
    rows = [make_row(+2.0, ts=T0 + timedelta(days=i)) for i in range(60)]
    rows += [make_row(-1.0, ts=T0 + timedelta(days=100 + i)) for i in range(40)]
    result = walk_forward(rows, calibration_share=0.60, resamples=800)
    assert result.calibration.n == 60
    assert result.test.n == 40
    assert result.calibration.mean == pytest.approx(2.0)
    assert result.test.mean == pytest.approx(-1.0)
    assert "suspect" in result.note


# --- loaders and guards --------------------------------------------------

def test_fred_missing_marker_is_dropped_not_zeroed(tmp_path: Path):
    path = tmp_path / "dgs2.csv"
    path.write_text("observation_date,DGS2\n2024-01-02,4.33\n2024-01-03,.\n2024-01-04,4.41\n")
    assert [value for _, value in loaders.load_daily(path)] == [4.33, 4.41]


def test_bar_file_missing_a_column_is_rejected_not_half_parsed(tmp_path: Path):
    path = tmp_path / "bars.csv"
    path.write_text("timestamp,open,high,close\n2024-01-02 12:00:00,1,2,1.5\n")
    with pytest.raises(loaders.IngestError):
        loaders.load_bars(path, "XAU")


def test_pair_daily_is_an_inner_join():
    gold = [(date(2024, 1, 2), 2000.0), (date(2024, 1, 3), 2010.0)]
    assert len(loaders.pair_daily(gold, [(date(2024, 1, 3), 4.4)])) == 1


def test_bar_lookup_will_not_jump_a_weekend_gap():
    series = BarSeries("X", make_bars(T0, [100.0] * 10))
    assert series.bar_at_or_after(T0 - timedelta(days=2)) is None


def test_apply_filters_rejects_an_unknown_key():
    with pytest.raises(KeyError):
        filters.apply_filters([make_row(1.0)], {"not_a_filter": 1.0})


def test_filters_reject_rows_whose_feature_is_missing():
    assert filters.FILTERS_BY_KEY["surprise_z"].passes(make_row(1.0, surprise_z=float("nan")), 0.0) is False


# --- the Phase 1 gate ----------------------------------------------------

def _results(provenance: Provenance) -> report.Phase0Results:
    rows = [make_row(+1.0, ts=T0 + timedelta(days=i)) for i in range(60)]
    baseline = _baseline_from(rows)
    return report.Phase0Results(
        provenance=provenance, spec=ControlSpec(), rows=rows, baseline=baseline,
        ablations=[
            ablate_one(rows, filters.FILTERS_BY_KEY["origin_held"], 0.0, baseline, resamples=400)
        ],
        sweeps=[], regime=beta_regime_table(rows, resamples=400),
        costs=cost_curve(rows, resamples=400), walk=walk_forward(rows, resamples=400),
        atr_bases=[],
    )


def test_a_synthetic_run_cannot_produce_calibrated_constants(tmp_path: Path):
    provenance = Provenance(quality="synthetic")
    provenance.record("xau_1m", "synthetic")
    written = report.write_outputs(_results(provenance), tmp_path)
    assert written["constants"].name == "calibrated_constants.SYNTHETIC.json"
    assert not (tmp_path / "calibrated_constants.json").exists()
    with pytest.raises(report.NotCalibrated):
        report.verify_constants(written["constants"])


def test_a_partially_real_run_cannot_produce_calibrated_constants(tmp_path: Path):
    provenance = Provenance(quality="real")
    provenance.record("xau_1m", "real")
    provenance.record("consensus", "absent", "no calendar available")
    written = report.write_outputs(_results(provenance), tmp_path)
    assert written["constants"].name == "calibrated_constants.SYNTHETIC.json"
    with pytest.raises(report.NotCalibrated):
        report.verify_constants(written["constants"])


def test_a_fully_real_run_produces_constants_that_verify(tmp_path: Path):
    provenance = Provenance(quality="real")
    for key in ("xau_1m", "us2y_intraday", "dgs2_daily", "gold_daily",
                "actuals_first_print", "consensus"):
        provenance.record(key, "real", "test fixture")
    written = report.write_outputs(_results(provenance), tmp_path)
    assert written["constants"].name == "calibrated_constants.json"
    payload = report.verify_constants(written["constants"])
    assert payload["calibrated"] is True
    assert payload["schema"] == "hermicane/calibrated_constants/1"


def test_the_report_leads_with_a_warning_when_the_run_is_not_real():
    provenance = Provenance(quality="synthetic")
    provenance.record("xau_1m", "synthetic")
    text = report.render_report(_results(provenance))
    assert "THIS RUN IS NOT CALIBRATED OUTPUT" in text.split("## Provenance")[0]


def test_constants_payload_records_deletions_as_well_as_survivors():
    provenance = Provenance(quality="real")
    provenance.record("xau_1m", "real")
    payload = report.constants_payload(_results(provenance))
    assert "deleted_filters" in payload
    assert len(payload["structural_choices"]) >= 5


def test_verify_rejects_a_file_that_is_not_ours(tmp_path: Path):
    path = tmp_path / "other.json"
    path.write_text(json.dumps({"schema": "something/else", "calibrated": True}))
    with pytest.raises(report.NotCalibrated):
        report.verify_constants(path)


# --- end to end ----------------------------------------------------------

def test_the_synthetic_world_builds_a_panel_end_to_end():
    from phase0.synthetic import generate

    world = generate(years=1, seed=7)
    rows = panel.build_panel(
        panel.PanelInputs(world.events, world.prices, world.yields, world.daily, world.dxy)
    )
    assert rows
    assert all(row.ts_ny.tzinfo is not None for row in rows)
    assert any(row.is_evaluable for row in rows)
    assert not world.provenance.is_real
