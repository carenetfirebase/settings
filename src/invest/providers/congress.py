"""Congressional trade disclosures — House Clerk and Senate eFD.

FIREWALLED. Everything this module produces is stored with
`firewall_status='investigate_only'` and can never reach a score. That is a
deliberate design decision, not an oversight, and the reasons are worth
stating because the temptation to score this data is strong:

1. **The disclosure lag destroys most of the edge.** The STOCK Act allows 30-45
   days, and late filings are routine and weakly penalised. By the time a trade
   is public the information that motivated it is usually priced in.
2. **Amount ranges are uselessly wide.** Disclosures report brackets
   ($1,001-$15,000, $50,001-$100,000, and so on), so position sizing cannot be
   inferred. The midpoint of a bracket is an invention, and this module stores
   both bounds rather than one made-up number.
3. **The dataset is survivorship-biased in how it reaches you.** Profitable
   congressional trades get written up; the boring majority does not. Fitting a
   signal to the trades that became news is fitting to a filtered sample.
4. **Attribution is ambiguous.** Filings cover spouses, dependent children and
   blind trusts, and the filer often did not make the decision.

So: useful context when reading about a company, never an input to a number.

## Data shape

The House Clerk publishes annual ZIP archives of financial disclosures, with
an XML index of filings plus PDF documents. The Senate eFD is a search-based
web application. **Neither offers a clean structured feed of transactions**,
and the per-transaction detail lives in PDFs whose layout varies by filer.

This module therefore parses the *structured formats that do exist* — the
House XML filing index, and CSV exports in the layout the community datasets
use — and stops there. It does not attempt PDF table extraction, because a
mis-parsed PDF row would put a fabricated number in the database, and that is
worse than having no row at all.
"""

from __future__ import annotations

import csv
import io
import logging
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from xml.etree import ElementTree

from invest.providers.base import PoliticalTradeRecord, ProviderError

logger = logging.getLogger(__name__)

HOUSE_SOURCE = "house_clerk"
SENATE_SOURCE = "senate_efd"

HOUSE_DISCLOSURE_INDEX = "https://disclosures-clerk.house.gov/public_disc/financial-pdfs/{year}FD.ZIP"
SENATE_EFD_SEARCH = "https://efdsearch.senate.gov/search/"


# --------------------------------------------------------------------------
# Amount ranges
#
# Disclosures report brackets, not amounts. Both bounds are stored; no
# midpoint is ever computed, because a midpoint is a number nobody reported.
# --------------------------------------------------------------------------

AMOUNT_RANGES: dict[str, tuple[Decimal, Decimal | None]] = {
    "$1,001 - $15,000": (Decimal(1001), Decimal(15000)),
    "$15,001 - $50,000": (Decimal(15001), Decimal(50000)),
    "$50,001 - $100,000": (Decimal(50001), Decimal(100000)),
    "$100,001 - $250,000": (Decimal(100001), Decimal(250000)),
    "$250,001 - $500,000": (Decimal(250001), Decimal(500000)),
    "$500,001 - $1,000,000": (Decimal(500001), Decimal(1000000)),
    "$1,000,001 - $5,000,000": (Decimal(1000001), Decimal(5000000)),
    "$5,000,001 - $25,000,000": (Decimal(5000001), Decimal(25000000)),
    "$25,000,001 - $50,000,000": (Decimal(25000001), Decimal(50000000)),
    "Over $50,000,000": (Decimal(50000000), None),
    "$1,000 - $15,000": (Decimal(1000), Decimal(15000)),
}


def parse_amount_range(raw: str | None) -> tuple[Decimal | None, Decimal | None]:
    """Parse a disclosure bracket into (low, high).

    An open-ended top bracket returns `high=None` — genuinely unbounded, not
    capped at the lower figure. Unrecognised text returns (None, None) rather
    than a guess.
    """
    if not raw:
        return None, None

    normalized = " ".join(raw.split()).replace("–", "-").replace("—", "-")
    if normalized in AMOUNT_RANGES:
        return AMOUNT_RANGES[normalized]

    # Fall back to extracting two currency figures from free text.
    figures = re.findall(r"\$\s?([\d,]+)", normalized)
    parsed: list[Decimal] = []
    for figure in figures:
        try:
            parsed.append(Decimal(figure.replace(",", "")))
        except InvalidOperation:
            continue

    if len(parsed) >= 2:
        return min(parsed), max(parsed)
    if len(parsed) == 1:
        if "over" in normalized.lower() or "+" in normalized:
            return parsed[0], None
        return parsed[0], parsed[0]

    logger.info("unrecognised amount range %r — storing as unknown", raw)
    return None, None


# --------------------------------------------------------------------------
# Transaction types
# --------------------------------------------------------------------------

#: Single-letter filing codes. Matched EXACTLY — a prefix match here would
#: read "something else" as a sale, which is how silent data corruption starts.
SINGLE_LETTER_CODES = {"p": "purchase", "s": "sale", "e": "exchange"}

#: Word forms, matched as a prefix so "Sale (Partial)" and "Purchase (Full)"
#: both resolve.
WORD_PREFIXES = (
    ("purchase", "purchase"),
    ("buy", "purchase"),
    ("sale", "sale"),
    ("sold", "sale"),
    ("sell", "sale"),
    ("exchange", "exchange"),
)


def normalize_transaction_type(raw: str | None) -> str | None:
    """Map filer-specific wording onto purchase / sale / exchange.

    'Sale (Partial)' and 'Sale (Full)' both normalise to 'sale'. The
    partial/full distinction is not lost — it stays in the source row, since
    this function does not overwrite anything.

    Anything unrecognised returns None rather than a best guess.
    """
    if not raw:
        return None
    text = raw.strip().lower()

    if text in SINGLE_LETTER_CODES:
        return SINGLE_LETTER_CODES[text]

    for prefix, normalized in WORD_PREFIXES:
        if text.startswith(prefix):
            return normalized
    return None


TICKER_PATTERN = re.compile(r"^[A-Z][A-Z.\-]{0,9}$")


def clean_ticker(raw: str | None) -> str | None:
    """Extract a plausible ticker, or None.

    Disclosures frequently carry '--', 'N/A', a fund name, or a description
    instead of a symbol. Returning None keeps `ticker_raw` honest; a bad
    ticker would silently attribute one company's disclosures to another.
    """
    if not raw:
        return None
    text = raw.strip().upper().strip("$")
    if text in ("", "--", "-", "N/A", "NA", "NONE", "UNKNOWN"):
        return None
    if not TICKER_PATTERN.match(text):
        return None
    return text


def _parse_date(raw: str | None) -> date | None:
    if not raw:
        return None
    text = raw.strip()
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%d %B %Y", "%B %d, %Y"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    return None


# --------------------------------------------------------------------------
# House Clerk XML filing index
# --------------------------------------------------------------------------


def parse_house_index(xml_text: str) -> list[dict]:
    """Parse the House Clerk annual filing index.

    This is an index of *filings*, not transactions — it tells you who filed
    what and when, and gives the document ID needed to retrieve the PDF. The
    transactions themselves are inside those PDFs.

    Returned as plain dicts rather than PoliticalTradeRecord because an index
    entry is not a trade, and pretending otherwise would invite exactly the
    fabrication this module exists to avoid.
    """
    try:
        root = ElementTree.fromstring(xml_text)
    except ElementTree.ParseError as exc:
        raise ProviderError(f"{HOUSE_SOURCE}: filing index is not well-formed XML: {exc}") from exc

    def text_of(member, tag: str) -> str | None:
        node = member.find(tag)
        if node is None or node.text is None:
            return None
        value = node.text.strip()
        return value or None

    filings: list[dict] = []
    for member in root.iter("Member"):
        filed = _parse_date(text_of(member, "FilingDate"))
        last = text_of(member, "Last")
        first = text_of(member, "First")
        if filed is None or not last:
            continue

        filings.append(
            {
                "name": " ".join(part for part in (first, last) if part),
                "state": text_of(member, "StateDst"),
                "filing_type": text_of(member, "FilingType"),
                "year": text_of(member, "Year"),
                "filing_date": filed,
                "doc_id": text_of(member, "DocID"),
            }
        )
    return filings


# --------------------------------------------------------------------------
# CSV transaction exports
# --------------------------------------------------------------------------

#: Column aliases seen across the community-maintained disclosure exports.
COLUMN_ALIASES: dict[str, tuple[str, ...]] = {
    "name": ("representative", "senator", "name", "member", "politician"),
    "ticker": ("ticker", "symbol", "asset_ticker"),
    "asset_description": ("asset_description", "asset", "asset_name", "description"),
    "transaction_type": ("type", "transaction_type", "transaction"),
    "transaction_date": ("transaction_date", "date", "trade_date"),
    "disclosure_date": ("disclosure_date", "notification_date", "filed_date", "date_received"),
    "amount": ("amount", "amount_range", "value", "range"),
    "chamber": ("chamber", "house_senate"),
    "state": ("state", "district"),
}


def _resolve_columns(header: list[str]) -> dict[str, str]:
    normalized = {column.strip().lower().replace(" ", "_"): column for column in header}
    resolved: dict[str, str] = {}
    for field, aliases in COLUMN_ALIASES.items():
        for alias in aliases:
            if alias in normalized:
                resolved[field] = normalized[alias]
                break
    return resolved


def parse_disclosure_csv(
    text: str, *, source: str = HOUSE_SOURCE, default_chamber: str | None = None
) -> list[PoliticalTradeRecord]:
    """Parse a structured CSV export of congressional transactions.

    Column names vary between sources, so aliases are resolved rather than
    assuming a fixed layout. A row missing either date is skipped: both the
    transaction date and the disclosure date are required, because the gap
    between them is the only genuinely interesting thing in this dataset.
    """
    stripped = text.strip()
    if not stripped:
        return []

    reader = csv.DictReader(io.StringIO(stripped))
    if reader.fieldnames is None:
        raise ProviderError(f"{source}: CSV has no header row")

    columns = _resolve_columns(list(reader.fieldnames))
    for required in ("name", "transaction_date", "disclosure_date"):
        if required not in columns:
            raise ProviderError(
                f"{source}: CSV is missing a column for {required!r}; "
                f"found {reader.fieldnames!r}. Refusing to guess the layout."
            )

    records: list[PoliticalTradeRecord] = []
    skipped = 0

    def make_cell_reader(source_row: dict):
        """Bind the row explicitly rather than closing over the loop variable."""

        def cell(field: str) -> str | None:
            column = columns.get(field)
            if column is None:
                return None
            value = (source_row.get(column) or "").strip()
            return value or None

        return cell

    for row in reader:
        cell = make_cell_reader(row)

        transaction_date = _parse_date(cell("transaction_date"))
        disclosure_date = _parse_date(cell("disclosure_date"))
        name = cell("name")

        if transaction_date is None or disclosure_date is None or not name:
            skipped += 1
            continue

        if disclosure_date < transaction_date:
            # Nonsense ordering — the whole point of storing both dates is the
            # lag between them, so a negative lag is a corrupt row.
            skipped += 1
            continue

        low, high = parse_amount_range(cell("amount"))
        chamber = (cell("chamber") or default_chamber or "").strip().lower() or None

        try:
            records.append(
                PoliticalTradeRecord(
                    politician_name=name,
                    chamber=chamber,
                    state=(cell("state") or None),
                    ticker_raw=clean_ticker(cell("ticker")),
                    asset_description=cell("asset_description"),
                    transaction_type=normalize_transaction_type(cell("transaction_type")),
                    transaction_date=transaction_date,
                    disclosure_date=disclosure_date,
                    amount_range_low=low,
                    amount_range_high=high,
                    source=source,
                )
            )
        except ValueError as exc:
            logger.info("%s: rejected a disclosure row: %s", source, exc)
            skipped += 1

    if skipped:
        logger.info("%s: skipped %d unusable disclosure rows", source, skipped)
    return records


class CongressProvider:
    """Satisfies PoliticalDisclosureProvider.

    Deliberately limited: it parses the structured formats that exist and
    refuses to invent the ones that do not. `fetch_disclosures` returns []
    when given no local export, rather than scraping PDFs and guessing.
    """

    source_name = HOUSE_SOURCE

    def __init__(self, client=None) -> None:
        self.client = client

    def fetch_disclosures(
        self, start: date | None = None, end: date | None = None
    ) -> list[PoliticalTradeRecord]:
        """No automated transaction feed exists on the official sources.

        The House publishes PDFs; the Senate publishes a search UI. Extracting
        per-transaction rows means PDF table parsing whose failure mode is a
        plausible-looking wrong number — precisely what the ground rules
        forbid. Use `load_csv_export` with a structured file instead.
        """
        logger.warning(
            "%s: no structured transaction feed is published. Supply a CSV export "
            "via `invest ingest political --file`.",
            self.source_name,
        )
        return []

    def load_csv_export(
        self, text: str, *, source: str | None = None, default_chamber: str | None = None
    ) -> list[PoliticalTradeRecord]:
        return parse_disclosure_csv(
            text, source=source or self.source_name, default_chamber=default_chamber
        )

    def fetch_house_filing_index(self, year: int) -> list[dict]:
        """Fetch the House Clerk's annual index of filings (not transactions)."""
        if self.client is None:
            raise ProviderError(f"{HOUSE_SOURCE}: no HTTP client configured")
        response = self.client.get(HOUSE_DISCLOSURE_INDEX.format(year=year))
        return parse_house_index(response.text)
