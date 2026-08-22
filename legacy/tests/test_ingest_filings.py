"""Filings and insider ingestion, plus the point-in-time guarantee that the
insider signal rests on.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import select

from invest.db.enums import JobStatus
from invest.db.models import Filing, InsiderTransaction, WorkflowJob
from invest.ingest.filings import ingest_filings_for_security, ingest_insider_for_security
from invest.providers.base import FilingRecord, InsiderTransactionRecord, ProviderUnavailable
from invest.providers.form4 import InsiderSummary
from invest.repository import get_insider_transactions, get_recent_filings
from invest.security_master import resolve, seed_universe

TODAY = date(2026, 6, 15)


class FakeEdgar:
    source_name = "sec_edgar"

    def __init__(self, filings=None, insider=None) -> None:
        self._filings = filings or []
        self._insider = insider or []

    def fetch_filings(self, cik, forms=None):
        if forms:
            wanted = {f.upper() for f in forms}
            return [f for f in self._filings if f.form_type.upper() in wanted]
        return list(self._filings)

    def fetch_form4_documents(self, cik, limit=50):
        return list(self._insider[:limit])


class FailingEdgar:
    source_name = "sec_edgar"

    def fetch_filings(self, cik, forms=None):
        raise ProviderUnavailable("sec_edgar: HTTP 503")

    def fetch_form4_documents(self, cik, limit=50):
        raise ProviderUnavailable("sec_edgar: HTTP 503")


def filing(**overrides) -> FilingRecord:
    base = {
        "cik": "0000320193",
        "accession_number": "0000320193-26-000001",
        "form_type": "10-K",
        "filed_date": date(2026, 2, 1),
        "period_of_report": date(2025, 12, 31),
        "primary_doc_url": "https://www.sec.gov/Archives/x.htm",
        "source": "sec_edgar",
    }
    base.update(overrides)
    return FilingRecord(**base)


def insider(**overrides) -> InsiderTransactionRecord:
    base = {
        "cik": "0000320193",
        "insider_name": "DOE JANE",
        "insider_cik": "0001234567",
        "is_director": True,
        "transaction_date": date(2026, 3, 14),
        "filed_date": date(2026, 3, 16),
        "transaction_code": "P",
        "acquired_disposed": "A",
        "shares": Decimal(1000),
        "price_per_share": Decimal(150),
        "is_derivative": False,
        "accession_number": "acc-form4-1",
        "source": "sec_edgar",
    }
    base.update(overrides)
    return InsiderTransactionRecord(**base)


@pytest.fixture
def aapl(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


# --------------------------------------------------------------------------
# Filings index
# --------------------------------------------------------------------------


def test_filings_are_written(db_session, aapl) -> None:
    provider = FakeEdgar(
        filings=[filing(), filing(accession_number="acc-2", form_type="8-K")]
    )
    result = ingest_filings_for_security(db_session, provider, aapl)
    db_session.commit()

    assert result.ok
    assert result.filings_written == 2
    rows = db_session.scalars(select(Filing)).all()
    assert {r.form_type for r in rows} == {"10-K", "8-K"}


def test_filings_rerun_is_idempotent(db_session, aapl) -> None:
    provider = FakeEdgar(filings=[filing()])
    ingest_filings_for_security(db_session, provider, aapl)
    db_session.commit()
    second = ingest_filings_for_security(db_session, provider, aapl)
    db_session.commit()

    assert second.filings_written == 0
    assert second.filings_skipped == 1
    assert len(db_session.scalars(select(Filing)).all()) == 1


def test_filings_failure_writes_nothing(db_session, aapl) -> None:
    result = ingest_filings_for_security(db_session, FailingEdgar(), aapl)
    db_session.commit()
    assert result.ok is False
    assert db_session.scalars(select(Filing)).all() == []
    assert db_session.scalars(select(WorkflowJob)).one().status == JobStatus.FAILED


def test_filings_can_be_read_back_point_in_time(db_session, aapl) -> None:
    provider = FakeEdgar(
        filings=[
            filing(accession_number="old", filed_date=date(2025, 2, 1)),
            filing(accession_number="new", filed_date=date(2026, 2, 1)),
        ]
    )
    ingest_filings_for_security(db_session, provider, aapl)
    db_session.commit()

    visible = get_recent_filings(db_session, aapl.entity_id, as_of=date(2025, 6, 1))
    assert [f.accession_number for f in visible] == ["old"]


# --------------------------------------------------------------------------
# Insider transactions
# --------------------------------------------------------------------------


def test_insider_transactions_are_written(db_session, aapl) -> None:
    result = ingest_insider_for_security(
        db_session, FakeEdgar(insider=[insider()]), aapl, today=TODAY
    )
    db_session.commit()

    assert result.insider_written == 1
    row = db_session.scalars(select(InsiderTransaction)).one()
    assert row.transaction_code == "P"
    assert row.transaction_date == date(2026, 3, 14)
    assert row.filed_date == date(2026, 3, 16)
    assert row.security_id == aapl.security_id
    assert float(row.shares) == 1000.0


def test_insider_rerun_is_idempotent(db_session, aapl) -> None:
    provider = FakeEdgar(insider=[insider()])
    ingest_insider_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()
    second = ingest_insider_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert second.insider_written == 0
    assert second.insider_skipped == 1


def test_future_filed_date_is_rejected(db_session, aapl) -> None:
    result = ingest_insider_for_security(
        db_session,
        FakeEdgar(insider=[insider(filed_date=date(2027, 1, 1))]),
        aapl,
        today=TODAY,
    )
    db_session.commit()
    assert result.insider_written == 0
    assert db_session.scalars(select(InsiderTransaction)).all() == []


def test_transaction_after_its_own_filing_is_rejected(db_session, aapl) -> None:
    """Nonsense ordering — would corrupt the disclosure-lag analysis."""
    result = ingest_insider_for_security(
        db_session,
        FakeEdgar(
            insider=[insider(transaction_date=date(2026, 4, 1), filed_date=date(2026, 3, 16))]
        ),
        aapl,
        today=TODAY,
    )
    db_session.commit()
    assert result.insider_written == 0


def test_insider_failure_writes_nothing(db_session, aapl) -> None:
    result = ingest_insider_for_security(db_session, FailingEdgar(), aapl, today=TODAY)
    db_session.commit()
    assert result.ok is False
    assert db_session.scalars(select(InsiderTransaction)).all() == []


def test_missing_cik_fails_loudly(db_session, aapl) -> None:
    from dataclasses import replace

    result = ingest_insider_for_security(
        db_session, FakeEdgar(insider=[insider()]), replace(aapl, cik=None), today=TODAY
    )
    assert result.ok is False
    assert "no CIK" in result.error


# --------------------------------------------------------------------------
# Point in time — the guarantee the insider signal rests on
# --------------------------------------------------------------------------


def test_trade_is_invisible_between_transaction_and_filing(db_session, aapl) -> None:
    """An insider has two business days to file. On the 15th the trade of the
    14th is not yet public, and a point-in-time run must not see it.
    """
    ingest_insider_for_security(
        db_session, FakeEdgar(insider=[insider()]), aapl, today=TODAY
    )
    db_session.commit()

    # Transaction 2026-03-14, filed 2026-03-16.
    before_filing = get_insider_transactions(
        db_session, aapl.entity_id, as_of=date(2026, 3, 15)
    )
    after_filing = get_insider_transactions(
        db_session, aapl.entity_id, as_of=date(2026, 3, 16)
    )
    assert before_filing == []
    assert len(after_filing) == 1


def test_lookback_window_excludes_ancient_activity(db_session, aapl) -> None:
    ingest_insider_for_security(
        db_session,
        FakeEdgar(
            insider=[
                insider(
                    accession_number="old",
                    transaction_date=date(2024, 1, 10),
                    filed_date=date(2024, 1, 12),
                ),
                insider(
                    accession_number="recent",
                    transaction_date=date(2026, 6, 1),
                    filed_date=date(2026, 6, 3),
                ),
            ]
        ),
        aapl,
        today=TODAY,
    )
    db_session.commit()

    recent = get_insider_transactions(
        db_session, aapl.entity_id, as_of=TODAY, lookback_days=180
    )
    assert len(recent) == 1
    assert recent[0].accession_number == "recent"


def test_summary_over_stored_records(db_session, aapl) -> None:
    ingest_insider_for_security(
        db_session,
        FakeEdgar(
            insider=[
                insider(accession_number="a", transaction_code="P", acquired_disposed="A"),
                insider(
                    accession_number="b",
                    transaction_code="A",  # a grant: not conviction
                    acquired_disposed="A",
                ),
            ]
        ),
        aapl,
        today=TODAY,
    )
    db_session.commit()

    records = get_insider_transactions(db_session, aapl.entity_id, as_of=TODAY)
    summary = InsiderSummary(records)
    assert len(records) == 2
    assert summary.transaction_count == 1  # the grant does not count
    assert summary.net_buy_ratio == pytest.approx(1.0)
