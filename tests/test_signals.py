"""The V1 signal engine. Pure: every test builds its own bars.

The bars here are synthetic by design. They exist to put the engine in a known
state (an uptrend, a pullback, a crash) and check the rule that should fire.
"""

from __future__ import annotations

import ast
import inspect
import math
from datetime import date, timedelta
from decimal import Decimal

import pandas as pd
import pytest

from invest.engines import signals
from invest.engines.fundamentals import BeneishResult, Component, PiotroskiResult
from invest.engines.signals import (
    MIN_BARS,
    Check,
    Levels,
    MarketContext,
    SignalStatus,
    SymbolInputs,
    VolatilityScale,
    classify_insider,
    completed_month_end_closes,
    earnings_veto,
    evaluate_symbol,
    insider_tilt,
    momentum_12_1,
    percentile_ranks,
    projected_earnings_date,
    pullback,
    quality_veto,
    relative_strength_score,
    size_position,
    stock_trend,
    trade_levels,
    trend_gate,
    volatility_scale,
)
from invest.providers.base import InsiderTransactionRecord

AS_OF = date(2026, 9, 24)


def business_days(end: date, count: int) -> list[date]:
    days: list[date] = []
    d = end
    while len(days) < count:
        if d.weekday() < 5:
            days.append(d)
        d -= timedelta(days=1)
    return list(reversed(days))


def frame_from_closes(
    closes: list[float], *, end: date = AS_OF, spread: float = 0.01
) -> pd.DataFrame:
    """Bars whose high/low sit `spread` either side of the close."""
    days = business_days(end, len(closes))
    rows = []
    prev = closes[0]
    for c in closes:
        rows.append(
            {
                "open": prev,
                "high": c * (1 + spread),
                "low": c * (1 - spread),
                "close": c,
                "volume": 1_000_000,
            }
        )
        prev = c
    return pd.DataFrame(rows, index=days)


def rising(n: int, start: float = 100.0, daily: float = 0.001) -> list[float]:
    return [start * (1 + daily) ** i for i in range(n)]


def uptrend_with_pullback(n: int = 320, dip_days: int = 5, dip: float = 0.012) -> list[float]:
    """A steady uptrend whose last `dip_days` bars each fall `dip`."""
    closes = rising(n - dip_days, daily=0.0015)
    for _ in range(dip_days):
        closes.append(closes[-1] * (1 - dip))
    return closes


def open_market() -> MarketContext:
    return MarketContext(
        as_of=AS_OF,
        gate=Check("trend_gate", True, "open"),
        volatility=VolatilityScale(1.0, "calm"),
        equity=100_000.0,
    )


def piotroski(score: int, available: int = 9) -> PiotroskiResult:
    comps = [Component(f"s{i}", 1.0 if i < score else 0.0, "") for i in range(available)]
    comps += [Component(f"m{i}", None, "", "missing") for i in range(9 - available)]
    return PiotroskiResult(components=comps)


def insider(
    name: str, day: date, code: str = "P", side: str = "A", filed: date | None = None
) -> InsiderTransactionRecord:
    return InsiderTransactionRecord(
        cik="1",
        insider_name=name,
        transaction_date=day,
        filed_date=filed or day + timedelta(days=2),
        transaction_code=code,
        acquired_disposed=side,
        shares=Decimal(100),
        price_per_share=Decimal(10),
        source="test",
    )


# --------------------------------------------------------------------------
# The 10/10 rule, enforced structurally
# --------------------------------------------------------------------------

FORBIDDEN = {
    "rsi",
    "macd",
    "bollinger_bands",
    "position_in_52_week_range",
    "regime",
    "breadth",
    "political",
}


def test_engine_uses_no_input_outside_the_10_of_10_list() -> None:
    """docs/ENGINE_INPUTS.md: only inputs meeting all eight criteria may move
    a score. RSI, MACD, 52-week position, breadth and the macro regime are
    not on the list, so the engine must not even reference them.
    """
    tree = ast.parse(inspect.getsource(signals))
    names = {n.id.lower() for n in ast.walk(tree) if isinstance(n, ast.Name)}
    names |= {n.attr.lower() for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
    imported = {
        (alias.name or "").lower()
        for n in ast.walk(tree)
        if isinstance(n, ast.ImportFrom | ast.Import)
        for alias in n.names
    }
    modules = {(n.module or "").lower() for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)}
    assert not (names | imported) & FORBIDDEN
    assert not any("regime" in m or "political" in m or "congress" in m for m in modules)


# --------------------------------------------------------------------------
# Trend (input 3)
# --------------------------------------------------------------------------


def test_month_end_closes_skip_the_unfinished_month() -> None:
    frame = frame_from_closes(rising(90), end=date(2026, 9, 24))
    month_ends = completed_month_end_closes(frame["close"], date(2026, 9, 24))
    assert month_ends.index[-1] == date(2026, 8, 31)
    assert all(d.month != 9 or d.year != 2026 for d in month_ends.index)
    # Each value is that month's last close.
    aug = frame["close"][[d.month == 8 and d.year == 2026 for d in frame.index]]
    assert month_ends.iloc[-1] == pytest.approx(aug.iloc[-1])


def test_trend_gate_open_in_an_uptrend_and_closed_in_a_downtrend() -> None:
    up = frame_from_closes(rising(300))["close"]
    down = frame_from_closes(rising(300, daily=-0.001))["close"]
    assert trend_gate(up, AS_OF).passed is True
    assert trend_gate(down, AS_OF).passed is False
    assert "10-month average" in trend_gate(up, AS_OF).detail


def test_trend_gate_unknown_without_ten_month_ends() -> None:
    short = frame_from_closes(rising(100))["close"]
    assert trend_gate(short, AS_OF).passed is None


def test_stock_trend_filter_and_strength() -> None:
    up = stock_trend(frame_from_closes(rising(300))["close"])
    assert up.filter.passed is True
    assert up.score.value == pytest.approx(100.0)
    down = stock_trend(frame_from_closes(rising(300, daily=-0.001))["close"])
    assert down.filter.passed is False
    assert down.score.value == pytest.approx(0.0)
    thin = stock_trend(frame_from_closes(rising(100))["close"])
    assert thin.filter.passed is None and thin.score.value is None


# --------------------------------------------------------------------------
# Relative strength (input 4)
# --------------------------------------------------------------------------


def test_momentum_skips_the_latest_month() -> None:
    closes = rising(MIN_BARS + 30)
    # Crash the last month: 12-1 momentum must not see it.
    closes[-signals.MOMENTUM_SKIP_DAYS :] = [1.0] * signals.MOMENTUM_SKIP_DAYS
    series = frame_from_closes(closes)["close"]
    expected = closes[-1 - signals.MOMENTUM_SKIP_DAYS] / closes[-1 - signals.TWELVE_MONTHS] - 1
    assert momentum_12_1(series) == pytest.approx(expected)
    assert momentum_12_1(frame_from_closes(rising(50))["close"]) is None


def test_percentile_ranks() -> None:
    ranks = percentile_ranks({"a": 0.1, "b": 0.3, "c": 0.2, "d": None})
    assert ranks == {"a": 0.0, "b": 100.0, "c": 50.0, "d": None}
    tied = percentile_ranks({"a": 0.1, "b": 0.1, "c": 0.3})
    assert tied["a"] == tied["b"] == pytest.approx(25.0)
    assert percentile_ranks({"a": 0.1}) == {"a": None}


def test_relative_strength_averages_stock_and_sector() -> None:
    both = relative_strength_score(80.0, 40.0, sector_fund="XLK")
    assert both.value == pytest.approx(60.0)
    assert "XLK" in both.detail
    assert relative_strength_score(80.0, None, sector_fund=None).value == pytest.approx(80.0)
    assert relative_strength_score(None, None, sector_fund=None).value is None


# --------------------------------------------------------------------------
# Pullback (input 5) and volatility (input 6)
# --------------------------------------------------------------------------


def test_pullback_detected_in_an_uptrend_dip() -> None:
    result = pullback(frame_from_closes(uptrend_with_pullback()))
    assert result.present is True
    assert result.five_day_return < 0
    assert signals.PULLBACK_MIN_ATR <= result.depth_atr <= signals.PULLBACK_MAX_ATR
    assert 0 < result.score.value <= 100


def test_no_pullback_while_rising() -> None:
    result = pullback(frame_from_closes(rising(320)))
    assert result.present is False
    assert "not declining" in result.score.detail


def test_a_crash_is_a_breakdown_not_a_pullback() -> None:
    result = pullback(frame_from_closes(uptrend_with_pullback(dip=0.06)))
    assert result.present is False
    assert "breakdown" in result.score.detail


def test_volatility_scale_cuts_risk_when_markets_run_hot() -> None:
    calm = rising(300, daily=0.0005)
    wild = list(calm)
    for i in range(1, 22):
        wild[-i] = wild[-i] * (1.04 if i % 2 else 0.96)
    hot = volatility_scale(frame_from_closes(wild)["close"])
    assert signals.VOL_SCALE_FLOOR <= hot.multiplier < 1.0
    unknown = volatility_scale(frame_from_closes(rising(50))["close"])
    assert unknown.multiplier == signals.VOL_SCALE_FLOOR


def test_volatility_scale_never_levers_up() -> None:
    noisy = [100 * (1.02 if i % 2 else 0.98) ** (i % 3) for i in range(300)]
    noisy[-22:] = [noisy[-23]] * 22  # a dead-calm final month
    assert volatility_scale(frame_from_closes(noisy)["close"]).multiplier <= 1.0


# --------------------------------------------------------------------------
# Trade card
# --------------------------------------------------------------------------


def test_trade_levels_geometry() -> None:
    frame = frame_from_closes(uptrend_with_pullback())
    levels = trade_levels(frame)
    assert isinstance(levels, Levels)
    assert levels.entry > frame["high"].iloc[-1]
    assert levels.entry - levels.stop >= signals.MIN_STOP_ATR * levels.atr - 0.02
    assert levels.target == pytest.approx(
        levels.entry + 2 * (levels.entry - levels.stop), abs=0.011
    )
    for price in (levels.entry, levels.stop, levels.target):
        assert round(price, 2) == price


def test_trade_levels_refuse_a_stop_too_far_away() -> None:
    closes = rising(300)
    frame = frame_from_closes(closes, spread=0.002)
    frame.iloc[-5, frame.columns.get_loc("low")] = frame["close"].iloc[-1] * 0.5
    result = trade_levels(frame)
    assert isinstance(result, Check) and result.passed is False


def test_size_position() -> None:
    levels = Levels(entry=100.0, stop=95.0, target=110.0, atr=2.5)
    sized = size_position(levels, equity=100_000, vol_multiplier=0.8)
    assert sized.risk_fraction == pytest.approx(0.006)
    assert sized.shares == 120  # $600 / $5
    unsized = size_position(levels, equity=None, vol_multiplier=1.0)
    assert unsized.shares is None and "ACCOUNT_EQUITY" in unsized.detail


# --------------------------------------------------------------------------
# Vetoes (inputs 7 and 8)
# --------------------------------------------------------------------------


def test_quality_veto() -> None:
    assert quality_veto(piotroski(7), BeneishResult(score=-2.5)).passed is True
    assert quality_veto(piotroski(2), None).passed is False
    assert quality_veto(piotroski(8), BeneishResult(score=-1.0)).passed is False
    assert quality_veto(None, None).passed is None
    # An unreliable F-score (too many missing signals) is not evidence.
    assert quality_veto(piotroski(1, available=4), None).passed is None


def test_projected_earnings_rolls_past_missed_quarters() -> None:
    assert projected_earnings_date([date(2026, 7, 30)], AS_OF) == date(2026, 10, 29)
    rolled = projected_earnings_date([date(2025, 7, 30)], AS_OF)
    assert rolled >= AS_OF - timedelta(days=signals.EARNINGS_UNCERTAINTY_DAYS)
    assert projected_earnings_date([], AS_OF) is None


def test_earnings_veto() -> None:
    history = [date(2026, 4, 30), date(2026, 7, 30)]
    assert earnings_veto(history, date(2026, 10, 10)).passed is False
    assert earnings_veto(history, date(2026, 8, 14)).passed is True
    assert earnings_veto([], AS_OF).passed is None


# --------------------------------------------------------------------------
# Insider tilt (input 9)
# --------------------------------------------------------------------------


def test_classify_insider() -> None:
    routine = [date(2023, 3, 1), date(2024, 3, 5), date(2025, 3, 2)]
    opportunistic = [date(2023, 3, 1), date(2024, 6, 5), date(2025, 11, 2)]
    patchy = [date(2023, 3, 1), date(2025, 3, 2)]
    assert classify_insider(routine, AS_OF) == "routine"
    assert classify_insider(opportunistic, AS_OF) == "opportunistic"
    assert classify_insider(patchy, AS_OF) == "unclassified"


def test_insider_tilt_rewards_only_opportunistic_buys() -> None:
    history = [insider("Ada", d) for d in (date(2023, 2, 1), date(2024, 6, 1), date(2025, 10, 1))]
    recent_buy = insider("Ada", AS_OF - timedelta(days=20))
    tilt = insider_tilt([*history, recent_buy], AS_OF)
    assert tilt.bonus == signals.INSIDER_BONUS and tilt.opportunistic_buys == 1

    routine_history = [
        insider("Bo", d) for d in (date(2023, 9, 1), date(2024, 9, 1), date(2025, 9, 1))
    ]
    routine = insider_tilt([*routine_history, insider("Bo", AS_OF - timedelta(days=10))], AS_OF)
    assert routine.bonus == 0 and routine.other_buys == 1

    sale = insider_tilt(
        [*history, insider("Ada", AS_OF - timedelta(days=5), code="S", side="D")], AS_OF
    )
    assert sale.bonus == 0

    assert insider_tilt([], AS_OF).bonus == 0


def test_insider_tilt_ignores_filings_after_as_of() -> None:
    history = [insider("Ada", d) for d in (date(2023, 2, 1), date(2024, 6, 1), date(2025, 10, 1))]
    late = insider("Ada", AS_OF - timedelta(days=1), filed=AS_OF + timedelta(days=1))
    assert insider_tilt([*history, late], AS_OF).bonus == 0


# --------------------------------------------------------------------------
# End to end, one symbol
# --------------------------------------------------------------------------


def good_inputs(**overrides) -> SymbolInputs:
    base = {
        "ticker": "TEST",
        "frame": frame_from_closes(uptrend_with_pullback()),
        "sector": "Information Technology",
        "sector_fund": "XLK",
        "stock_momentum_percentile": 90.0,
        "sector_momentum_percentile": 70.0,
        "piotroski": piotroski(7),
        "beneish": BeneishResult(score=-2.6),
        "earnings_dates": [date(2026, 8, 20)],  # next expected ~Nov 19: outside the hold
    }
    base.update(overrides)
    return SymbolInputs(**base)


def test_card_when_every_rule_passes() -> None:
    signal = evaluate_symbol(good_inputs(), open_market())
    assert signal.status == SignalStatus.CARD
    assert signal.fired and signal.is_candidate
    assert signal.levels is not None and signal.sizing.shares > 0
    assert 0 < signal.final_score <= 100
    assert signal.score.coverage == pytest.approx(0.75)  # ecosystem is V2
    components = {c.name for c in signal.score.components}
    assert components == {"trend", "relative_strength", "pullback", "ecosystem_lead_lag"}


def test_gate_closed_is_still_recorded_as_a_candidate() -> None:
    market = open_market()
    market.gate = Check("trend_gate", False, "below average")
    signal = evaluate_symbol(good_inputs(), market)
    assert signal.status == SignalStatus.GATE_CLOSED
    assert signal.is_candidate and not signal.fired


def test_unknown_gate_counts_as_closed() -> None:
    market = open_market()
    market.gate = Check("trend_gate", None, "not enough history")
    assert evaluate_symbol(good_inputs(), market).status == SignalStatus.GATE_CLOSED


def test_vetoes_block_the_card() -> None:
    weak = evaluate_symbol(good_inputs(piotroski=piotroski(1)), open_market())
    assert weak.status == SignalStatus.VETOED and weak.is_candidate
    near_earnings = evaluate_symbol(good_inputs(earnings_dates=[date(2026, 7, 15)]), open_market())
    assert near_earnings.status == SignalStatus.VETOED
    assert any("Earnings" in r for r in near_earnings.reasons)


def test_unknown_vetoes_warn_but_do_not_block() -> None:
    signal = evaluate_symbol(
        good_inputs(piotroski=None, beneish=None, earnings_dates=[]), open_market()
    )
    assert signal.status == SignalStatus.CARD
    assert sum(r.startswith("Unverified") for r in signal.reasons) == 2


def test_statuses_before_a_setup_exists() -> None:
    thin = evaluate_symbol(good_inputs(frame=frame_from_closes(rising(100))), open_market())
    assert thin.status == SignalStatus.INSUFFICIENT_DATA and not thin.is_candidate
    falling = evaluate_symbol(
        good_inputs(frame=frame_from_closes(rising(320, daily=-0.001))), open_market()
    )
    assert falling.status == SignalStatus.NOT_IN_UPTREND
    flat_up = evaluate_symbol(good_inputs(frame=frame_from_closes(rising(320))), open_market())
    assert flat_up.status == SignalStatus.NO_PULLBACK


def test_the_insider_bonus_is_capped_at_100() -> None:
    history = [insider("Ada", d) for d in (date(2023, 2, 1), date(2024, 6, 1), date(2025, 10, 1))]
    signal = evaluate_symbol(
        good_inputs(
            stock_momentum_percentile=100.0,
            sector_momentum_percentile=100.0,
            insider_records=[*history, insider("Ada", AS_OF - timedelta(days=3))],
        ),
        open_market(),
    )
    assert signal.insider.bonus == signals.INSIDER_BONUS
    assert signal.final_score <= 100.0
    assert math.isclose(signal.final_score, min(100.0, signal.base_score + signals.INSIDER_BONUS))


def test_signal_serialises() -> None:
    payload = evaluate_symbol(good_inputs(), open_market()).as_dict()
    assert payload["status"] == "card"
    assert payload["levels"]["target_r"] == signals.TARGET_R
    assert payload["model_version"] == signals.MODEL_VERSION


def test_tiny_moves_never_print_as_negative_zero() -> None:
    assert signals._pct(-0.0004) == "-0.04%"
    assert signals._pct(0.123) == "+12.3%"
    assert signals._pct(0.0) == "+0.0%"
