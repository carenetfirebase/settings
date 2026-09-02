"""Tests for the CYBER MCGIVER v7 reference engine and the Pine linter.

The two properties that matter most here are not "does it produce trades" but
**causality** — a decision made on bar N must not move when bar N+1 changes —
and **the hard limits actually holding**, because a daily cap that leaks makes
every frequency number in the report meaningless.
"""

from __future__ import annotations

import sys
from dataclasses import replace
from datetime import date
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import synthetic  # noqa: E402
from pine_lint import lint  # noqa: E402
from reference import N_SCORE, Params, run, score_bucket  # noqa: E402

PINE = ROOT.parent / "CYBER_MCGIVER_v7.pine"
SHORT_RUN = (date(2019, 1, 1), date(2020, 7, 1))


@pytest.fixture(scope="module")
def bars():
    return synthetic.generate(*SHORT_RUN, seed=12345)


# --- the Pine source ---------------------------------------------------------

def test_pine_source_is_clean():
    assert lint(PINE.read_text(encoding="utf-8")) == []


def test_linter_catches_a_table_overrun():
    """The linter is only worth having if it fails on a real defect."""
    source = PINE.read_text(encoding="utf-8")
    broken = source.replace("table.new(position.bottom_right, 3, 30,",
                            "table.new(position.bottom_right, 3, 12,", 1)
    assert any(f.rule == "table-bounds" for f in lint(broken))


def test_linter_catches_a_removed_mandatory_gate():
    source = PINE.read_text(encoding="utf-8")
    broken = source.replace("bool okRoom   = roomR >= i_minRoomR",
                            "bool unchecked = roomR >= i_minRoomR", 1)
    assert any(f.rule == "spec" and "okRoom" in f.message for f in lint(broken))


# --- causality ----------------------------------------------------------------

def test_future_bars_cannot_change_past_decisions(bars):
    """Truncating the future must not change anything already decided.

    This is the property the whole engine rests on. If a decision made on bar N
    moves when bar N+500 changes, the backtest is reading its own answers.
    """
    cut = len(bars) // 2
    full = run(bars)
    partial = run(bars[:cut])
    early_full = [t for t in full.trades if t.entered <= bars[cut - 1].ts]
    early_partial = [t for t in partial.trades if t.entered <= bars[cut - 1].ts]
    # The last trade of the truncated run may still be open at the cut, so
    # compare everything that had already closed.
    n = min(len(early_full), len(early_partial)) - 1
    assert n > 5, "the window is too short to prove anything"
    for a, b in zip(early_full[:n], early_partial[:n]):
        assert a.entered == b.entered
        assert a.family == b.family
        assert a.entry == pytest.approx(b.entry)
        assert a.score == pytest.approx(b.score)


def test_mutating_the_final_bars_does_not_move_earlier_trades(bars):
    """Same property, approached from the other side: rewrite the tail."""
    cut = len(bars) - 200
    mutated = list(bars[:cut]) + [
        replace_bar(b, factor=1.05) for b in bars[cut:]
    ]
    a = run(bars)
    b = run(mutated)
    ka = [t for t in a.trades if t.exited and t.exited < bars[cut].ts]
    kb = [t for t in b.trades if t.exited and t.exited < bars[cut].ts]
    assert len(ka) > 5
    assert [(t.entered, t.family, round(t.r_multiple, 9)) for t in ka] == \
           [(t.entered, t.family, round(t.r_multiple, 9)) for t in kb]


def replace_bar(bar, factor: float):
    return type(bar)(ts=bar.ts, open=bar.open * factor, high=bar.high * factor,
                     low=bar.low * factor, close=bar.close * factor, dxy=bar.dxy)


# --- hard limits ---------------------------------------------------------------

def test_daily_cap_is_never_exceeded(bars):
    engine = run(bars)
    assert engine.day_hist[4] == 0, "a day booked more than the hard cap"
    per_day: dict = {}
    for t in engine.trades:
        key = (t.entered + __import__("datetime").timedelta(hours=7)).date()
        per_day[key] = per_day.get(key, 0) + 1
    assert max(per_day.values()) <= Params().max_per_day


def test_lower_cap_reduces_trades(bars):
    base = len(run(bars).trades)
    capped = len(run(bars, replace(Params(), max_per_day=1)).trades)
    assert capped < base


def test_no_trade_below_the_score_floor(bars):
    engine = run(bars)
    assert engine.trades
    assert min(t.score for t in engine.trades) >= Params().thr_bp


def test_risk_never_exceeds_the_hard_ceiling(bars):
    engine = run(bars)
    assert max(t.risk_pct for t in engine.trades) <= Params().risk_ceil + 1e-9


def test_later_trades_in_a_day_are_sized_down():
    """The 2nd and 3rd trades of a day must not get full tier risk."""
    p = Params()
    assert p.scale2 < 1.0 and p.scale3 < p.scale2


# --- independence ---------------------------------------------------------------

def test_no_immediate_re_entry(bars):
    """Exit then straight back in on the same structure is the failure mode
    the independence rules exist to prevent, so it is worth asserting on bar
    indices rather than on timestamps, which weekends and session gaps blur."""
    p = Params()
    engine = run(bars)
    ordered = sorted(engine.trades, key=lambda t: t.entry_bar)
    assert len(ordered) > 20
    for prev, nxt in zip(ordered, ordered[1:]):
        assert nxt.entry_bar - prev.exit_bar >= p.cooldown, (
            f"re-entered {nxt.entry_bar - prev.exit_bar} bars after an exit, "
            f"cooldown is {p.cooldown}"
        )


def test_cooldown_actually_binds(bars):
    """And the rule must be doing work: removing it has to change the result."""
    slow = run(bars, replace(Params(), cooldown=40))
    fast = run(bars, replace(Params(), cooldown=0))
    assert len(slow.trades) < len(fast.trades)


def test_anchor_rule_blocks_something(bars):
    """If the anchor rule never fires it is not doing any work."""
    engine = run(bars)
    assert engine.f.block_anchor > 0


# --- the funnel adds up -----------------------------------------------------------

def test_funnel_is_internally_consistent(bars):
    f = run(bars).f
    assert sum(f.passed) + f.score_fail == sum(f.candidates)
    assert sum(f.cand_by_score) == sum(f.candidates)
    assert f.filled <= f.armed
    assert f.arm_expired + f.arm_voided + f.filled <= f.armed
    assert f.same_bar <= f.filled
    assert sum(f.taken) == f.filled


def test_every_candidate_is_scored_and_bucketed(bars):
    """No candidate may be dropped before it reaches the calibration table."""
    engine = run(bars)
    assert sum(engine.f.cand_by_score) == sum(engine.f.candidates)
    # Bucket 0 is below the trade floor and must therefore never hold a trade.
    assert all(score_bucket(t.score) > 0 for t in engine.trades)


def test_score_bucket_boundaries():
    assert score_bucket(71.9) == 0
    assert score_bucket(72.0) == 1
    assert score_bucket(74.9) == 1
    assert score_bucket(75.0) == 2
    assert score_bucket(100.0) == N_SCORE - 1


# --- the generator ----------------------------------------------------------------

def test_synthetic_bars_are_well_formed(bars):
    for bar in bars[:2000]:
        assert bar.low <= bar.open <= bar.high
        assert bar.low <= bar.close <= bar.high
        assert bar.high >= bar.low


def test_synthetic_volatility_is_in_the_right_range(bars):
    """True range near 0.10% of price is what real XAUUSD 15m runs at."""
    trs = [max(b.high - b.low, abs(b.high - a.close), abs(b.low - a.close))
           for a, b in zip(bars, bars[1:])]
    mean_tr = sum(trs) / len(trs)
    mean_px = sum(b.close for b in bars) / len(bars)
    assert 0.05 <= mean_tr / mean_px * 100 <= 0.20


def test_generator_is_deterministic():
    a = synthetic.generate(date(2020, 1, 1), date(2020, 3, 1), seed=99)
    b = synthetic.generate(date(2020, 1, 1), date(2020, 3, 1), seed=99)
    assert [x.close for x in a] == [x.close for x in b]
