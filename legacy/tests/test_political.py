"""Political disclosure parsing and firewalled ingestion.

The firewall itself is tested in test_scoring.py and test_analysis_and_report.py.
These tests cover parsing, the honest handling of bracket amounts, and the
guarantee that ingesting this data cannot reach a score.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import select

from invest.db.enums import FirewallStatus
from invest.db.models import PoliticalTrade
from invest.ingest.political import (
    get_disclosure_context,
    ingest_political_trades,
)
from invest.providers.base import PoliticalTradeRecord, ProviderError
from invest.providers.congress import (
    CongressProvider,
    clean_ticker,
    normalize_transaction_type,
    parse_amount_range,
    parse_disclosure_csv,
    parse_house_index,
)
from invest.security_master import resolve, seed_universe

TODAY = date(2026, 6, 15)


# --------------------------------------------------------------------------
# Amount ranges — brackets, never midpoints
# --------------------------------------------------------------------------


def test_standard_brackets_parse() -> None:
    low, high = parse_amount_range("$1,001 - $15,000")
    assert low == Decimal(1001)
    assert high == Decimal(15000)


def test_large_bracket_parses() -> None:
    low, high = parse_amount_range("$1,000,001 - $5,000,000")
    assert low == Decimal(1000001)
    assert high == Decimal(5000000)


def test_open_ended_top_bracket_has_no_upper_bound() -> None:
    """'Over $50,000,000' is genuinely unbounded, not capped at 50m."""
    low, high = parse_amount_range("Over $50,000,000")
    assert low == Decimal(50000000)
    assert high is None


def test_unrecognised_amount_is_unknown_not_guessed() -> None:
    assert parse_amount_range("some free text") == (None, None)
    assert parse_amount_range(None) == (None, None)
    assert parse_amount_range("") == (None, None)


def test_whitespace_and_dash_variants_are_tolerated() -> None:
    low, high = parse_amount_range("$15,001  –  $50,000")
    assert low == Decimal(15001)
    assert high == Decimal(50000)


def test_no_midpoint_is_ever_computed() -> None:
    """A midpoint is a number nobody reported. Both bounds are stored so the
    caller can see the width of the uncertainty.
    """
    low, high = parse_amount_range("$1,001 - $15,000")
    assert (low, high) != (Decimal(8000), Decimal(8000))
    assert high - low == Decimal(13999)


# --------------------------------------------------------------------------
# Transaction types and tickers
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("Purchase", "purchase"),
        ("purchase", "purchase"),
        ("P", "purchase"),
        ("Sale", "sale"),
        ("Sale (Partial)", "sale"),
        ("Sale (Full)", "sale"),
        ("S", "sale"),
        ("Exchange", "exchange"),
    ],
)
def test_transaction_types_normalise(raw, expected) -> None:
    assert normalize_transaction_type(raw) == expected


def test_unknown_transaction_type_is_none() -> None:
    assert normalize_transaction_type("something else") is None
    assert normalize_transaction_type(None) is None


@pytest.mark.parametrize("raw", ["AAPL", "aapl", " AAPL ", "BRK.B"])
def test_valid_tickers_are_cleaned(raw) -> None:
    assert clean_ticker(raw) == raw.strip().upper()


@pytest.mark.parametrize("raw", ["--", "N/A", "", None, "Apple Inc Common Stock", "some fund"])
def test_non_tickers_become_none(raw) -> None:
    """A bad ticker would attribute one company's disclosures to another."""
    assert clean_ticker(raw) is None


# --------------------------------------------------------------------------
# CSV parsing
# --------------------------------------------------------------------------


GOOD_CSV = """representative,ticker,asset_description,type,transaction_date,disclosure_date,amount
Rep A,AAPL,Apple Inc,Purchase,2026-01-15,2026-02-20,"$1,001 - $15,000"
Rep B,MSFT,Microsoft Corp,Sale (Partial),2026-01-20,2026-03-01,"$50,001 - $100,000"
"""


def test_csv_parses_transactions() -> None:
    records = parse_disclosure_csv(GOOD_CSV)
    assert len(records) == 2
    first = records[0]
    assert first.politician_name == "Rep A"
    assert first.ticker_raw == "AAPL"
    assert first.transaction_type == "purchase"
    assert first.transaction_date == date(2026, 1, 15)
    assert first.disclosure_date == date(2026, 2, 20)
    assert first.amount_range_low == Decimal(1001)
    assert first.amount_range_high == Decimal(15000)


def test_both_dates_are_kept_separately() -> None:
    """The lag between them is the only genuinely interesting thing here."""
    record = parse_disclosure_csv(GOOD_CSV)[0]
    assert record.disclosure_date > record.transaction_date
    assert (record.disclosure_date - record.transaction_date).days == 36


def test_column_aliases_are_resolved() -> None:
    """Different exports use different headers; the layout is not assumed."""
    alt = """senator,symbol,asset,transaction,date,notification_date,amount_range
Sen C,TSLA,Tesla Inc,Purchase,2026-02-01,2026-03-05,"$15,001 - $50,000"
"""
    records = parse_disclosure_csv(alt, source="senate_efd")
    assert len(records) == 1
    assert records[0].politician_name == "Sen C"
    assert records[0].ticker_raw == "TSLA"
    assert records[0].source == "senate_efd"


def test_rows_missing_a_date_are_skipped() -> None:
    csv_text = """representative,ticker,type,transaction_date,disclosure_date,amount
Rep A,AAPL,Purchase,2026-01-15,,"$1,001 - $15,000"
Rep B,MSFT,Purchase,2026-01-20,2026-03-01,"$1,001 - $15,000"
"""
    assert len(parse_disclosure_csv(csv_text)) == 1


def test_disclosure_before_transaction_is_rejected() -> None:
    """A negative lag is a corrupt row."""
    csv_text = """representative,ticker,type,transaction_date,disclosure_date,amount
Rep A,AAPL,Purchase,2026-03-01,2026-01-15,"$1,001 - $15,000"
"""
    assert parse_disclosure_csv(csv_text) == []


def test_unknown_layout_raises_rather_than_guessing() -> None:
    csv_text = "col_one,col_two\n1,2\n"
    with pytest.raises(ProviderError, match="Refusing to guess the layout"):
        parse_disclosure_csv(csv_text)


def test_empty_csv_is_not_an_error() -> None:
    assert parse_disclosure_csv("") == []


def test_asset_without_a_ticker_keeps_the_description() -> None:
    csv_text = """representative,ticker,asset_description,type,transaction_date,disclosure_date,amount
Rep A,--,Vanguard Total Bond Fund,Purchase,2026-01-15,2026-02-20,"$1,001 - $15,000"
"""
    record = parse_disclosure_csv(csv_text)[0]
    assert record.ticker_raw is None
    assert record.asset_description == "Vanguard Total Bond Fund"


# --------------------------------------------------------------------------
# House filing index
# --------------------------------------------------------------------------


def test_house_index_parses() -> None:
    xml = """<?xml version="1.0"?>
<FinancialDisclosure>
  <Member>
    <Prefix>Hon.</Prefix><Last>Doe</Last><First>Jane</First>
    <StateDst>CA12</StateDst><Year>2026</Year>
    <FilingType>P</FilingType><DocID>20026001</DocID>
    <FilingDate>3/15/2026</FilingDate>
  </Member>
</FinancialDisclosure>"""
    filings = parse_house_index(xml)
    assert len(filings) == 1
    assert filings[0]["name"] == "Jane Doe"
    assert filings[0]["filing_date"] == date(2026, 3, 15)
    assert filings[0]["doc_id"] == "20026001"


def test_house_index_rejects_malformed_xml() -> None:
    with pytest.raises(ProviderError, match="not well-formed"):
        parse_house_index("<FinancialDisclosure><unclosed>")


def test_provider_refuses_to_scrape_pdfs() -> None:
    """No structured transaction feed exists on the official sources, and
    guessing at PDF tables would put fabricated numbers in the database.
    """
    assert CongressProvider().fetch_disclosures() == []


# --------------------------------------------------------------------------
# Ingestion — firewalled
# --------------------------------------------------------------------------


def record(**overrides) -> PoliticalTradeRecord:
    base = {
        "politician_name": "Rep A",
        "chamber": "house",
        "ticker_raw": "AAPL",
        "asset_description": "Apple Inc",
        "transaction_type": "purchase",
        "transaction_date": date(2026, 1, 15),
        "disclosure_date": date(2026, 2, 20),
        "amount_range_low": Decimal(1001),
        "amount_range_high": Decimal(15000),
        "source": "house_clerk",
    }
    base.update(overrides)
    return PoliticalTradeRecord(**base)


@pytest.fixture
def universe(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


def test_trades_are_written_firewalled(db_session, universe) -> None:
    result = ingest_political_trades(db_session, [record()], today=TODAY)
    db_session.commit()

    assert result.written == 1
    row = db_session.scalars(select(PoliticalTrade)).one()
    assert row.firewall_status == FirewallStatus.INVESTIGATE_ONLY
    assert row.security_id == universe.security_id
    assert row.transaction_date == date(2026, 1, 15)
    assert row.disclosure_date == date(2026, 2, 20)


def test_every_row_is_firewalled_regardless_of_input(db_session, universe) -> None:
    """There is no code path that writes any other firewall status."""
    ingest_political_trades(
        db_session,
        [record(), record(politician_name="Rep B"), record(politician_name="Rep C")],
        today=TODAY,
    )
    db_session.commit()
    rows = db_session.scalars(select(PoliticalTrade)).all()
    assert len(rows) == 3
    assert {r.firewall_status for r in rows} == {FirewallStatus.INVESTIGATE_ONLY}


def test_rerun_is_idempotent(db_session, universe) -> None:
    ingest_political_trades(db_session, [record()], today=TODAY)
    db_session.commit()
    second = ingest_political_trades(db_session, [record()], today=TODAY)
    db_session.commit()

    assert second.written == 0
    assert second.skipped == 1
    assert len(db_session.scalars(select(PoliticalTrade)).all()) == 1


def test_unknown_ticker_is_stored_unresolved(db_session, universe) -> None:
    """Out-of-universe disclosures are kept with a NULL security_id rather
    than dropped or fuzzy-matched.
    """
    result = ingest_political_trades(
        db_session, [record(ticker_raw="ZZZZ")], today=TODAY
    )
    db_session.commit()

    assert result.written == 1
    assert result.out_of_universe == 1
    assert db_session.scalars(select(PoliticalTrade)).one().security_id is None


def test_universe_only_mode_filters(db_session, universe) -> None:
    result = ingest_political_trades(
        db_session,
        [record(), record(politician_name="Rep B", ticker_raw="ZZZZ")],
        today=TODAY,
        universe_only=True,
    )
    db_session.commit()
    assert result.written == 1
    assert result.skipped == 1


def test_asset_with_no_ticker_is_counted_as_unresolved(db_session, universe) -> None:
    result = ingest_political_trades(
        db_session,
        [record(ticker_raw=None, asset_description="Some Municipal Bond")],
        today=TODAY,
    )
    db_session.commit()
    assert result.unresolved_tickers == 1
    assert result.unresolved_examples == ["Some Municipal Bond"]


def test_future_disclosure_is_skipped(db_session, universe) -> None:
    result = ingest_political_trades(
        db_session,
        [record(transaction_date=date(2027, 1, 1), disclosure_date=date(2027, 2, 1))],
        today=TODAY,
    )
    db_session.commit()
    assert result.written == 0


# --------------------------------------------------------------------------
# Research context
# --------------------------------------------------------------------------


def test_disclosure_lag_is_the_headline_number(db_session, universe) -> None:
    """Usually the most informative figure here, and the argument against
    using this data for anything timely.
    """
    ingest_political_trades(
        db_session,
        [
            record(transaction_date=date(2026, 1, 1), disclosure_date=date(2026, 2, 1)),
            record(
                politician_name="Rep B",
                transaction_date=date(2026, 1, 1),
                disclosure_date=date(2026, 3, 2),
            ),
        ],
        today=TODAY,
    )
    db_session.commit()

    context = get_disclosure_context(db_session, universe.security_id, as_of=TODAY)
    assert context.count == 2
    # Lags of 31 and 60 days -> median 45.5
    assert context.median_disclosure_lag_days == pytest.approx(45.5)


def test_context_respects_the_disclosure_date_cutoff(db_session, universe) -> None:
    ingest_political_trades(db_session, [record()], today=TODAY)
    db_session.commit()

    before = get_disclosure_context(db_session, universe.security_id, as_of=date(2026, 2, 1))
    after = get_disclosure_context(db_session, universe.security_id, as_of=date(2026, 3, 1))
    assert before.count == 0
    assert after.count == 1


def test_context_labels_itself_as_non_scoring(db_session, universe) -> None:
    ingest_political_trades(db_session, [record()], today=TODAY)
    db_session.commit()
    payload = get_disclosure_context(db_session, universe.security_id, as_of=TODAY).as_dict()
    assert payload["firewall_status"] == "investigate_only"
    assert "Contributes nothing to any score" in payload["note"]


def test_context_helper_is_not_importable_from_the_repository() -> None:
    """Engines import from `repository`; keeping this out of that module means
    no engine can reach political data by accident.
    """
    import invest.repository as repo

    assert not hasattr(repo, "get_disclosure_context")
    assert "political" not in repo.__file__.lower()


def test_ingesting_disclosures_cannot_move_a_score(db_session, universe) -> None:
    """The end-to-end firewall guarantee, restated at the ingestion boundary."""
    from invest.analysis import analyze

    before = analyze(db_session, "AAPL", as_of=TODAY)
    ingest_political_trades(
        db_session,
        [record(politician_name=f"Rep {i}") for i in range(30)],
        today=TODAY,
    )
    db_session.commit()
    after = analyze(db_session, "AAPL", as_of=TODAY)

    assert after.scores.quality.value == before.scores.quality.value
    assert after.scores.setup.value == before.scores.setup.value
    assert after.scores.confidence.value == before.scores.confidence.value
