"""EDGAR discovery, ownership, 8-K, and Stooq adapters.

All parsing is pure, so these run without HTTP. The point-in-time tests in
``TestPublicAvailableAt`` are the ones that matter most: that function is the
backtest's entry clock, and every look-ahead bug in this system would enter
through it.
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import ClassVar
from zoneinfo import ZoneInfo

import pytest

from imt.adapters.sec_edgar import (
    parse_company_tickers,
    parse_daily_index,
    parse_submissions,
    public_available_at,
)
from imt.adapters.sec_eightk import classify, classify_content, is_informative, normalize_item
from imt.adapters.sec_ownership import classify_item4, is_activist_form, strip_markup
from imt.adapters.stooq import parse_daily_csv, stooq_symbol

ET = ZoneInfo("America/New_York")


class TestPublicAvailableAt:
    """SPEC §7.1 — the only clock a backtest may use."""

    def test_morning_filing_is_available_immediately(self) -> None:
        accepted = datetime(2026, 8, 20, 10, 15, tzinfo=ET)
        assert public_available_at(date(2026, 8, 20), accepted) == accepted

    def test_after_close_rolls_to_the_next_session_open(self) -> None:
        """A filing accepted at 16:30 could not be acted on until the open."""
        accepted = datetime(2026, 8, 20, 16, 30, tzinfo=ET)
        result = public_available_at(date(2026, 8, 20), accepted)
        assert result == datetime(2026, 8, 21, 9, 30, tzinfo=ET)

    def test_friday_evening_rolls_over_the_weekend(self) -> None:
        friday = datetime(2026, 8, 21, 17, 0, tzinfo=ET)  # 2026-08-21 is a Friday
        result = public_available_at(date(2026, 8, 21), friday)
        assert result.date() == date(2026, 8, 24)  # Monday
        assert result.hour == 9

    def test_exactly_at_the_close_rolls_forward(self) -> None:
        """16:00:00 is not before the close. The boundary goes the safe way."""
        accepted = datetime(2026, 8, 20, 16, 0, tzinfo=ET)
        assert public_available_at(date(2026, 8, 20), accepted).date() == date(2026, 8, 21)

    def test_missing_acceptance_assumes_the_close_not_the_open(self) -> None:
        """The conservative direction.

        Assuming the open would let a backtest trade on information that may
        not have existed yet, which is exactly the bug this function exists to
        prevent.
        """
        result = public_available_at(date(2026, 8, 20), None)
        assert result == datetime(2026, 8, 20, 16, 0, tzinfo=ET)

    def test_utc_acceptance_is_converted_to_market_time(self) -> None:
        """20:30 UTC is 16:30 ET — after the close, despite looking like 20:30."""
        accepted = datetime(2026, 8, 20, 20, 30, tzinfo=ZoneInfo("UTC"))
        assert public_available_at(date(2026, 8, 20), accepted).date() == date(2026, 8, 21)


class TestSubmissions:
    PAYLOAD: ClassVar[dict] = {
        "name": "ALPHA BUILDERS INC",
        "filings": {
            "recent": {
                "accessionNumber": ["0001234567-26-000001", "0001234567-26-000002"],
                "form": ["4", "8-K"],
                "filingDate": ["2026-08-16", "2026-08-17"],
                "acceptanceDateTime": ["2026-08-16T18:31:00.000Z", "2026-08-17T09:02:00.000Z"],
                "primaryDocument": ["form4.xml", "eightk.htm"],
                "items": ["", "5.02"],
            }
        },
    }

    def test_parses_refs_with_both_dates(self) -> None:
        refs = parse_submissions(self.PAYLOAD, cik="0000320193")
        assert len(refs) == 2
        assert refs[0].form_type == "4"
        assert refs[0].filed_date == date(2026, 8, 16)
        assert refs[0].acceptance_datetime is not None

    def test_builds_the_archive_url(self) -> None:
        refs = parse_submissions(self.PAYLOAD, cik="0000320193")
        assert refs[0].primary_doc_url.endswith("/320193/000123456726000001/form4.xml")

    def test_empty_payload_is_not_an_error(self) -> None:
        assert parse_submissions({}, cik="0000320193") == []

    def test_a_bad_date_skips_the_row_rather_than_the_document(self) -> None:
        payload = {
            "filings": {
                "recent": {
                    "accessionNumber": ["a", "b"],
                    "form": ["4", "4"],
                    "filingDate": ["not-a-date", "2026-08-16"],
                    "acceptanceDateTime": ["", ""],
                    "primaryDocument": ["x.xml", "y.xml"],
                }
            }
        }
        refs = parse_submissions(payload, cik="0000320193")
        assert len(refs) == 1


class TestDailyIndex:
    INDEX = """Description:           Daily Index of EDGAR Dissemination Feed
Last Data Received:    August 20, 2026

Form Type   Company Name                                       CIK         Date Filed  File Name
---------------------------------------------------------------------------------------------
4           ALPHA BUILDERS INC                                 320193      20260820    edgar/data/320193/0001234567-26-000001.txt
8-K         BETA CORP OF AMERICA                               789019      20260820    edgar/data/789019/0000789019-26-000045.txt
SC 13D      GAMMA PARTNERS LP                                  1018724     20260820    edgar/data/1018724/0001018724-26-000009.txt
"""

    def test_parses_every_row(self) -> None:
        refs = parse_daily_index(self.INDEX, filed_date=date(2026, 8, 20))
        assert len(refs) == 3
        assert [r.form_type for r in refs] == ["4", "8-K", "SC 13D"]

    def test_company_names_with_spaces_survive(self) -> None:
        """Splitting on whitespace would truncate 'BETA CORP OF AMERICA'."""
        refs = parse_daily_index(self.INDEX, filed_date=date(2026, 8, 20))
        assert refs[1].company_name == "BETA CORP OF AMERICA"

    def test_ciks_are_zero_padded(self) -> None:
        refs = parse_daily_index(self.INDEX, filed_date=date(2026, 8, 20))
        assert refs[0].cik == "0000320193"

    def test_accession_is_taken_from_the_path(self) -> None:
        refs = parse_daily_index(self.INDEX, filed_date=date(2026, 8, 20))
        assert refs[0].accession == "0001234567-26-000001"

    def test_index_without_a_separator_returns_nothing(self) -> None:
        assert parse_daily_index("garbage\nmore garbage", filed_date=date(2026, 8, 20)) == []


class TestCompanyTickers:
    def test_parses_the_index_keyed_object(self) -> None:
        payload = {
            "0": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."},
            "1": {"cik_str": 789019, "ticker": "msft", "title": "MICROSOFT CORP"},
        }
        rows = parse_company_tickers(payload)
        assert rows[0] == {"cik": "0000320193", "ticker": "AAPL", "name": "Apple Inc."}
        assert rows[1]["ticker"] == "MSFT"


class TestOwnershipForms:
    def test_13d_is_activist_and_13g_is_not(self) -> None:
        """SPEC §8: conflating these is a correctness bug.

        A 13G is typically an index fund crossing 5% — mechanical and
        information-free. Scoring it as activist pressure would put the least
        informative event in the corpus at the top of the ranking.
        """
        assert is_activist_form("SC 13D") is True
        assert is_activist_form("SC 13D/A") is True
        assert is_activist_form("SC 13G") is False
        assert is_activist_form("SC 13G/A") is False

    def test_an_unrelated_form_raises_rather_than_defaulting(self) -> None:
        with pytest.raises(ValueError, match="never guessed"):
            is_activist_form("13F-HR")

    def test_item4_classification_is_deterministic(self) -> None:
        text = "The Reporting Persons intend to seek board representation and may explore strategic alternatives."
        categories = classify_item4(text)
        assert "board_representation" in categories
        assert "strategic_alternatives" in categories

    def test_no_match_returns_empty_not_a_guess(self) -> None:
        assert classify_item4("The Reporting Person acquired shares for investment.") == ()

    def test_markup_is_stripped_before_matching(self) -> None:
        html = "<p>seek <b>board</b> representation</p>"
        assert "board representation" in strip_markup(html)


class TestEightK:
    def test_item_numbers_map_to_the_sec_taxonomy(self) -> None:
        numbers, categories = classify(["5.02"])
        assert numbers == ("5.02",)
        assert categories == ("executive_change",)

    def test_multiple_items_in_one_string(self) -> None:
        numbers, categories = classify(["2.02,9.01"])
        assert numbers == ("2.02", "9.01")
        assert "earnings" in categories

    def test_items_recovered_from_the_body_when_the_index_omits_them(self) -> None:
        numbers, _ = classify([], body="<p>Item 1.05 Material Cybersecurity Incident</p>")
        assert numbers == ("1.05",)

    def test_content_keywords_add_detail(self) -> None:
        assert "government_contract" in classify_content("The Company was awarded a contract.")

    def test_exhibits_only_filing_is_not_informative(self) -> None:
        """A filing whose only item is 9.01 carries no catalyst.

        Counting it as one inflates the corporate-event category with
        administrative noise.
        """
        assert is_informative(("9.01",)) is False
        assert is_informative(("5.02", "9.01")) is True

    def test_unknown_item_numbers_are_dropped_not_bucketed(self) -> None:
        numbers, categories = classify(["9.99"])
        assert numbers == ("9.99",)
        assert categories == ()

    @pytest.mark.parametrize(
        ("raw", "expected"),
        [("Item 5.02", "5.02"), ("5.02", "5.02"), ("nonsense", None)],
    )
    def test_normalize_item(self, raw: str, expected: str | None) -> None:
        assert normalize_item(raw) == expected


class TestStooq:
    CSV = """Date,Open,High,Low,Close,Volume
2026-08-19,60.10,61.00,59.80,60.75,1200000
2026-08-20,60.80,61.50,60.20,61.20,980000
"""

    def test_parses_bars(self) -> None:
        bars = parse_daily_csv(self.CSV, symbol="ABC")
        assert len(bars) == 2
        assert bars[0].close == Decimal("60.75")
        assert bars[1].volume == 980000

    def test_bars_are_sorted_by_date(self) -> None:
        reversed_csv = (
            "Date,Open,High,Low,Close,Volume\n2026-08-20,1,1,1,61.20,1\n2026-08-19,1,1,1,60.75,1\n"
        )
        bars = parse_daily_csv(reversed_csv, symbol="ABC")
        assert [b.trade_date for b in bars] == [date(2026, 8, 19), date(2026, 8, 20)]

    def test_a_row_without_a_close_is_dropped_not_interpolated(self) -> None:
        """A bar without a close is not a bar. Inventing one fabricates a price."""
        csv_text = "Date,Open,High,Low,Close,Volume\n2026-08-19,60.10,61.00,59.80,,1200000\n"
        assert parse_daily_csv(csv_text, symbol="ABC") == []

    def test_empty_response_returns_nothing(self) -> None:
        assert parse_daily_csv("", symbol="ABC") == []
        assert parse_daily_csv("No data", symbol="ABC") == []

    def test_series_is_always_marked_adjusted(self) -> None:
        """SPEC §4: adjusted-only, and the UI must say so."""
        assert all(bar.is_adjusted for bar in parse_daily_csv(self.CSV, symbol="ABC"))

    @pytest.mark.parametrize(
        ("ticker", "expected"),
        [
            ("AAPL", "aapl.us"),
            ("aapl", "aapl.us"),
            # SEC writes class shares with a dot, Stooq with a dash. Getting
            # this wrong returns an empty CSV rather than an error.
            ("BRK.B", "brk-b.us"),
            ("^SPX", "^spx"),
        ],
    )
    def test_symbol_mapping(self, ticker: str, expected: str) -> None:
        assert stooq_symbol(ticker) == expected
