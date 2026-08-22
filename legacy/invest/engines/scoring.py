"""Scoring: Investment Quality, Trade Setup, Confidence.

Three deliberately independent scores. They are NOT combined into a single
number, because a great company at a terrible entry point and a mediocre
company at a great entry point are different situations that a blended score
would render identical.

Every score is decomposable: the sub-components are always returned and always
displayed. A score with no visible components is an opinion wearing a number.

## The political-trade firewall

`political_trades` must never contribute to a score. That is enforced three
ways, deliberately redundantly:

1. This module never imports the PoliticalTrade model.
2. `FirewalledSession` wraps the session used during scoring and raises if any
   emitted SQL touches a firewalled table.
3. A test inspects this module's AST for references to firewalled tables.

Congressional disclosure data is research context — worth reading, never worth
scoring against, given the disclosure lag and the survivorship-biased way it
gets publicised.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date
from typing import Any

from sqlalchemy import event
from sqlalchemy.orm import Session

from invest.db.models import FIREWALLED_TABLES
from invest.engines.fundamentals import (
    AltmanResult,
    BeneishResult,
    DuPontResult,
    PiotroskiResult,
    RoicResult,
)

#: Bump when any scoring weight or component changes, so old snapshots stay
#: interpretable. Never reuse a version number with different maths.
MODEL_VERSION = "HF-QM-v1.0"


class FirewallViolation(RuntimeError):
    """Raised when scoring attempts to read a firewalled table."""


class FirewalledSession:
    """Wraps a Session and refuses queries touching firewalled tables.

    A belt-and-braces guard: the scoring code does not reference these tables,
    and this makes it impossible for a future edit to start doing so without
    the test suite screaming.
    """

    def __init__(self, session: Session) -> None:
        self._session = session
        self._pattern = re.compile(
            r"\b(" + "|".join(re.escape(t) for t in sorted(FIREWALLED_TABLES)) + r")\b",
            re.IGNORECASE,
        )
        self._listener = self._make_listener()
        event.listen(session.get_bind(), "before_cursor_execute", self._listener)

    def _make_listener(self):
        def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
            if self._pattern.search(statement or ""):
                raise FirewallViolation(
                    "The scoring engine attempted to read a firewalled table "
                    f"({', '.join(sorted(FIREWALLED_TABLES))}). Political disclosure "
                    "data is investigate-only and must never contribute to a score."
                )

        return before_cursor_execute

    @property
    def session(self) -> Session:
        return self._session

    def close(self) -> None:
        event.remove(self._session.get_bind(), "before_cursor_execute", self._listener)

    def __enter__(self) -> Session:
        return self._session

    def __exit__(self, *exc_info: object) -> None:
        self.close()


# --------------------------------------------------------------------------
# Shared score plumbing
# --------------------------------------------------------------------------


@dataclass
class SubScore:
    """One weighted contributor to a score."""

    name: str
    #: 0-100, or None when the input was unavailable.
    value: float | None
    weight: float
    detail: str
    unavailable_reason: str | None = None

    @property
    def available(self) -> bool:
        return self.value is not None

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "value": self.value,
            "weight": self.weight,
            "detail": self.detail,
            "unavailable_reason": self.unavailable_reason,
        }


@dataclass
class Score:
    """A total plus the parts it came from. Never displayed without them."""

    name: str
    components: list[SubScore] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def available_weight(self) -> float:
        return sum(c.weight for c in self.components if c.available)

    @property
    def total_weight(self) -> float:
        return sum(c.weight for c in self.components)

    @property
    def value(self) -> float | None:
        """Weighted average over AVAILABLE components only.

        Re-normalising over what is present, rather than treating missing
        inputs as zero, keeps the score on a 0-100 scale. The honesty cost is
        paid by `coverage` and by the confidence score, not by silently
        depressing this number.
        """
        available = [c for c in self.components if c.available]
        if not available or self.available_weight == 0:
            return None
        return sum(c.value * c.weight for c in available) / self.available_weight

    @property
    def coverage(self) -> float:
        """Fraction of the intended weight that had data behind it."""
        if self.total_weight == 0:
            return 0.0
        return self.available_weight / self.total_weight

    @property
    def is_reliable(self) -> bool:
        return self.coverage >= 0.6

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "value": self.value,
            "coverage": self.coverage,
            "reliable": self.is_reliable,
            "warnings": self.warnings,
            "components": [c.as_dict() for c in self.components],
        }


def _scale(value: float, low: float, high: float) -> float:
    """Map a raw value onto 0-100, clamped at both ends."""
    if high == low:
        return 50.0
    return max(0.0, min(100.0, (value - low) / (high - low) * 100.0))


# --------------------------------------------------------------------------
# 1. Investment Quality Score
# --------------------------------------------------------------------------


@dataclass
class QualityInputs:
    piotroski: PiotroskiResult | None = None
    altman: AltmanResult | None = None
    beneish: BeneishResult | None = None
    dupont: DuPontResult | None = None
    roic: RoicResult | None = None
    revenue_cagr: float | None = None
    fcf_cagr: float | None = None
    gross_margin_trend: float | None = None  # change in margin, in points
    dcf_upside: float | None = None
    implied_growth_gap: float | None = None  # historical minus implied growth


def investment_quality_score(inputs: QualityInputs) -> Score:
    """Fundamental quality + valuation + growth trend.

    Weights are a judgement call and are stated here rather than buried, so
    they can be argued with and versioned.
    """
    components: list[SubScore] = []
    warnings: list[str] = []

    # --- Fundamental quality (55%) ---
    piotroski_value = None
    piotroski_detail = "Piotroski F-Score unavailable"
    if inputs.piotroski is not None and inputs.piotroski.max_possible > 0:
        if inputs.piotroski.is_reliable:
            piotroski_value = inputs.piotroski.score / inputs.piotroski.max_possible * 100.0
            piotroski_detail = (
                f"F-Score {inputs.piotroski.score}/{inputs.piotroski.max_possible}"
            )
        else:
            warnings.append(
                f"Piotroski excluded: {inputs.piotroski.missing_count} of 9 signals "
                f"lacked data."
            )
            piotroski_detail = "F-Score computed from too few signals to be comparable"
    components.append(
        SubScore(
            "piotroski_f_score",
            piotroski_value,
            0.20,
            piotroski_detail,
            None if piotroski_value is not None else "insufficient signals",
        )
    )

    altman_value = None
    altman_detail = "Altman Z unavailable"
    if inputs.altman is not None:
        if not inputs.altman.applicable:
            altman_detail = "Altman Z not applicable to this company type"
            warnings.append(inputs.altman.note or "Altman Z not applicable.")
        elif inputs.altman.score is not None:
            # 1.8 = distress threshold, 3.0 = safe threshold (original variant).
            altman_value = _scale(inputs.altman.score, 1.0, 4.0)
            altman_detail = f"Z-Score {inputs.altman.score:.2f} ({inputs.altman.zone})"
    components.append(
        SubScore(
            "altman_z_score",
            altman_value,
            0.15,
            altman_detail,
            None if altman_value is not None else "not applicable or insufficient data",
        )
    )

    beneish_value = None
    beneish_detail = "Beneish M unavailable"
    if inputs.beneish is not None and inputs.beneish.score is not None:
        # Below -1.78 is clean; further below is better. Inverted scale.
        beneish_value = _scale(-inputs.beneish.score, 1.0, 3.5)
        beneish_detail = f"M-Score {inputs.beneish.score:.2f} ({inputs.beneish.interpretation})"
        if inputs.beneish.flags_manipulation:
            warnings.append(
                "Beneish M-Score is above the -1.78 threshold: the accounting "
                "resembles that of known manipulators. This is a prompt to read "
                "the filings, not a conclusion."
            )
    components.append(
        SubScore(
            "beneish_m_score",
            beneish_value,
            0.10,
            beneish_detail,
            None if beneish_value is not None else "insufficient data",
        )
    )

    roic_value = None
    roic_detail = "ROIC vs WACC unavailable"
    if inputs.roic is not None:
        if inputs.roic.spread is not None:
            # -5% spread scores 0, +15% scores 100.
            roic_value = _scale(inputs.roic.spread, -0.05, 0.15)
            roic_detail = (
                f"ROIC {inputs.roic.roic:.1%} vs WACC {inputs.roic.wacc:.1%} "
                f"(spread {inputs.roic.spread:+.1%}, WACC is modelled)"
            )
        elif inputs.roic.roic is not None:
            roic_value = _scale(inputs.roic.roic, 0.0, 0.20)
            roic_detail = f"ROIC {inputs.roic.roic:.1%} (no WACC: cost of capital not estimable)"
    components.append(
        SubScore(
            "roic_vs_wacc",
            roic_value,
            0.10,
            roic_detail,
            None if roic_value is not None else "insufficient data",
        )
    )

    # --- Growth (20%) ---
    revenue_value = (
        None if inputs.revenue_cagr is None else _scale(inputs.revenue_cagr, -0.05, 0.20)
    )
    components.append(
        SubScore(
            "revenue_growth",
            revenue_value,
            0.10,
            "Revenue CAGR unavailable"
            if inputs.revenue_cagr is None
            else f"Revenue CAGR {inputs.revenue_cagr:.1%}",
            None if revenue_value is not None else "insufficient history",
        )
    )

    fcf_value = None if inputs.fcf_cagr is None else _scale(inputs.fcf_cagr, -0.10, 0.20)
    components.append(
        SubScore(
            "fcf_growth",
            fcf_value,
            0.10,
            "FCF CAGR unavailable"
            if inputs.fcf_cagr is None
            else f"Free cash flow CAGR {inputs.fcf_cagr:.1%}",
            None if fcf_value is not None else "insufficient history",
        )
    )

    # --- Valuation (25%) ---
    upside_value = None if inputs.dcf_upside is None else _scale(inputs.dcf_upside, -0.30, 0.50)
    components.append(
        SubScore(
            "dcf_upside",
            upside_value,
            0.15,
            "DCF upside unavailable"
            if inputs.dcf_upside is None
            else f"DCF base case implies {inputs.dcf_upside:+.1%} vs current price",
            None if upside_value is not None else "valuation not computable",
        )
    )

    gap_value = (
        None if inputs.implied_growth_gap is None else _scale(inputs.implied_growth_gap, -0.10, 0.10)
    )
    components.append(
        SubScore(
            "implied_growth_gap",
            gap_value,
            0.10,
            "Reverse DCF unavailable"
            if inputs.implied_growth_gap is None
            else (
                f"Historical growth exceeds price-implied growth by "
                f"{inputs.implied_growth_gap:+.1%}"
            ),
            None if gap_value is not None else "reverse DCF not solvable",
        )
    )

    return Score("Investment Quality", components, warnings)


# --------------------------------------------------------------------------
# 2. Trade Setup Score
# --------------------------------------------------------------------------


@dataclass
class TradeSetupInputs:
    price: float | None = None
    sma_20: float | None = None
    sma_50: float | None = None
    sma_100: float | None = None
    sma_200: float | None = None
    rsi: float | None = None
    macd_histogram: float | None = None
    percent_b: float | None = None
    atr_pct: float | None = None  # ATR as a fraction of price
    relative_strength: float | None = None
    position_52w: float | None = None
    insider_net_buy_ratio: float | None = None  # -1 (all selling) .. +1 (all buying)
    insider_transaction_count: int = 0


def trade_setup_score(inputs: TradeSetupInputs) -> Score:
    """Price structure, momentum, and insider conviction.

    Entirely separate from quality: this measures whether NOW looks like a
    reasonable entry, not whether the business is any good.
    """
    components: list[SubScore] = []
    warnings: list[str] = []

    # --- Trend structure (30%) ---
    trend_value = None
    trend_detail = "Moving averages unavailable"
    smas = [inputs.sma_20, inputs.sma_50, inputs.sma_100, inputs.sma_200]
    if inputs.price is not None and any(s is not None for s in smas):
        above = [inputs.price > s for s in smas if s is not None]
        trend_value = sum(above) / len(above) * 100.0
        trend_detail = f"Price above {sum(above)} of {len(above)} moving averages"
    components.append(
        SubScore(
            "trend_structure",
            trend_value,
            0.20,
            trend_detail,
            None if trend_value is not None else "insufficient price history",
        )
    )

    stack_value = None
    stack_detail = "Moving-average alignment unavailable"
    if all(s is not None for s in (inputs.sma_20, inputs.sma_50, inputs.sma_200)):
        # A textbook uptrend stacks 20 > 50 > 200.
        aligned = inputs.sma_20 > inputs.sma_50 > inputs.sma_200
        inverted = inputs.sma_20 < inputs.sma_50 < inputs.sma_200
        stack_value = 100.0 if aligned else (0.0 if inverted else 50.0)
        stack_detail = (
            "20/50/200 stacked bullishly"
            if aligned
            else ("20/50/200 stacked bearishly" if inverted else "Moving averages mixed")
        )
    components.append(
        SubScore(
            "ma_alignment",
            stack_value,
            0.10,
            stack_detail,
            None if stack_value is not None else "insufficient price history",
        )
    )

    # --- Momentum (30%) ---
    rsi_value = None
    rsi_detail = "RSI unavailable"
    if inputs.rsi is not None:
        # Peak score in the 40-60 band: strong but not stretched. Both
        # extremes are penalised, so this is a tent, not a ramp.
        rsi_value = max(0.0, 100.0 - abs(inputs.rsi - 50.0) * 2.5)
        rsi_detail = f"RSI {inputs.rsi:.1f}"
        if inputs.rsi > 70:
            warnings.append(f"RSI {inputs.rsi:.1f} is overbought.")
        elif inputs.rsi < 30:
            warnings.append(f"RSI {inputs.rsi:.1f} is oversold.")
    components.append(
        SubScore(
            "rsi", rsi_value, 0.10, rsi_detail,
            None if rsi_value is not None else "insufficient price history",
        )
    )

    macd_value = None
    macd_detail = "MACD unavailable"
    if inputs.macd_histogram is not None and inputs.price:
        # Normalise by price so the reading is comparable across securities.
        normalised = inputs.macd_histogram / inputs.price
        macd_value = _scale(normalised, -0.02, 0.02)
        macd_detail = f"MACD histogram {inputs.macd_histogram:+.3f}"
    components.append(
        SubScore(
            "macd", macd_value, 0.10, macd_detail,
            None if macd_value is not None else "insufficient price history",
        )
    )

    rs_value = (
        None if inputs.relative_strength is None else _scale(inputs.relative_strength, -0.20, 0.20)
    )
    components.append(
        SubScore(
            "relative_strength",
            rs_value,
            0.10,
            "Relative strength unavailable"
            if inputs.relative_strength is None
            else f"{inputs.relative_strength:+.1%} vs benchmark over 12 months",
            None if rs_value is not None else "benchmark history unavailable",
        )
    )

    # --- Position in range (20%) ---
    position_value = None
    position_detail = "52-week position unavailable"
    if inputs.position_52w is not None:
        # Mid-to-upper range scores best: near the low often means a broken
        # trend, near the high leaves little room before resistance.
        position_value = max(0.0, 100.0 - abs(inputs.position_52w - 0.65) * 200.0)
        position_detail = f"{inputs.position_52w:.0%} of the 52-week range"
    components.append(
        SubScore(
            "position_52w",
            position_value,
            0.10,
            position_detail,
            None if position_value is not None else "insufficient price history",
        )
    )

    volatility_value = None
    volatility_detail = "ATR unavailable"
    if inputs.atr_pct is not None:
        # Lower daily range is a cleaner setup; 1% scores 100, 6% scores 0.
        volatility_value = _scale(-inputs.atr_pct, -0.06, -0.01)
        volatility_detail = f"ATR is {inputs.atr_pct:.1%} of price"
    components.append(
        SubScore(
            "volatility",
            volatility_value,
            0.10,
            volatility_detail,
            None if volatility_value is not None else "insufficient price history",
        )
    )

    # --- Insider conviction (20%) ---
    insider_value = None
    insider_detail = "No insider transactions on file"
    if inputs.insider_transaction_count > 0 and inputs.insider_net_buy_ratio is not None:
        insider_value = _scale(inputs.insider_net_buy_ratio, -1.0, 1.0)
        insider_detail = (
            f"Net insider buy ratio {inputs.insider_net_buy_ratio:+.2f} "
            f"across {inputs.insider_transaction_count} transactions"
        )
    components.append(
        SubScore(
            "insider_conviction",
            insider_value,
            0.20,
            insider_detail,
            None if insider_value is not None else "no Form 4 data available",
        )
    )

    return Score("Trade Setup", components, warnings)


# --------------------------------------------------------------------------
# 3. Confidence Score
# --------------------------------------------------------------------------


#: Inputs an institutional process would use that V1's free sources cannot
#: provide. Their absence must visibly reduce confidence rather than being
#: quietly ignored.
PREMIUM_DEPENDENT_INPUTS = (
    "analyst estimates and revisions",
    "options-implied volatility and skew",
    "real-time quotes and intraday liquidity",
    "executability / bid-ask spread modelling",
    "institutional ownership and flow data",
)


@dataclass
class ConfidenceInputs:
    price_observations: int = 0
    price_days_stale: int | None = None
    fundamental_periods: int = 0
    fundamental_days_stale: int | None = None
    conflict_count: int = 0
    critical_conflict_count: int = 0
    sources_agreeing: int = 0
    sources_total: int = 0
    quality_coverage: float = 0.0
    setup_coverage: float = 0.0
    unverified_identifiers: bool = False


def confidence_score(inputs: ConfidenceInputs) -> Score:
    """How much the other two scores should be trusted.

    Materially reduced whenever premium-dependent inputs are absent — which,
    in V1, is always. That is the honest position: this platform sees less
    than a professional desk does, and the score says so out loud instead of
    presenting free-data conclusions with paid-data confidence.
    """
    components: list[SubScore] = []
    warnings: list[str] = []

    # --- Data completeness (30%) ---
    price_value = _scale(float(inputs.price_observations), 0.0, 500.0)
    components.append(
        SubScore(
            "price_history_depth",
            price_value,
            0.10,
            f"{inputs.price_observations} usable daily observations",
        )
    )

    fundamentals_value = _scale(float(inputs.fundamental_periods), 0.0, 5.0)
    components.append(
        SubScore(
            "fundamental_history_depth",
            fundamentals_value,
            0.10,
            f"{inputs.fundamental_periods} annual periods available",
        )
    )

    coverage_value = (inputs.quality_coverage + inputs.setup_coverage) / 2 * 100.0
    components.append(
        SubScore(
            "score_input_coverage",
            coverage_value,
            0.10,
            (
                f"Quality inputs {inputs.quality_coverage:.0%} complete, "
                f"setup inputs {inputs.setup_coverage:.0%} complete"
            ),
        )
    )

    # --- Freshness (20%) ---
    price_fresh_value = None
    price_fresh_detail = "Price freshness unknown"
    if inputs.price_days_stale is not None:
        price_fresh_value = _scale(-float(inputs.price_days_stale), -30.0, 0.0)
        price_fresh_detail = f"Most recent price is {inputs.price_days_stale} days old"
        if inputs.price_days_stale > 7:
            warnings.append(f"Price data is {inputs.price_days_stale} days stale.")
    components.append(
        SubScore(
            "price_freshness",
            price_fresh_value,
            0.10,
            price_fresh_detail,
            None if price_fresh_value is not None else "no price data",
        )
    )

    fund_fresh_value = None
    fund_fresh_detail = "Fundamental freshness unknown"
    if inputs.fundamental_days_stale is not None:
        # Annual filings are inherently a few months old; 400 days is the
        # point at which a filing has genuinely been superseded.
        fund_fresh_value = _scale(-float(inputs.fundamental_days_stale), -400.0, -90.0)
        fund_fresh_detail = f"Most recent filing is {inputs.fundamental_days_stale} days old"
    components.append(
        SubScore(
            "fundamental_freshness",
            fund_fresh_value,
            0.10,
            fund_fresh_detail,
            None if fund_fresh_value is not None else "no fundamental data",
        )
    )

    # --- Source agreement and conflicts (25%) ---
    agreement_value = None
    agreement_detail = "Only one source available — no cross-check possible"
    if inputs.sources_total > 1:
        agreement_value = inputs.sources_agreeing / inputs.sources_total * 100.0
        agreement_detail = (
            f"{inputs.sources_agreeing} of {inputs.sources_total} sources agree"
        )
    else:
        # A single source is not corroboration. Score it low rather than
        # treating "nothing disagreed" as "everything agreed".
        agreement_value = 40.0
    components.append(
        SubScore("source_agreement", agreement_value, 0.15, agreement_detail)
    )

    conflict_value = _scale(-float(inputs.conflict_count), -20.0, 0.0)
    if inputs.critical_conflict_count > 0:
        conflict_value = min(conflict_value, 25.0)
        warnings.append(
            f"{inputs.critical_conflict_count} critical data conflict(s) were "
            f"quarantined and excluded from the calculations."
        )
    components.append(
        SubScore(
            "data_conflicts",
            conflict_value,
            0.10,
            f"{inputs.conflict_count} conflicts recorded "
            f"({inputs.critical_conflict_count} critical)",
        )
    )

    # --- Premium data availability (25%) ---
    # Always zero in V1. This is the point: it is a permanent, visible haircut
    # rather than a footnote.
    components.append(
        SubScore(
            "premium_data_availability",
            0.0,
            0.25,
            "PREMIUM-DATA DEPENDENT: "
            + "; ".join(PREMIUM_DEPENDENT_INPUTS)
            + " are unavailable on free sources",
        )
    )
    warnings.append(
        "Confidence is capped because V1 runs on free data only. Analyst "
        "estimates, options data, real-time quotes and executability modelling "
        "are PREMIUM-DATA DEPENDENT and absent."
    )

    if inputs.unverified_identifiers:
        warnings.append(
            "Security identifiers have not been verified against SEC EDGAR. "
            "Run `invest universe verify`."
        )

    return Score("Confidence", components, warnings)


# --------------------------------------------------------------------------
# Bundle
# --------------------------------------------------------------------------


@dataclass
class ScoreSet:
    """The three scores, kept separate on purpose."""

    quality: Score
    setup: Score
    confidence: Score
    model_version: str = MODEL_VERSION
    as_of: date | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "model_version": self.model_version,
            "as_of": self.as_of.isoformat() if self.as_of else None,
            "investment_quality": self.quality.as_dict(),
            "trade_setup": self.setup.as_dict(),
            "confidence": self.confidence.as_dict(),
        }

    @property
    def all_warnings(self) -> list[str]:
        return [*self.quality.warnings, *self.setup.warnings, *self.confidence.warnings]
