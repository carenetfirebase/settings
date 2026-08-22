"""Stooq CSV parsing. Exercised against fixture text rather than the network,
so the tests are deterministic and run offline.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from invest.providers.base import ProviderError, ProviderUnavailable
from invest.providers.stooq import parse_csv

GOOD_CSV = """Date,Open,High,Low,Close,Volume
2026-01-02,185.00,187.50,184.25,186.75,52000000
2026-01-05,186.80,188.00,186.10,187.20,48000000
2026-01-06,187.00,187.90,185.50,185.90,51000000
"""


def test_parses_rows_into_bars() -> None:
    bars = parse_csv(GOOD_CSV, "aapl.us")
    assert len(bars) == 3
    first = bars[0]
    assert first.obs_date == date(2026, 1, 2)
    assert first.open == Decimal("185.00")
    assert first.high == Decimal("187.50")
    assert first.low == Decimal("184.25")
    assert first.close == Decimal("186.75")
    assert first.volume == 52000000
    assert first.source == "stooq"


def test_values_stay_exact_decimals() -> None:
    """Binary floats would introduce error before the data even lands."""
    bars = parse_csv(GOOD_CSV, "aapl.us")
    assert isinstance(bars[0].close, Decimal)
    assert bars[0].close == Decimal("186.75")


def test_adjustment_basis_is_recorded_not_assumed() -> None:
    """Stooq is split-adjusted only; total-return maths must not use it blindly."""
    bar = parse_csv(GOOD_CSV, "aapl.us")[0]
    assert bar.is_split_adjusted is True
    assert bar.is_dividend_adjusted is False
    assert bar.adj_close is None  # NULL means "not provided", not "same as close"


def test_bars_come_back_sorted() -> None:
    scrambled = """Date,Open,High,Low,Close,Volume
2026-01-06,187.00,187.90,185.50,185.90,51000000
2026-01-02,185.00,187.50,184.25,186.75,52000000
"""
    bars = parse_csv(scrambled, "aapl.us")
    assert [b.obs_date for b in bars] == [date(2026, 1, 2), date(2026, 1, 6)]


def test_blank_cells_become_none_not_zero() -> None:
    csv_text = """Date,Open,High,Low,Close,Volume
2026-01-02,185.00,187.50,184.25,186.75,
"""
    bar = parse_csv(csv_text, "aapl.us")[0]
    assert bar.volume is None


def test_unknown_symbol_raises_unavailable() -> None:
    """Stooq answers HTTP 200 with 'No data' — status code alone is not proof."""
    with pytest.raises(ProviderUnavailable, match="no data for symbol"):
        parse_csv("No data", "nosuchticker.us")


def test_empty_body_raises_unavailable() -> None:
    with pytest.raises(ProviderUnavailable, match="empty response"):
        parse_csv("   ", "aapl.us")


def test_changed_header_refuses_to_guess() -> None:
    """A silently reordered feed is the nightmare case: refuse, don't adapt."""
    csv_text = """Date,Close,Open,High,Low,Volume
2026-01-02,186.75,185.00,187.50,184.25,52000000
"""
    with pytest.raises(ProviderError, match="unexpected CSV header"):
        parse_csv(csv_text, "aapl.us")


def test_corrupt_bar_is_rejected_at_the_boundary() -> None:
    """high < low never reaches the database."""
    csv_text = """Date,Open,High,Low,Close,Volume
2026-01-02,185.00,180.00,190.00,186.75,52000000
"""
    with pytest.raises(ValueError, match="high"):
        parse_csv(csv_text, "aapl.us")


def test_negative_price_is_rejected_at_the_boundary() -> None:
    csv_text = """Date,Open,High,Low,Close,Volume
2026-01-02,-185.00,187.50,184.25,186.75,52000000
"""
    with pytest.raises(ValueError, match="negative"):
        parse_csv(csv_text, "aapl.us")


def test_bad_date_raises() -> None:
    csv_text = """Date,Open,High,Low,Close,Volume
not-a-date,185.00,187.50,184.25,186.75,52000000
"""
    with pytest.raises(ProviderError, match="bad date"):
        parse_csv(csv_text, "aapl.us")


def test_short_row_raises() -> None:
    csv_text = """Date,Open,High,Low,Close,Volume
2026-01-02,185.00,187.50
"""
    with pytest.raises(ProviderError, match="short row"):
        parse_csv(csv_text, "aapl.us")


def test_blank_lines_are_skipped() -> None:
    csv_text = GOOD_CSV + "\n\n"
    assert len(parse_csv(csv_text, "aapl.us")) == 3
