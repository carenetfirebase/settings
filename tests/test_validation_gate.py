"""The validation gate. The contract under test: nothing is silently dropped
and nothing is silently accepted.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import select

from invest.db.enums import ConflictType, DataQualityFlag, Severity
from invest.db.models import DataConflict
from invest.providers.base import FundamentalFact, PriceBar
from invest.validation import rules
from invest.validation.gate import Outcome, ValidationGate
from invest.validation.rules import RuleContext

TODAY = date(2026, 6, 15)


def bar(**overrides) -> PriceBar:
    base = {
        "symbol": "aapl.us",
        "obs_date": date(2026, 6, 12),  # a Friday
        "open": Decimal(100),
        "high": Decimal(102),
        "low": Decimal(99),
        "close": Decimal(101),
        "volume": 1_000_000,
        "currency": "USD",
        "source": "stooq",
    }
    base.update(overrides)
    return PriceBar(**base)


def flat_bar(day: date, close: str, **overrides) -> PriceBar:
    """A bar where OHLC are all the same price — avoids tripping the
    boundary's high/low consistency check when a test only cares about close.
    """
    price = Decimal(close)
    return bar(obs_date=day, open=price, high=price, low=price, close=price, **overrides)


def ctx(**overrides) -> RuleContext:
    base = {"today": TODAY}
    base.update(overrides)
    return RuleContext(**base)


# --------------------------------------------------------------------------
# Rules in isolation
# --------------------------------------------------------------------------


def test_clean_bar_produces_no_findings() -> None:
    assert rules.check_timestamp_sanity(bar(), ctx()) == []
    assert rules.check_impossible_values(bar(), ctx()) == []


def test_future_dated_observation_is_critical() -> None:
    findings = rules.check_timestamp_sanity(bar(obs_date=date(2026, 12, 1)), ctx())
    assert len(findings) == 1
    assert findings[0].is_critical
    assert findings[0].conflict_type == ConflictType.TIMESTAMP_SANITY


def test_small_future_skew_is_tolerated() -> None:
    """Timezone slop around the date line should not quarantine a good bar."""
    assert rules.check_timestamp_sanity(bar(obs_date=date(2026, 6, 16)), ctx()) == []


def test_weekend_observation_warns_but_does_not_quarantine() -> None:
    findings = rules.check_timestamp_sanity(bar(obs_date=date(2026, 6, 13)), ctx())
    assert [f.severity for f in findings] == [Severity.WARNING]


def test_zero_close_is_critical() -> None:
    findings = rules.check_impossible_values(flat_bar(date(2026, 6, 12), "0"), ctx())
    assert any(f.rule == "zero_close" and f.is_critical for f in findings)


def test_currency_mismatch_is_critical() -> None:
    findings = rules.check_currency_consistency(bar(currency="EUR"), ctx(expected_currency="USD"))
    assert len(findings) == 1
    assert findings[0].is_critical


def test_cross_source_agreement_within_tolerance_is_silent() -> None:
    context = ctx(existing_closes={date(2026, 6, 12): {"yfinance": Decimal("101.50")}})
    assert rules.check_cross_source_agreement(bar(), context) == []


def test_cross_source_disagreement_is_flagged_with_both_values() -> None:
    context = ctx(existing_closes={date(2026, 6, 12): {"yfinance": Decimal("120.00")}})
    findings = rules.check_cross_source_agreement(bar(), context)
    assert len(findings) == 1
    finding = findings[0]
    assert finding.severity == Severity.WARNING
    assert finding.source_a == "stooq"
    assert finding.value_a == Decimal(101)
    assert finding.source_b == "yfinance"
    assert finding.value_b == Decimal("120.00")
    assert finding.pct_difference is not None


def test_extreme_move_suggests_unapplied_split() -> None:
    series = [
        flat_bar(date(2026, 6, 10), "400"),
        flat_bar(date(2026, 6, 11), "100"),  # 4:1 split
    ]
    findings = rules.check_adjustment_consistency(series)
    assert len(findings) == 1
    assert findings[0].conflict_type == ConflictType.ADJUSTMENT_INCONSISTENCY


def test_split_is_flagged_never_auto_corrected() -> None:
    """Inferring a split ratio would be fabricating a corporate action."""
    series = [
        flat_bar(date(2026, 6, 10), "400"),
        flat_bar(date(2026, 6, 11), "100"),
    ]
    rules.check_adjustment_consistency(series)
    assert series[1].close == Decimal(100)  # untouched


def test_stale_series_is_flagged() -> None:
    series = [bar(obs_date=date(2026, 5, 1))]
    findings = rules.check_series_staleness(series, ctx(staleness_days=7))
    assert len(findings) == 1
    assert findings[0].conflict_type == ConflictType.STALENESS


def test_fresh_series_is_not_flagged() -> None:
    series = [bar(obs_date=date(2026, 6, 12))]
    assert rules.check_series_staleness(series, ctx(staleness_days=7)) == []


# --------------------------------------------------------------------------
# Fundamentals rules
# --------------------------------------------------------------------------


def fact(**overrides) -> FundamentalFact:
    base = {
        "cik": "0000320193",
        "metric_name": "Revenues",
        "value": Decimal(1000000),
        "unit": "USD",
        "period_start": date(2025, 1, 1),
        "period_end": date(2025, 12, 31),
        "fiscal_period": "FY",
        "filed_date": date(2026, 2, 1),
        "source": "sec_edgar",
    }
    base.update(overrides)
    return FundamentalFact(**base)


def test_filing_before_period_end_is_critical() -> None:
    """This is the look-ahead bias trap — it must never be a mere warning."""
    findings = rules.check_fact_timestamps(fact(filed_date=date(2025, 6, 1)), ctx())
    assert any(f.rule == "filed_before_period_end" and f.is_critical for f in findings)


def test_impossible_negative_revenue_is_critical() -> None:
    findings = rules.check_fact_plausibility(fact(value=Decimal(-5)), ctx())
    assert any(f.rule == "impossible_negative" and f.is_critical for f in findings)


def test_negative_net_income_is_allowed() -> None:
    """Losses are real. Only structurally-impossible negatives are rejected."""
    findings = rules.check_fact_plausibility(
        fact(metric_name="NetIncomeLoss", value=Decimal(-5000)), ctx()
    )
    assert findings == []


def test_quarter_spanning_a_year_is_flagged() -> None:
    findings = rules.check_fact_plausibility(
        fact(fiscal_period="Q4", period_start=date(2025, 1, 1), period_end=date(2025, 12, 31)),
        ctx(),
    )
    assert any(f.rule == "quarter_span_too_long" for f in findings)


def test_missing_unit_is_critical() -> None:
    findings = rules.check_fact_units(fact(unit="  "), ctx())
    assert findings and findings[0].is_critical


# --------------------------------------------------------------------------
# The gate: outcomes and persistence
# --------------------------------------------------------------------------


def test_clean_bar_is_accepted(db_session) -> None:
    gate = ValidationGate(db_session)
    result = gate.check_price_bar(bar(), ctx())
    assert result.outcome == Outcome.ACCEPTED
    assert result.data_quality_flag == DataQualityFlag.OK
    assert result.is_usable


def test_critical_finding_quarantines_rather_than_drops(db_session) -> None:
    """The row is still written — auditable, but excluded from the engines."""
    gate = ValidationGate(db_session)
    result = gate.check_price_bar(bar(obs_date=date(2027, 1, 1)), ctx())
    assert result.outcome == Outcome.QUARANTINED
    assert result.data_quality_flag == DataQualityFlag.QUARANTINED
    assert result.should_write is True
    assert result.is_usable is False


def test_warning_flags_but_keeps_usable(db_session) -> None:
    gate = ValidationGate(db_session)
    context = ctx(existing_closes={date(2026, 6, 12): {"yfinance": Decimal("120.00")}})
    result = gate.check_price_bar(bar(), context)
    assert result.outcome == Outcome.FLAGGED
    assert result.data_quality_flag == DataQualityFlag.CONFLICTED
    assert result.is_usable is True


def test_duplicate_is_skipped_not_rewritten(db_session) -> None:
    gate = ValidationGate(db_session)
    result = gate.check_price_bar(bar(), ctx(known_dates={date(2026, 6, 12)}))
    assert result.outcome == Outcome.SKIPPED
    assert result.should_write is False


def test_every_finding_lands_in_data_conflicts(db_session) -> None:
    """Nothing the gate notices is forgotten."""
    gate = ValidationGate(db_session)
    gate.check_price_bar(bar(obs_date=date(2027, 1, 1)), ctx())
    db_session.commit()

    conflicts = db_session.scalars(select(DataConflict)).all()
    assert len(conflicts) == 1
    assert conflicts[0].table_name == "price_observations"
    assert conflicts[0].conflict_type == ConflictType.TIMESTAMP_SANITY
    assert conflicts[0].severity == Severity.CRITICAL
    assert "timestamp_sanity" in conflicts[0].detail


def test_conflict_row_records_both_disagreeing_values(db_session) -> None:
    gate = ValidationGate(db_session)
    context = ctx(existing_closes={date(2026, 6, 12): {"yfinance": Decimal("120.00")}})
    gate.check_price_bar(bar(), context, security_id=None)
    db_session.commit()

    conflict = db_session.scalars(select(DataConflict)).one()
    assert conflict.source_a == "stooq"
    assert float(conflict.value_a) == 101.0
    assert conflict.source_b == "yfinance"
    assert float(conflict.value_b) == 120.0
    assert conflict.pct_difference is not None


def test_fundamental_gate_quarantines_lookahead(db_session) -> None:
    gate = ValidationGate(db_session)
    result = gate.check_fundamental_fact(fact(filed_date=date(2025, 6, 1)), ctx())
    assert result.outcome == Outcome.QUARANTINED
    db_session.commit()
    assert db_session.scalars(select(DataConflict)).all()


@pytest.mark.parametrize(
    ("outcome", "usable"),
    [
        (Outcome.ACCEPTED, True),
        (Outcome.FLAGGED, True),
        (Outcome.QUARANTINED, False),
        (Outcome.SKIPPED, False),
    ],
)
def test_usability_matrix(outcome, usable) -> None:
    from invest.validation.gate import GateResult

    assert GateResult(outcome).is_usable is usable
