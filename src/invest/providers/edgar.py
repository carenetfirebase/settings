"""SEC EDGAR — fundamentals, filings, and the authoritative ticker->CIK map.

No API key. EDGAR requires a descriptive `User-Agent` naming the application
and a contact address, and enforces a hard 10 requests/second ceiling with IP
blocking for offenders. We run the token bucket at 8 rps.

Endpoints used:
    https://www.sec.gov/files/company_tickers.json      ticker -> CIK (authority)
    https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json
    https://data.sec.gov/submissions/CIK##########.json

For a full backfill across many companies, prefer the bulk
`https://www.sec.gov/Archives/edgar/daily-index/xbrl/companyfacts.zip`
over per-company calls — one download instead of thousands of requests.

## Why the XBRL shape needs normalizing

`companyfacts` nests facts as:

    facts -> taxonomy (us-gaap|dei|ifrs-full) -> tag -> units -> unit -> [entries]

and each entry carries `val`, `end`, optionally `start`, plus `fy`, `fp`,
`form`, `filed`, `accn`. The same economic quantity appears under different
tags depending on filer and year (`Revenues` vs
`RevenueFromContractWithCustomerExcludingAssessedTax`), so a concept map
resolves synonyms to one canonical metric name. The raw tag is preserved on
every row so nothing is lost in translation.

`filed` is what makes point-in-time work: it is the date the fact became
public, and every row carries it.
"""

from __future__ import annotations

import logging
import pathlib
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any

from invest.providers.base import (
    FilingRecord,
    FundamentalFact,
    InsiderTransactionRecord,
    ProviderError,
)
from invest.providers.form4 import parse_form4
from invest.providers.http import HttpClient

logger = logging.getLogger(__name__)

SOURCE_NAME = "sec_edgar"

COMPANY_TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
COMPANY_FACTS_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik}.json"
SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik}.json"

#: The whole XBRL corpus in one archive. Published by the SEC specifically so
#: bulk consumers do not hammer the per-company endpoint.
BULK_COMPANYFACTS_URL = "https://www.sec.gov/Archives/edgar/daily-index/xbrl/companyfacts.zip"

#: EDGAR's published ceiling is 10 rps. 8 leaves headroom for clock skew and
#: for anything else sharing our IP.
EDGAR_RATE_LIMIT = 8.0


# --------------------------------------------------------------------------
# Concept map: XBRL tag -> canonical metric name
#
# Order matters within a metric: earlier tags win when a filer reports several.
# Only add a synonym when it is genuinely the same quantity — a near-miss here
# silently corrupts every ratio built on it.
# --------------------------------------------------------------------------

CONCEPT_MAP: dict[str, tuple[str, ...]] = {
    # Income statement
    "Revenues": (
        "RevenueFromContractWithCustomerExcludingAssessedTax",
        "RevenueFromContractWithCustomerIncludingAssessedTax",
        "Revenues",
        "SalesRevenueNet",
        "SalesRevenueGoodsNet",
    ),
    "CostOfRevenue": ("CostOfRevenue", "CostOfGoodsAndServicesSold", "CostOfGoodsSold"),
    "GrossProfit": ("GrossProfit",),
    "OperatingIncomeLoss": ("OperatingIncomeLoss",),
    "NetIncomeLoss": ("NetIncomeLoss", "ProfitLoss"),
    "ResearchAndDevelopmentExpense": ("ResearchAndDevelopmentExpense",),
    "SellingGeneralAndAdministrativeExpense": (
        "SellingGeneralAndAdministrativeExpense",
        "GeneralAndAdministrativeExpense",
    ),
    "InterestExpense": ("InterestExpense", "InterestIncomeExpenseNet"),
    "IncomeTaxExpenseBenefit": ("IncomeTaxExpenseBenefit",),
    "IncomeLossBeforeIncomeTaxes": (
        "IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest",
        "IncomeLossFromContinuingOperationsBeforeIncomeTaxesMinorityInterestAndIncomeLossFromEquityMethodInvestments",
    ),
    "DepreciationAndAmortization": (
        "DepreciationDepletionAndAmortization",
        "DepreciationAmortizationAndAccretionNet",
        "Depreciation",
    ),
    # Balance sheet
    "Assets": ("Assets",),
    "AssetsCurrent": ("AssetsCurrent",),
    "Liabilities": ("Liabilities",),
    "LiabilitiesCurrent": ("LiabilitiesCurrent",),
    "StockholdersEquity": (
        "StockholdersEquity",
        "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest",
    ),
    "CashAndCashEquivalents": (
        "CashAndCashEquivalentsAtCarryingValue",
        "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
    ),
    "InventoryNet": ("InventoryNet",),
    "AccountsReceivableNetCurrent": ("AccountsReceivableNetCurrent",),
    "PropertyPlantAndEquipmentNet": ("PropertyPlantAndEquipmentNet",),
    "LongTermDebtNoncurrent": ("LongTermDebtNoncurrent", "LongTermDebt"),
    "LongTermDebtCurrent": ("LongTermDebtCurrent",),
    "RetainedEarningsAccumulatedDeficit": ("RetainedEarningsAccumulatedDeficit",),
    "Goodwill": ("Goodwill",),
    "IntangibleAssetsNetExcludingGoodwill": ("IntangibleAssetsNetExcludingGoodwill",),
    # Cash flow
    "NetCashProvidedByOperatingActivities": (
        "NetCashProvidedByUsedInOperatingActivities",
        "NetCashProvidedByUsedInOperatingActivitiesContinuingOperations",
    ),
    "CapitalExpenditures": (
        "PaymentsToAcquirePropertyPlantAndEquipment",
        "PaymentsToAcquireProductiveAssets",
    ),
    "DividendsPaid": (
        "PaymentsOfDividendsCommonStock",
        "PaymentsOfDividends",
    ),
    # Shares
    "SharesOutstanding": (
        "CommonStockSharesOutstanding",
        "EntityCommonStockSharesOutstanding",
    ),
    "WeightedAverageDilutedShares": (
        "WeightedAverageNumberOfDilutedSharesOutstanding",
        "WeightedAverageNumberOfSharesOutstandingBasic",
    ),
    "EarningsPerShareDiluted": ("EarningsPerShareDiluted",),
}

#: Reverse index built once: xbrl tag -> (canonical name, preference rank).
_TAG_INDEX: dict[str, tuple[str, int]] = {
    tag: (metric, rank)
    for metric, tags in CONCEPT_MAP.items()
    for rank, tag in enumerate(tags)
}

VALID_FISCAL_PERIODS = frozenset({"FY", "Q1", "Q2", "Q3", "Q4"})


def canonical_metric(tag: str) -> tuple[str, int] | None:
    """Map an XBRL tag to our canonical metric name, or None if unmapped.

    Unmapped tags are skipped rather than stored under a made-up name — an
    unrecognised concept is not the same as a missing value.
    """
    return _TAG_INDEX.get(tag)


def _parse_date(raw: str | None) -> date | None:
    if not raw:
        return None
    try:
        return datetime.strptime(raw[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def _parse_decimal(raw: Any) -> Decimal | None:
    if raw is None:
        return None
    try:
        return Decimal(str(raw))
    except (InvalidOperation, ValueError):
        return None


def parse_company_facts(payload: dict, cik: str) -> list[FundamentalFact]:
    """Flatten a `companyfacts` document into canonical facts.

    Deliberately permissive about what it *skips* and strict about what it
    *keeps*: an entry without a `filed` date is dropped entirely, because a
    fact with no point-in-time key cannot be used safely by anything.
    """
    facts_root = payload.get("facts")
    if not isinstance(facts_root, dict):
        raise ProviderError(f"{SOURCE_NAME}: companyfacts payload has no 'facts' object")

    # metric key -> (rank, fact); a better-ranked tag replaces a worse one.
    best: dict[tuple, tuple[int, FundamentalFact]] = {}
    skipped_no_filed = 0

    for taxonomy, tags in facts_root.items():
        if not isinstance(tags, dict):
            continue
        for tag, tag_body in tags.items():
            mapped = canonical_metric(tag)
            if mapped is None:
                continue
            metric_name, rank = mapped

            units = (tag_body or {}).get("units")
            if not isinstance(units, dict):
                continue

            for unit, entries in units.items():
                if not isinstance(entries, list):
                    continue
                for entry in entries:
                    if not isinstance(entry, dict):
                        continue

                    filed = _parse_date(entry.get("filed"))
                    period_end = _parse_date(entry.get("end"))
                    if filed is None or period_end is None:
                        skipped_no_filed += 1
                        continue

                    fiscal_period = entry.get("fp")
                    if fiscal_period not in VALID_FISCAL_PERIODS:
                        fiscal_period = None

                    period_start = _parse_date(entry.get("start"))
                    if period_start is not None and period_start > period_end:
                        # Corrupt duration — skip rather than silently swap.
                        continue

                    try:
                        fact = FundamentalFact(
                            cik=cik,
                            metric_name=metric_name,
                            xbrl_tag=tag,
                            taxonomy=taxonomy,
                            value=_parse_decimal(entry.get("val")),
                            unit=unit,
                            period_start=period_start,
                            period_end=period_end,
                            fiscal_year=entry.get("fy"),
                            fiscal_period=fiscal_period,
                            filed_date=filed,
                            form_type=entry.get("form"),
                            accession_number=entry.get("accn"),
                            source=SOURCE_NAME,
                        )
                    except ValueError:
                        # Boundary validation rejected it; do not coerce.
                        continue

                    # One canonical value per (metric, period, filing). When a
                    # filer tags the same quantity twice, the preferred tag wins
                    # deterministically instead of by dict ordering.
                    key = (
                        metric_name,
                        period_start,
                        period_end,
                        fiscal_period,
                        filed,
                        fact.accession_number,
                        unit,
                    )
                    existing = best.get(key)
                    if existing is None or rank < existing[0]:
                        best[key] = (rank, fact)

    if skipped_no_filed:
        logger.info(
            "%s: skipped %d entries with no usable filed/end date for CIK %s",
            SOURCE_NAME,
            skipped_no_filed,
            cik,
        )

    facts = [fact for _, fact in best.values()]
    facts.sort(key=lambda f: (f.metric_name, f.period_end, f.filed_date))
    return facts


def parse_company_tickers(payload: dict) -> dict[str, str]:
    """`company_tickers.json` is a dict of positional records:
    {"0": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."}, ...}
    """
    mapping: dict[str, str] = {}
    for record in payload.values():
        if not isinstance(record, dict):
            continue
        ticker = record.get("ticker")
        cik = record.get("cik_str")
        if ticker and cik is not None:
            mapping[str(ticker).upper()] = str(cik).zfill(10)
    if not mapping:
        raise ProviderError(f"{SOURCE_NAME}: company_tickers.json produced no mappings")
    return mapping


def parse_submissions(payload: dict, cik: str) -> list[FilingRecord]:
    """Recent filings live in `filings.recent`, stored column-wise as parallel
    arrays rather than as a list of records.
    """
    recent = ((payload.get("filings") or {}).get("recent")) or {}
    accessions = recent.get("accessionNumber") or []
    forms = recent.get("form") or []
    filing_dates = recent.get("filingDate") or []
    report_dates = recent.get("reportDate") or []
    primary_docs = recent.get("primaryDocument") or []
    acceptance = recent.get("acceptanceDateTime") or []
    items = recent.get("items") or []

    records: list[FilingRecord] = []
    for i, accession in enumerate(accessions):
        filed = _parse_date(filing_dates[i] if i < len(filing_dates) else None)
        form = forms[i] if i < len(forms) else None
        if filed is None or not form:
            continue
        doc = primary_docs[i] if i < len(primary_docs) else None
        naked = str(accession).replace("-", "")
        url = (
            f"https://www.sec.gov/Archives/edgar/data/{int(cik)}/{naked}/{doc}" if doc else None
        )
        records.append(
            FilingRecord(
                cik=cik,
                accession_number=str(accession),
                form_type=str(form),
                filed_date=filed,
                acceptance_datetime=(acceptance[i] if i < len(acceptance) else None),
                period_of_report=_parse_date(report_dates[i] if i < len(report_dates) else None),
                primary_doc_url=url,
                items=(items[i] if i < len(items) else None) or None,
                source=SOURCE_NAME,
            )
        )
    return records


class EdgarProvider:
    """Satisfies FundamentalsProvider and FilingsProvider."""

    source_name = SOURCE_NAME

    def __init__(self, user_agent: str | None = None, client: HttpClient | None = None) -> None:
        if client is None:
            from invest.config import get_settings

            agent = user_agent or get_settings().edgar_user_agent
            if "@" not in agent:
                # EDGAR blocks requests without a contact address. Failing here
                # is friendlier than being IP-banned mid-backfill.
                raise ValueError(
                    "EDGAR_USER_AGENT must include a contact email, e.g. "
                    "'invest-research-platform you@example.com'. "
                    "SEC blocks clients that do not identify themselves."
                )
            client = HttpClient(
                source_name=SOURCE_NAME,
                user_agent=agent,
                rate_per_second=EDGAR_RATE_LIMIT,
            )
        self.client = client

    def _json(self, url: str) -> dict:
        response = self.client.get(url)
        try:
            payload = response.json()
        except ValueError as exc:
            raise ProviderError(f"{SOURCE_NAME}: non-JSON response from {url}") from exc
        if not isinstance(payload, dict):
            raise ProviderError(f"{SOURCE_NAME}: unexpected JSON shape from {url}")
        return payload

    def fetch_ticker_cik_map(self) -> dict[str, str]:
        return parse_company_tickers(self._json(COMPANY_TICKERS_URL))

    def fetch_company_facts(self, cik: str) -> list[FundamentalFact]:
        padded = str(cik).zfill(10)
        payload = self._json(COMPANY_FACTS_URL.format(cik=padded))
        return parse_company_facts(payload, padded)

    def fetch_filings(self, cik: str, forms: list[str] | None = None) -> list[FilingRecord]:
        padded = str(cik).zfill(10)
        records = parse_submissions(self._json(SUBMISSIONS_URL.format(cik=padded)), padded)
        if forms:
            wanted = {f.upper() for f in forms}
            records = [r for r in records if r.form_type.upper() in wanted]
        return records

    def fetch_form4_documents(self, cik: str, *, limit: int = 50) -> list[InsiderTransactionRecord]:
        """Fetch and parse recent Form 4 filings for an issuer.

        One request per filing, so this is the most rate-limit-hungry call in
        the system — hence `limit`, and hence the 8 rps token bucket. The
        filing index gives us the accession number and the authoritative filed
        date; the document itself gives us the transactions.
        """
        records: list[InsiderTransactionRecord] = []
        for filing in self.fetch_filings(cik, forms=["4"])[:limit]:
            try:
                xml_text = self.fetch_filing_document(filing)
            except ProviderError as exc:
                # One unreadable filing must not abandon the rest of the batch.
                logger.warning(
                    "%s: could not fetch Form 4 %s: %s", SOURCE_NAME, filing.accession_number, exc
                )
                continue
            try:
                records.extend(
                    parse_form4(
                        xml_text,
                        filed_date=filing.filed_date,
                        accession_number=filing.accession_number,
                    )
                )
            except ProviderError as exc:
                logger.warning(
                    "%s: could not parse Form 4 %s: %s", SOURCE_NAME, filing.accession_number, exc
                )
        return records

    def download_bulk_companyfacts(self, destination: str) -> str:
        """Download the full companyfacts archive to a local path.

        One request instead of one per company. At 21 tickers that is a
        convenience; at 500 it is the difference between a polite client and
        a rude one, and the SEC publishes this file precisely so nobody has to
        hammer the per-company endpoint.

        The archive is large — several gigabytes uncompressed — so it streams
        to disk rather than through memory.
        """
        logger.info("%s: downloading bulk companyfacts to %s", SOURCE_NAME, destination)
        written = self.client.stream_to_file(BULK_COMPANYFACTS_URL, destination)
        logger.info("%s: wrote %.1f MB", SOURCE_NAME, written / 1e6)
        return destination

    def fetch_filing_document(self, filing: FilingRecord) -> str:
        """Fetch a filing's primary document as text.

        Form 4 primary documents are XML. EDGAR sometimes lists the rendered
        HTML wrapper as primary instead, so fall back to the canonical
        `<accession>.txt` submission when the primary is not XML.
        """
        url = filing.primary_doc_url
        if url and url.lower().endswith(".xml"):
            return self.client.get(url).text

        naked = filing.accession_number.replace("-", "")
        fallback = (
            f"https://www.sec.gov/Archives/edgar/data/{int(filing.cik)}/{naked}/"
            f"{filing.accession_number}.txt"
        )
        return self.client.get(fallback).text

    def close(self) -> None:
        self.client.close()


def iter_bulk_companyfacts(archive_path: str, ciks: set[str] | None = None):
    """Yield (cik, facts) from a bulk companyfacts archive.

    Entries are named `CIK##########.json` and hold exactly the payload the
    per-company endpoint returns, so the same parser handles both — the bulk
    path is a different delivery mechanism, not a different format, and gets
    no second implementation to drift.

    `ciks` filters to the universe you care about without unpacking the rest.
    """
    import json
    import zipfile

    wanted = {c.zfill(10) for c in ciks} if ciks else None

    with zipfile.ZipFile(archive_path) as archive:
        for name in archive.namelist():
            if not name.endswith(".json"):
                continue
            stem = pathlib.Path(name).stem  # CIK0000320193
            cik = stem.upper().removeprefix("CIK").zfill(10)
            if wanted is not None and cik not in wanted:
                continue
            try:
                with archive.open(name) as handle:
                    payload = json.load(handle)
            except (json.JSONDecodeError, KeyError) as exc:
                logger.warning("%s: unreadable bulk entry %s: %s", SOURCE_NAME, name, exc)
                continue
            try:
                yield cik, parse_company_facts(payload, cik)
            except ProviderError as exc:
                # One malformed company must not abandon the other 10,000.
                logger.warning("%s: skipping %s in bulk archive: %s", SOURCE_NAME, cik, exc)
