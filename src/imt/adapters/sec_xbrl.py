"""SEC XBRL Company Facts. SPEC §4, §7.2, §8.

## As-filed, always

Every fact carries the ``filed_date`` of the document that reported it, and a
restatement **inserts a new row** rather than updating the old one. A backtest
asks "what was known on date D", which is a query over ``filed_date <= D`` —
and that only works if the original figure is still there. The database
enforces it with an append-only trigger on ``xbrl_facts``.

## Tag coverage is inconsistent and that must stay visible

Filers use different tags for the same concept: ``Revenues``,
``RevenueFromContractWithCustomerExcludingAssessedTax``,
``SalesRevenueNet``, and more. This module resolves a concept by trying an
ordered list and **records which tag it actually matched**.

When no tag resolves, the metric is NULL with a reason code. It is never zero
and never estimated from a neighbouring concept — a company that does not
report gross profit is not a company with zero gross profit, and SPEC §8
requires every metric to mark itself unavailable rather than guess.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Any

from imt.adapters.records import FundamentalFact
from imt.core.logging import get_logger
from imt.entities.identifiers import normalize_cik

log = get_logger(__name__)

SOURCE_ID = "sec_edgar"
COMPANY_FACTS_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik}.json"

#: Concept → candidate tags, most-preferred first. Order matters: the first
#: tag a filer actually reports wins, and which one it was is recorded on the
#: metric so a surprising number can be traced to its source concept.
CONCEPT_TAGS: dict[str, tuple[str, ...]] = {
    "revenue": (
        "RevenueFromContractWithCustomerExcludingAssessedTax",
        "RevenueFromContractWithCustomerIncludingAssessedTax",
        "Revenues",
        "SalesRevenueNet",
        "SalesRevenueGoodsNet",
    ),
    "cost_of_revenue": ("CostOfRevenue", "CostOfGoodsAndServicesSold", "CostOfGoodsSold"),
    "gross_profit": ("GrossProfit",),
    "operating_income": ("OperatingIncomeLoss",),
    "net_income": ("NetIncomeLoss", "ProfitLoss"),
    "eps_diluted": ("EarningsPerShareDiluted", "EarningsPerShareBasicAndDiluted"),
    "assets": ("Assets",),
    "current_assets": ("AssetsCurrent",),
    "liabilities": ("Liabilities",),
    "current_liabilities": ("LiabilitiesCurrent",),
    "equity": (
        "StockholdersEquity",
        "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest",
    ),
    "cash": (
        "CashAndCashEquivalentsAtCarryingValue",
        "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
    ),
    "inventory": ("InventoryNet",),
    "receivables": ("AccountsReceivableNetCurrent",),
    "long_term_debt": ("LongTermDebtNoncurrent", "LongTermDebt"),
    "short_term_debt": ("LongTermDebtCurrent", "ShortTermBorrowings"),
    "interest_expense": ("InterestExpense", "InterestIncomeExpenseNet"),
    "operating_cash_flow": (
        "NetCashProvidedByUsedInOperatingActivities",
        "NetCashProvidedByUsedInOperatingActivitiesContinuingOperations",
    ),
    "capex": (
        "PaymentsToAcquirePropertyPlantAndEquipment",
        "PaymentsToAcquireProductiveAssets",
    ),
    "depreciation": (
        "DepreciationDepletionAndAmortization",
        "DepreciationAmortizationAndAccretionNet",
    ),
    "shares_outstanding": (
        "dei:EntityCommonStockSharesOutstanding",
        "CommonStockSharesOutstanding",
        "WeightedAverageNumberOfDilutedSharesOutstanding",
    ),
    "share_based_compensation": ("ShareBasedCompensation",),
    "dividends_paid": ("PaymentsOfDividendsCommonStock", "PaymentsOfDividends"),
    "buybacks": ("PaymentsForRepurchaseOfCommonStock",),
}


class XbrlParseError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class ResolvedFact:
    """A fact plus the tag that produced it.

    ``tag`` is carried all the way to the metric row so "why is revenue this
    number" is answerable without re-reading the filing (SPEC §8).
    """

    concept: str
    tag: str
    value: Decimal
    period_end: date
    period_start: date | None
    filed_date: date
    unit: str
    fiscal_period: str | None
    accession: str | None


def _decimal(raw: Any) -> Decimal | None:
    if raw is None:
        return None
    try:
        return Decimal(str(raw))
    except (InvalidOperation, ValueError):
        return None


def _parse_date(raw: str | None) -> date | None:
    if not raw:
        return None
    try:
        return date.fromisoformat(raw[:10])
    except ValueError:
        return None


def parse_company_facts(payload: dict[str, Any]) -> list[FundamentalFact]:
    """Flatten a Company Facts document into per-fact rows.

    The structure is ``facts → taxonomy → tag → units → unit → [entries]``.
    Every entry keeps its own ``filed`` date, which is what makes as-filed
    point-in-time queries possible.
    """
    cik_raw = payload.get("cik")
    if cik_raw is None:
        raise XbrlParseError("Company Facts document has no CIK")
    cik = normalize_cik(cik_raw)

    out: list[FundamentalFact] = []
    for taxonomy, tags in (payload.get("facts") or {}).items():
        for tag, body in tags.items():
            qualified = f"{taxonomy}:{tag}" if taxonomy != "us-gaap" else tag
            for unit, entries in (body.get("units") or {}).items():
                for entry in entries:
                    value = _decimal(entry.get("val"))
                    period_end = _parse_date(entry.get("end"))
                    filed = _parse_date(entry.get("filed"))
                    if value is None or period_end is None or filed is None:
                        # A fact without a value, a period, or a filing date
                        # cannot be placed in time and is dropped rather than
                        # defaulted into one.
                        continue
                    out.append(
                        FundamentalFact(
                            cik=cik,
                            tag=qualified,
                            unit=unit,
                            period_start=_parse_date(entry.get("start")),
                            period_end=period_end,
                            filed_date=filed,
                            value=value,
                            fiscal_period=entry.get("fp"),
                            accession=entry.get("accn"),
                        )
                    )
    return out


def resolve_concept(
    facts: Iterable[FundamentalFact],
    concept: str,
    *,
    as_of: date,
    period_end: date | None = None,
) -> ResolvedFact | None:
    """Resolve one concept as it was known on ``as_of``.

    Two filters, both load-bearing:

    * ``filed_date <= as_of`` — the point-in-time gate. Without it a backtest
      reads a restatement published months after the date it is simulating.
    * among the remaining candidates, the **latest filed** wins, which is the
      most recent information available at that moment.

    Tags are tried in preference order, so a filer using a non-standard tag
    still resolves, and the tag that matched is recorded.
    """
    candidates = CONCEPT_TAGS.get(concept)
    if not candidates:
        raise KeyError(f"Unknown concept {concept!r}. Add it to CONCEPT_TAGS explicitly.")

    by_tag: dict[str, list[FundamentalFact]] = {}
    for fact in facts:
        if fact.filed_date > as_of:
            continue
        if period_end is not None and fact.period_end != period_end:
            continue
        by_tag.setdefault(fact.tag, []).append(fact)

    for tag in candidates:
        matches = by_tag.get(tag)
        if not matches:
            continue
        # Latest period, then latest filing for that period.
        best = max(matches, key=lambda f: (f.period_end, f.filed_date))
        return ResolvedFact(
            concept=concept,
            tag=tag,
            value=best.value,
            period_end=best.period_end,
            period_start=best.period_start,
            filed_date=best.filed_date,
            unit=best.unit,
            fiscal_period=best.fiscal_period,
            accession=best.accession,
        )
    return None


def as_filed_value(
    facts: Iterable[FundamentalFact], tag: str, period_end: date, *, as_of: date
) -> Decimal | None:
    """The value for a period **as it was reported on** ``as_of``.

    This is the function a restatement test exercises: asking for a period
    before the restatement was filed must return the original figure, not the
    corrected one. Returning the latest value regardless of date is the
    single most common way a backtest quietly uses information from the
    future.
    """
    candidates = [
        f for f in facts if f.tag == tag and f.period_end == period_end and f.filed_date <= as_of
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda f: f.filed_date).value
