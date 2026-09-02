"""Tests for the AURUM-NY PRIME engine specification and validation stack.

The Pine script cannot be executed here, so these tests do two things:

1. **Static checks on the Pine source** — version, ordering, repainting
   hazards, and the presence of every mandatory condition from S55 in the
   entry gate. `test_lint_detects_seeded_defects` proves the checker is not
   vacuously passing.
2. **Behavioural checks on the reference implementation** — the same setup
   rules written a second time, in Python, where causality can be attacked
   directly: mutate the future and assert the past does not move.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta
from pathlib import Path

import pytest

from validation.ablation import build_table, plateau_verdict, stability_surface
from validation.montecarlo import (
    FtmoRules,
    TradingDay,
    block_bootstrap_days,
    group_by_day,
    run_monte_carlo,
    simulate_path,
)
from validation.pine_lint import lint
from validation.reference import Bar, Context, Engine, Params, State, hm, in_window, run
from validation.stats import bootstrap_expectancy, summarize, wilson_interval
from validation.trades import (
    TradeExportError,
    chronological_split,
    parse_csv,
    walk_forward_windows,
)

PINE = Path(__file__).resolve().parents[2] / "AURUM_NY_PRIME.pine"


# ---------------------------------------------------------------------------
# Pine source
# ---------------------------------------------------------------------------


def test_pine_source_is_clean():
    findings = lint(PINE.read_text(encoding="utf-8"))
    assert findings == [], "\n".join(str(f) for f in findings)


def test_lint_detects_seeded_defects():
    """A checker that never fails is not a checker."""
    broken = "\n".join(
        [
            "//@version=5",
            'strategy("x")',
            "y = z + 1",
            "z = 2",
            "var float a = na, var float b = na",
            'w = request.security(syminfo.tickerid, "D", close)',
            'v = request.security(syminfo.tickerid, "D", close, lookahead=barmerge.lookahead_on)',
            "armed = true",
        ]
    )
    rules = {f.rule for f in lint(broken)}
    assert {"version", "use-before-decl", "comma-decl", "lookahead", "spec"} <= rules


def test_lint_detects_integer_division():
    """`int / int` is integer division in Pine, so a win rate computed that way
    is always 0. It reads as correct in every other language here."""
    probe = "\n".join(
        [
            "//@version=6",
            'strategy("x")',
            "var int nWins = 0",
            "var int nTrades = 0",
            "rate = nWins / nTrades",
            "armed = true",
        ]
    )
    assert any(f.rule == "int-division" for f in lint(probe))


def test_lint_detects_unguarded_loops_over_arrays():
    """`for k = 0 to array.size(x) - 1` counts DOWN when x is empty: Pine runs
    it with k = 0 then k = -1 and array.get throws."""
    probe = "\n".join(
        [
            "//@version=6",
            'strategy("x")',
            "rows = array.new<string>()",
            "for k = 0 to array.size(rows) - 1",
            "    log.info(array.get(rows, k))",
            "armed = true",
        ]
    )
    assert any(f.rule == "empty-loop" for f in lint(probe))


def test_pine_declares_no_lookahead_anywhere():
    source = PINE.read_text(encoding="utf-8")
    assert "lookahead_on" not in source
    assert source.count("request.security(") == source.count("lookahead = barmerge.lookahead_off")


def test_pine_is_long_only_and_single_position():
    source = PINE.read_text(encoding="utf-8")
    assert "strategy.short" not in source
    assert "pyramiding               = 0" in source or "pyramiding              = 0" in source


def test_pine_exit_ids_are_not_reissued_after_filling():
    """Re-issuing a filled exit id would open a second exit against the
    remainder of the position, silently doubling the reduction."""
    source = PINE.read_text(encoding="utf-8")
    assert 'if not tp1Done and nz(aQ1, 0) > 0' in source
    assert 'if not tp2Done and nz(aQ2, 0) > 0' in source


# ---------------------------------------------------------------------------
# Time helpers
# ---------------------------------------------------------------------------


def test_hm_and_wrapping_windows():
    assert hm("08:35") == 515
    assert hm("00:00") == 0
    # Asia wraps past midnight; London does not.
    assert in_window(hm("21:00"), hm("20:00"), hm("02:00"))
    assert in_window(hm("01:00"), hm("20:00"), hm("02:00"))
    assert not in_window(hm("03:00"), hm("20:00"), hm("02:00"))
    assert in_window(hm("07:00"), hm("02:00"), hm("08:20"))
    assert not in_window(hm("08:20"), hm("02:00"), hm("08:20"))  # end is exclusive


# ---------------------------------------------------------------------------
# Synthetic market
# ---------------------------------------------------------------------------

BAR = timedelta(minutes=5)


def _bar(ts: datetime, low: float, high: float, open_: float, close: float, volume: float = 1000.0) -> Bar:
    return Bar(ts=ts, open=open_, high=high, low=low, close=close, volume=volume)


def _path_bars(start: datetime, closes: list[float], first_open: float, wick: float = 1.0) -> list[Bar]:
    """Bars along a close path with a fixed wick, so ATR stays predictable."""
    bars = []
    open_ = first_open
    for i, close in enumerate(closes):
        bars.append(
            _bar(
                start + i * BAR,
                min(open_, close) - wick,
                max(open_, close) + wick,
                open_,
                close,
            )
        )
        open_ = close
    return bars


# The New York leg, written as offsets from the London close so the geometry
# stays self-consistent when the surrounding levels move. Columns: open, high,
# low, close. The comments name what each bar is FOR — the fixture is a
# specification example (S83), not a random walk that happened to pass.
NY_SCALE = 2.0

NY_OFFSETS = [
    (+0.00, +0.70, -0.60, +0.20),   # 08:20 opening range
    (+0.20, +0.90, -0.40, +0.40),   # 08:25 opening range
    (+0.40, +1.00, -0.30, +0.60),   # 08:30 opening range  → ORH +1.00, ORL -0.60
    (+0.60, +1.90, +0.40, +1.70),   # 08:35 breakout: closes above ORH + buffer
    (+1.70, +2.00, +1.00, +1.50),   # 08:40 momentum acceptance, holds above ORH
    (+1.50, +1.80, +0.80, +1.20),   # 08:45
    (+1.20, +1.40, +0.60, +1.10),   # 08:50
    (+1.10, +1.50, +0.30, +1.20),   # 08:55 P1 — first confirmed higher low
    (+1.20, +1.70, +0.90, +1.50),   # 09:00
    (+1.50, +1.75, +1.20, +1.65),   # 09:05 HH1
    (+1.65, +1.70, +1.10, +1.40),   # 09:10 P1 confirms here (three bars right)
    (+1.40, +1.60, +0.90, +1.10),   # 09:15
    (+1.10, +1.45, +0.80, +1.30),   # 09:20
    (+1.30, +1.55, +0.70, +1.40),   # 09:25 P2 — second confirmed higher low
    (+1.40, +1.70, +1.10, +1.60),   # 09:30
    (+1.60, +1.85, +1.35, +1.75),   # 09:35 HH2, and the micro pivot high that
                                    #       becomes the entry trigger
    (+1.75, +1.80, +1.25, +1.45),   # 09:40 P2 confirms here
    (+1.45, +1.65, +1.15, +1.30),   # 09:45
    (+1.28, +1.80, +1.03, +1.75),   # 09:50 THIRD TOUCH + bullish rejection
    (+1.75, +2.20, +1.55, +2.10),   # 09:55 follow-through
    (+2.10, +2.50, +1.90, +2.40),   # 10:00
    (+2.40, +2.90, +2.20, +2.80),   # 10:05
]


def a_plus_day() -> list[Bar]:
    """A textbook S83 day.

    Previous ET day prints the liquidity overhead (PDH). Asia builds a balanced
    range. London continues: higher high, higher low, close above its midpoint.
    New York opens, breaks the opening range and accepts above it, builds two
    ascending pivot lows, returns for a third interaction with the line they
    define, and rejects it with a strong bullish candle.
    """
    bars: list[Bar] = []

    # --- previous ET day: rallies to 2018.7 then fades. That high is the
    # overhead liquidity the reward-space rule measures against (S44).
    closes = [2002 + 16 * (i / 60) for i in range(61)] + [2018 - 16 * (i / 71) for i in range(1, 72)]
    bars += _path_bars(datetime(2026, 3, 9, 9, 0), closes, first_open=2002.0)

    # --- Asia 20:00 → 02:00: balanced range, 1998 – 2004.
    asia_closes = [2001 + 2.3 * math.sin(i / 5.0) for i in range(72)]
    bars += _path_bars(datetime(2026, 3, 9, 20, 0), asia_closes, first_open=bars[-1].close)
    asia_close = bars[-1].close

    # --- London 02:00 → 08:20: continuation into the New York open.
    london_closes = [asia_close + (2010.4 - asia_close) * (i + 1) / 76 for i in range(76)]
    bars += _path_bars(datetime(2026, 3, 10, 2, 0), london_closes, first_open=asia_close)

    # --- New York, from the opening range onward. The offsets are scaled up
    # because New York bars are larger than Asia bars, which is both realistic
    # and what keeps the setup inside the ATR-relative gates (spread/ATR, stop
    # distance, touch tolerance) rather than squeaking past them.
    base = bars[-1].close
    ts = datetime(2026, 3, 10, 8, 20)
    for i, (o, h, low, c) in enumerate(NY_OFFSETS):
        bars.append(
            _bar(
                ts + i * BAR,
                base + low * NY_SCALE,
                base + h * NY_SCALE,
                base + o * NY_SCALE,
                base + c * NY_SCALE,
            )
        )
    return bars


def test_synthetic_day_produces_a_valid_setup():
    """End to end: the rules, applied to a textbook day, arm a trade."""
    bars = a_plus_day()
    signals = run(bars)
    armed = [s for s in signals if s.armed]
    assert armed, "no ARMED signal; reasons seen: " + ", ".join(
        sorted({s.reason for s in signals if s.ts.hour >= 8 and s.ts.day == 10})
    )
    first = armed[0]
    assert first.entry > first.stop
    assert first.units >= 1
    assert first.state is State.ARMED
    assert first.touch_number == 3
    assert first.score >= 80


def test_setup_requires_every_mandatory_condition():
    """Turn one mandatory condition off at a time; the setup must disappear."""
    bars = a_plus_day()
    baseline = [s for s in run(bars) if s.armed]
    assert baseline

    for field, value, expected in [
        ("gold_bull", False, "NO TRADE — HTF NOT BULL"),
        ("dxy_score", 0, "NO TRADE — DXY"),
        ("gc_count", 0, "NO TRADE — GC NOT CONFIRMING"),
        ("news_blackout", True, "NO TRADE — NEWS BLACKOUT"),
        ("feeds_ok", False, "NO TRADE — DATA FEED FAILURE"),
    ]:
        ctx = Context(**{field: value})
        signals = run(bars, [ctx] * len(bars))
        assert not any(s.armed for s in signals), f"{field}={value} still armed"
        assert expected in {s.reason for s in signals}


# ---------------------------------------------------------------------------
# Causality — the anti-repainting tests
# ---------------------------------------------------------------------------


def test_future_bars_cannot_change_past_decisions():
    """Mutate every bar after bar k and assert the first k decisions are
    bit-identical. This is the strongest statement available about lookahead."""
    bars = a_plus_day()
    reference = [s.key() for s in run(bars)]

    for cut in (len(bars) // 3, len(bars) // 2, len(bars) - 10):
        mutated = list(bars[:cut])
        for b in bars[cut:]:
            mutated.append(_bar(b.ts, b.low - 25.0, b.high + 25.0, b.open + 12.0, b.close - 18.0))
        assert [s.key() for s in run(mutated)][:cut] == reference[:cut]


def test_truncating_the_series_does_not_change_earlier_decisions():
    bars = a_plus_day()
    reference = [s.key() for s in run(bars)]
    for cut in (40, 90, 150, len(bars) - 1):
        assert [s.key() for s in run(bars[:cut])] == reference[:cut]


def test_opening_range_is_locked_and_immutable():
    bars = a_plus_day()
    engine = Engine()
    locked: tuple[float, float] | None = None
    for bar in bars:
        engine.update(bar)
        if engine.or_ready:
            if locked is None:
                locked = (engine.orh, engine.orl)
                assert bar.et_minute >= hm("08:35")
            elif bar.et_date == 20260310:
                assert (engine.orh, engine.orl) == locked
    assert locked is not None


def test_pivots_are_only_reported_after_their_confirmation_bars():
    bars = a_plus_day()
    engine = Engine()
    for index, bar in enumerate(bars):
        engine.update(bar)
        if engine.p2 is not None:
            # A pivot's own bar index must be at least `right` bars behind.
            assert index - engine.p2[0] >= engine.p.pivot_right


def test_session_ranges_are_not_visible_before_the_session_ends():
    engine = Engine()
    seen_ready_at = None
    for bar in a_plus_day():
        engine.update(bar)
        if engine.asia.ready and seen_ready_at is None:
            seen_ready_at = bar
    assert seen_ready_at is not None
    # Asia ends at 02:00 ET; the range cannot be readable before that.
    assert seen_ready_at.et_minute >= hm("02:00")


# ---------------------------------------------------------------------------
# Risk and sizing
# ---------------------------------------------------------------------------


def test_position_size_rounds_down_and_respects_the_budget():
    bars = a_plus_day()
    for signal in run(bars):
        if not signal.armed:
            continue
        params = Params()
        assert signal.units % params.unit_step == pytest.approx(0.0, abs=1e-9)
        budget = min(100_000 * params.risk_std_pct / 100, params.risk_hard_cap)
        assert signal.risk_usd <= budget + 1e-6
        # Rounding down must have cost at most one step of risk.
        per_unit = signal.risk_usd / signal.units
        assert signal.risk_usd + per_unit * params.unit_step > budget - 1e-6


def test_hard_risk_cap_binds_on_a_large_account():
    engine = Engine(Params(), equity=1_000_000.0)
    engine.account = 1_000_000.0
    armed = None
    for bar in a_plus_day():
        signal = engine.update(bar)
        if signal.armed:
            armed = signal
            break
    assert armed is not None
    # 0.5% of 1,000,000 is 5,000, but the hard cap is 1,000 (S7).
    assert armed.risk_usd <= Params().risk_hard_cap + 1e-6


def test_risk_schedule_never_increases_as_the_target_approaches():
    rules = FtmoRules()
    schedule = [rules.risk_pct_for(gain) for gain in (0, 4.9, 5.0, 7.9, 8.0, 8.9, 9.0, 9.9)]
    assert schedule == sorted(schedule, reverse=True)
    assert max(schedule) <= rules.risk_abs_max_pct


def test_stop_distance_bounds_are_enforced():
    """A stop outside [0.20, 1.25] ATR must reject the setup, not resize it."""
    bars = a_plus_day()
    tight = run(bars, params=Params(max_stop_atr=0.01))
    assert not any(s.armed for s in tight)
    assert "NO TRADE — STOP DISTANCE" in {s.reason for s in tight}


def test_reward_space_gate_blocks_a_capped_setup():
    """With a resistance level parked just above entry, clearance fails."""
    bars = a_plus_day()
    engine = Engine(Params(min_room_r=99.0))
    reasons = {engine.update(bar).reason for bar in bars}
    assert any(r.startswith("NO TRADE — RESISTANCE") for r in reasons)


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------


def test_wilson_interval_matches_known_values():
    interval = wilson_interval(70, 100)
    assert interval.low == pytest.approx(0.6041, abs=5e-4)
    assert interval.high == pytest.approx(0.7811, abs=5e-4)
    # The same point estimate on a small sample must be far less persuasive.
    small = wilson_interval(21, 30)
    assert small.high - small.low > interval.high - interval.low
    assert 0.0 <= small.low <= small.high <= 1.0


def test_wilson_interval_handles_degenerate_samples():
    assert wilson_interval(0, 10).low == pytest.approx(0.0, abs=1e-9)
    assert wilson_interval(10, 10).high == pytest.approx(1.0, abs=1e-9)
    assert math.isnan(wilson_interval(0, 0).low)


def test_summary_arithmetic():
    r = [1.5, -1.0, 3.0, -1.0, -1.0, 1.5]
    s = summarize(r, mae_r=[0.3, 1.0, 0.2, 1.0, 1.0, 0.4], mfe_r=[1.6, 0.4, 3.2, 0.2, 0.5, 1.7])
    assert s.n == 6
    assert s.wins == 3
    assert s.win_rate == pytest.approx(0.5)
    assert s.expectancy_r == pytest.approx(3.0 / 6)
    assert s.profit_factor == pytest.approx(6.0 / 3.0)
    assert s.max_consecutive_losses == 2  # losses at index 1, then 3 and 4
    assert s.net_r == pytest.approx(3.0)
    assert s.sample_label == "PRELIMINARY"


def test_expectancy_can_be_positive_with_a_losing_majority():
    """S1: win rate is not the objective. 40% winners at 3R is a good strategy."""
    r = [3.0, 3.0, -1.0, -1.0, -1.0]
    s = summarize(r)
    assert s.win_rate < 0.5
    assert s.expectancy_r > 0.5


def test_bootstrap_is_deterministic_and_bounded():
    r = [1.5, -1.0, 3.0, -1.0, -1.0, 1.5, 1.5, -1.0]
    first = bootstrap_expectancy(r, samples=2000, seed=7)
    second = bootstrap_expectancy(r, samples=2000, seed=7)
    assert first == second
    assert first.p5 <= first.median <= first.p95
    assert 0.0 <= first.prob_positive <= 1.0
    assert bootstrap_expectancy([1.0] * 20, samples=500).prob_positive == 1.0


# ---------------------------------------------------------------------------
# Monte Carlo and FTMO simulation
# ---------------------------------------------------------------------------


def test_block_bootstrap_preserves_consecutive_days():
    days = [TradingDay(date=f"2026-01-{i:02d}", r_values=(float(i),)) for i in range(1, 21)]
    import random

    sample = block_bootstrap_days(days, length=20, block=5, rng=random.Random(1))
    assert len(sample) == 20
    # Within each drawn block, days must be consecutive in the original order.
    consecutive = sum(
        1
        for a, b in zip(sample, sample[1:], strict=False)
        if (days.index(b) - days.index(a)) % len(days) == 1
    )
    assert consecutive >= 15  # 4 links per 5-day block, 4 blocks


def test_simulate_path_passes_on_a_winning_sequence():
    rules = FtmoRules(min_trading_days=4)
    days = [TradingDay(f"d{i}", (2.0,)) for i in range(60)]
    result = simulate_path(days, rules, use_mae=False)
    assert result.outcome == "PASS"
    assert result.trading_days >= rules.min_trading_days
    assert result.final_equity >= rules.account * 1.10


def test_simulate_path_cannot_pass_before_the_minimum_trading_days():
    rules = FtmoRules(min_trading_days=10)
    days = [TradingDay(f"d{i}", (40.0,)) for i in range(3)]
    result = simulate_path(days, rules, use_mae=False)
    assert result.outcome != "PASS"


def test_simulate_path_detects_a_max_loss_breach():
    rules = FtmoRules(internal_daily_stop_pct=100.0, daily_loss_pct=100.0)
    days = [TradingDay(f"d{i}", (-40.0,)) for i in range(20)]
    result = simulate_path(days, rules, use_mae=False)
    assert result.outcome == "MAX_LOSS"
    assert result.final_equity <= rules.account * 0.90


def test_simulate_path_detects_a_daily_loss_breach():
    rules = FtmoRules(internal_daily_stop_pct=100.0, daily_loss_pct=5.0, max_loss_pct=90.0)
    days = [TradingDay("d0", (-6.0, -6.0))]
    result = simulate_path(days, rules, use_mae=False)
    assert result.outcome == "DAILY_LOSS"


def test_floating_loss_counts_against_the_daily_limit():
    """A trade that dips 6% and recovers to +1R is still a daily breach."""
    rules = FtmoRules(internal_daily_stop_pct=100.0, daily_loss_pct=5.0, risk_std_pct=1.0)
    day = TradingDay("d0", (1.0,), mae_r=(6.0,))
    assert simulate_path([day], rules, use_mae=True).outcome == "DAILY_LOSS"
    assert simulate_path([day], rules, use_mae=False).outcome != "DAILY_LOSS"


def test_monte_carlo_is_deterministic_and_reports_missing_mae():
    days = group_by_day(
        ["2026-01-01", "2026-01-02", "2026-01-05", "2026-01-06"],
        [1.5, -1.0, 3.0, 1.5],
    )
    first = run_monte_carlo(days, paths=200, block=3, seed=11)
    second = run_monte_carlo(days, paths=200, block=3, seed=11)
    assert first == second
    assert "NO MAE" in first.note
    assert first.p_pass + first.p_daily_loss + first.p_max_loss + first.p_timeout == pytest.approx(1.0)


def test_a_losing_strategy_almost_never_passes():
    days = group_by_day([f"2026-01-{i:02d}" for i in range(1, 21)], [-1.0] * 20, [1.0] * 20)
    result = run_monte_carlo(days, paths=500, block=5, seed=3)
    assert result.p_pass < 0.01
    assert result.p_max_loss + result.p_daily_loss > 0.9


# ---------------------------------------------------------------------------
# Trade export
# ---------------------------------------------------------------------------

HEADER = (
    "ts_entry,ts_exit,symbol,session_type,orb_model,entry,stop,init_R,units,lots,risk_usd,"
    "realized_R,score,grade,htf_4h,htf_1h,vwap_ext,vwap_slope,gc_count,dxy_score,corr_gold_dxy,"
    "ry_mom,vix_support,pivot_slope_norm,strict_struct,touch3_dist_atr,rej_br,rej_clv,atr_shock,"
    "modeled_spread,vol_mode,dist_pdh,dist_london_high,mae_R,mfe_R,exit_type,hold_bars,"
    "news_blackout,rule_violation,eval_mode,ablation,entry_mode,stop_model"
)


def _row(date: str, realized: float, mae: float = 0.4, score: float = 86.0) -> str:
    return (
        f"{date} 09:40,{date} 10:15,XAUUSD,SESSION_CONTINUATION,ORB_RETEST_ACCEPTANCE,"
        f"2010.5,2008.0,2.5,200,2.0,500,{realized},{score},A+,1,1,0.42,0.11,3,3,-0.44,"
        f"-0.01,0.0,0.02,1,0.03,0.55,0.82,1.02,0.30,Broker volume,12.5,4.2,{mae},2.1,"
        f"TP1+TRAIL,7,0,0,FTMO 2-Step,J · Full AURUM-NY PRIME,Conservative,A · Touch #3"
    )


def _export(dates_and_r: list[tuple[str, float]]) -> str:
    body = "\n".join(_row(date, r) for date, r in dates_and_r)
    return f"AURUM-NY PRIME v2.0 trade export · {len(dates_and_r)} positions\n{HEADER}\n{body}\n"


def test_parse_export_skips_log_preamble_and_sorts():
    text = _export([("2026-03-11", 1.5), ("2026-03-10", -1.0)])
    trades = parse_csv(text)
    assert len(trades) == 2
    assert [t.date for t in trades] == ["2026-03-10", "2026-03-11"]
    assert trades[0].realized_r == -1.0
    assert trades[1].grade == "A+"
    assert trades[1].ablation.startswith("J")


def test_parse_export_rejects_a_file_from_another_version():
    with pytest.raises(TradeExportError):
        parse_csv("ts_entry,ts_exit,realized_R\n2026-01-01 09:00,2026-01-01 09:30,1.0\n")
    with pytest.raises(TradeExportError):
        parse_csv("something else entirely\n")


def test_chronological_split_never_splits_a_trading_day():
    dates = [f"2026-0{1 + i // 28}-{1 + i % 28:02d}" for i in range(100)]
    text = _export([(d, 1.0 if i % 2 else -1.0) for i, d in enumerate(dates)])
    trades = parse_csv(text)
    split = chronological_split(trades)
    dev_days = {t.date for t in split.development}
    val_days = {t.date for t in split.validation}
    oos_days = {t.date for t in split.out_of_sample}
    assert not dev_days & val_days
    assert not val_days & oos_days
    assert max(dev_days) < min(val_days) < min(oos_days)
    assert len(split.development) + len(split.validation) + len(split.out_of_sample) == len(trades)
    assert 0.5 < len(split.development) / len(trades) < 0.7


def test_walk_forward_windows_roll_without_overlap():
    dates = []
    for month in range(1, 13):
        for day in (5, 15, 25):
            dates.append(f"2026-{month:02d}-{day:02d}")
    trades = parse_csv(_export([(d, 1.0) for d in dates]))
    windows = walk_forward_windows(trades, train_months=6, test_months=3)
    assert windows
    for a, b in zip(windows, windows[1:], strict=False):
        assert a.test_end < b.test_start
    for window in windows:
        assert window.train_end < window.test_start


# ---------------------------------------------------------------------------
# Ablation and stability
# ---------------------------------------------------------------------------


def test_ablation_table_flags_a_component_that_costs_expectancy():
    dates = [f"2026-0{1 + i // 28}-{1 + i % 28:02d}" for i in range(60)]
    good = parse_csv(_export([(d, 1.5 if i % 3 else -1.0) for i, d in enumerate(dates)]))
    bad = parse_csv(_export([(d, -1.0 if i % 3 else 1.5) for i, d in enumerate(dates)]))
    rows = build_table(
        {"A · ORB only": good, "J · Full AURUM-NY PRIME": bad},
        mc_paths=200,
        bootstrap_samples=200,
    )
    by_name = {row.name: row for row in rows}
    assert by_name["A · ORB only"].verdict == "baseline"
    assert by_name["J · Full AURUM-NY PRIME"].d_expectancy < 0
    assert by_name["J · Full AURUM-NY PRIME"].verdict.startswith("DROP")


def test_plateau_verdict_distinguishes_a_plateau_from_a_spike():
    def points(values: list[float]):
        runs = {
            float(i): parse_csv(_export([(f"2026-01-{d:02d}", value) for d in range(1, 21)]))
            for i, value in enumerate(values)
        }
        return stability_surface(runs)

    assert plateau_verdict(points([0.1, 0.9, 1.0, 0.9, 0.1])).startswith("PLATEAU")
    assert plateau_verdict(points([0.1, 0.05, 3.0, 0.05, 0.1])).startswith("ISOLATED")
    assert plateau_verdict(points([0.1, 0.2, 0.3, 0.4, 2.0])).startswith("EDGE")
    assert plateau_verdict(points([0.1, 0.2])).startswith("INSUFFICIENT")
