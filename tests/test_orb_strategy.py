"""Behavioural tests for the 08:30 NY opening-range-breakout model.

Every fixture here is *constructed*, not sampled from a market. That is
deliberate: these tests answer "do the rules fire when they should, on the bar
they should, at the price they should", which is a question about the rule set,
not about gold. No assertion in this file makes a claim about profitability,
and none should be added.

The bar geometry is chosen so the ATR is exactly 1.00 through the opening
range, which makes the tolerance, buffer and floor terms readable in the
assertions (0.05, 0.02, 0.50) instead of arriving as magic decimals.
"""

from __future__ import annotations

from collections import Counter
from datetime import date, datetime, time, timedelta

import pytest

from invest.strategies.orb import (
    Bar,
    Direction,
    EntryReason,
    ExitReason,
    NoTradeReason,
    OrbConfig,
    WilderAtr,
    simulate,
    true_range,
)

DAY = date(2026, 3, 3)  # a Tuesday
OR_HIGH = 2001.5
OR_LOW = 1999.5
OR_MID = 2000.5


# ---------------------------------------------------------------------------
# fixture construction
# ---------------------------------------------------------------------------


def at(day: date, hhmm: str) -> datetime:
    hh, mm = hhmm.split(":")
    return datetime.combine(day, time(int(hh), int(mm)))


def bar(day: date, hhmm: str, o: float, h: float, low: float, c: float) -> Bar:
    return Bar(ts=at(day, hhmm), open=o, high=h, low=low, close=c)


def quiet(day: date, start: str, end: str, price: float, width: float = 0.5) -> list[Bar]:
    """Filler bars that sit still at ``price``. Used to warm the ATR and to
    occupy minutes where the test does not care what happens."""
    out: list[Bar] = []
    cur, stop = at(day, start), at(day, end)
    while cur <= stop:
        out.append(Bar(ts=cur, open=price, high=price + width, low=price - width, close=price))
        cur += timedelta(minutes=1)
    return out


#: Warm-up bars: 90 identical minutes, each with a true range of exactly 1.00,
#: so the Wilder ATR is exactly 1.00 when the opening range starts. Ninety
#: minutes rather than thirty because the same fixture gets resampled to
#: 5-minute bars, and a 14-period ATR needs 14 bars at *that* size too.
def warmup(day: date) -> list[Bar]:
    return quiet(day, "07:00", "08:29", 2000.0, width=0.5)


#: The opening range: high 2001.50, low 1999.50, every bar a 1.00 true range so
#: the ATR is still exactly 1.00 at 08:35.
def opening_range(day: date) -> list[Bar]:
    return [
        bar(day, "08:30", 2000.0, 2000.5, 1999.5, 2000.5),
        bar(day, "08:31", 2000.5, 2001.5, 2000.5, 2001.5),
        bar(day, "08:32", 2001.5, 2001.5, 2000.5, 2000.5),
        bar(day, "08:33", 2000.5, 2001.0, 2000.0, 2000.5),
        bar(day, "08:34", 2000.5, 2001.0, 2000.0, 2000.5),
    ]


def assemble(*groups: list[Bar]) -> list[Bar]:
    """Merge bar groups; a later group wins on a duplicated timestamp."""
    merged: dict[datetime, Bar] = {}
    for group in groups:
        for b in group:
            merged[b.ts] = b
    return [merged[ts] for ts in sorted(merged)]


def atr_at(bars: list[Bar], hhmm: str, day: date = DAY) -> float:
    """Wilder ATR as of the bar at ``hhmm``, computed independently here.

    Deliberately a separate five-line implementation from the module's, so a
    stop-placement assertion is not checked against the same code that produced
    it.
    """
    target_ts = at(day, hhmm)
    value: float | None = None
    seed: list[float] = []
    prev_close: float | None = None
    for b in bars:
        tr = true_range(b, prev_close)
        prev_close = b.close
        if value is None:
            seed.append(tr)
            if len(seed) == 14:
                value = sum(seed) / 14
        else:
            value = (value * 13 + tr) / 14
        if b.ts == target_ts:
            assert value is not None, "ATR not warm at the asserted bar"
            return value
    raise AssertionError(f"no bar at {hhmm}")


# Interaction bar: reaches the OR high and stays in the tolerance zone.
TOUCH_LONG = (2000.6, 2001.6, 2000.5, 2001.4)
# Confirmation bar: closes clear of the OR high, strong body, close at the top.
CONFIRM_LONG = (2001.4, 2003.0, 2001.3, 2002.9)


def confirmed_long_day(day: date = DAY, tail: list[Bar] | None = None) -> list[Bar]:
    return assemble(
        warmup(day),
        opening_range(day),
        [bar(day, "08:35", *TOUCH_LONG), bar(day, "08:36", *CONFIRM_LONG)],
        tail if tail is not None else quiet(day, "08:37", "09:05", 2003.0),
    )


# ---------------------------------------------------------------------------
# ATR
# ---------------------------------------------------------------------------


def test_wilder_atr_matches_hand_computed_series():
    """Seeded with an SMA of the first 14 true ranges, then Wilder-smoothed."""
    atr = WilderAtr(3)
    bars = [
        bar(DAY, "09:00", 100, 102, 99, 101),  # TR 3 (no prior close)
        bar(DAY, "09:01", 101, 104, 100, 103),  # TR max(4, 3, 1) = 4
        bar(DAY, "09:02", 103, 105, 102, 104),  # TR max(3, 2, 1) = 3
        bar(DAY, "09:03", 104, 108, 104, 107),  # TR max(4, 4, 0) = 4
    ]
    assert atr.update(bars[0]) is None
    assert atr.update(bars[1]) is None
    assert atr.update(bars[2]) == pytest.approx((3 + 4 + 3) / 3)  # SMA seed
    assert atr.update(bars[3]) == pytest.approx((10 / 3 * 2 + 4) / 3)


def test_atr_is_exactly_one_through_the_opening_range():
    """The fixtures depend on this; if it drifts the other assertions lie."""
    bars = assemble(warmup(DAY), opening_range(DAY))
    assert atr_at(bars, "08:34") == pytest.approx(1.0)


# ---------------------------------------------------------------------------
# the opening range itself
# ---------------------------------------------------------------------------


def test_opening_range_is_built_from_five_one_minute_bars():
    """08:30-08:35 is one bar on a 5m chart and five decisions on a 1m chart."""
    result = simulate(confirmed_long_day())
    day = result.days[0]
    assert result.bar_seconds == 60
    assert day.or_bars == 5
    assert (day.or_high, day.or_low) == (OR_HIGH, OR_LOW)


def test_opening_range_bars_never_trade():
    """08:30-08:34 builds the range. Nothing may fire inside it."""
    result = simulate(confirmed_long_day())
    trade = result.trades[0]
    assert trade.entry_time.time() >= time(8, 35)


# ---------------------------------------------------------------------------
# confirmed entries
# ---------------------------------------------------------------------------


def test_confirmed_long_enters_on_the_bar_after_the_interaction():
    bars = confirmed_long_day()
    result = simulate(bars)

    assert len(result.trades) == 1
    trade = result.trades[0]
    assert trade.reason is EntryReason.CONFIRMED
    assert trade.direction is Direction.LONG
    assert trade.entry_time == at(DAY, "08:36")
    assert trade.entry_price == CONFIRM_LONG[3]


def test_stop_sits_below_the_interaction_bar_wick_not_the_signal_bar():
    """The structural stop is the *touch* bar's low, buffered by 0.05 ATR."""
    bars = confirmed_long_day()
    atr = atr_at(bars, "08:36")
    trade = simulate(bars).trades[0]

    touch_low = TOUCH_LONG[2]
    assert trade.stop == pytest.approx(touch_low - 0.05 * atr)
    assert trade.risk == pytest.approx(trade.entry_price - trade.stop)


def test_target_is_exactly_the_configured_r_multiple():
    bars = confirmed_long_day()
    trade = simulate(bars, OrbConfig(rr=2.5)).trades[0]
    assert trade.target - trade.entry_price == pytest.approx(2.5 * trade.risk)


def test_a_single_bar_cannot_confirm_itself():
    """The whole rule is touch-then-break. One bar doing both is not a signal.

    The 08:35 bar below touches the OR high *and* closes far beyond it with a
    textbook body. It must not trade. The day falls through to the forced
    entry instead.
    """
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        [
            bar(DAY, "08:35", 2000.6, 2003.5, 2000.5, 2003.4),  # touch + close beyond
            bar(DAY, "08:36", 2003.4, 2003.5, 2002.6, 2002.7),  # red: no confirmation
        ],
        quiet(DAY, "08:37", "09:05", 2000.4),  # back inside, no further touches
    )
    result = simulate(bars)
    trade = result.trades[0]

    assert trade.entry_time != at(DAY, "08:35")
    assert trade.reason is EntryReason.FORCED


def test_weak_break_bar_is_rejected_on_body_and_close_location():
    """Closing beyond the range is not enough; the bar must look like a break."""
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        [
            bar(DAY, "08:35", *TOUCH_LONG),
            # Closes above the OR high, but the body is 4% of a long range and
            # the close is mid-bar: a rejection candle, not a break.
            bar(DAY, "08:36", 2001.5, 2003.0, 2000.0, 2001.6),
        ],
        quiet(DAY, "08:37", "09:05", 2000.4),
    )
    trade = simulate(bars).trades[0]
    assert trade.reason is EntryReason.FORCED


def test_confirmation_window_after_a_touch_is_configurable():
    """Strictly-next-bar is the Pine original. On 1m, price usually probes a
    level for a few minutes before it goes, so the allowance is a knob."""
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        [
            bar(DAY, "08:35", *TOUCH_LONG),
            bar(DAY, "08:36", 2001.4, 2001.45, 2000.9, 2001.0),  # pause, no touch
            bar(DAY, "08:37", *CONFIRM_LONG),  # break, two bars after the touch
        ],
        quiet(DAY, "08:38", "09:05", 2003.0),
    )

    strict = simulate(bars, OrbConfig(max_bars_since_touch=1)).trades[0]
    assert strict.reason is EntryReason.FORCED

    relaxed = simulate(bars, OrbConfig(max_bars_since_touch=3)).trades[0]
    assert relaxed.reason is EntryReason.CONFIRMED
    assert relaxed.entry_time == at(DAY, "08:37")


def test_confirmed_short_mirrors_the_long_case():
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        [
            bar(DAY, "08:35", 2000.4, 2000.5, 1999.4, 1999.6),  # touches OR low
            bar(DAY, "08:36", 1999.6, 1999.7, 1998.0, 1998.1),  # closes below
        ],
        quiet(DAY, "08:37", "09:05", 1998.0),
    )
    atr = atr_at(bars, "08:36")
    trade = simulate(bars).trades[0]

    assert trade.reason is EntryReason.CONFIRMED
    assert trade.direction is Direction.SHORT
    assert trade.stop == pytest.approx(2000.5 + 0.05 * atr)
    assert trade.target == pytest.approx(trade.entry_price - 2 * trade.risk)


# ---------------------------------------------------------------------------
# the forced entry — the "one trade every day" guarantee
# ---------------------------------------------------------------------------


def inside_day(day: date = DAY) -> list[Bar]:
    """A day that never reaches either boundary: nothing can confirm."""
    return assemble(
        warmup(day),
        opening_range(day),
        quiet(day, "08:35", "09:05", 2000.9, width=0.2),
    )


def test_forced_entry_fires_on_the_last_minute_of_the_window():
    result = simulate(inside_day())
    trade = result.trades[0]
    assert trade.reason is EntryReason.FORCED
    assert trade.entry_time == at(DAY, "08:59")


def test_forced_entry_stop_is_the_opposite_side_of_the_range():
    """With no interaction there is no wick to hide behind, so the structure is
    the far edge of the opening range."""
    bars = inside_day()
    atr = atr_at(bars, "08:59")
    trade = simulate(bars).trades[0]

    assert trade.direction is Direction.LONG  # close 2000.9 sits above the mid
    assert trade.stop == pytest.approx(OR_LOW - 0.05 * atr)
    assert trade.stop < OR_LOW


def test_forced_direction_follows_pressure_not_the_last_tick():
    """Excursion below the range outweighs a close a hair above the mid."""
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        quiet(DAY, "08:35", "08:44", 1996.0),  # a long push below the range
        quiet(DAY, "08:45", "09:05", 2000.6),  # drifts back just over the mid
    )
    trade = simulate(bars).trades[0]
    assert trade.reason is EntryReason.FORCED
    assert trade.direction is Direction.SHORT


def test_forced_entry_survives_a_missing_forced_bar():
    """A gap in the feed at 08:59 must not cost the day its trade."""
    bars = [b for b in inside_day() if not (time(8, 55) <= b.ny_time < time(9, 0))]
    result = simulate(bars)
    trade = result.trades[0]
    assert trade.reason is EntryReason.FORCED
    assert trade.entry_time == at(DAY, "09:00")


def test_forced_entry_can_be_switched_off():
    """The guarantee is a choice, and turning it off is visible in the summary."""
    result = simulate(inside_day(), OrbConfig(force_daily_entry=False))
    assert result.trades == []
    assert result.days[0].no_trade_reason is NoTradeReason.FORCED_ENTRY_DISABLED


def test_pine_original_forced_bar_gives_up_the_last_four_minutes():
    """08:55 is one bar on a 5m chart and four wasted minutes on a 1m chart."""
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        quiet(DAY, "08:35", "08:56", 2000.9, width=0.2),
        # A textbook confirmation that only sets up at 08:57-08:58.
        [
            bar(DAY, "08:57", 2000.9, 2001.6, 2000.8, 2001.4),
            bar(DAY, "08:58", 2001.4, 2003.0, 2001.3, 2002.9),
        ],
        quiet(DAY, "08:59", "09:05", 2003.0),
    )

    pine_original = simulate(bars, OrbConfig(forced_from=time(8, 55))).trades[0]
    assert pine_original.reason is EntryReason.FORCED
    assert pine_original.entry_time == at(DAY, "08:55")

    full_window = simulate(bars).trades[0]
    assert full_window.reason is EntryReason.CONFIRMED
    assert full_window.entry_time == at(DAY, "08:58")


# ---------------------------------------------------------------------------
# exits
# ---------------------------------------------------------------------------


def test_target_hit_returns_exactly_the_configured_r():
    bars = confirmed_long_day(
        tail=assemble(
            quiet(DAY, "08:37", "08:39", 2003.0),
            [bar(DAY, "08:40", 2003.0, 2009.0, 2002.9, 2008.5)],
            quiet(DAY, "08:41", "09:05", 2008.0),
        )
    )
    trade = simulate(bars).trades[0]
    assert trade.exit_reason is ExitReason.TARGET
    assert trade.exit_price == pytest.approx(trade.target)
    assert trade.r_multiple == pytest.approx(2.0)


def test_stop_hit_returns_minus_one_r():
    bars = confirmed_long_day(
        tail=assemble(
            [bar(DAY, "08:37", 2002.9, 2003.0, 2000.0, 2000.2)],
            quiet(DAY, "08:38", "09:05", 2000.0),
        )
    )
    trade = simulate(bars).trades[0]
    assert trade.exit_reason is ExitReason.STOP
    assert trade.r_multiple == pytest.approx(-1.0)


def test_a_bar_spanning_both_levels_is_resolved_against_the_position():
    """OHLC cannot say which came first, so the model takes the stop."""
    bars = confirmed_long_day(
        tail=assemble(
            [bar(DAY, "08:37", 2002.9, 2012.0, 1998.0, 2010.0)],
            quiet(DAY, "08:38", "09:05", 2010.0),
        )
    )
    trade = simulate(bars).trades[0]
    assert trade.exit_reason is ExitReason.STOP
    assert trade.r_multiple == pytest.approx(-1.0)


def test_a_gap_through_the_stop_fills_at_the_open_not_at_the_level():
    """Assuming the stop price is always available is how backtests flatter."""
    bars = confirmed_long_day(
        tail=assemble(
            [bar(DAY, "08:37", 1995.0, 1995.5, 1994.0, 1994.5)],
            quiet(DAY, "08:38", "09:05", 1994.0),
        )
    )
    trade = simulate(bars).trades[0]
    assert trade.exit_reason is ExitReason.STOP
    assert trade.exit_price == 1995.0
    assert trade.r_multiple < -1.0


def test_protective_orders_are_not_live_on_the_entry_bar():
    """The fill is at the close; the bar's own low happened before the fill."""
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        [
            bar(DAY, "08:35", *TOUCH_LONG),
            # Dips to 1999.9 — below where the stop will sit — then closes high.
            bar(DAY, "08:36", 2001.4, 2003.0, 1999.9, 2002.9),
        ],
        quiet(DAY, "08:37", "09:05", 2002.9, width=0.2),
    )
    trade = simulate(bars).trades[0]
    assert trade.entry_time == at(DAY, "08:36")
    assert trade.stop > 1999.9  # the entry bar traded through the stop level
    assert trade.exit_reason is not ExitReason.STOP


def test_open_position_is_flattened_at_the_end_of_the_day():
    bars = assemble(
        confirmed_long_day(tail=quiet(DAY, "08:37", "16:00", 2003.0, width=0.2)),
        quiet(DAY, "16:01", "17:00", 2003.0, width=0.2),
    )
    trade = simulate(bars).trades[0]
    assert trade.exit_reason is ExitReason.FLAT
    assert trade.exit_time == at(DAY, "16:55")


# ---------------------------------------------------------------------------
# position sizing
# ---------------------------------------------------------------------------


def test_stop_distance_is_floored_so_size_cannot_explode():
    """A 1-minute interaction bar can sit a few cents from the break. Without a
    floor the risk distance approaches zero and the quantity approaches the
    account."""
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        [
            # A touch bar that barely pokes through and closes on its own low,
            # then a five-cent confirmation bar right on top of it.
            bar(DAY, "08:35", 2001.50, 2001.55, 2001.50, 2001.52),
            bar(DAY, "08:36", 2001.50, 2001.54, 2001.49, 2001.53),
        ],
        quiet(DAY, "08:37", "09:05", 2001.7, width=0.05),
    )
    atr = atr_at(bars, "08:36")
    # The notional cap is switched off here so the floor's effect on size is
    # isolated; it is tested on its own below.
    unfloored = simulate(bars, OrbConfig(min_stop_atr=0.0, max_notional_mult=0.0)).trades[0]
    floored = simulate(bars, OrbConfig(max_notional_mult=0.0)).trades[0]

    assert unfloored.risk < 0.10  # eight cents of risk on a $2000 instrument
    assert floored.risk == pytest.approx(0.5 * atr)
    assert floored.qty < unfloored.qty / 2


def test_notional_is_capped_independently_of_the_risk_budget():
    """Risk-based sizing answers "how much can I lose", not "can the account
    carry this". On a tight 1-minute stop the two diverge violently."""
    bars = assemble(
        warmup(DAY),
        opening_range(DAY),
        [
            bar(DAY, "08:35", 2001.50, 2001.55, 2001.50, 2001.52),
            bar(DAY, "08:36", 2001.50, 2001.54, 2001.49, 2001.53),
        ],
        quiet(DAY, "08:37", "09:05", 2001.7, width=0.05),
    )
    equity = 100_000.0
    uncapped = simulate(
        bars, OrbConfig(min_stop_atr=0.0, max_notional_mult=0.0, initial_equity=equity)
    ).trades[0]
    capped = simulate(
        bars, OrbConfig(min_stop_atr=0.0, max_notional_mult=5.0, initial_equity=equity)
    ).trades[0]

    assert uncapped.qty * uncapped.entry_price > 100 * equity  # eight figures
    assert capped.qty * capped.entry_price <= 5 * equity + 1e-6


def test_quantity_follows_the_risk_budget():
    bars = confirmed_long_day()
    cfg = OrbConfig(initial_equity=100_000.0, risk_pct=0.5, qty_step=0.01)
    trade = simulate(bars, cfg).trades[0]

    budget = 100_000.0 * 0.005
    expected = int((budget / trade.risk) / 0.01) * 0.01
    assert trade.qty == pytest.approx(expected, abs=1e-9)


# ---------------------------------------------------------------------------
# the daily guarantee, across days
# ---------------------------------------------------------------------------


def multi_day_bars() -> list[Bar]:
    """Five consecutive weekdays, deliberately mixed: two clean breaks, one
    fake-out, one range-bound day, one day that gaps straight through."""
    days = [date(2026, 3, 2) + timedelta(days=i) for i in range(5)]
    out: list[Bar] = []

    out += confirmed_long_day(days[0])
    out += inside_day(days[1])
    out += assemble(  # short break
        warmup(days[2]),
        opening_range(days[2]),
        [
            bar(days[2], "08:35", 2000.4, 2000.5, 1999.4, 1999.6),
            bar(days[2], "08:36", 1999.6, 1999.7, 1998.0, 1998.1),
        ],
        quiet(days[2], "08:37", "09:05", 1998.0),
    )
    out += assemble(  # fake-out: touches, never confirms
        warmup(days[3]),
        opening_range(days[3]),
        [bar(days[3], "08:35", 2000.6, 2001.6, 2000.5, 2000.6)],
        quiet(days[3], "08:36", "09:05", 2000.2, width=0.2),
    )
    out += assemble(  # a straight run away from the range
        warmup(days[4]),
        opening_range(days[4]),
        quiet(days[4], "08:35", "09:05", 2012.0),
    )
    return out


def test_every_day_with_an_opening_range_trades_exactly_once():
    result = simulate(multi_day_bars())

    assert len(result.days_with_opening_range) == 5
    assert result.untraded_days == []
    assert len(result.trades) == 5
    per_day = Counter(t.day for t in result.trades)
    assert set(per_day.values()) == {1}


def test_a_stopped_out_day_does_not_re_enter():
    """One trade per day means one, including after a loss."""
    bars = confirmed_long_day(
        tail=assemble(
            [bar(DAY, "08:37", 2002.9, 2003.0, 1999.0, 1999.2)],  # stopped
            # Then a textbook second setup inside the same window.
            [
                bar(DAY, "08:38", 1999.2, 2001.6, 1999.1, 2001.4),
                bar(DAY, "08:39", 2001.4, 2003.0, 2001.3, 2002.9),
            ],
            quiet(DAY, "08:40", "09:05", 2003.0),
        )
    )
    result = simulate(bars)
    assert len(result.trades) == 1
    assert result.trades[0].exit_reason is ExitReason.STOP


def test_state_does_not_leak_across_days():
    """Yesterday's range, touches and traded-flag must all be gone by 08:30."""
    result = simulate(multi_day_bars())
    ranges = {(d.or_high, d.or_low) for d in result.days}
    assert ranges == {(OR_HIGH, OR_LOW)}
    assert all(d.trade is not None and d.trade.day == d.day for d in result.days)


def test_a_day_with_no_opening_range_is_reported_not_traded():
    """No 08:30-08:35 data is a data problem, and the model says so rather than
    inventing a range."""
    bars = assemble(
        warmup(DAY),
        quiet(DAY, "08:35", "09:05", 2000.0),
    )
    result = simulate(bars)
    assert result.trades == []
    assert result.days[0].no_trade_reason is NoTradeReason.NO_OPENING_RANGE


# ---------------------------------------------------------------------------
# decision granularity: the actual question
# ---------------------------------------------------------------------------


def resample(bars: list[Bar], minutes: int) -> list[Bar]:
    buckets: dict[datetime, list[Bar]] = {}
    for b in bars:
        anchor = b.ts.replace(minute=(b.ts.minute // minutes) * minutes, second=0)
        buckets.setdefault(anchor, []).append(b)
    return [
        Bar(
            ts=anchor,
            open=group[0].open,
            high=max(x.high for x in group),
            low=min(x.low for x in group),
            close=group[-1].close,
        )
        for anchor, group in sorted(buckets.items())
    ]


def test_one_minute_bars_decide_earlier_than_five_minute_bars():
    """The same tape, two decision granularities. This is the whole question.

    On 1-minute bars the interaction is 08:35 and the confirmation is 08:36:
    two separate decisions, and the trade is a confirmed break with its stop
    under a 1-minute wick.

    On 5-minute bars that entire sequence is swallowed by the single
    08:35-08:40 candle. A bar cannot confirm itself, so the break is invisible,
    nothing confirms all window, and the day ends on the forced entry with a
    stop at the far side of the opening range instead.
    """
    bars = confirmed_long_day()
    one_minute = simulate(bars).trades[0]
    five_minute = simulate(resample(bars, 5)).trades[0]

    assert one_minute.reason is EntryReason.CONFIRMED
    assert one_minute.entry_time == at(DAY, "08:36")

    assert five_minute.reason is EntryReason.FORCED
    assert five_minute.entry_time > one_minute.entry_time
    # The 1m stop hangs off a 1-minute wick, so it is materially tighter.
    assert one_minute.risk < five_minute.risk


def test_the_model_runs_on_whatever_bar_size_it_is_given():
    """There is no hard-coded timeframe gate: feeding 5m bars is a choice, not
    a silent no-op."""
    bars = confirmed_long_day()
    assert simulate(bars).bar_seconds == 60
    assert simulate(resample(bars, 5)).bar_seconds == 300
    assert len(simulate(resample(bars, 5)).trades) == 1
