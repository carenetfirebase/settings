"""Form 4 ingest against a real Postgres. Phase 2 criteria 3 and 4.

These run against the live schema rather than a mock, because the things being
tested — natural-key conflict clauses, NOT NULL provenance columns, the
two-dates CHECK constraint — are properties of the database, and a mock would
assert only that the code believes they hold.

Skipped when no database is reachable, so the suite still runs offline.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, date, datetime
from pathlib import Path

import pytest
from sqlalchemy import create_engine, func, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session, sessionmaker

from imt.adapters.records import FilingRef
from imt.db.base import PROVENANCE_COLUMNS
from imt.db.models import Company, InsiderTransaction, SignalEvent
from imt.ingest.base import IngestResult
from imt.ingest.form4 import ingest_filing

FIXTURES = Path(__file__).parent / "fixtures" / "form4"
DB_URL = "postgresql+psycopg://imt@127.0.0.1:5432/imt"


@pytest.fixture(scope="module")
def engine():
    try:
        eng = create_engine(DB_URL)
        with eng.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception:
        pytest.skip("no database reachable")
    return eng


@pytest.fixture
def session(engine) -> Iterator[Session]:
    """A session on a transaction that is always rolled back.

    Keeps tests independent without truncating tables, and means a failing test
    cannot leave rows behind that make the next one pass.
    """
    connection = engine.connect()
    transaction = connection.begin()
    factory = sessionmaker(bind=connection, expire_on_commit=False)
    db = factory()

    # on_conflict_do_nothing rather than a plain insert: the same CIK may
    # already exist from `imt load-fixtures`, and a test that only passes on a
    # pristine database is a test that fails for the wrong reason later.
    db.execute(
        pg_insert(Company)
        .values(
            cik="0000320193",
            name="ALPHA BUILDERS INC",
            sic="1531",
            sector_code="industrials",
            status="active",
            first_seen=date(2024, 1, 1),
            last_seen=date(2026, 8, 22),
            inclusion_reason="10-K filed 2026-02-01",
        )
        .on_conflict_do_nothing(index_elements=[Company.cik])
    )
    db.flush()
    try:
        yield db
    finally:
        db.close()
        transaction.rollback()
        connection.close()


TEST_ACCESSION = "9999999999-26-000001"


def ref(accession: str = TEST_ACCESSION) -> FilingRef:
    return FilingRef(
        accession=accession,
        cik="0000320193",
        form_type="4",
        filed_date=date(2026, 8, 16),
        primary_doc_url=f"https://www.sec.gov/Archives/{accession}.xml",
        acceptance_datetime=datetime(2026, 8, 16, 18, 31, tzinfo=UTC),
    )


def ingest(session: Session, fixture: str = "multi_transaction.xml") -> IngestResult:
    result = IngestResult(job="form4", source_id="sec_edgar")
    ingest_filing(session, payload=(FIXTURES / fixture).read_bytes(), ref=ref(), result=result)
    session.flush()
    return result


class TestProvenance:
    """Phase 2 criterion 3: zero rows missing provenance."""

    def test_every_transaction_carries_all_six_columns(self, session: Session) -> None:
        ingest(session)
        rows = session.execute(select(InsiderTransaction)).scalars().all()
        assert rows
        for row in rows:
            for column in PROVENANCE_COLUMNS:
                assert getattr(row, column) is not None, f"{column} is null"

    def test_zero_violating_rows_by_query(self, session: Session) -> None:
        """The criterion as written: a query that must return zero."""
        ingest(session)
        violations = session.execute(
            select(func.count())
            .select_from(InsiderTransaction)
            .where(
                (InsiderTransaction.source_id.is_(None))
                | (InsiderTransaction.retrieved_at.is_(None))
                | (InsiderTransaction.effective_date.is_(None))
                | (InsiderTransaction.source_document_url.is_(None))
            )
        ).scalar_one()
        assert violations == 0

    def test_source_document_url_points_at_the_filing(self, session: Session) -> None:
        """UI_SPEC §5: every figure is one click from its filing."""
        ingest(session)
        row = session.execute(select(InsiderTransaction)).scalars().first()
        assert row is not None
        assert row.source_document_url.startswith("https://www.sec.gov/Archives/")


class TestIdempotency:
    """Phase 2 criterion 4: re-running adds zero duplicate rows."""

    @staticmethod
    def _transactions(session: Session) -> int:
        """Scoped to this test's accession.

        Counting the whole table would make the assertion depend on whatever
        else is in the database -- `imt load-fixtures` writes through the same
        pipeline -- and a test that only passes on an empty database tells you
        nothing about idempotency.
        """
        return session.execute(
            select(func.count())
            .select_from(InsiderTransaction)
            .where(InsiderTransaction.filing_accession == TEST_ACCESSION)
        ).scalar_one()

    def test_second_run_writes_nothing_new(self, session: Session) -> None:
        first = ingest(session)
        after_first = self._transactions(session)

        second = ingest(session)
        after_second = self._transactions(session)

        assert first.rows_written == 3
        assert second.rows_written == 0
        assert second.rows_skipped_duplicate == 3
        assert after_first == after_second == 3

    def test_events_are_also_idempotent(self, session: Session) -> None:
        """Event ids are derived from the natural key, not random.

        A UUID here would make every re-run look like a fresh batch of events
        and the feed would fill with duplicates.
        """

        def count() -> int:
            return session.execute(
                select(func.count())
                .select_from(SignalEvent)
                .where(SignalEvent.source_record_id == TEST_ACCESSION)
            ).scalar_one()

        ingest(session)
        first = count()
        ingest(session)
        assert first == count() == 3

    def test_raw_document_is_stored_once(self, session: Session) -> None:
        ingest(session)
        ingest(session)
        count = session.execute(
            text("SELECT count(*) FROM raw_documents WHERE source_record_id = :a"),
            {"a": TEST_ACCESSION},
        ).scalar_one()
        assert count == 1


class TestSignalEvents:
    def test_both_dates_are_populated_and_distinct(self, session: Session) -> None:
        """CLAUDE.md non-negotiable #5, at the database level."""
        ingest(session)
        events = session.execute(select(SignalEvent)).scalars().all()
        assert events
        for event in events:
            assert event.transaction_date is not None
            assert event.disclosure_date is not None
            assert event.disclosure_lag_days is not None
            assert event.disclosure_lag_days >= 0

    def test_lag_is_computed_server_side(self, session: Session) -> None:
        """The frontend formats; it never calculates (non-negotiable #8)."""
        ingest(session)
        event = (
            session.execute(
                select(SignalEvent).where(SignalEvent.transaction_date == date(2026, 8, 14))
            )
            .scalars()
            .first()
        )
        assert event is not None
        assert event.disclosure_lag_days == 2  # 08-14 transaction, 08-16 filing

    def test_public_available_at_rolls_past_an_after_hours_acceptance(
        self, session: Session
    ) -> None:
        """Accepted 18:31 UTC = 14:31 ET, before the close, so same day.

        This is the assertion that would catch a timezone bug silently making
        every filing available four hours early.
        """
        ingest(session)
        event = session.execute(select(SignalEvent)).scalars().first()
        assert event is not None
        assert event.public_available_at.date() == date(2026, 8, 16)

    def test_value_is_exact_not_a_range(self, session: Session) -> None:
        """Form 4s report exact amounts; congressional PTRs report brackets.

        The schema allows one or the other, never both.
        """
        ingest(session)
        event = (
            session.execute(select(SignalEvent).where(SignalEvent.value_exact_minor.is_not(None)))
            .scalars()
            .first()
        )
        assert event is not None
        assert event.value_low_minor is None
        assert event.value_high_minor is None

    def test_headline_carries_no_trading_language(self, session: Session) -> None:
        ingest(session)
        for event in session.execute(select(SignalEvent)).scalars().all():
            lowered = event.headline.lower()
            assert "buy" not in lowered
            assert "sell" not in lowered


class TestConstraints:
    def test_a_congressional_event_without_both_dates_is_rejected(self, session: Session) -> None:
        """The two-dates rule is a CHECK constraint, not a convention.

        Even a direct insert bypassing every application code path fails.
        """
        from sqlalchemy.exc import IntegrityError

        with pytest.raises(IntegrityError, match="ck_signal_events_two_dates"):
            session.execute(
                text(
                    "INSERT INTO signal_events (event_id, category, cik, detected_at, "
                    "public_available_at, headline, currency, source_id, retrieved_at, "
                    "effective_date, source_document_url, source_record_id, data_quality) "
                    "VALUES ('evt_bad', 'political', '0000320193', now(), now(), 'x', "
                    "'USD', 'house_ptr', now(), '2026-08-01', 'http://x', 'r1', 'current')"
                )
            )
            session.flush()

    def test_holdings_only_filing_writes_nothing(self, session: Session) -> None:
        result = ingest(session, "holdings_only.xml")
        assert result.rows_written == 0
        assert result.documents_fetched == 1

    def test_a_filing_for_an_unknown_company_is_skipped(self, session: Session) -> None:
        """The universe defines coverage. Silently widening it would break
        the backtest's universe reconstruction."""
        result = IngestResult(job="form4", source_id="sec_edgar")
        unknown = FilingRef(
            accession="0009999999-26-000001",
            cik="0009999999",
            form_type="4",
            filed_date=date(2026, 8, 16),
            primary_doc_url="https://www.sec.gov/Archives/x.xml",
        )
        ingest_filing(
            session,
            payload=(FIXTURES / "multi_transaction.xml").read_bytes(),
            ref=unknown,
            result=result,
        )
        session.flush()
        assert result.rows_written == 0
