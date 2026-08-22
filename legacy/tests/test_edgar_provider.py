"""EDGAR companyfacts / submissions parsing, against fixture payloads.

The fixtures mirror the real XBRL shape but carry obviously synthetic numbers —
they test the parser, and no figure here is ever presented as a real financial
fact.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from invest.providers.base import ProviderError
from invest.providers.edgar import (
    CONCEPT_MAP,
    canonical_metric,
    parse_company_facts,
    parse_company_tickers,
    parse_submissions,
)

CIK = "0000320193"


def companyfacts(entries: list[dict], tag: str = "Revenues", unit: str = "USD") -> dict:
    return {
        "cik": 320193,
        "entityName": "Test Co",
        "facts": {"us-gaap": {tag: {"label": tag, "units": {unit: entries}}}},
    }


def entry(**overrides) -> dict:
    base = {
        "start": "2025-01-01",
        "end": "2025-12-31",
        "val": 1000,
        "fy": 2025,
        "fp": "FY",
        "form": "10-K",
        "filed": "2026-02-01",
        "accn": "0000320193-26-000001",
    }
    base.update(overrides)
    return base


# --------------------------------------------------------------------------
# Concept mapping
# --------------------------------------------------------------------------


def test_concept_map_resolves_tag_synonyms() -> None:
    """The same quantity is tagged differently by filer and by year."""
    assert canonical_metric("Revenues")[0] == "Revenues"
    assert canonical_metric("RevenueFromContractWithCustomerExcludingAssessedTax")[0] == "Revenues"
    assert canonical_metric("SalesRevenueNet")[0] == "Revenues"


def test_unmapped_tag_is_skipped_not_invented() -> None:
    assert canonical_metric("SomeTagWeHaveNeverSeen") is None


def test_no_tag_maps_to_two_metrics() -> None:
    """A duplicated tag would make one number mean two things."""
    seen: dict[str, str] = {}
    for metric, tags in CONCEPT_MAP.items():
        for tag in tags:
            assert tag not in seen, f"{tag} maps to both {seen.get(tag)} and {metric}"
            seen[tag] = metric


def test_preferred_tag_wins_deterministically() -> None:
    """When a filer reports both synonyms for one period, the ranked-first tag
    wins — not whichever dict ordering happened to surface last.
    """
    payload = {
        "facts": {
            "us-gaap": {
                "SalesRevenueNet": {"units": {"USD": [entry(val=111)]}},
                "RevenueFromContractWithCustomerExcludingAssessedTax": {
                    "units": {"USD": [entry(val=999)]}
                },
            }
        }
    }
    facts = parse_company_facts(payload, CIK)
    revenues = [f for f in facts if f.metric_name == "Revenues"]
    assert len(revenues) == 1
    assert revenues[0].value == Decimal(999)  # the preferred tag


# --------------------------------------------------------------------------
# Fact extraction
# --------------------------------------------------------------------------


def test_extracts_the_point_in_time_key() -> None:
    fact = parse_company_facts(companyfacts([entry()]), CIK)[0]
    assert fact.filed_date == date(2026, 2, 1)
    assert fact.period_end == date(2025, 12, 31)
    assert fact.period_start == date(2025, 1, 1)
    assert fact.fiscal_period == "FY"
    assert fact.fiscal_year == 2025
    assert fact.form_type == "10-K"
    assert fact.accession_number == "0000320193-26-000001"


def test_preserves_raw_tag_and_taxonomy() -> None:
    """Normalization must be reversible — nothing is lost in translation."""
    fact = parse_company_facts(companyfacts([entry()], tag="SalesRevenueNet"), CIK)[0]
    assert fact.metric_name == "Revenues"
    assert fact.xbrl_tag == "SalesRevenueNet"
    assert fact.taxonomy == "us-gaap"


def test_unit_is_carried_through() -> None:
    fact = parse_company_facts(companyfacts([entry()], unit="USD"), CIK)[0]
    assert fact.unit == "USD"


def test_entry_without_filed_date_is_dropped() -> None:
    """A fact with no point-in-time key cannot be used safely by anything."""
    payload = companyfacts([entry(filed=None), entry()])
    facts = parse_company_facts(payload, CIK)
    assert len(facts) == 1


def test_entry_without_end_date_is_dropped() -> None:
    payload = companyfacts([entry(end=None), entry()])
    assert len(parse_company_facts(payload, CIK)) == 1


def test_restatement_produces_two_rows() -> None:
    """Same period, two filings — both survive so point-in-time works later."""
    payload = companyfacts(
        [
            entry(val=1000, filed="2026-02-01", accn="acc-1"),
            entry(val=950, filed="2026-08-01", accn="acc-2"),
        ]
    )
    facts = parse_company_facts(payload, CIK)
    assert len(facts) == 2
    assert {f.filed_date for f in facts} == {date(2026, 2, 1), date(2026, 8, 1)}


def test_instant_facts_have_no_period_start() -> None:
    payload = companyfacts([entry(start=None)], tag="Assets")
    fact = parse_company_facts(payload, CIK)[0]
    assert fact.period_start is None
    assert fact.period_end == date(2025, 12, 31)


def test_invalid_fiscal_period_becomes_none_not_a_guess() -> None:
    fact = parse_company_facts(companyfacts([entry(fp="H1")]), CIK)[0]
    assert fact.fiscal_period is None


def test_reversed_period_is_skipped() -> None:
    payload = companyfacts([entry(start="2026-01-01", end="2025-12-31")])
    assert parse_company_facts(payload, CIK) == []


def test_null_value_is_preserved_as_none() -> None:
    """A missing value is NULL, never zero."""
    fact = parse_company_facts(companyfacts([entry(val=None)]), CIK)[0]
    assert fact.value is None


def test_values_are_decimals() -> None:
    fact = parse_company_facts(companyfacts([entry(val=123456789.12)]), CIK)[0]
    assert isinstance(fact.value, Decimal)


def test_quarterly_and_annual_coexist() -> None:
    payload = companyfacts(
        [
            entry(fp="FY", start="2025-01-01", end="2025-12-31", accn="a1"),
            entry(fp="Q4", start="2025-10-01", end="2025-12-31", accn="a2"),
        ]
    )
    facts = parse_company_facts(payload, CIK)
    assert {f.fiscal_period for f in facts} == {"FY", "Q4"}


def test_payload_without_facts_raises() -> None:
    with pytest.raises(ProviderError, match="no 'facts' object"):
        parse_company_facts({"cik": 320193}, CIK)


def test_unmapped_tags_do_not_appear() -> None:
    payload = {
        "facts": {"us-gaap": {"ObscureUnmappedConcept": {"units": {"USD": [entry()]}}}}
    }
    assert parse_company_facts(payload, CIK) == []


def test_results_are_sorted_deterministically() -> None:
    payload = companyfacts(
        [
            entry(start="2025-01-01", end="2025-12-31", filed="2026-02-01", accn="a"),
            entry(start="2024-01-01", end="2024-12-31", filed="2025-02-01", accn="b"),
        ]
    )
    facts = parse_company_facts(payload, CIK)
    assert [f.period_end for f in facts] == [date(2024, 12, 31), date(2025, 12, 31)]


# --------------------------------------------------------------------------
# company_tickers.json — the CIK authority
# --------------------------------------------------------------------------


def test_parses_ticker_cik_map() -> None:
    payload = {
        "0": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."},
        "1": {"cik_str": 789019, "ticker": "MSFT", "title": "MICROSOFT CORP"},
    }
    mapping = parse_company_tickers(payload)
    assert mapping == {"AAPL": "0000320193", "MSFT": "0000789019"}


def test_empty_ticker_map_raises_rather_than_wiping_the_master() -> None:
    """An empty authority response must not be read as 'nothing is valid'."""
    with pytest.raises(ProviderError, match="no mappings"):
        parse_company_tickers({})


# --------------------------------------------------------------------------
# submissions
# --------------------------------------------------------------------------


def test_parses_column_wise_submissions() -> None:
    payload = {
        "filings": {
            "recent": {
                "accessionNumber": ["0000320193-26-000001", "0000320193-26-000002"],
                "form": ["10-K", "4"],
                "filingDate": ["2026-02-01", "2026-02-05"],
                "reportDate": ["2025-12-31", "2026-02-03"],
                "primaryDocument": ["aapl-10k.htm", "form4.xml"],
                "acceptanceDateTime": ["2026-02-01T16:30:00.000Z", "2026-02-05T18:00:00.000Z"],
                "items": ["", ""],
            }
        }
    }
    records = parse_submissions(payload, CIK)
    assert len(records) == 2
    assert records[0].form_type == "10-K"
    assert records[0].filed_date == date(2026, 2, 1)
    assert records[0].period_of_report == date(2025, 12, 31)
    assert "320193" in records[0].primary_doc_url
    assert records[0].acceptance_datetime.startswith("2026-02-01")


def test_submissions_without_filings_is_empty_not_an_error() -> None:
    assert parse_submissions({}, CIK) == []
