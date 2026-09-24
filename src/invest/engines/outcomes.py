"""What actually happened after a signal: the ledger's scorekeeper.

Given a trade card (entry, stop, target) and the daily bars that followed it,
this decides whether the buy-stop triggered, how the trade exited, and what it
earned in R (multiples of the planned risk), net of costs.

## Pessimistic by construction

Daily bars do not say what happened inside the day, so every ambiguity is
resolved against the trade:

* **Gaps fill at the open.** A buy-stop gapped over fills at the open (worse
  than the entry); a stop gapped through fills at the open (worse than -1R).
* **Stop before target.** When one bar touches both, the stop is assumed to
  have come first.
* **The fill bar can stop out.** On the day of entry, a low at or below the
  stop counts as a stop, even though the low may have come before the fill.
* **Costs on both sides** from the shared cost model (spread and slippage),
  expressed in R.

A result that survives these assumptions is worth more than one that needs
the benefit of the doubt.

This module is pure: no database and no clock.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import StrEnum

import pandas as pd

from invest.engines.costs import DEFAULT_COSTS, CostModel
from invest.engines.signals import TIME_STOP_DAYS, TRIGGER_WINDOW_DAYS


class OutcomeStatus(StrEnum):
    #: Trigger window still open and not yet triggered.
    PENDING = "pending"
    #: The buy-stop never triggered: no trade.
    EXPIRED = "expired"
    #: Triggered, still held at the last available bar.
    OPEN = "open"
    TARGET = "target"
    STOP = "stop"
    #: Held for the full time stop and closed at that day's close.
    TIME = "time"


FINAL_STATUSES = frozenset(
    {OutcomeStatus.EXPIRED, OutcomeStatus.TARGET, OutcomeStatus.STOP, OutcomeStatus.TIME}
)


@dataclass(frozen=True)
class Outcome:
    status: OutcomeStatus
    evaluated_through: date | None
    trigger_date: date | None = None
    entry_fill: float | None = None
    exit_date: date | None = None
    exit_fill: float | None = None
    bars_held: int | None = None
    r_gross: float | None = None
    cost_r: float | None = None
    r_net: float | None = None
    mfe_r: float | None = None
    mae_r: float | None = None
    #: Which of +1R / -1R (from the planned entry) was touched first.
    first_touch: str | None = None

    @property
    def is_final(self) -> bool:
        return self.status in FINAL_STATUSES

    def as_dict(self) -> dict:
        return {
            "status": self.status.value,
            "evaluated_through": self.evaluated_through.isoformat()
            if self.evaluated_through
            else None,
            "trigger_date": self.trigger_date.isoformat() if self.trigger_date else None,
            "entry_fill": self.entry_fill,
            "exit_date": self.exit_date.isoformat() if self.exit_date else None,
            "exit_fill": self.exit_fill,
            "bars_held": self.bars_held,
            "r_gross": self.r_gross,
            "cost_r": self.cost_r,
            "r_net": self.r_net,
            "mfe_r": self.mfe_r,
            "mae_r": self.mae_r,
            "first_touch": self.first_touch,
            "is_final": self.is_final,
        }


def _cost_in_r(entry_fill: float, exit_fill: float, risk: float, costs: CostModel) -> float:
    """Round-trip friction per share, in R. Flat per-trade commissions are
    not included: they depend on share count, and the V1 broker charges none.
    """
    per_side = (costs.half_spread_bps + costs.slippage_bps + costs.commission_bps) / 10_000.0
    return (entry_fill + exit_fill) * per_side / risk


def evaluate_outcome(
    *,
    entry: float,
    stop: float,
    target: float,
    bars_after: pd.DataFrame,
    costs: CostModel = DEFAULT_COSTS,
    trigger_window: int = TRIGGER_WINDOW_DAYS,
    time_stop: int = TIME_STOP_DAYS,
) -> Outcome:
    """Score one card against the bars strictly after its signal date.

    `bars_after` must be ascending with open/high/low/close columns. Bars
    with a missing field are skipped rather than guessed at.
    """
    if entry <= stop:
        raise ValueError("entry must be above stop for a long card")
    risk = entry - stop
    bars = bars_after.dropna(subset=["open", "high", "low", "close"])
    dates = list(bars.index)
    if not dates:
        return Outcome(OutcomeStatus.PENDING, None)

    # ---- trigger -----------------------------------------------------------
    trigger_at: int | None = None
    for i in range(min(trigger_window, len(bars))):
        if float(bars["high"].iloc[i]) >= entry:
            trigger_at = i
            break
    if trigger_at is None:
        if len(bars) >= trigger_window:
            return Outcome(OutcomeStatus.EXPIRED, dates[trigger_window - 1])
        return Outcome(OutcomeStatus.PENDING, dates[-1])

    first_open = float(bars["open"].iloc[trigger_at])
    fill = max(first_open, entry)
    one_r_up = entry + risk

    max_high = fill
    min_low = fill
    first_touch: str | None = None

    def result(status: OutcomeStatus, exit_index: int | None, exit_price: float | None) -> Outcome:
        last_index = exit_index if exit_index is not None else len(bars) - 1
        mark = exit_price if exit_price is not None else float(bars["close"].iloc[last_index])
        r_gross = (mark - fill) / risk
        cost_r = _cost_in_r(fill, mark, risk, costs)
        return Outcome(
            status=status,
            evaluated_through=dates[last_index],
            trigger_date=dates[trigger_at],
            entry_fill=round(fill, 4),
            exit_date=dates[exit_index] if exit_index is not None else None,
            exit_fill=round(exit_price, 4) if exit_price is not None else None,
            bars_held=last_index - trigger_at + 1,
            r_gross=round(r_gross, 4),
            cost_r=round(cost_r, 4),
            r_net=round(r_gross - cost_r, 4),
            mfe_r=round((max_high - fill) / risk, 4),
            mae_r=round((min_low - fill) / risk, 4),
            first_touch=first_touch,
        )

    for i in range(trigger_at, len(bars)):
        o = float(bars["open"].iloc[i])
        h = float(bars["high"].iloc[i])
        low = float(bars["low"].iloc[i])
        c = float(bars["close"].iloc[i])

        if first_touch is None:
            if low <= stop:
                first_touch = "down"
            elif h >= one_r_up:
                first_touch = "up"

        # Excursions count only prices the position was still holding through:
        # nothing beyond a gap exit at the open, nothing past the exit price.
        if i > trigger_at and (o <= stop or o >= target):
            max_high, min_low = max(max_high, o), min(min_low, o)
            return result(OutcomeStatus.STOP if o <= stop else OutcomeStatus.TARGET, i, o)
        if i == trigger_at and fill >= target:
            # Gapped over the target at the open: the bracket's limit fills at once.
            return result(OutcomeStatus.TARGET, i, fill)
        if low <= stop:
            max_high, min_low = max(max_high, h), min(min_low, stop)
            return result(OutcomeStatus.STOP, i, stop)
        if h >= target:
            max_high, min_low = max(max_high, target), min(min_low, low)
            return result(OutcomeStatus.TARGET, i, target)

        max_high, min_low = max(max_high, h), min(min_low, low)
        if i - trigger_at + 1 >= time_stop:
            return result(OutcomeStatus.TIME, i, c)

    return result(OutcomeStatus.OPEN, None, None)
