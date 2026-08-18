"""Individual validation rules.

Each rule is a small pure function returning a list of Findings. Pure because
rules are the part of the system most likely to be argued about and tuned, and
arguing is easier when a rule can be exercised in three lines of test.

Severity drives what the gate does with a record:

    CRITICAL -> quarantine (row is written flagged, never used by engines)
    WARNING  -> write, flag, and log a conflict
    INFO     -> write, note only
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta
from decimal import Decimal

from invest.db.enums import ConflictType, Severity
from invest.providers.base import FundamentalFact, PriceBar

#: A price that moves more than this in one session is not impossible, but it
#: is rare enough to deserve a human look before it feeds a momentum signal.
EXTREME_DAILY_MOVE = Decimal("0.50")

#: Cross-source price agreement tolerance (fractional).
PRICE_DISAGREEMENT_TOLERANCE = Decimal("0.01")

#: Trading-day gap beyond which a series is treated as having a hole.
MAX_GAP_TRADING_DAYS = 10

#: How far in the future a filing/observation date may sit before we call it
#: nonsense. Allows for timezone slop around the international date line.
FUTURE_DATE_GRACE = timedelta(days=2)


@dataclass(frozen=True)
class Finding:
    """One thing the gate noticed."""

    rule: str
    conflict_type: ConflictType
    severity: Severity
    detail: str
    obs_date: date | None = None
    metric_name: str | None = None
    source_a: str | None = None
    value_a: Decimal | None = None
    source_b: str | None = None
    value_b: Decimal | None = None
    pct_difference: Decimal | None = None

    @property
    def is_critical(self) -> bool:
        return self.severity == Severity.CRITICAL


@dataclass
class RuleContext:
    """Everything a rule may need that is not the record itself."""

    today: date
    known_dates: set[date] = field(default_factory=set)
    #: obs_date -> {source: close} already stored, for cross-source comparison.
    existing_closes: dict[date, dict[str, Decimal]] = field(default_factory=dict)
    staleness_days: int | None = None
    expected_currency: str | None = None


# --------------------------------------------------------------------------
# Price rules
# --------------------------------------------------------------------------


def check_timestamp_sanity(bar: PriceBar, ctx: RuleContext) -> list[Finding]:
    findings: list[Finding] = []
    if bar.obs_date > ctx.today + FUTURE_DATE_GRACE:
        findings.append(
            Finding(
                rule="timestamp_sanity",
                conflict_type=ConflictType.TIMESTAMP_SANITY,
                severity=Severity.CRITICAL,
                detail=f"observation dated {bar.obs_date} is in the future (today {ctx.today})",
                obs_date=bar.obs_date,
                source_a=bar.source,
            )
        )
    if bar.obs_date < date(1900, 1, 1):
        findings.append(
            Finding(
                rule="timestamp_sanity",
                conflict_type=ConflictType.TIMESTAMP_SANITY,
                severity=Severity.CRITICAL,
                detail=f"observation dated {bar.obs_date} predates modern records",
                obs_date=bar.obs_date,
                source_a=bar.source,
            )
        )
    if bar.obs_date.weekday() >= 5:
        findings.append(
            Finding(
                rule="weekend_observation",
                conflict_type=ConflictType.TIMESTAMP_SANITY,
                severity=Severity.WARNING,
                detail=f"{bar.obs_date} is a weekend — US equities do not trade",
                obs_date=bar.obs_date,
                source_a=bar.source,
            )
        )
    return findings


def check_impossible_values(bar: PriceBar, ctx: RuleContext) -> list[Finding]:
    """Structural impossibilities. Pydantic already rejects the worst of these
    at the provider boundary; this catches anything that entered another way
    and makes the reason explicit in `data_conflicts`.
    """
    findings: list[Finding] = []

    for name in ("open", "high", "low", "close", "adj_close"):
        value = getattr(bar, name)
        if value is not None and value < 0:
            findings.append(
                Finding(
                    rule="negative_price",
                    conflict_type=ConflictType.IMPOSSIBLE_VALUE,
                    severity=Severity.CRITICAL,
                    detail=f"{name} is negative ({value})",
                    obs_date=bar.obs_date,
                    metric_name=name,
                    source_a=bar.source,
                    value_a=value,
                )
            )

    if bar.high is not None and bar.low is not None and bar.high < bar.low:
        findings.append(
            Finding(
                rule="high_below_low",
                conflict_type=ConflictType.IMPOSSIBLE_VALUE,
                severity=Severity.CRITICAL,
                detail=f"high {bar.high} below low {bar.low}",
                obs_date=bar.obs_date,
                source_a=bar.source,
                value_a=bar.high,
                value_b=bar.low,
            )
        )

    if bar.close is not None and bar.close == 0:
        findings.append(
            Finding(
                rule="zero_close",
                conflict_type=ConflictType.IMPOSSIBLE_VALUE,
                severity=Severity.CRITICAL,
                detail="close is exactly zero — a listed security cannot settle at 0",
                obs_date=bar.obs_date,
                source_a=bar.source,
                value_a=bar.close,
            )
        )

    if bar.volume is not None and bar.volume < 0:
        findings.append(
            Finding(
                rule="negative_volume",
                conflict_type=ConflictType.IMPOSSIBLE_VALUE,
                severity=Severity.CRITICAL,
                detail=f"volume is negative ({bar.volume})",
                obs_date=bar.obs_date,
                source_a=bar.source,
            )
        )
    return findings


def check_currency_consistency(bar: PriceBar, ctx: RuleContext) -> list[Finding]:
    if ctx.expected_currency and bar.currency != ctx.expected_currency:
        return [
            Finding(
                rule="currency_mismatch",
                conflict_type=ConflictType.UNIT_MISMATCH,
                severity=Severity.CRITICAL,
                detail=(
                    f"bar currency {bar.currency} does not match security currency "
                    f"{ctx.expected_currency}"
                ),
                obs_date=bar.obs_date,
                source_a=bar.source,
            )
        ]
    return []


def check_duplicate(bar: PriceBar, ctx: RuleContext) -> list[Finding]:
    if bar.obs_date in ctx.known_dates:
        return [
            Finding(
                rule="duplicate_observation",
                conflict_type=ConflictType.DUPLICATE,
                severity=Severity.INFO,
                detail=f"{bar.source} already has {bar.obs_date} stored; skipping re-insert",
                obs_date=bar.obs_date,
                source_a=bar.source,
            )
        ]
    return []


def check_cross_source_agreement(bar: PriceBar, ctx: RuleContext) -> list[Finding]:
    """Compare against closes already stored by other sources for the same day.

    Disagreement does not mean either source is wrong — it means we do not yet
    know which is right, so confidence must fall.
    """
    if bar.close is None or bar.close == 0:
        return []
    others = ctx.existing_closes.get(bar.obs_date, {})
    findings: list[Finding] = []
    for other_source, other_close in others.items():
        if other_source == bar.source or other_close is None or other_close == 0:
            continue
        diff = abs(bar.close - other_close) / other_close
        if diff > PRICE_DISAGREEMENT_TOLERANCE:
            findings.append(
                Finding(
                    rule="cross_source_disagreement",
                    conflict_type=ConflictType.CROSS_SOURCE_DISAGREEMENT,
                    severity=Severity.WARNING,
                    detail=(
                        f"close differs from {other_source} by {diff:.2%} "
                        f"(tolerance {PRICE_DISAGREEMENT_TOLERANCE:.2%})"
                    ),
                    obs_date=bar.obs_date,
                    metric_name="close",
                    source_a=bar.source,
                    value_a=bar.close,
                    source_b=other_source,
                    value_b=other_close,
                    pct_difference=diff,
                )
            )
    return findings


def check_adjustment_consistency(bars: list[PriceBar]) -> list[Finding]:
    """A jump too large to be a price move is usually an un-applied split.

    Flagged, never auto-corrected: guessing a split ratio would be fabricating
    a corporate action.
    """
    findings: list[Finding] = []
    previous: PriceBar | None = None
    for bar in bars:
        if previous is not None and previous.close and bar.close:
            change = (bar.close - previous.close) / previous.close
            if abs(change) > EXTREME_DAILY_MOVE:
                findings.append(
                    Finding(
                        rule="extreme_move_possible_split",
                        conflict_type=ConflictType.ADJUSTMENT_INCONSISTENCY,
                        severity=Severity.WARNING,
                        detail=(
                            f"close moved {change:.1%} from {previous.obs_date} to "
                            f"{bar.obs_date} — possible unadjusted split or bad print"
                        ),
                        obs_date=bar.obs_date,
                        metric_name="close",
                        source_a=bar.source,
                        value_a=bar.close,
                        value_b=previous.close,
                        pct_difference=change,
                    )
                )
        previous = bar
    return findings


def check_series_staleness(bars: list[PriceBar], ctx: RuleContext) -> list[Finding]:
    if not bars or ctx.staleness_days is None:
        return []
    latest = max(b.obs_date for b in bars)
    age = (ctx.today - latest).days
    if age > ctx.staleness_days:
        return [
            Finding(
                rule="stale_series",
                conflict_type=ConflictType.STALENESS,
                severity=Severity.WARNING,
                detail=(
                    f"most recent observation {latest} is {age} days old "
                    f"(threshold {ctx.staleness_days})"
                ),
                obs_date=latest,
                source_a=bars[0].source,
            )
        ]
    return []


# --------------------------------------------------------------------------
# Fundamentals rules
# --------------------------------------------------------------------------


def check_fact_timestamps(fact: FundamentalFact, ctx: RuleContext) -> list[Finding]:
    findings: list[Finding] = []
    if fact.filed_date > ctx.today + FUTURE_DATE_GRACE:
        findings.append(
            Finding(
                rule="filed_date_in_future",
                conflict_type=ConflictType.TIMESTAMP_SANITY,
                severity=Severity.CRITICAL,
                detail=f"filed_date {fact.filed_date} is in the future",
                metric_name=fact.metric_name,
                source_a=fact.source,
            )
        )
    if fact.filed_date < fact.period_end:
        # Filing before the period it reports on is a data error, and it would
        # corrupt every point-in-time backtest that trusted it.
        findings.append(
            Finding(
                rule="filed_before_period_end",
                conflict_type=ConflictType.TIMESTAMP_SANITY,
                severity=Severity.CRITICAL,
                detail=(
                    f"filed_date {fact.filed_date} precedes period_end {fact.period_end} — "
                    f"would leak future information into a backtest"
                ),
                metric_name=fact.metric_name,
                source_a=fact.source,
            )
        )
    return findings


def check_fact_units(fact: FundamentalFact, ctx: RuleContext) -> list[Finding]:
    if not fact.unit or not fact.unit.strip():
        return [
            Finding(
                rule="missing_unit",
                conflict_type=ConflictType.UNIT_MISMATCH,
                severity=Severity.CRITICAL,
                detail="fact has no unit — magnitude is uninterpretable",
                metric_name=fact.metric_name,
                source_a=fact.source,
            )
        ]
    return []


#: Metrics that cannot legitimately be negative.
NON_NEGATIVE_METRICS = frozenset(
    {
        "Revenues",
        "Assets",
        "AssetsCurrent",
        "Liabilities",
        "LiabilitiesCurrent",
        "CashAndCashEquivalentsAtCarryingValue",
        "CommonStockSharesOutstanding",
        "WeightedAverageNumberOfDilutedSharesOutstanding",
        "InventoryNet",
    }
)


def check_fact_plausibility(fact: FundamentalFact, ctx: RuleContext) -> list[Finding]:
    findings: list[Finding] = []
    if fact.value is None:
        return findings

    if fact.metric_name in NON_NEGATIVE_METRICS and fact.value < 0:
        findings.append(
            Finding(
                rule="impossible_negative",
                conflict_type=ConflictType.IMPOSSIBLE_VALUE,
                severity=Severity.CRITICAL,
                detail=f"{fact.metric_name} cannot be negative (got {fact.value})",
                metric_name=fact.metric_name,
                source_a=fact.source,
                value_a=fact.value,
            )
        )

    if fact.period_start is not None:
        span = (fact.period_end - fact.period_start).days
        # A "quarterly" fact spanning a year is a duration-tagging error and
        # would silently quadruple a growth rate.
        if fact.fiscal_period in ("Q1", "Q2", "Q3", "Q4") and span > 190:
            findings.append(
                Finding(
                    rule="quarter_span_too_long",
                    conflict_type=ConflictType.UNIT_MISMATCH,
                    severity=Severity.WARNING,
                    detail=(
                        f"{fact.fiscal_period} fact spans {span} days "
                        f"({fact.period_start}..{fact.period_end}) — likely a cumulative figure"
                    ),
                    metric_name=fact.metric_name,
                    source_a=fact.source,
                )
            )
        if fact.fiscal_period == "FY" and not (300 <= span <= 400):
            findings.append(
                Finding(
                    rule="annual_span_implausible",
                    conflict_type=ConflictType.UNIT_MISMATCH,
                    severity=Severity.WARNING,
                    detail=f"FY fact spans {span} days, expected roughly 365",
                    metric_name=fact.metric_name,
                    source_a=fact.source,
                )
            )
    return findings
