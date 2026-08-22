"""Macro regime classification and positioning. SPEC §8.

Two things this module keeps apart that are easy to conflate, and one of them
is a stated correctness rule:

**Short interest and short-sale volume are different quantities.** Short
interest is a bi-monthly snapshot of open short positions, published with an
~8-day lag. Short-sale volume is a daily count of shares sold short, which
includes market-maker hedging that closes the same day. They live in separate
tables with no join between them (SPEC §8, Phase 7 criterion 3), because a
single "short" figure computed from both would be meaningless in a way nobody
would notice.

**Short interest is expressed as a percentage of shares outstanding, never of
float.** Free float is not available at $0 (SPEC §4). The two numbers differ
materially — often by a factor of two for closely-held companies — and calling
one by the other's name overstates crowding.

The regime classifier is deterministic and its thresholds are config, not
constants, so Phase 8 can backtest them rather than trusting them.
"""

from __future__ import annotations

from bisect import bisect_left
from dataclasses import dataclass, field
from decimal import Decimal
from enum import StrEnum


class Regime(StrEnum):
    """SPEC §8's five labels. The vocabulary is fixed."""

    STRONG_RISK_ON = "strong_risk_on"
    MODERATE_RISK_ON = "moderate_risk_on"
    NEUTRAL = "neutral"
    MODERATE_RISK_OFF = "moderate_risk_off"
    STRONG_RISK_OFF = "strong_risk_off"

    @property
    def label(self) -> str:
        return (
            self.value.replace("_", " ")
            .title()
            .replace("Risk On", "Risk-On")
            .replace("Risk Off", "Risk-Off")
        )


#: Direction each factor pushes when it rises. Written down rather than
#: inferred, because "unemployment up is risk-off" and "curve steepening is
#: risk-on" are judgements, and a reader should be able to see and dispute
#: them without reading the arithmetic.
FACTOR_DIRECTION: dict[str, int] = {
    "growth": +1,
    "inflation": -1,
    "liquidity": +1,
    "rates": -1,
    "risk_appetite": +1,
    "usd_trend": -1,
    "credit_spreads": -1,
    "unemployment": -1,
}


@dataclass(frozen=True, slots=True)
class Factor:
    """One macro input, already normalized to -1..+1.

    ``series_id`` is carried so the UI tooltip can name the FRED series behind
    each row (UI_SPEC §4.7) rather than presenting a number with no lineage.
    """

    key: str
    value: float
    series_id: str
    as_of: str | None = None

    def __post_init__(self) -> None:
        if not -1.0 <= self.value <= 1.0:
            raise ValueError(
                f"Factor {self.key!r} is {self.value}, outside -1..+1. Normalize before "
                f"classification so the weighting stays interpretable."
            )


@dataclass(frozen=True, slots=True)
class RegimeResult:
    regime: Regime
    score: float
    contributing: tuple[Factor, ...] = ()
    #: Factors with no data. Named so the UI can say what was not considered,
    #: rather than presenting a regime from three inputs as though it were
    #: from eight.
    unavailable: tuple[str, ...] = ()

    @property
    def coverage(self) -> float:
        total = len(self.contributing) + len(self.unavailable)
        return len(self.contributing) / total if total else 0.0


#: Score boundaries. Config-shaped so Phase 8 can vary them.
REGIME_THRESHOLDS: tuple[tuple[float, Regime], ...] = (
    (-0.60, Regime.STRONG_RISK_OFF),
    (-0.20, Regime.MODERATE_RISK_OFF),
    (0.20, Regime.NEUTRAL),
    (0.60, Regime.MODERATE_RISK_ON),
)


def classify_regime(
    factors: list[Factor], *, expected: frozenset[str] | None = None
) -> RegimeResult:
    """Weighted mean of directional factors, mapped to a label.

    Sorted before summing so the result does not depend on input order — the
    same determinism rule the scoring engine follows.
    """
    known = expected or frozenset(FACTOR_DIRECTION)
    present = {f.key for f in factors}
    unavailable = tuple(sorted(known - present))

    usable = sorted((f for f in factors if f.key in FACTOR_DIRECTION), key=lambda f: f.key)
    if not usable:
        return RegimeResult(
            regime=Regime.NEUTRAL, score=0.0, contributing=(), unavailable=unavailable
        )

    total = sum(f.value * FACTOR_DIRECTION[f.key] for f in usable)
    score = total / len(usable)

    regime = Regime.STRONG_RISK_ON
    for boundary, label in REGIME_THRESHOLDS:
        if score < boundary:
            regime = label
            break

    return RegimeResult(
        regime=regime,
        score=round(score, 6),
        contributing=tuple(usable),
        unavailable=unavailable,
    )


def historical_percentile(series: list[float], value: float) -> float | None:
    """Where ``value`` sits in its own history, 0-100.

    Returns None below 20 observations rather than a number: a percentile from
    six data points is not a percentile, and COT extremes are exactly where an
    unreliable one would be most tempting to act on.
    """
    if len(series) < 20:
        return None
    ordered = sorted(series)
    return round(100.0 * bisect_left(ordered, value) / len(ordered), 4)


@dataclass(frozen=True, slots=True)
class CotReading:
    """One Commitments of Traders observation with its context."""

    market: str
    report_date: str
    net_position: int
    change_1w: int | None = None
    change_4w: int | None = None
    change_12w: int | None = None
    percentile: float | None = None

    @property
    def is_extreme(self) -> bool:
        """Top or bottom decile of its own history.

        Undefined — and therefore False — when the percentile could not be
        computed, so a short history cannot produce a false extreme.
        """
        return self.percentile is not None and (self.percentile >= 90.0 or self.percentile <= 10.0)


def cot_reading(market: str, *, report_date: str, net_positions: list[int]) -> CotReading:
    """Build a reading from a net-position history, newest last."""
    if not net_positions:
        raise ValueError(f"No COT history for {market!r}")

    latest = net_positions[-1]

    def change(weeks: int) -> int | None:
        return latest - net_positions[-1 - weeks] if len(net_positions) > weeks else None

    return CotReading(
        market=market,
        report_date=report_date,
        net_position=latest,
        change_1w=change(1),
        change_4w=change(4),
        change_12w=change(12),
        percentile=historical_percentile([float(v) for v in net_positions], float(latest)),
    )


# ───────────────────────────── positioning ────────────────────────────────


@dataclass(frozen=True, slots=True)
class ShortInterestReading:
    """Bi-monthly short interest.

    The field name says ``shares_outstanding`` because that is what the
    denominator is. There is no float-based field anywhere in this system and
    a schema test asserts it (API_CONTRACT).
    """

    settlement_date: str
    publication_date: str
    shares_short: int
    shares_outstanding: int | None
    average_daily_volume: int | None = None

    @property
    def pct_shares_outstanding(self) -> Decimal | None:
        if not self.shares_outstanding:
            return None
        return (
            Decimal(self.shares_short) / Decimal(self.shares_outstanding) * Decimal(100)
        ).quantize(Decimal("0.0001"))

    @property
    def days_to_cover(self) -> Decimal | None:
        """Short interest over average daily volume.

        None when volume is unknown — dividing by an assumed volume would
        invent the most quoted number on the panel.
        """
        if not self.average_daily_volume:
            return None
        return (Decimal(self.shares_short) / Decimal(self.average_daily_volume)).quantize(
            Decimal("0.01")
        )

    @property
    def publication_lag_days(self) -> int:
        from datetime import date

        return (
            date.fromisoformat(self.publication_date) - date.fromisoformat(self.settlement_date)
        ).days


@dataclass(frozen=True, slots=True)
class ShortVolumeReading:
    """Daily short-sale volume. **Not** short interest.

    Includes market-maker hedging that closes intraday, so a high ratio does
    not mean a large open short position. Kept in its own type so the two
    cannot be passed interchangeably.
    """

    trade_date: str
    short_volume: int
    total_volume: int

    @property
    def short_volume_ratio(self) -> Decimal | None:
        if not self.total_volume:
            return None
        return (Decimal(self.short_volume) / Decimal(self.total_volume) * Decimal(100)).quantize(
            Decimal("0.01")
        )


@dataclass(frozen=True, slots=True)
class PositioningSummary:
    """What the Short Interest & Price panel renders. UI_SPEC §4.7.

    Carries ``float_available: False`` explicitly rather than omitting it, so
    the UI states the limitation instead of leaving the reader to assume the
    percentage is float-based.
    """

    short_interest_pct_shares_outstanding: Decimal | None
    change_30d_pp: Decimal | None
    days_to_cover: Decimal | None
    settlement_cadence: str = "bimonthly"
    publication_lag_days: int = 8
    float_available: bool = False
    reason_codes: dict[str, str] = field(default_factory=dict)


def build_positioning(
    readings: list[ShortInterestReading],
) -> PositioningSummary:
    """Summarize short interest. Never mixes in short volume."""
    if not readings:
        return PositioningSummary(
            short_interest_pct_shares_outstanding=None,
            change_30d_pp=None,
            days_to_cover=None,
            reason_codes={"short_interest": "no_data"},
        )

    ordered = sorted(readings, key=lambda r: r.settlement_date)
    latest = ordered[-1]
    current = latest.pct_shares_outstanding

    change: Decimal | None = None
    reasons: dict[str, str] = {}
    if len(ordered) >= 2 and current is not None:
        prior = ordered[-2].pct_shares_outstanding
        if prior is not None:
            change = current - prior
        else:
            reasons["change_30d_pp"] = "prior_period_shares_outstanding_unavailable"
    elif current is None:
        reasons["short_interest"] = "shares_outstanding_unavailable"
    else:
        reasons["change_30d_pp"] = "insufficient_history"

    if latest.days_to_cover is None:
        reasons["days_to_cover"] = "average_daily_volume_unavailable"

    return PositioningSummary(
        short_interest_pct_shares_outstanding=current,
        change_30d_pp=change,
        days_to_cover=latest.days_to_cover,
        publication_lag_days=latest.publication_lag_days,
        reason_codes=reasons,
    )
