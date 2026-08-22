"""Market regime classification.

Deterministic rules over macro observations. No LLM, no fitted model, no
optimisation over history — just a handful of named indicators with published
thresholds, each one visible in the output.

## What this is, and what it deliberately is not

It is a **descriptive summary of current conditions**: is the curve inverted,
are credit spreads wide, is unemployment rising, is realised volatility
elevated. Each signal is a well-known indicator with a conventional threshold.

It is **not a forecast and not a trading signal.** The thresholds here are
convention, not fitted parameters, and deliberately so: a classifier tuned on
history would fit the handful of recessions in the sample and tell you mostly
about those specific episodes. Roughly a dozen US recessions have decent data
coverage — that is not enough observations to fit anything, and any classifier
claiming otherwise is overfitted.

The regime is therefore surfaced as context alongside a research report, and
carries no weight in the Investment Quality or Trade Setup scores.

## Missing data

A signal whose input is unavailable is `None` and does not vote. The overall
classification reports how many signals were available, and refuses to name a
regime when too few are.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from enum import StrEnum

# --------------------------------------------------------------------------
# Conventional thresholds. Each is a published convention, not a fitted value.
# --------------------------------------------------------------------------

#: A 10y-2y spread below zero is the classic inversion signal.
CURVE_INVERSION_THRESHOLD = 0.0

#: High-yield OAS above ~5% is historically consistent with credit stress;
#: below ~3.5% with complacency. Both are conventional reference points.
HY_SPREAD_STRESS = 5.0
HY_SPREAD_CALM = 3.5

#: VIX above 25 is elevated; below 15 is calm.
VIX_ELEVATED = 25.0
VIX_CALM = 15.0

#: The Sahm rule: unemployment's 3-month average rising 0.5pp above its
#: 12-month low has historically coincided with recession onset.
SAHM_THRESHOLD = 0.5

#: Year-over-year CPI above 4% is meaningfully above target.
INFLATION_HIGH = 4.0
INFLATION_LOW = 2.0

#: Below this many available signals, no regime is named.
MIN_SIGNALS_FOR_CLASSIFICATION = 3


class Regime(StrEnum):
    EXPANSION = "expansion"
    LATE_CYCLE = "late_cycle"
    STRESS = "stress"
    RECOVERY = "recovery"
    INSUFFICIENT_DATA = "insufficient_data"


@dataclass(frozen=True)
class RegimeSignal:
    """One named indicator, its reading, and what it implies."""

    name: str
    value: float | None
    #: -1 = risk-off / deteriorating, 0 = neutral, +1 = risk-on / improving.
    direction: int | None
    detail: str
    unavailable_reason: str | None = None

    @property
    def available(self) -> bool:
        return self.direction is not None

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "value": self.value,
            "direction": self.direction,
            "detail": self.detail,
            "unavailable_reason": self.unavailable_reason,
        }


@dataclass
class RegimeAssessment:
    as_of: date
    signals: list[RegimeSignal] = field(default_factory=list)

    @property
    def available_signals(self) -> list[RegimeSignal]:
        return [s for s in self.signals if s.available]

    @property
    def risk_score(self) -> float | None:
        """Mean signal direction, -1 to +1. None when too few signals."""
        available = self.available_signals
        if len(available) < MIN_SIGNALS_FOR_CLASSIFICATION:
            return None
        return sum(s.direction for s in available) / len(available)

    @property
    def regime(self) -> Regime:
        score = self.risk_score
        if score is None:
            return Regime.INSUFFICIENT_DATA

        stressed = [s for s in self.available_signals if s.direction < 0]
        # Curve inversion and credit stress together is the combination that
        # historically matters, so it is named explicitly rather than being
        # averaged away.
        curve = self._signal("yield_curve")
        credit = self._signal("credit_spreads")
        if (
            curve is not None
            and credit is not None
            and curve.direction == -1
            and credit.direction == -1
        ):
            return Regime.STRESS

        if score <= -0.4:
            return Regime.STRESS
        if score < 0:
            return Regime.LATE_CYCLE
        if score < 0.4:
            return Regime.RECOVERY if len(stressed) else Regime.EXPANSION
        return Regime.EXPANSION

    def _signal(self, name: str) -> RegimeSignal | None:
        return next((s for s in self.signals if s.name == name and s.available), None)

    @property
    def coverage(self) -> float:
        if not self.signals:
            return 0.0
        return len(self.available_signals) / len(self.signals)

    @property
    def is_reliable(self) -> bool:
        return len(self.available_signals) >= MIN_SIGNALS_FOR_CLASSIFICATION

    def as_dict(self) -> dict:
        return {
            "as_of": self.as_of.isoformat(),
            "regime": self.regime.value,
            "risk_score": self.risk_score,
            "coverage": self.coverage,
            "reliable": self.is_reliable,
            "signals": [s.as_dict() for s in self.signals],
            "value_type": "calculated",
            "note": (
                "Descriptive summary of current conditions using conventional "
                "thresholds. Not a forecast, not a trading signal, and carries "
                "no weight in any security score."
            ),
        }


# --------------------------------------------------------------------------
# Individual signals
# --------------------------------------------------------------------------


def yield_curve_signal(spread_10y2y: float | None) -> RegimeSignal:
    if spread_10y2y is None:
        return RegimeSignal(
            "yield_curve", None, None, "10y-2y spread unavailable", "no data"
        )
    if spread_10y2y < CURVE_INVERSION_THRESHOLD:
        direction = -1
        detail = f"Curve inverted at {spread_10y2y:+.2f}pp (10y minus 2y)"
    elif spread_10y2y < 0.5:
        direction = 0
        detail = f"Curve flat at {spread_10y2y:+.2f}pp"
    else:
        direction = 1
        detail = f"Curve positively sloped at {spread_10y2y:+.2f}pp"
    return RegimeSignal("yield_curve", spread_10y2y, direction, detail)


def credit_spread_signal(hy_oas: float | None) -> RegimeSignal:
    if hy_oas is None:
        return RegimeSignal(
            "credit_spreads", None, None, "High-yield spread unavailable", "no data"
        )
    if hy_oas > HY_SPREAD_STRESS:
        direction = -1
        detail = f"High-yield OAS wide at {hy_oas:.2f}% — credit stress"
    elif hy_oas < HY_SPREAD_CALM:
        direction = 1
        detail = f"High-yield OAS tight at {hy_oas:.2f}%"
    else:
        direction = 0
        detail = f"High-yield OAS mid-range at {hy_oas:.2f}%"
    return RegimeSignal("credit_spreads", hy_oas, direction, detail)


def volatility_signal(vix: float | None) -> RegimeSignal:
    if vix is None:
        return RegimeSignal("volatility", None, None, "VIX unavailable", "no data")
    if vix > VIX_ELEVATED:
        direction = -1
        detail = f"VIX elevated at {vix:.1f}"
    elif vix < VIX_CALM:
        direction = 1
        detail = f"VIX calm at {vix:.1f}"
    else:
        direction = 0
        detail = f"VIX moderate at {vix:.1f}"
    return RegimeSignal("volatility", vix, direction, detail)


def sahm_signal(
    unemployment_series: list[tuple[date, float]] | None,
) -> RegimeSignal:
    """The Sahm rule: 3-month average unemployment vs its trailing 12-month low.

    Needs 12 months of history; returns unavailable rather than approximating
    from a shorter window, which would change what the indicator means.
    """
    if not unemployment_series or len(unemployment_series) < 12:
        return RegimeSignal(
            "unemployment_trend",
            None,
            None,
            "Unemployment history unavailable",
            "needs 12 months of observations",
        )

    values = [value for _, value in unemployment_series]
    recent_average = sum(values[-3:]) / 3
    trailing_low = min(values[-12:])
    gap = recent_average - trailing_low

    if gap >= SAHM_THRESHOLD:
        direction = -1
        detail = (
            f"Unemployment 3m average {recent_average:.2f}% is {gap:.2f}pp above "
            f"its 12m low — Sahm rule triggered"
        )
    elif gap >= 0.2:
        direction = 0
        detail = f"Unemployment drifting up: {gap:.2f}pp above its 12m low"
    else:
        direction = 1
        detail = f"Unemployment stable at {recent_average:.2f}%"
    return RegimeSignal("unemployment_trend", gap, direction, detail)


def inflation_signal(cpi_series: list[tuple[date, float]] | None) -> RegimeSignal:
    """Year-over-year CPI change. Needs 13 monthly points for a clean YoY."""
    if not cpi_series or len(cpi_series) < 13:
        return RegimeSignal(
            "inflation",
            None,
            None,
            "CPI history unavailable",
            "needs 13 months of observations",
        )

    latest = cpi_series[-1][1]
    year_ago = cpi_series[-13][1]
    if year_ago <= 0:
        return RegimeSignal("inflation", None, None, "CPI base invalid", "bad base value")

    yoy = (latest / year_ago - 1.0) * 100.0
    if yoy > INFLATION_HIGH:
        direction = -1
        detail = f"CPI running {yoy:.1f}% year over year — above target"
    elif yoy < 0:
        direction = -1
        detail = f"CPI {yoy:.1f}% year over year — deflation"
    elif yoy < INFLATION_LOW:
        direction = 1
        detail = f"CPI subdued at {yoy:.1f}% year over year"
    else:
        direction = 0
        detail = f"CPI at {yoy:.1f}% year over year"
    return RegimeSignal("inflation", yoy, direction, detail)


def classify_regime(
    *,
    as_of: date,
    spread_10y2y: float | None = None,
    hy_oas: float | None = None,
    vix: float | None = None,
    unemployment_series: list[tuple[date, float]] | None = None,
    cpi_series: list[tuple[date, float]] | None = None,
) -> RegimeAssessment:
    """Assemble the regime picture from whatever inputs are available."""
    return RegimeAssessment(
        as_of=as_of,
        signals=[
            yield_curve_signal(spread_10y2y),
            credit_spread_signal(hy_oas),
            volatility_signal(vix),
            sahm_signal(unemployment_series),
            inflation_signal(cpi_series),
        ],
    )


def classify_from_database(session, *, as_of: date) -> RegimeAssessment:
    """Read the required series from `macro_observations` and classify.

    Every read is point-in-time: a revision published after `as_of` is
    invisible, so a historical regime call reflects what was knowable then.
    """
    from invest.ingest.macro import get_macro_series, latest_macro_value

    def latest(series_id: str) -> float | None:
        point = latest_macro_value(session, series_id, as_of=as_of)
        return point[1] if point else None

    return classify_regime(
        as_of=as_of,
        spread_10y2y=latest("T10Y2Y"),
        hy_oas=latest("BAMLH0A0HYM2"),
        vix=latest("VIXCLS"),
        unemployment_series=get_macro_series(session, "UNRATE", as_of=as_of, limit=24),
        cpi_series=get_macro_series(session, "CPIAUCSL", as_of=as_of, limit=24),
    )
