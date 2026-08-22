"""Congressional periodic transaction reports.

Two paths into the same records:

* **House PDF pipeline** — index ZIP, then per-filing PDFs, many of them
  scanned images and some handwritten. Text extraction, OCR fallback, review
  queue. Not built here: it needs Tesseract and network access, and
  DATA_SOURCES budgets it as its own phase.
* **Manual CSV** — ``imt ingest congress --from-csv``. The spec's explicit
  fallback so a stalled parser never blocks the rest of the system, and the
  only path for the Senate in V1 (session auth plus bot protection make
  automated retrieval unreliable, DATA_SOURCES Tier 3).

## Amounts are brackets, and stay brackets

The STOCK Act reports ranges: $1,001–$15,000, $15,001–$50,000, and so on. This
module returns ``value_low_minor`` and ``value_high_minor`` and there is no
single-amount field anywhere in the chain. A midpoint is an estimate, and an
estimate stored in a column called ``amount`` is read as a fact six months
later by someone who was not here for this conversation. The midpoint exists
only as a derived feature carrying the reason code
``derived_bracket_midpoint`` (SPEC §8).

## The lag is the point

``transaction_date`` and ``disclosure_date`` are both required. A PTR filed
today may cover a trade made 45 days ago, and every part of this system —
schema constraint, freshness half-life, UI row — is built to keep those two
dates visible and separate.
"""

from __future__ import annotations

import csv
import io
import re
from datetime import date, datetime

from imt.adapters.records import PoliticalTradeRecord
from imt.core.logging import get_logger

log = get_logger(__name__)

SOURCE_ID_HOUSE = "house_ptr"
SOURCE_ID_SENATE = "senate_efd"

#: STOCK Act disclosure brackets, in dollars. The upper bound of the top
#: bracket is open-ended ("over $50,000,000"); it is capped at the lower bound
#: rather than invented, and the row carries that as its high value.
BRACKETS: tuple[tuple[int, int], ...] = (
    (1_001, 15_000),
    (15_001, 50_000),
    (50_001, 100_000),
    (100_001, 250_000),
    (250_001, 500_000),
    (500_001, 1_000_000),
    (1_000_001, 5_000_000),
    (5_000_001, 25_000_000),
    (25_000_001, 50_000_000),
    (50_000_001, 50_000_001),
)

_AMOUNT = re.compile(r"\$?\s*([\d,]+)(?:\s*(?:-|–|—|to)\s*\$?\s*([\d,]+))?", re.I)
_OVER = re.compile(r"over\s*\$?\s*([\d,]+)", re.I)

_BUY_WORDS = ("purchase", "buy", "p")
_SELL_WORDS = ("sale", "sold", "sell", "s", "exchange")

_OWNER_MAP = {
    "self": "self",
    "sp": "spouse",
    "spouse": "spouse",
    "dc": "dependent",
    "child": "dependent",
    "dependent": "dependent",
    "jt": "joint",
    "joint": "joint",
}


class PtrParseError(ValueError):
    pass


def parse_amount_bracket(raw: str) -> tuple[int, int]:
    """Return ``(low_minor, high_minor)`` in cents.

    Never returns a midpoint and never invents a bound. "Over $50,000,000"
    sets both ends to the stated floor, because the true ceiling is unknown
    and picking one would be fabrication.
    """
    text = (raw or "").strip()
    if not text:
        raise PtrParseError("empty amount")

    over = _OVER.search(text)
    if over:
        floor = int(over.group(1).replace(",", ""))
        return floor * 100, floor * 100

    match = _AMOUNT.search(text)
    if not match:
        raise PtrParseError(f"unrecognised amount: {raw!r}")

    low = int(match.group(1).replace(",", ""))
    high = int(match.group(2).replace(",", "")) if match.group(2) else None

    if high is None:
        # A single figure: snap to the bracket containing it, because the
        # source reports brackets and a lone number is a formatting variant
        # rather than a precise amount.
        for bracket_low, bracket_high in BRACKETS:
            if bracket_low <= low <= bracket_high:
                return bracket_low * 100, bracket_high * 100
        return low * 100, low * 100

    if high < low:
        raise PtrParseError(f"inverted amount range: {raw!r}")
    return low * 100, high * 100


def normalize_transaction_type(raw: str) -> str:
    """Map filer wording to purchase / sale / exchange / other.

    Not "buy" and "sell": those are banned copy (UI_SPEC §5) and these values
    reach the screen directly, in the donut legend and the feed headline.
    "Purchase" and "sale" are also the words the filings themselves use.

    Anything unrecognised stays ``other`` rather than being forced into buy or
    sell — the donut's "Other" slice is a real category, and guessing here
    would put fabricated direction into a chart.
    """
    text = (raw or "").strip().lower()
    if not text:
        return "other"

    def matches(words: tuple[str, ...]) -> bool:
        # Single-letter filing codes match EXACTLY. Prefix-matching them turns
        # "something odd" into a sale and "partial distribution" into a
        # purchase, which puts fabricated direction into the donut.
        return any(text == w or (len(w) > 1 and text.startswith(w)) for w in words)

    if matches(_BUY_WORDS):
        return "purchase"
    if text in {"e", "exchange"}:
        return "exchange"
    if matches(_SELL_WORDS):
        return "sale"
    return "other"


def normalize_owner(raw: str) -> str:
    """Self, spouse, dependent, joint, or unknown.

    SPEC §8 keeps this as a distinct feature rather than collapsing filers into
    one actor: "Senator X bought" is wrong when the filing describes a
    dependent child's account.
    """
    return _OWNER_MAP.get((raw or "").strip().lower(), "unknown")


def _parse_date(raw: str) -> date:
    text = (raw or "").strip()
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%d %B %Y", "%B %d, %Y"):
        try:
            return datetime.strptime(text, fmt).date()  # noqa: DTZ007
        except ValueError:
            continue
    raise PtrParseError(f"unrecognised date: {raw!r}")


#: Column aliases. Community CSV exports and hand-built imports differ in
#: header naming, and rejecting a file over a header spelling would push the
#: user back to the PDF pipeline this path exists to avoid.
_COLUMNS: dict[str, tuple[str, ...]] = {
    "filer": ("filer", "filer_name", "representative", "senator", "name", "member"),
    "chamber": ("chamber", "house_senate"),
    "owner": ("owner", "owner_type"),
    "asset": ("asset", "asset_description", "ticker_description", "security"),
    "type": ("type", "transaction_type", "transaction"),
    "transaction_date": ("transaction_date", "date", "txn_date", "trade_date"),
    "disclosure_date": ("disclosure_date", "filed_date", "notification_date", "report_date"),
    "amount": ("amount", "amount_range", "value", "range"),
    "doc_id": ("doc_id", "document_id", "ptr_id", "record_id"),
    "url": ("url", "document_url", "link", "ptr_link"),
}


def _pick(row: dict[str, str], key: str) -> str:
    lowered = {(k or "").strip().lower(): (v or "") for k, v in row.items()}
    for alias in _COLUMNS[key]:
        if alias in lowered and lowered[alias].strip():
            return lowered[alias].strip()
    return ""


def parse_csv(
    text: str, *, default_chamber: str = "house", source_id: str = SOURCE_ID_HOUSE
) -> tuple[list[PoliticalTradeRecord], list[str]]:
    """Parse a manual PTR import. Returns ``(records, errors)``.

    Bad rows are collected and reported rather than aborting the file: a single
    unparseable date in a 900-row export should not cost the other 899, and a
    silent skip would make the count wrong without saying so.
    """
    records: list[PoliticalTradeRecord] = []
    errors: list[str] = []

    reader = csv.DictReader(io.StringIO(text.strip()))
    for line_number, row in enumerate(reader, start=2):
        try:
            transaction_date = _parse_date(_pick(row, "transaction_date"))
            disclosure_date = _parse_date(_pick(row, "disclosure_date"))
            if disclosure_date < transaction_date:
                # Physically impossible: a trade cannot be disclosed before it
                # happened. Usually a swapped column, and letting it through
                # would produce a negative lag that the schema rejects anyway.
                raise PtrParseError(
                    f"disclosure {disclosure_date} precedes transaction {transaction_date}"
                )

            low, high = parse_amount_bracket(_pick(row, "amount"))
            filer = _pick(row, "filer")
            if not filer:
                raise PtrParseError("no filer name")

            asset = _pick(row, "asset")
            if not asset:
                raise PtrParseError("no asset description")

            doc_id = _pick(row, "doc_id") or f"manual-{line_number}"
            chamber = (_pick(row, "chamber") or default_chamber).strip().lower()

            records.append(
                PoliticalTradeRecord(
                    filer_name=filer,
                    filer_id=filer.upper().replace(" ", "_"),
                    chamber="senate" if chamber.startswith("s") else "house",
                    owner_type=normalize_owner(_pick(row, "owner")),
                    asset_description=asset,
                    transaction_type=normalize_transaction_type(_pick(row, "type")),
                    transaction_date=transaction_date,
                    disclosure_date=disclosure_date,
                    value_low_minor=low,
                    value_high_minor=high,
                    parse_outcome="manual_import",
                    source_record_id=doc_id,
                    document_url=_pick(row, "url") or "",
                )
            )
        except PtrParseError as exc:
            errors.append(f"line {line_number}: {exc}")
            log.info("ptr.row_rejected", line=line_number, error=str(exc))

    return records, errors


def bracket_midpoint_minor(low_minor: int, high_minor: int) -> int:
    """Derived feature only. Never stored as a fact.

    Callers stamp ``derived_bracket_midpoint`` as the reason code so the
    estimate is traceable wherever it surfaces.
    """
    return (low_minor + high_minor) // 2
