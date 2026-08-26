"""Executable reference for the deterministic arithmetic in CYBER MCGIVER v1.0.

Pine cannot be run outside TradingView, so the parts of the specification that
are pure arithmetic are mirrored here and tested. Anything this module and the
Pine source disagree about is a bug in one of them; the tests in
``validation/tests`` are the record of which behaviours are actually pinned.

Scope is deliberately narrow. This is NOT a backtester and does not pretend to
reproduce fills, spreads or bar sequencing — only the closed-form rules:

* S30 / S38  trendline projection from P1 and P2
* S31 / S39  contact tolerance
* S33 / S41  rejection-candle body ratio and close-location measure
* S35 / S43  structural stop beyond P3
* S47        exact 1% sizing, rounded DOWN, verified after rounding
* S7         margin feasibility
* S49        maximum stop distance in ATR
* S2  / S67  session classification in America/New_York
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime
from zoneinfo import ZoneInfo

NY = ZoneInfo("America/New_York")

SESSIONS = ("Asia", "London", "LDN/NY", "NY", "Late")


def floor_to_step(value: float, step: float) -> float:
    """Round DOWN to a whole number of lot steps (S10). Never upward."""
    if step <= 0:
        return value
    return math.floor(value / step + 1e-9) * step


def trendline_at(p2_bar: int, p2_price: float, slope: float, bar: int) -> float:
    """TL_j = L2 + m (j - i2)  — S30 / S38."""
    return p2_price + slope * (bar - p2_bar)


def slope_from(p1: tuple[int, float], p2: tuple[int, float]) -> float:
    """m = (L2 - L1) / (i2 - i1). Bars are the x-axis, exactly as in Pine."""
    (i1, v1), (i2, v2) = p1, p2
    if i2 == i1:
        raise ValueError("two pivots cannot share a bar index")
    return (v2 - v1) / (i2 - i1)


def is_contact(wick: float, line: float, atr: float, tol_atr: float = 0.12) -> bool:
    """|wick - TL| <= tolerance × ATR  — S31 / S39 / S32 / S40."""
    return abs(wick - line) <= tol_atr * atr


def body_ratio(open_: float, high: float, low: float, close: float) -> float:
    """BR = |C - O| / (H - L)  — S33 / S41. A doji with H == L scores 0."""
    rng = high - low
    return 0.0 if rng <= 0 else abs(close - open_) / rng


def close_location(open_: float, high: float, low: float, close: float, long: bool) -> float:
    """CLV for longs, BCLV for shorts — S33 / S41."""
    rng = high - low
    if rng <= 0:
        return 0.0
    return (close - low) / rng if long else (high - close) / rng


def rejection_ok(
    open_: float,
    high: float,
    low: float,
    close: float,
    long: bool,
    min_body: float = 0.35,
    min_clv: float = 0.65,
) -> bool:
    """Directional candle, body ratio and close location all pass — S33 / S41."""
    directional = close > open_ if long else close < open_
    return (
        directional
        and body_ratio(open_, high, low, close) >= min_body
        and close_location(open_, high, low, close, long) >= min_clv
    )


def structural_stop(p3_wick: float, atr: float, long: bool, buffer_atr: float = 0.10) -> float:
    """Stop beyond P3, never beyond P2 — S35 / S43.

    The stop is a function of structure and ATR only. Nothing about the
    account enters this calculation; that ordering is the point of S48.
    """
    return p3_wick - buffer_atr * atr if long else p3_wick + buffer_atr * atr


def round_trip_cost_per_lot(
    spread: float = 0.30,
    slip_in: float = 0.10,
    slip_out: float = 0.10,
    commission_per_lot: float = 7.00,
    commission_pct: float = 0.0,
    price: float = 2000.0,
    contract: float = 100.0,
) -> float:
    """EstimatedTradingCosts, expressed per lot round turn — S11 / S12."""
    notional_fee = price * contract * (commission_pct / 100.0) * 2.0
    return (spread + slip_in + slip_out) * contract + commission_per_lot + notional_fee


@dataclass(frozen=True)
class Sizing:
    """The outcome of S47. ``lots == 0`` means the trade is skipped."""

    lots: float
    risk_budget: float
    risk_per_lot: float
    planned_loss: float
    reason: str


def size_position(
    equity: float,
    risk_distance: float,
    *,
    risk_pct: float = 1.00,
    cost_per_lot: float = 57.0,
    contract: float = 100.0,
    lot_step: float = 0.01,
    min_lot: float = 0.01,
    leverage: float = 50.0,
    price: float = 2000.0,
    margin_pct: float = 100.0,
    atr: float | None = None,
    max_stop_atr: float = 3.0,
    absolute_cap: float | None = None,
) -> Sizing:
    """Structure → stop → size → risk (S46, S47, S48, S49, S7).

    The risk budget is a fraction of CURRENT equity (S5, S6), the lot count is
    rounded DOWN (S10) and then re-verified against the budget, and margin can
    only ever reduce the size, never raise it (S7).
    """
    budget = equity * risk_pct / 100.0
    if absolute_cap is not None:
        budget = min(budget, absolute_cap)

    if risk_distance <= 0:
        return Sizing(0.0, budget, 0.0, 0.0, "invalid risk distance")
    if atr is not None and atr > 0 and risk_distance / atr > max_stop_atr:
        return Sizing(0.0, budget, 0.0, 0.0, "stop distance exceeds max ATR")

    risk_per_lot = risk_distance * contract + cost_per_lot
    lots = floor_to_step(budget / risk_per_lot, lot_step)
    # Rounding down can still leave the product above budget when the step is
    # coarse relative to the budget, so verify and step down again (S47).
    while lots > 0 and lots * risk_per_lot > budget:
        lots = floor_to_step(lots - lot_step, lot_step)

    reason = "ok"
    max_by_margin = floor_to_step(
        (equity * margin_pct / 100.0) * leverage / (price * contract), lot_step
    )
    if lots > max_by_margin:
        lots = max_by_margin
        reason = "reduced by margin"

    if lots < min_lot:
        return Sizing(0.0, budget, risk_per_lot, 0.0, "size below minimum lot")
    return Sizing(lots, budget, risk_per_lot, lots * risk_per_lot, reason)


def r_multiple(pnl: float, risk_distance: float, units: float) -> float:
    """Realised R against the risk frozen at entry (S50)."""
    denom = risk_distance * units
    return 0.0 if denom == 0 else pnl / denom


def _minutes(value: str) -> int:
    hh, mm = value.split(":")
    return int(hh) * 60 + int(mm)


def _in_window(minute: int, start: int, end: int) -> bool:
    """Half-open [start, end), wrapping over midnight when start > end."""
    if start <= end:
        return start <= minute < end
    return minute >= start or minute < end


def classify_session(
    moment: datetime,
    asia_start: str = "20:00",
    asia_end: str = "02:00",
    london_end: str = "08:00",
    ny_start: str = "09:30",
    ny_end: str = "16:00",
) -> str:
    """Label a bar by session (S2, S67). A label only — never an entry veto."""
    local = moment.astimezone(NY)
    minute = local.hour * 60 + local.minute
    if _in_window(minute, _minutes(asia_start), _minutes(asia_end)):
        return "Asia"
    if _in_window(minute, _minutes(asia_end), _minutes(london_end)):
        return "London"
    if _in_window(minute, _minutes(london_end), _minutes(ny_start)):
        return "LDN/NY"
    if _in_window(minute, _minutes(ny_start), _minutes(ny_end)):
        return "NY"
    return "Late"


def expectancy(r_values: list[float]) -> float:
    """E[R]. The only question version 1 is asking (S70)."""
    return sum(r_values) / len(r_values) if r_values else 0.0


def profit_factor(r_values: list[float]) -> float | None:
    """Gross win / gross loss. None when there is no loss to divide by."""
    gross_win = sum(r for r in r_values if r > 0)
    gross_loss = -sum(r for r in r_values if r < 0)
    return None if gross_loss == 0 else gross_win / gross_loss


def max_drawdown_r(r_values: list[float]) -> float:
    """Peak-to-trough of the R-denominated equity curve."""
    equity = 0.0
    peak = 0.0
    worst = 0.0
    for r in r_values:
        equity += r
        peak = max(peak, equity)
        worst = max(worst, peak - equity)
    return worst


__all__ = [
    "NY",
    "SESSIONS",
    "Sizing",
    "body_ratio",
    "classify_session",
    "close_location",
    "expectancy",
    "floor_to_step",
    "is_contact",
    "max_drawdown_r",
    "profit_factor",
    "r_multiple",
    "rejection_ok",
    "round_trip_cost_per_lot",
    "size_position",
    "slope_from",
    "structural_stop",
    "trendline_at",
]
