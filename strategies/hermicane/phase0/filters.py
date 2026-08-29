"""Every v1 filter, restated as a testable predicate (§3.4).

v1 asserts eight conditions and a weighted score. This module makes each one an
independent, sweepable predicate over a panel row so the ablation can ask the
only question that keeps a filter in a strategy: does applying it to the
control beat the control?

Two deliberate departures from v1's shape:

* **Bands are split into two filters.** v1 requires the impulse to sit inside
  [min, max] ATR and the pullback inside [min, max] of the impulse. Testing the
  floor and the ceiling separately says which half is doing the work, and it is
  common for one half to be carrying a band whose other half is noise.
* **No filter carries a default threshold.** The `sweep` tuple is the plausible
  range §3.4 asks to scan; the chosen value comes out of the sweep and lands in
  `calibrated_constants.json`. A default here would be the invented constant
  this whole phase exists to remove.

`SCORE_COMPONENTS_TO_DROP` records the §4.2 item 2 finding, because it is a
statement about the design rather than about the data and no amount of sample
will change it.
"""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass

from .panel import EventRow

#: Components of v1's 0-10 score that are constant at entry and therefore
#: cannot discriminate. `entryCondition` already requires `breakout` and
#: `fiveMinOK`, so both score terms are pinned at 10 on every trade that
#: happens — a fixed +0.8 that looks variable. Worse, with the 5-minute
#: confirmation switched off, `fiveScore` stays 10, so *disabling* a filter
#: raises the score. A filter that is already a hard gate must never also
#: contribute a score term.
SCORE_COMPONENTS_TO_DROP = ("breakoutScore", "fiveScore")


@dataclass(frozen=True)
class Filter:
    """One v1 condition, its claim, and the range over which to test it."""

    key: str
    label: str
    #: What v1 asserts by including this condition. Quoted in the report next
    #: to the verdict, so a deletion reads as a refuted claim rather than as a
    #: number that came out low.
    v1_claim: str
    predicate: Callable[[EventRow, float], bool]
    #: Values to scan in §3.4's threshold sweep. Empty for a boolean filter.
    sweep: tuple[float, ...] = ()
    #: Human-readable units for the swept threshold.
    units: str = ""

    @property
    def is_boolean(self) -> bool:
        return not self.sweep

    def passes(self, row: EventRow, threshold: float = 0.0) -> bool:
        try:
            return bool(self.predicate(row, threshold))
        except (TypeError, ValueError):
            return False


def _finite(value: float) -> bool:
    return not (value is None or math.isnan(value))


# --- predicates ----------------------------------------------------------
# Each returns False on missing data. That is a real design decision: an event
# whose feature could not be measured is an event the filter would not have
# been able to approve live either, and counting it as a pass would credit the
# filter with trades it could not have taken.

def _surprise(row: EventRow, threshold: float) -> bool:
    return _finite(row.surprise_z) and abs(row.surprise_z) >= threshold


def _impulse_min(row: EventRow, threshold: float) -> bool:
    return _finite(row.impulse_atr) and row.impulse_atr >= threshold


def _impulse_max(row: EventRow, threshold: float) -> bool:
    return _finite(row.impulse_atr) and row.impulse_atr <= threshold


def _pullback_min(row: EventRow, threshold: float) -> bool:
    return _finite(row.pullback_frac) and row.pullback_frac >= threshold


def _pullback_max(row: EventRow, threshold: float) -> bool:
    return _finite(row.pullback_frac) and row.pullback_frac <= threshold


def _origin_held(row: EventRow, _: float) -> bool:
    return row.origin_held


def _macro_align(row: EventRow, threshold: float) -> bool:
    return _finite(row.macro_aligned) and row.macro_aligned >= threshold


def _micro_breakout(row: EventRow, _: float) -> bool:
    return row.micro_breakout


def _five_min_confirm(row: EventRow, _: float) -> bool:
    return row.five_min_dir != 0 and row.five_min_dir == row.predicted_dir


def _impulse_agrees(row: EventRow, _: float) -> bool:
    """The 3-minute gold impulse points the way the 2Y says it should.

    Not a v1 filter as such — v1 derives direction from the surprise sign and
    never checks it against the 2Y. It is included because v2's direction comes
    from Δ2Y, and whether gold agreed within three minutes is the cheapest
    possible test of whether gold is listening at all.
    """
    return row.impulse_dir != 0 and row.impulse_dir == row.predicted_dir


def _trend_align(row: EventRow, _: float) -> bool:
    return row.trend_1h != 0 and row.trend_1h == row.predicted_dir


def _vol_max(row: EventRow, threshold: float) -> bool:
    return _finite(row.realised_vol_20d) and row.realised_vol_20d <= threshold


def beta_r2_at(row: EventRow, window: int) -> float:
    fit = row.beta(window)
    return float("nan") if fit is None else fit.r_squared


def beta_at(row: EventRow, window: int) -> float:
    fit = row.beta(window)
    return float("nan") if fit is None else fit.beta


def _beta_classic(row: EventRow, _: float) -> bool:
    """Beta negative on the 90-day window: the v1 reaction function is live."""
    value = beta_at(row, 90)
    return _finite(value) and value < 0


def _beta_r2(row: EventRow, threshold: float) -> bool:
    value = beta_r2_at(row, 90)
    return _finite(value) and value >= threshold


def _beta_gate(row: EventRow, threshold: float) -> bool:
    """The full v2 regime gate: classic sign *and* an R² above the threshold."""
    return _beta_classic(row, 0.0) and _beta_r2(row, threshold)


#: The catalogue. Sweep ranges are plausible spans, not preferences — §3.4 asks
#: for mean R plotted against threshold across a range wide enough to show
#: whether a plateau exists, and a narrow range cannot show that.
FILTERS: tuple[Filter, ...] = (
    Filter(
        "surprise_z", "Surprise magnitude",
        "A bigger surprise moves gold further and more reliably.",
        _surprise, tuple(round(0.0 + 0.25 * i, 2) for i in range(13)), "|z|",
    ),
    Filter(
        "impulse_min", "Impulse floor",
        "Below some size the release did not actually move the market.",
        _impulse_min, tuple(round(0.1 * i, 2) for i in range(16)), "ATR",
    ),
    Filter(
        "impulse_max", "Impulse ceiling (anti-chase)",
        "Above some size the move is exhausted and entering is chasing.",
        _impulse_max, tuple(round(0.5 + 0.25 * i, 2) for i in range(11)), "ATR",
    ),
    Filter(
        "pullback_min", "Pullback floor",
        "A shallow pullback offers no better price than the impulse high.",
        _pullback_min, tuple(round(0.05 * i, 2) for i in range(13)), "fraction of impulse",
    ),
    Filter(
        "pullback_max", "Pullback ceiling",
        "A deep pullback means the impulse is being rejected outright.",
        _pullback_max, tuple(round(0.2 + 0.05 * i, 2) for i in range(17)), "fraction of impulse",
    ),
    Filter(
        "origin_held", "Pre-news level held",
        "A retracement through the pre-news level invalidates the reaction.",
        _origin_held,
    ),
    Filter(
        "macro_align", "Macro confirmation",
        "DXY and the 2Y agreeing with gold confirms the read.",
        _macro_align, (0.0, 0.5, 1.0), "share of legs agreeing",
    ),
    Filter(
        "micro_breakout", "Micro-structure breakout",
        "Continuation needs a break of structure, not just a pullback.",
        _micro_breakout,
    ),
    Filter(
        "five_min_confirm", "5-minute confirmation",
        "The higher timeframe should agree before entering.",
        _five_min_confirm,
    ),
    Filter(
        "impulse_agrees", "Gold impulse agrees with Δ2Y",
        "New in v2: gold should move the way the 2Y implies within 3 minutes.",
        _impulse_agrees,
    ),
    Filter(
        "trend_align", "1H trend alignment",
        "v1's regime score: trade with the prevailing hourly trend.",
        _trend_align,
    ),
    Filter(
        "vol_max", "Realised-vol ceiling",
        "In a high-vol regime the ATR-scaled stop is too easily reached.",
        _vol_max, tuple(round(0.004 + 0.002 * i, 4) for i in range(10)), "daily sigma",
    ),
    Filter(
        "beta_classic", "Beta sign is classic",
        "v2 thesis: trade only while gold trades as a real-rates instrument.",
        _beta_classic,
    ),
    Filter(
        "beta_r2", "Beta R² floor",
        "v2 thesis: a collapsed R² means gold is driven from outside the model.",
        _beta_r2, tuple(round(0.02 * i, 2) for i in range(16)), "R²",
    ),
    Filter(
        "beta_gate", "Full beta regime gate",
        "v2 thesis: classic sign AND healthy R², as a single hard gate.",
        _beta_gate, tuple(round(0.02 * i, 2) for i in range(16)), "R²",
    ),
)

FILTERS_BY_KEY = {f.key: f for f in FILTERS}


def apply_filters(
    rows: list[EventRow],
    selections: dict[str, float],
) -> list[EventRow]:
    """Rows surviving every named filter at its given threshold.

    `selections` maps filter key to threshold; a boolean filter's value is
    ignored. An unknown key raises rather than being skipped, so a typo in a
    constants file cannot quietly widen the strategy.
    """
    survivors = rows
    for key, threshold in selections.items():
        if key not in FILTERS_BY_KEY:
            raise KeyError(f"unknown filter {key!r}; known: {sorted(FILTERS_BY_KEY)}")
        filt = FILTERS_BY_KEY[key]
        survivors = [row for row in survivors if filt.passes(row, threshold)]
    return survivors
