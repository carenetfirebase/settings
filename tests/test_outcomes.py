"""Outcome evaluation: every exit path, and every pessimistic tie-break."""

from __future__ import annotations

from datetime import date, timedelta

import pandas as pd
import pytest

from invest.engines.costs import CostModel
from invest.engines.outcomes import OutcomeStatus, evaluate_outcome

FREE = CostModel(half_spread_bps=0.0, slippage_bps=0.0)
START = date(2026, 3, 2)

# A card: entry 100, stop 95 (R = 5), target 110 (+2R).
CARD = {"entry": 100.0, "stop": 95.0, "target": 110.0}


def bars(*ohlc: tuple[float, float, float, float]) -> pd.DataFrame:
    days = [START + timedelta(days=i) for i in range(len(ohlc))]
    return pd.DataFrame(ohlc, columns=["open", "high", "low", "close"], index=days)


def test_no_bars_is_pending() -> None:
    assert evaluate_outcome(**CARD, bars_after=bars(), costs=FREE).status == OutcomeStatus.PENDING


def test_not_yet_triggered_inside_the_window_is_pending() -> None:
    out = evaluate_outcome(**CARD, bars_after=bars((98, 99, 97, 98)), costs=FREE)
    assert out.status == OutcomeStatus.PENDING and not out.is_final


def test_never_triggered_expires_after_the_window() -> None:
    quiet = bars(*[(98, 99, 97, 98)] * 5)
    out = evaluate_outcome(**CARD, bars_after=quiet, costs=FREE)
    assert out.status == OutcomeStatus.EXPIRED and out.is_final
    assert out.r_net is None


def test_target_hit_is_plus_two_r() -> None:
    out = evaluate_outcome(
        **CARD, bars_after=bars((99, 101, 98, 100), (101, 111, 100, 109)), costs=FREE
    )
    assert out.status == OutcomeStatus.TARGET
    assert out.entry_fill == 100 and out.exit_fill == 110
    assert out.r_net == pytest.approx(2.0)
    assert out.first_touch == "up"
    assert out.bars_held == 2


def test_stop_hit_is_minus_one_r() -> None:
    out = evaluate_outcome(**CARD, bars_after=bars((99, 101, 98, 99), (98, 99, 94, 95)), costs=FREE)
    assert out.status == OutcomeStatus.STOP
    assert out.r_net == pytest.approx(-1.0)
    assert out.first_touch == "down"


def test_gap_through_the_stop_fills_at_the_open() -> None:
    out = evaluate_outcome(**CARD, bars_after=bars((99, 101, 98, 99), (90, 92, 89, 91)), costs=FREE)
    assert out.status == OutcomeStatus.STOP
    assert out.exit_fill == 90
    assert out.r_net == pytest.approx(-2.0)


def test_gap_over_the_entry_fills_at_the_open() -> None:
    out = evaluate_outcome(**CARD, bars_after=bars((103, 111, 102, 110)), costs=FREE)
    assert out.entry_fill == 103
    assert out.status == OutcomeStatus.TARGET
    assert out.r_net == pytest.approx((110 - 103) / 5)


def test_a_bar_touching_both_stop_and_target_is_a_stop() -> None:
    out = evaluate_outcome(
        **CARD, bars_after=bars((99, 101, 98, 100), (100, 112, 94, 105)), costs=FREE
    )
    assert out.status == OutcomeStatus.STOP


def test_the_fill_bar_can_stop_out() -> None:
    out = evaluate_outcome(**CARD, bars_after=bars((97, 101, 94, 96)), costs=FREE)
    assert out.status == OutcomeStatus.STOP and out.bars_held == 1


def test_time_stop_closes_at_the_close() -> None:
    drift = [(99, 101, 98, 100)] + [(100, 102, 99, 101)] * 20
    out = evaluate_outcome(**CARD, bars_after=bars(*drift), costs=FREE, time_stop=15)
    assert out.status == OutcomeStatus.TIME
    assert out.bars_held == 15
    assert out.exit_fill == 101
    assert out.r_net == pytest.approx(0.2)


def test_still_open_marks_to_the_last_close() -> None:
    out = evaluate_outcome(
        **CARD, bars_after=bars((99, 101, 98, 100), (100, 104, 99, 103)), costs=FREE
    )
    assert out.status == OutcomeStatus.OPEN and not out.is_final
    assert out.exit_fill is None
    assert out.r_net == pytest.approx(0.6)


def test_mfe_and_mae() -> None:
    out = evaluate_outcome(
        **CARD,
        bars_after=bars((99, 101, 98, 100), (100, 106, 97, 104), (104, 111, 103, 110)),
        costs=FREE,
    )
    assert out.mfe_r == pytest.approx(2.0)  # max high 110 (exit), fill 100
    assert out.mae_r == pytest.approx(-0.6)  # min low 97


def test_costs_reduce_the_result() -> None:
    priced = CostModel(half_spread_bps=2.5, slippage_bps=5.0)
    path = bars((99, 101, 98, 100), (101, 111, 100, 109))
    free = evaluate_outcome(**CARD, bars_after=path, costs=FREE)
    paid = evaluate_outcome(**CARD, bars_after=path, costs=priced)
    assert paid.cost_r == pytest.approx((100 + 110) * 7.5 / 10_000 / 5)
    assert paid.r_net == pytest.approx(free.r_net - paid.cost_r)


def test_incomplete_bars_are_skipped_not_guessed() -> None:
    path = bars((99, 101, 98, 100), (None, None, None, None), (101, 111, 100, 109))
    out = evaluate_outcome(**CARD, bars_after=path, costs=FREE)
    assert out.status == OutcomeStatus.TARGET and out.bars_held == 2


def test_rejects_an_inverted_card() -> None:
    with pytest.raises(ValueError):
        evaluate_outcome(entry=95, stop=100, target=110, bars_after=bars(), costs=FREE)
