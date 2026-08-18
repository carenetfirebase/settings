from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import select

from invest.db.enums import DataQualityFlag, JobStatus
from invest.db.models import Fundamental, WorkflowJob
from invest.ingest.fundamentals import ingest_fundamentals_for_security
from invest.providers.base import FundamentalFact, FundamentalsProvider, ProviderUnavailable
from invest.repository import latest_fundamental
from invest.security_master import resolve, seed_universe

TODAY = date(2026, 6, 15)


class FakeEdgar:
    source_name = "sec_edgar"

    def __init__(self, facts: list[FundamentalFact]) -> None:
        self._facts = facts

    def fetch_company_facts(self, cik: str) -> list[FundamentalFact]:
        return list(self._facts)


class FailingEdgar:
    source_name = "sec_edgar"

    def fetch_company_facts(self, cik: str):
        raise ProviderUnavailable("sec_edgar: HTTP 503")


def fact(**overrides) -> FundamentalFact:
    base = {
        "cik": "0000320193",
        "metric_name": "Revenues",
        "xbrl_tag": "Revenues",
        "taxonomy": "us-gaap",
        "value": Decimal(1000),
        "unit": "USD",
        "period_start": date(2025, 1, 1),
        "period_end": date(2025, 12, 31),
        "fiscal_year": 2025,
        "fiscal_period": "FY",
        "filed_date": date(2026, 2, 1),
        "form_type": "10-K",
        "accession_number": "acc-1",
        "source": "sec_edgar",
    }
    base.update(overrides)
    return FundamentalFact(**base)


@pytest.fixture
def aapl(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


def test_fake_satisfies_the_protocol() -> None:
    assert isinstance(FakeEdgar([]), FundamentalsProvider)


def test_facts_are_written_with_their_filed_date(db_session, aapl) -> None:
    result = ingest_fundamentals_for_security(db_session, FakeEdgar([fact()]), aapl, today=TODAY)
    db_session.commit()

    assert result.ok
    assert result.written == 1
    row = db_session.scalars(select(Fundamental)).one()
    assert row.filed_date == date(2026, 2, 1)
    assert row.entity_id == aapl.entity_id
    assert row.xbrl_tag == "Revenues"
    assert float(row.metric_value) == 1000.0


def test_rerun_is_idempotent(db_session, aapl) -> None:
    provider = FakeEdgar([fact()])
    ingest_fundamentals_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()
    second = ingest_fundamentals_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert second.written == 0
    assert second.skipped == 1
    assert len(db_session.scalars(select(Fundamental)).all()) == 1


def test_restatement_lands_as_a_second_row(db_session, aapl) -> None:
    provider = FakeEdgar(
        [
            fact(value=Decimal(1000), filed_date=date(2026, 2, 1), accession_number="orig"),
            fact(value=Decimal(950), filed_date=date(2026, 8, 1), accession_number="restated"),
        ]
    )
    result = ingest_fundamentals_for_security(db_session, provider, aapl, today=date(2026, 9, 1))
    db_session.commit()

    assert result.written == 2
    assert latest_fundamental(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 5, 1)).value == 1000.0
    assert latest_fundamental(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 9, 1)).value == 950.0


def test_lookahead_fact_is_quarantined_and_invisible(db_session, aapl) -> None:
    """filed_date before period_end would leak the future into a backtest."""
    provider = FakeEdgar([fact(filed_date=date(2025, 6, 1))])
    result = ingest_fundamentals_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert result.quarantined == 1
    row = db_session.scalars(select(Fundamental)).one()
    assert row.data_quality_flag == DataQualityFlag.QUARANTINED
    # And the repository refuses to hand it to an engine.
    assert latest_fundamental(db_session, aapl.entity_id, "Revenues", as_of=TODAY) is None


def test_impossible_negative_revenue_is_quarantined(db_session, aapl) -> None:
    provider = FakeEdgar([fact(value=Decimal(-500))])
    result = ingest_fundamentals_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()
    assert result.quarantined == 1


def test_null_value_is_stored_as_null(db_session, aapl) -> None:
    """Ground rule 2: a missing fundamental is NULL, never interpolated."""
    provider = FakeEdgar([fact(value=None)])
    ingest_fundamentals_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()
    assert db_session.scalars(select(Fundamental)).one().metric_value is None


def test_provider_failure_writes_nothing(db_session, aapl) -> None:
    result = ingest_fundamentals_for_security(db_session, FailingEdgar(), aapl, today=TODAY)
    db_session.commit()

    assert result.ok is False
    assert result.written == 0
    assert db_session.scalars(select(Fundamental)).all() == []
    assert db_session.scalars(select(WorkflowJob)).one().status == JobStatus.FAILED


def test_missing_cik_fails_loudly(db_session, aapl) -> None:
    from dataclasses import replace

    no_cik = replace(aapl, cik=None)
    result = ingest_fundamentals_for_security(db_session, FakeEdgar([fact()]), no_cik, today=TODAY)
    assert result.ok is False
    assert "no CIK" in result.error


def test_job_records_stats(db_session, aapl) -> None:
    provider = FakeEdgar([fact(), fact(accession_number="acc-2", value=Decimal(-1))])
    ingest_fundamentals_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    job = db_session.scalars(select(WorkflowJob)).one()
    assert job.status == JobStatus.SUCCEEDED
    assert job.stats_json["accepted"] == 1
    assert job.stats_json["quarantined"] == 1
