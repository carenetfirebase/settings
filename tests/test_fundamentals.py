"""XBRL parsing and fundamental metrics. docs/PHASES.md Phase 5.

Criterion 1 (≥3,000 companies) and criterion 4 (hand-check against a real
10-K) need live EDGAR and are not met here. Criterion 2 — every metric records
its tags, and unavailable metrics are NULL with a reason rather than zero — is
the one these tests are built around, because it is the property that decides
whether the scoring engine can be trusted with inconsistent tag coverage.

Criterion 3, the point-in-time restatement test, is in
``TestAsFiledPointInTime``.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any, ClassVar

import pytest

from imt.adapters.records import FundamentalFact
from imt.adapters.sec_xbrl import (
    XbrlParseError,
    as_filed_value,
    parse_company_facts,
    resolve_concept,
)
from imt.features.fundamentals import (
    FactWindow,
    altman_z_score,
    compute_all,
    free_cash_flow,
    gross_margin,
    interest_coverage,
    inventory_vs_revenue,
    piotroski_f_score,
    return_on_equity,
    revenue_growth,
    share_dilution,
)

AS_OF = date(2026, 6, 1)


def fact(
    tag: str,
    value: str,
    *,
    period_end: date,
    filed: date,
    unit: str = "USD",
    cik: str = "0000320193",
) -> FundamentalFact:
    return FundamentalFact(
        cik=cik,
        tag=tag,
        unit=unit,
        period_start=None,
        period_end=period_end,
        filed_date=filed,
        value=Decimal(value),
    )


def window(facts: list[FundamentalFact], *, as_of: date = AS_OF) -> FactWindow:
    return FactWindow(facts, as_of=as_of)


BASE_FACTS = [
    fact("Revenues", "1000000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
    fact("CostOfRevenue", "600000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
    fact("OperatingIncomeLoss", "250000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
    fact("NetIncomeLoss", "180000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
    fact("Assets", "2000000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
    fact("StockholdersEquity", "1200000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
]


class TestParsing:
    PAYLOAD: ClassVar[dict[str, Any]] = {
        "cik": 320193,
        "entityName": "DEMO",
        "facts": {
            "us-gaap": {
                "Revenues": {
                    "units": {
                        "USD": [
                            {
                                "val": 1000000,
                                "end": "2025-12-31",
                                "start": "2025-01-01",
                                "filed": "2026-02-15",
                                "fp": "FY",
                                "accn": "0000320193-26-000001",
                            }
                        ]
                    }
                }
            },
            "dei": {
                "EntityCommonStockSharesOutstanding": {
                    "units": {
                        "shares": [{"val": 500000, "end": "2025-12-31", "filed": "2026-02-15"}]
                    }
                }
            },
        },
    }

    def test_flattens_facts_with_their_filed_dates(self) -> None:
        facts = parse_company_facts(self.PAYLOAD)
        assert len(facts) == 2
        assert all(f.filed_date == date(2026, 2, 15) for f in facts)

    def test_qualifies_non_gaap_taxonomies(self) -> None:
        """dei tags keep their prefix; us-gaap tags do not.

        Without this, `EntityCommonStockSharesOutstanding` would collide with
        any identically-named us-gaap concept.
        """
        tags = {f.tag for f in parse_company_facts(self.PAYLOAD)}
        assert "Revenues" in tags
        assert "dei:EntityCommonStockSharesOutstanding" in tags

    def test_a_fact_without_a_filed_date_is_dropped(self) -> None:
        """It cannot be placed in time, and defaulting it into a date would
        make it visible to a backtest that should not see it."""
        payload = {
            "cik": 1,
            "facts": {
                "us-gaap": {"Revenues": {"units": {"USD": [{"val": 1, "end": "2025-12-31"}]}}}
            },
        }
        assert parse_company_facts(payload) == []

    def test_rejects_a_document_with_no_cik(self) -> None:
        with pytest.raises(XbrlParseError, match="no CIK"):
            parse_company_facts({"facts": {}})


class TestTagResolution:
    def test_tries_tags_in_preference_order(self) -> None:
        facts = [
            fact(
                "SalesRevenueNet", "900000", period_end=date(2025, 12, 31), filed=date(2026, 2, 1)
            ),
            fact("Revenues", "1000000", period_end=date(2025, 12, 31), filed=date(2026, 2, 1)),
        ]
        resolved = resolve_concept(facts, "revenue", as_of=AS_OF)
        assert resolved is not None
        assert resolved.tag == "Revenues"
        assert resolved.value == Decimal("1000000")

    def test_falls_back_to_a_less_preferred_tag(self) -> None:
        """Filers using non-standard tags still resolve; the tag is recorded."""
        facts = [
            fact("SalesRevenueNet", "900000", period_end=date(2025, 12, 31), filed=date(2026, 2, 1))
        ]
        resolved = resolve_concept(facts, "revenue", as_of=AS_OF)
        assert resolved is not None
        assert resolved.tag == "SalesRevenueNet"

    def test_returns_none_when_no_tag_matches(self) -> None:
        assert resolve_concept([], "revenue", as_of=AS_OF) is None

    def test_an_unknown_concept_raises_rather_than_returning_none(self) -> None:
        """A typo in a concept name must not look like missing data."""
        with pytest.raises(KeyError, match="Unknown concept"):
            resolve_concept([], "revenu", as_of=AS_OF)


class TestAsFiledPointInTime:
    """Phase 5 criterion 3 — the restatement test.

    This is the fundamentals equivalent of the backtest entry clock. Reading
    the corrected figure when simulating a date before the correction was
    filed is look-ahead, and it is invisible unless tested.
    """

    RESTATED: ClassVar[list[FundamentalFact]] = [
        # Original figure, filed February.
        fact("Revenues", "1000000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
        # Restatement of the SAME period, filed August.
        fact("Revenues", "850000", period_end=date(2025, 12, 31), filed=date(2026, 8, 10)),
    ]

    def test_before_the_restatement_returns_the_original(self) -> None:
        value = as_filed_value(
            self.RESTATED, "Revenues", date(2025, 12, 31), as_of=date(2026, 6, 1)
        )
        assert value == Decimal("1000000")

    def test_after_the_restatement_returns_the_corrected_figure(self) -> None:
        value = as_filed_value(
            self.RESTATED, "Revenues", date(2025, 12, 31), as_of=date(2026, 9, 1)
        )
        assert value == Decimal("850000")

    def test_before_either_filing_returns_nothing(self) -> None:
        assert (
            as_filed_value(self.RESTATED, "Revenues", date(2025, 12, 31), as_of=date(2026, 1, 1))
            is None
        )

    def test_metrics_respect_the_as_of_date(self) -> None:
        """The whole window is gated, not just direct lookups."""
        facts = [*self.RESTATED, *BASE_FACTS[1:]]
        early = gross_margin(window(facts, as_of=date(2026, 6, 1)))
        late = gross_margin(window(facts, as_of=date(2026, 9, 1)))
        assert early.value != late.value


class TestMissingIsNullNotZero:
    """Phase 5 criterion 2. The property the scoring engine depends on."""

    def test_absent_revenue_gives_null_with_a_reason(self) -> None:
        result = gross_margin(window([]))
        assert result.value is None
        assert result.reason_code is not None
        assert not result.available

    def test_no_capex_line_does_not_become_zero_capex(self) -> None:
        """Reporting OCF as FCF would overstate every capital-intensive
        business in the universe."""
        facts = [
            fact(
                "NetCashProvidedByUsedInOperatingActivities",
                "300000",
                period_end=date(2025, 12, 31),
                filed=date(2026, 2, 15),
            )
        ]
        result = free_cash_flow(window(facts))
        assert result.value is None
        assert result.reason_code == "capex_unavailable"

    def test_zero_revenue_gives_undefined_margin_not_zero(self) -> None:
        """A company with no revenue has an undefined margin. Rendering it as
        0% puts it in the same bucket as a company selling at cost."""
        facts = [
            fact("Revenues", "0", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
            fact("GrossProfit", "0", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
        ]
        result = gross_margin(window(facts))
        assert result.value is None
        assert result.reason_code == "denominator_zero"

    def test_negative_equity_makes_roe_unavailable(self) -> None:
        """A loss on negative equity produces a positive ratio, which reads as
        excellent performance."""
        facts = [
            fact("NetIncomeLoss", "-50000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
            fact(
                "StockholdersEquity",
                "-200000",
                period_end=date(2025, 12, 31),
                filed=date(2026, 2, 15),
            ),
        ]
        result = return_on_equity(window(facts))
        assert result.value is None
        assert result.reason_code == "negative_equity"

    def test_no_interest_expense_is_undefined_not_infinite(self) -> None:
        """A debt-free company should read as not-applicable, not as the
        best-covered company in the universe."""
        facts = [
            fact(
                "OperatingIncomeLoss",
                "250000",
                period_end=date(2025, 12, 31),
                filed=date(2026, 2, 15),
            ),
            fact("InterestExpense", "0", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
        ]
        result = interest_coverage(window(facts))
        assert result.value is None
        assert result.reason_code == "no_interest_expense"

    def test_every_unavailable_metric_carries_a_reason(self) -> None:
        """Criterion 2, over the whole metric set against an empty fact base."""
        for key, metric in compute_all(window([])).items():
            assert not metric.available, key
            assert metric.reason_code is not None, f"{key} is unavailable with no reason"


class TestMetricsRecordTheirTags:
    """Phase 5 criterion 2: which XBRL tags each metric resolved."""

    def test_gross_margin_records_both_tags(self) -> None:
        result = gross_margin(window(BASE_FACTS))
        assert result.value == pytest.approx(Decimal(40))
        assert "Revenues" in result.tags

    def test_derived_gross_profit_records_the_derivation(self) -> None:
        """Gross profit derived from revenue minus cost says so in its tags."""
        result = gross_margin(window(BASE_FACTS))
        assert any("-" in tag for tag in result.tags)


class TestCalculations:
    def test_gross_margin(self) -> None:
        assert gross_margin(window(BASE_FACTS)).value == pytest.approx(Decimal(40))

    def test_return_on_equity(self) -> None:
        assert return_on_equity(window(BASE_FACTS)).value == pytest.approx(Decimal(15))

    def test_free_cash_flow_subtracts_capex_as_an_outflow(self) -> None:
        """Capex is reported as a positive payment; FCF must subtract it
        regardless of the sign the filer used."""
        for capex in ("80000", "-80000"):
            facts = [
                fact(
                    "NetCashProvidedByUsedInOperatingActivities",
                    "300000",
                    period_end=date(2025, 12, 31),
                    filed=date(2026, 2, 15),
                ),
                fact(
                    "PaymentsToAcquirePropertyPlantAndEquipment",
                    capex,
                    period_end=date(2025, 12, 31),
                    filed=date(2026, 2, 15),
                ),
            ]
            assert free_cash_flow(window(facts)).value == Decimal("220000")

    def test_revenue_growth_over_two_periods(self) -> None:
        facts = [
            fact("Revenues", "1200000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
            fact("Revenues", "1000000", period_end=date(2024, 12, 31), filed=date(2025, 2, 15)),
        ]
        assert revenue_growth(window(facts)).value == pytest.approx(Decimal(20))

    def test_share_dilution_is_positive_when_shares_increase(self) -> None:
        facts = [
            fact(
                "dei:EntityCommonStockSharesOutstanding",
                "110",
                period_end=date(2025, 12, 31),
                filed=date(2026, 2, 15),
                unit="shares",
            ),
            fact(
                "dei:EntityCommonStockSharesOutstanding",
                "100",
                period_end=date(2024, 12, 31),
                filed=date(2025, 2, 15),
                unit="shares",
            ),
        ]
        assert share_dilution(window(facts)).value == pytest.approx(Decimal(10))

    def test_inventory_outpacing_revenue_is_positive(self) -> None:
        """SPEC §6.6 contradiction check: goods accumulating faster than sales."""
        facts = [
            fact("InventoryNet", "150", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
            fact("InventoryNet", "100", period_end=date(2024, 12, 31), filed=date(2025, 2, 15)),
            fact("Revenues", "1050", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
            fact("Revenues", "1000", period_end=date(2024, 12, 31), filed=date(2025, 2, 15)),
        ]
        result = inventory_vs_revenue(window(facts))
        assert result.value is not None
        assert result.value > 0


class TestCompositeScores:
    def test_piotroski_refuses_a_partial_score(self) -> None:
        """A 4 from 5 of 9 signals is not a Piotroski score, and reporting it
        as one makes an incomplete company look merely mediocre."""
        result = piotroski_f_score(window(BASE_FACTS))
        assert result.value is None
        assert result.reason_code == "incomplete_inputs"
        assert result.signals_available < result.signals_total

    def test_piotroski_reports_how_many_signals_resolved(self) -> None:
        result = piotroski_f_score(window(BASE_FACTS))
        assert result.signals_available > 0
        assert result.signals_total == 9

    def test_altman_without_market_cap_says_so(self) -> None:
        """Substituting book equity would be a different formula wearing the
        same name."""
        result = altman_z_score(window(BASE_FACTS), market_cap=None)
        assert result.value is None
        assert result.reason_code == "market_cap_unavailable"

    def test_altman_computes_with_complete_inputs(self) -> None:
        facts = [
            *BASE_FACTS,
            fact("Liabilities", "800000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
            fact("AssetsCurrent", "900000", period_end=date(2025, 12, 31), filed=date(2026, 2, 15)),
            fact(
                "LiabilitiesCurrent",
                "400000",
                period_end=date(2025, 12, 31),
                filed=date(2026, 2, 15),
            ),
        ]
        result = altman_z_score(window(facts), market_cap=Decimal("3000000"))
        assert result.value is not None
        assert result.signals_available == result.signals_total
