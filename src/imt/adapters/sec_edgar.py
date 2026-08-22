"""SEC EDGAR: discovery and document retrieval.

Two discovery paths, for different jobs:

* **daily index** — everything filed on one day, across all filers. This is the
  primary loop: cheap, complete, and the only way to notice a filing by a
  company you were not already watching.
* **submissions** — one company's filing history. Used for backfill and for
  the universe's 10-K/10-Q inclusion test.

``public_available_at`` is computed here rather than at ingest, because it is a
property of the filing and getting it wrong quietly invalidates every backtest
(SPEC §7.1). A filing accepted after 16:00 ET could not be acted on until the
next session's open.
"""

from __future__ import annotations

import json
from datetime import date, datetime, time, timedelta
from typing import Any

from imt.adapters.records import FilingRef
from imt.core.clock import MARKET_TZ
from imt.core.http import HttpClient
from imt.core.logging import get_logger
from imt.entities.identifiers import normalize_cik

log = get_logger(__name__)

SOURCE_ID = "sec_edgar"

SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik}.json"
COMPANY_TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
# company_tickers.json carries no exchange; this file does, with a different
# shape (fields + data arrays). The universe builder needs both -- see
# docs/ARCHITECTURE.md §C.1.
COMPANY_TICKERS_EXCHANGE_URL = "https://www.sec.gov/files/company_tickers_exchange.json"
DAILY_INDEX_URL = (
    "https://www.sec.gov/Archives/edgar/daily-index/{year}/QTR{quarter}/form.{stamp}.idx"
)
ARCHIVE_BASE = "https://www.sec.gov/Archives/edgar/data"

#: SPEC §7.1. After this, the first tradable moment is the next session's open.
MARKET_CLOSE = time(16, 0)


def public_available_at(filed: date, acceptance: datetime | None) -> datetime:
    """When a filing could first have been acted upon.

    This is the backtest's entry clock and nothing else may be used for it.
    With no acceptance timestamp we assume the close of the filing date, which
    is the conservative choice: assuming the open would let a backtest trade on
    information that may not have existed yet.
    """
    if acceptance is None:
        return datetime.combine(filed, MARKET_CLOSE, tzinfo=MARKET_TZ)
    local = acceptance.astimezone(MARKET_TZ)
    if local.time() < MARKET_CLOSE:
        return local
    # Accepted after the close: the next session's open. Weekends roll forward;
    # market holidays are not modelled here, which makes this slightly
    # conservative rather than optimistic, and that is the right direction.
    following = local.date() + timedelta(days=1)
    while following.weekday() >= 5:
        following += timedelta(days=1)
    return datetime.combine(following, time(9, 30), tzinfo=MARKET_TZ)


def _parse_acceptance(raw: str | None) -> datetime | None:
    if not raw:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d %H:%M:%S"):
        try:
            parsed = datetime.strptime(raw, fmt)  # noqa: DTZ007
        except ValueError:
            continue
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=MARKET_TZ)
    return None


def _accession_path(cik: str, accession: str) -> str:
    return f"{ARCHIVE_BASE}/{int(cik)}/{accession.replace('-', '')}"


class SecEdgarAdapter:
    """Fetches through ``core.http``; never constructs its own client."""

    source_id = SOURCE_ID

    def __init__(self, client: HttpClient) -> None:
        self._client = client

    # ---------------------------------------------------------------- tickers

    def company_tickers(self) -> list[dict[str, Any]]:
        """CIK↔ticker map. Snapshotted daily with history retained (SPEC §2)."""
        payload = self._client.get(SOURCE_ID, COMPANY_TICKERS_URL).json()
        # Shape is {"0": {cik_str, ticker, title}, ...} -- an object keyed by
        # index, not an array.
        rows = payload.values() if isinstance(payload, dict) else payload
        return [
            {
                "cik": normalize_cik(row["cik_str"]),
                "ticker": str(row["ticker"]).upper(),
                "name": row["title"],
            }
            for row in rows
        ]

    def company_tickers_with_exchange(self) -> list[dict[str, Any]]:
        """The exchange-bearing file. Different shape: fields + data arrays."""
        payload = self._client.get(SOURCE_ID, COMPANY_TICKERS_EXCHANGE_URL).json()
        fields = [str(f) for f in payload["fields"]]
        index = {name: position for position, name in enumerate(fields)}
        out: list[dict[str, Any]] = []
        for row in payload["data"]:
            out.append(
                {
                    "cik": normalize_cik(row[index["cik"]]),
                    "name": row[index["name"]],
                    "ticker": str(row[index["ticker"]]).upper(),
                    "exchange": row[index["exchange"]],
                }
            )
        return out

    # ------------------------------------------------------------ submissions

    def submissions(self, cik: str) -> list[FilingRef]:
        """One company's recent filings."""
        cik = normalize_cik(cik)
        payload = self._client.get(SOURCE_ID, SUBMISSIONS_URL.format(cik=cik)).json()
        return list(parse_submissions(payload, cik=cik))

    # ------------------------------------------------------------ daily index

    def daily_index(self, day: date) -> list[FilingRef]:
        """Everything filed on one day. The primary discovery loop."""
        quarter = (day.month - 1) // 3 + 1
        url = DAILY_INDEX_URL.format(year=day.year, quarter=quarter, stamp=day.strftime("%Y%m%d"))
        response = self._client.get(SOURCE_ID, url)
        if response.status_code == 404:
            # Weekends and holidays have no index. Not an error.
            log.info("edgar.no_daily_index", day=day.isoformat())
            return []
        return list(parse_daily_index(response.text(), filed_date=day))

    def document(self, url: str) -> bytes:
        return self._client.get(SOURCE_ID, url).body


def parse_submissions(payload: dict[str, Any], *, cik: str) -> list[FilingRef]:
    """Pure parse of a submissions JSON document.

    Split out so it can be tested without HTTP, and so the whole corpus can be
    re-parsed from ``raw_documents`` after a parser fix.
    """
    recent = payload.get("filings", {}).get("recent", {})
    if not recent:
        return []
    name = payload.get("name")

    columns = (
        "accessionNumber",
        "form",
        "filingDate",
        "acceptanceDateTime",
        "primaryDocument",
        "items",
    )
    series = {key: recent.get(key, []) for key in columns}
    count = len(series["accessionNumber"])
    refs: list[FilingRef] = []

    for i in range(count):
        accession = series["accessionNumber"][i]
        filed_raw = series["filingDate"][i]
        try:
            filed = date.fromisoformat(filed_raw)
        except (TypeError, ValueError):
            log.info("edgar.bad_filing_date", accession=accession, raw=filed_raw)
            continue
        primary = series["primaryDocument"][i] if i < len(series["primaryDocument"]) else ""
        refs.append(
            FilingRef(
                accession=accession,
                cik=cik,
                form_type=series["form"][i],
                filed_date=filed,
                primary_doc_url=f"{_accession_path(cik, accession)}/{primary}",
                acceptance_datetime=_parse_acceptance(
                    series["acceptanceDateTime"][i]
                    if i < len(series["acceptanceDateTime"])
                    else None
                ),
                company_name=name,
            )
        )
    return refs


#: Header labels, in column order, as they appear in form.YYYYMMDD.idx.
_INDEX_COLUMNS = ("Form Type", "Company Name", "CIK", "Date Filed", "File Name")


def _column_offsets(header: str) -> list[int] | None:
    """Start offset of each column, read from the header line.

    The file is fixed-width. Splitting on whitespace breaks on company names
    ("BETA CORP OF AMERICA") and on form types that contain spaces ("SC 13D"),
    and anchoring from the right breaks because the CIK also appears inside the
    file path. Reading the header is the only approach that survives all three.
    """
    offsets: list[int] = []
    cursor = 0
    for label in _INDEX_COLUMNS:
        position = header.find(label, cursor)
        if position < 0:
            return None
        offsets.append(position)
        cursor = position + len(label)
    return offsets


def parse_daily_index(text: str, *, filed_date: date) -> list[FilingRef]:
    """Parse a form.YYYYMMDD.idx file.

    Fixed-width, with a dashed separator under a header row. The column layout
    has shifted historically, so offsets come from the header rather than being
    assumed.
    """
    lines = text.splitlines()
    separator = next((i for i, line in enumerate(lines) if set(line.strip()) == {"-"}), None)
    if separator is None or separator == 0:
        log.warning("edgar.daily_index_no_separator", day=filed_date.isoformat())
        return []

    offsets = _column_offsets(lines[separator - 1])
    if offsets is None:
        log.warning("edgar.daily_index_unrecognised_header", day=filed_date.isoformat())
        return []

    refs: list[FilingRef] = []
    for line in lines[separator + 1 :]:
        if not line.strip():
            continue
        fields = _split_index_line(line, offsets)
        if fields is None:
            continue
        form_type, company, cik_raw, _date_filed, path = fields
        try:
            cik = normalize_cik(cik_raw)
        except ValueError:
            log.info("edgar.bad_index_cik", raw=cik_raw)
            continue
        accession = path.rsplit("/", 1)[-1].removesuffix(".txt")
        refs.append(
            FilingRef(
                accession=accession,
                cik=cik,
                form_type=form_type,
                filed_date=filed_date,
                primary_doc_url=f"https://www.sec.gov/Archives/{path}",
                company_name=company or None,
            )
        )
    return refs


def _split_index_line(line: str, offsets: list[int]) -> tuple[str, str, str, str, str] | None:
    """Slice one .idx row at the header's column offsets."""
    bounds = [*offsets, len(line) + 1]
    fields = [line[bounds[i] : bounds[i + 1]].strip() for i in range(len(offsets))]
    form_type, company, cik, date_filed, path = fields
    if not form_type or not cik or not path:
        return None
    return form_type, company, cik, date_filed, path


def parse_company_tickers(payload: Any) -> list[dict[str, Any]]:
    """Pure parse, for tests and for re-parsing from raw_documents."""
    rows = payload.values() if isinstance(payload, dict) else payload
    return [
        {
            "cik": normalize_cik(row["cik_str"]),
            "ticker": str(row["ticker"]).upper(),
            "name": row["title"],
        }
        for row in rows
    ]


def load_json(payload: bytes) -> Any:
    return json.loads(payload)
