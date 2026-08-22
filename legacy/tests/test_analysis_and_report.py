"""End-to-end: ingest -> analyse -> snapshot -> report.

Uses synthetic price and fundamental data written directly to the database.
No figure here is presented as a real financial fact; the point is to exercise
the full pipeline and the report's handling of present vs missing data.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from sqlalchemy import select

from invest.analysis import analyze, save_snapshot
from invest.db.models import Fundamental, PoliticalTrade, PriceObservation, ResearchSnapshot
from invest.engines.scoring import MODEL_VERSION
from invest.reports.research_report import INSUFFICIENT, fmt_money, fmt_pct, fmt_score
from invest.security_master import resolve, seed_universe

AS_OF = date(2026, 6, 15)


@pytest.fixture
def aapl(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


def add_prices(session, security_id, *, days: int = 400, start_price: float = 100.0) -> None:
    """A gently rising synthetic series, weekdays only."""
    day = AS_OF - timedelta(days=days)
    price = start_price
    added = 0
    while day < AS_OF:
        if day.weekday() < 5:
            price *= 1.0008
            session.add(
                PriceObservation(
                    security_id=security_id,
                    obs_date=day,
                    open=price * 0.995,
                    high=price * 1.01,
                    low=price * 0.99,
                    close=price,
                    volume=1_000_000,
                    source="stooq",
                )
            )
            added += 1
        day += timedelta(days=1)
    session.flush()


def add_fundamentals(session, entity_id, *, years: int = 4) -> None:
    """Four years of internally-consistent synthetic annual statements."""
    base = {
        "Revenues": 1000.0,
        "GrossProfit": 400.0,
        "OperatingIncomeLoss": 200.0,
        "NetIncomeLoss": 150.0,
        "IncomeLossBeforeIncomeTaxes": 190.0,
        "IncomeTaxExpenseBenefit": 40.0,
        "InterestExpense": 10.0,
        "DepreciationAndAmortization": 50.0,
        "SellingGeneralAndAdministrativeExpense": 120.0,
        "Assets": 2000.0,
        "AssetsCurrent": 800.0,
        "Liabilities": 900.0,
        "LiabilitiesCurrent": 400.0,
        "StockholdersEquity": 1100.0,
        "CashAndCashEquivalents": 300.0,
        "InventoryNet": 150.0,
        "AccountsReceivableNetCurrent": 200.0,
        "PropertyPlantAndEquipmentNet": 600.0,
        "LongTermDebtNoncurrent": 400.0,
        "LongTermDebtCurrent": 50.0,
        "RetainedEarningsAccumulatedDeficit": 700.0,
        "NetCashProvidedByOperatingActivities": 250.0,
        "CapitalExpenditures": 80.0,
        "WeightedAverageDilutedShares": 100.0,
        "SharesOutstanding": 100.0,
    }
    for i in range(years):
        year = 2022 + i
        growth = 1.08**i
        for metric, value in base.items():
            scaled = value * (growth if metric not in ("WeightedAverageDilutedShares",
                                                       "SharesOutstanding") else 1.0)
            session.add(
                Fundamental(
                    entity_id=entity_id,
                    metric_name=metric,
                    xbrl_tag=metric,
                    taxonomy="us-gaap",
                    metric_value=scaled,
                    unit="USD" if "Shares" not in metric else "shares",
                    period_start=date(year, 1, 1),
                    period_end=date(year, 12, 31),
                    fiscal_year=year,
                    fiscal_period="FY",
                    filed_date=date(year + 1, 2, 15),
                    form_type="10-K",
                    accession_number=f"acc-{year}",
                    source="sec_edgar",
                )
            )
    session.flush()


# --------------------------------------------------------------------------
# Full pipeline
# --------------------------------------------------------------------------


def test_analysis_runs_end_to_end(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)

    assert result.scores.quality.value is not None
    assert result.scores.setup.value is not None
    assert result.scores.confidence.value is not None
    assert result.report_text


def test_all_three_scores_are_in_range(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    for score in (result.scores.quality, result.scores.setup, result.scores.confidence):
        assert 0.0 <= score.value <= 100.0


def test_analysis_with_no_data_still_produces_a_report(db_session, aapl) -> None:
    """The empty case must degrade gracefully, not crash — and must say
    INSUFFICIENT DATA rather than printing zeros.
    """
    result = analyze(db_session, "AAPL", as_of=AS_OF)
    assert result.scores.quality.value is None
    assert INSUFFICIENT in result.report_text
    assert result.report_text


def test_point_in_time_cutoff_changes_the_result(db_session, aapl) -> None:
    """An earlier as_of sees fewer filings, and the snapshot records which."""
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    early = analyze(db_session, "AAPL", as_of=date(2024, 6, 15))
    late = analyze(db_session, "AAPL", as_of=AS_OF)

    assert early.inputs_json["fundamental_periods"] < late.inputs_json["fundamental_periods"]


def test_inputs_json_records_what_was_missing(db_session, aapl) -> None:
    """Reproducibility: the snapshot says which metrics were unavailable."""
    add_prices(db_session, aapl.security_id)
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    assert "metrics_missing" in result.inputs_json
    assert "Revenues" in result.inputs_json["metrics_missing"]


def test_inputs_json_is_complete_enough_to_reproduce(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    for key in (
        "as_of",
        "price",
        "price_observations",
        "price_sources",
        "shares_outstanding",
        "fundamental_periods",
        "discount_rate",
        "base_free_cash_flow",
        "conflict_count",
    ):
        assert key in result.inputs_json


def test_quarantined_data_does_not_reach_the_analysis(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.add(
        PriceObservation(
            security_id=aapl.security_id,
            obs_date=AS_OF - timedelta(days=1),
            close=999999,
            source="stooq",
            data_quality_flag="quarantined",
        )
    )
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    assert result.inputs_json["price"] < 1000  # the absurd row was excluded


# --------------------------------------------------------------------------
# The firewall, end to end
# --------------------------------------------------------------------------


def test_political_trades_do_not_affect_the_score(db_session, aapl) -> None:
    """The spec's requirement, tested at the level that matters: adding
    disclosure data must not move any score by even a rounding error.
    """
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    before = analyze(db_session, "AAPL", as_of=AS_OF)

    for i in range(25):
        db_session.add(
            PoliticalTrade(
                politician_name=f"Representative {i}",
                chamber="house",
                security_id=aapl.security_id,
                ticker_raw="AAPL",
                transaction_type="purchase",
                transaction_date=AS_OF - timedelta(days=60),
                disclosure_date=AS_OF - timedelta(days=10),
                amount_range_low=1_000_000,
                amount_range_high=5_000_000,
                source="house_clerk",
            )
        )
    db_session.commit()

    after = analyze(db_session, "AAPL", as_of=AS_OF)

    assert after.scores.quality.value == before.scores.quality.value
    assert after.scores.setup.value == before.scores.setup.value
    assert after.scores.confidence.value == before.scores.confidence.value


def test_report_states_the_firewall(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.commit()
    result = analyze(db_session, "AAPL", as_of=AS_OF)
    assert "FIREWALLED" in result.report_text


# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------


def test_snapshot_is_written_with_components_and_inputs(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    save_snapshot(db_session, result)
    db_session.commit()

    snapshot = db_session.scalars(select(ResearchSnapshot)).one()
    assert snapshot.model_version == MODEL_VERSION
    assert snapshot.as_of_date == AS_OF
    assert snapshot.components_json["scores"]["investment_quality"]["components"]
    assert snapshot.inputs_json["as_of"] == AS_OF.isoformat()
    assert snapshot.report_text


def test_snapshot_is_immutable(db_session, aapl) -> None:
    from sqlalchemy.exc import DBAPIError

    add_prices(db_session, aapl.security_id)
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    snapshot = save_snapshot(db_session, result)
    db_session.commit()

    snapshot.investment_quality_score = 99.0
    with pytest.raises(DBAPIError, match="append-only"):
        db_session.commit()
    db_session.rollback()


def test_rerunning_creates_a_second_snapshot(db_session, aapl) -> None:
    """The history of what we thought, and when, is the point."""
    add_prices(db_session, aapl.security_id)
    db_session.commit()

    for _ in range(2):
        result = analyze(db_session, "AAPL", as_of=AS_OF)
        save_snapshot(db_session, result)
    db_session.commit()

    assert len(db_session.scalars(select(ResearchSnapshot)).all()) == 2


def test_snapshot_stores_every_score_component(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    save_snapshot(db_session, result)
    db_session.commit()

    snapshot = db_session.scalars(select(ResearchSnapshot)).one()
    for model in ("piotroski", "altman", "beneish", "dupont", "roic"):
        assert model in snapshot.components_json


# --------------------------------------------------------------------------
# Report rendering
# --------------------------------------------------------------------------


def test_report_shows_score_components_not_just_totals(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()

    text = analyze(db_session, "AAPL", as_of=AS_OF).report_text
    assert "piotroski_f_score" in text
    assert "trend_structure" in text
    assert "premium_data_availability" in text
    assert "COMPONENT" in text


def test_report_names_the_premium_data_gap(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.commit()
    text = analyze(db_session, "AAPL", as_of=AS_OF).report_text
    assert "PREMIUM-DATA DEPENDENT" in text
    assert "analyst estimates" in text
    assert "options-implied volatility" in text


def test_report_distinguishes_calculated_from_estimated(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.commit()
    text = analyze(db_session, "AAPL", as_of=AS_OF).report_text
    assert "[ESTIMATED" in text
    assert "calculated from filings" in text
    assert "observed" in text


def test_report_disclaims_llm_involvement(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.commit()
    text = analyze(db_session, "AAPL", as_of=AS_OF).report_text
    assert "Nothing in this report was generated or judged by a language model" in text


def test_report_states_the_point_in_time_cutoff(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.commit()
    text = analyze(db_session, "AAPL", as_of=AS_OF).report_text
    assert "point-in-time cutoff" in text
    assert AS_OF.isoformat() in text


def test_report_records_the_model_version(db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.commit()
    text = analyze(db_session, "AAPL", as_of=AS_OF).report_text
    assert MODEL_VERSION in text


# --------------------------------------------------------------------------
# Formatting helpers
# --------------------------------------------------------------------------


def test_missing_values_render_as_insufficient_data_not_zero() -> None:
    """The reader must be able to tell 'we looked and it was 0' from
    'we could not find out'.
    """
    assert fmt_pct(None) == INSUFFICIENT
    assert fmt_money(None) == INSUFFICIENT
    assert fmt_score(None) == INSUFFICIENT

    assert fmt_pct(0.0) == "0.0%"
    assert fmt_money(0.0) == "$0.00"
    assert fmt_score(0.0) == "0.0/100"


def test_money_formatting_hand_checked() -> None:
    assert fmt_money(1_500_000_000) == "$1.50B"
    assert fmt_money(2_400_000) == "$2.40M"
    assert fmt_money(-3_000_000_000) == "$-3.00B"


# --------------------------------------------------------------------------
# Insider conviction reaching the Trade Setup score (step 9)
# --------------------------------------------------------------------------


def test_insider_buying_lifts_the_trade_setup_score(db_session, aapl) -> None:
    """The insider_conviction component is 20% of Trade Setup, and reported
    unavailable until Form 4 data exists.
    """
    from invest.db.models import InsiderTransaction

    add_prices(db_session, aapl.security_id)
    db_session.commit()

    before = analyze(db_session, "AAPL", as_of=AS_OF)
    component = next(
        c for c in before.scores.setup.components if c.name == "insider_conviction"
    )
    assert component.value is None
    assert "no Form 4 data" in component.unavailable_reason

    for i in range(3):
        db_session.add(
            InsiderTransaction(
                entity_id=aapl.entity_id,
                security_id=aapl.security_id,
                insider_name=f"Officer {i}",
                insider_cik=f"000123456{i}",
                is_officer=True,
                transaction_date=AS_OF - timedelta(days=20),
                filed_date=AS_OF - timedelta(days=18),
                transaction_code="P",
                acquired_disposed="A",
                shares=1000,
                price_per_share=120,
                accession_number=f"acc-{i}",
                source="sec_edgar",
            )
        )
    db_session.commit()

    after = analyze(db_session, "AAPL", as_of=AS_OF)
    component = next(
        c for c in after.scores.setup.components if c.name == "insider_conviction"
    )
    assert component.value == pytest.approx(100.0)
    assert after.scores.setup.value > before.scores.setup.value
    assert after.scores.setup.coverage > before.scores.setup.coverage


def test_option_grants_do_not_register_as_conviction(db_session, aapl) -> None:
    """A scheduled equity award is not a view on the price."""
    from invest.db.models import InsiderTransaction

    add_prices(db_session, aapl.security_id)
    db_session.add(
        InsiderTransaction(
            entity_id=aapl.entity_id,
            security_id=aapl.security_id,
            insider_name="Officer A",
            transaction_date=AS_OF - timedelta(days=20),
            filed_date=AS_OF - timedelta(days=18),
            transaction_code="A",  # grant/award
            acquired_disposed="A",
            shares=50000,
            accession_number="grant-1",
            source="sec_edgar",
        )
    )
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    component = next(
        c for c in result.scores.setup.components if c.name == "insider_conviction"
    )
    assert component.value is None
    assert result.inputs_json["insider"]["total_filings"] == 1
    assert result.inputs_json["insider"]["transaction_count"] == 0


def test_insider_trade_not_yet_filed_is_invisible_to_the_score(db_session, aapl) -> None:
    """Point-in-time: the two-business-day filing lag must be respected."""
    from invest.db.models import InsiderTransaction

    add_prices(db_session, aapl.security_id)
    db_session.add(
        InsiderTransaction(
            entity_id=aapl.entity_id,
            security_id=aapl.security_id,
            insider_name="Officer A",
            transaction_date=AS_OF - timedelta(days=2),
            filed_date=AS_OF + timedelta(days=1),  # filed tomorrow
            transaction_code="P",
            acquired_disposed="A",
            shares=1000,
            price_per_share=120,
            accession_number="pending-1",
            source="sec_edgar",
        )
    )
    db_session.commit()

    result = analyze(db_session, "AAPL", as_of=AS_OF)
    assert result.inputs_json["insider"]["total_filings"] == 0
