"""Congressional ingest. docs/PHASES.md Phase 4.

The PDF and OCR pipeline is not built — it needs Tesseract and network access,
and DATA_SOURCES budgets it as its own phase. What is built and tested here is
the manual CSV path, which the spec requires as the fallback so a stalled
parser never blocks the system, and which is the only path for the Senate in
V1.

Criteria 1 and 2 (≥500 parsed from the House ZIP, and the parse-outcome
report) are therefore **not** covered by these tests.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date
from pathlib import Path

import pytest
from sqlalchemy import create_engine, func, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session, sessionmaker

from imt.adapters.house_ptr import (
    PtrParseError,
    bracket_midpoint_minor,
    normalize_owner,
    normalize_transaction_type,
    parse_amount_bracket,
    parse_csv,
)
from imt.db.models import (
    Company,
    CongressionalTransaction,
    EntityReviewQueue,
    SignalEvent,
    TickerMapRow,
)
from imt.ingest.base import IngestResult
from imt.ingest.congress import ingest_records

FIXTURE = Path(__file__).parent / "fixtures" / "manual_ptr.csv"
DB_URL = "postgresql+psycopg://imt@127.0.0.1:5432/imt"


class TestAmountBrackets:
    """Phase 4 criterion 8 at the parsing level: brackets stay brackets."""

    @pytest.mark.parametrize(
        ("raw", "low", "high"),
        [
            ("$1,001 - $15,000", 100_100, 1_500_000),
            ("$15,001 – $50,000", 1_500_100, 5_000_000),
            ("$1,000,001 to $5,000,000", 100_000_100, 500_000_000),
            ("1001-15000", 100_100, 1_500_000),
        ],
    )
    def test_parses_a_range(self, raw: str, low: int, high: int) -> None:
        assert parse_amount_bracket(raw) == (low, high)

    def test_open_ended_top_bracket_does_not_invent_a_ceiling(self) -> None:
        """ "Over $50,000,000" has no upper bound.

        Picking one would be fabrication, so both ends sit at the stated floor
        and the row is honest about knowing only that much.
        """
        low, high = parse_amount_bracket("Over $50,000,000")
        assert low == high == 5_000_000_000

    def test_a_lone_figure_snaps_to_its_bracket(self) -> None:
        """A single number is a formatting variant, not a precise amount."""
        assert parse_amount_bracket("$5,000") == (100_100, 1_500_000)

    def test_rejects_an_inverted_range(self) -> None:
        with pytest.raises(PtrParseError, match="inverted"):
            parse_amount_bracket("$50,000 - $1,000")

    def test_rejects_empty(self) -> None:
        with pytest.raises(PtrParseError, match="empty"):
            parse_amount_bracket("")

    def test_midpoint_is_a_derived_helper_not_a_parse_output(self) -> None:
        """The midpoint exists only where a feature asks for it."""
        low, high = parse_amount_bracket("$1,001 - $15,000")
        assert bracket_midpoint_minor(low, high) == 800_050


class TestNormalization:
    @pytest.mark.parametrize(
        ("raw", "expected"),
        [
            ("purchase", "purchase"),
            ("P", "purchase"),
            ("sale", "sale"),
            ("sale (partial)", "sale"),
            ("exchange", "exchange"),
            ("", "other"),
            ("something odd", "other"),
        ],
    )
    def test_transaction_type(self, raw: str, expected: str) -> None:
        assert normalize_transaction_type(raw) == expected

    def test_unrecognised_type_is_other_not_guessed(self) -> None:
        """The donut's "Other" slice is real. Guessing would put fabricated
        direction into a chart."""
        assert normalize_transaction_type("misc distribution") == "other"

    @pytest.mark.parametrize(
        ("raw", "expected"),
        [("self", "self"), ("SP", "spouse"), ("DC", "dependent"), ("JT", "joint"), ("", "unknown")],
    )
    def test_owner(self, raw: str, expected: str) -> None:
        """SPEC §8 keeps owner type distinct: "Senator X bought" is wrong when
        the filing describes a dependent child's account."""
        assert normalize_owner(raw) == expected


class TestCsvParsing:
    def parsed(self):
        return parse_csv(FIXTURE.read_text(encoding="utf-8"))

    def test_parses_the_good_rows_and_reports_the_bad(self) -> None:
        records, errors = self.parsed()
        assert len(records) == 5
        assert len(errors) == 2

    def test_a_bad_row_does_not_cost_the_file(self) -> None:
        """One unparseable date in a 900-row export should not lose 899 rows."""
        records, errors = self.parsed()
        assert records
        assert any("unrecognised date" in e for e in errors)

    def test_disclosure_before_transaction_is_rejected(self) -> None:
        """Physically impossible — usually a swapped column.

        Letting it through would produce a negative lag, which the schema
        rejects anyway; catching it here names the actual problem.
        """
        _, errors = self.parsed()
        assert any("precedes transaction" in e for e in errors)

    def test_every_record_has_both_dates_and_a_non_negative_lag(self) -> None:
        """Phase 4 criterion 3, at the parse boundary."""
        records, _ = self.parsed()
        for record in records:
            assert record.transaction_date is not None
            assert record.disclosure_date is not None
            assert record.disclosure_lag_days >= 0

    def test_lag_is_substantial_in_the_fixture(self) -> None:
        """The lag is the point. A 44-day gap is typical, not exceptional."""
        records, _ = self.parsed()
        assert max(r.disclosure_lag_days for r in records) > 30

    def test_senate_rows_are_recognised(self) -> None:
        records, _ = self.parsed()
        assert any(r.chamber == "senate" for r in records)

    def test_headers_are_matched_by_alias(self) -> None:
        """Exports differ in header spelling; rejecting a file over that would
        push the user back to the PDF pipeline this path exists to avoid."""
        alt = (
            "representative,ticker_description,transaction,date,notification_date,amount_range\n"
            "Rep. Test,ACME (ACME) Common Stock,purchase,2026-07-01,2026-08-01,"
            '"$1,001 - $15,000"\n'
        )
        records, errors = parse_csv(alt)
        assert errors == []
        assert records[0].filer_name == "Rep. Test"


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
    connection = engine.connect()
    transaction = connection.begin()
    db = sessionmaker(bind=connection, expire_on_commit=False)()
    db.execute(
        pg_insert(Company)
        .values(
            cik="0000320193",
            name="DEMO ALPHA BUILDERS INC",
            sic="1531",
            sector_code="industrials",
            status="active",
            first_seen=date(2024, 1, 1),
            last_seen=date(2026, 8, 22),
        )
        .on_conflict_do_nothing(index_elements=[Company.cik])
    )
    db.execute(
        pg_insert(TickerMapRow)
        .values(cik="0000320193", ticker="DEMO", exchange="Nasdaq", valid_from=date(2024, 1, 1))
        .on_conflict_do_nothing(constraint="uq_ticker_map_period")
    )
    db.flush()
    try:
        yield db
    finally:
        db.close()
        transaction.rollback()
        connection.close()


class TestIngest:
    def _ingest(self, session: Session):
        records, _ = parse_csv(FIXTURE.read_text(encoding="utf-8"))
        result = IngestResult(job="test", source_id="house_ptr")
        report = ingest_records(session, records, result)
        session.flush()
        return report, result

    def test_resolution_report_is_honest(self, session: Session) -> None:
        """Phase 4 criterion 4.

        The number is reported as it is, not improved by lowering the gate.
        """
        report, _ = self._ingest(session)
        assert report["total"] == 5
        assert report["resolved"] == 4
        assert report["queued_for_review"] == 1

    def test_unresolved_rows_go_to_the_queue_not_the_bin(self, session: Session) -> None:
        """Phase 4 criterion 4: never dropped and never force-matched."""
        self._ingest(session)
        queued = session.execute(select(EntityReviewQueue)).scalars().all()
        assert len(queued) == 1
        assert "Private Partnership" in (queued[0].free_text or "")

    def test_an_unresolved_row_produces_no_signal_event(self, session: Session) -> None:
        """The gate's whole purpose.

        A wrong join manufactures convergence that does not exist, so a
        low-confidence row must not reach anything that feeds a score.
        """
        self._ingest(session)
        events = (
            session.execute(select(SignalEvent).where(SignalEvent.category == "political"))
            .scalars()
            .all()
        )
        assert len(events) == 4
        for event in events:
            assert event.entity_match_confidence is not None
            assert float(event.entity_match_confidence) >= 0.85

    def test_unresolved_transaction_is_still_recorded_without_a_cik(self, session: Session) -> None:
        """The disclosure happened; that is a fact worth keeping.

        It simply carries no company, so it cannot contribute to a score.
        """
        self._ingest(session)
        # Scoped to the fixture's own row: the table also holds rows committed
        # by `imt ingest congress`, so an absolute count would be asserting
        # about those rather than about this ingest.
        orphan = (
            session.execute(
                select(CongressionalTransaction).where(
                    CongressionalTransaction.source_record_id == "20260810-0004"
                )
            )
            .scalars()
            .all()
        )
        assert len(orphan) == 1
        assert orphan[0].cik is None

    def test_every_stored_row_has_a_non_negative_lag(self, session: Session) -> None:
        """Phase 4 criterion 3, at the database level: 100% of rows."""
        self._ingest(session)
        bad = session.execute(
            select(func.count())
            .select_from(CongressionalTransaction)
            .where(CongressionalTransaction.disclosure_lag_days < 0)
        ).scalar_one()
        assert bad == 0

    def test_lag_matches_the_two_dates(self, session: Session) -> None:
        self._ingest(session)
        for row in session.execute(select(CongressionalTransaction)).scalars().all():
            assert row.disclosure_lag_days == (row.disclosure_date - row.transaction_date).days

    def test_rows_are_marked_manually_imported(self, session: Session) -> None:
        """A manual import is not a live feed and the UI must be able to say so."""
        self._ingest(session)
        row = session.execute(select(CongressionalTransaction)).scalars().first()
        assert row is not None
        assert row.data_quality.value == "manually_imported"

    def test_ingest_is_idempotent(self, session: Session) -> None:
        self._ingest(session)
        before = session.execute(
            select(func.count()).select_from(CongressionalTransaction)
        ).scalar_one()
        self._ingest(session)
        after = session.execute(
            select(func.count()).select_from(CongressionalTransaction)
        ).scalar_one()
        assert before == after


class TestNoSingleAmountColumn:
    """Phase 4 criterion 8, asserted against the live schema."""

    def test_congressional_table_has_no_amount_column(self, engine) -> None:
        """A midpoint stored in a column called `amount` is read as a fact.

        The estimate exists only as a derived feature; the schema must make
        the alternative impossible rather than merely discouraged.
        """
        with engine.connect() as conn:
            columns = {
                row[0]
                for row in conn.execute(
                    text(
                        "SELECT column_name FROM information_schema.columns "
                        "WHERE table_name = 'congressional_transactions'"
                    )
                )
            }
        assert "value_low_minor" in columns
        assert "value_high_minor" in columns
        for forbidden in ("amount", "value", "amount_minor", "value_minor", "midpoint"):
            assert forbidden not in columns, f"{forbidden!r} would be read as a fact"
