"""Stooq EOD prices. Primary market-data source (SPEC §4).

Two limitations that must reach the screen rather than staying in this
docstring:

* **Adjusted-only.** The series is split- and dividend-adjusted, and adjusted
  retroactively — a split today restates every historical bar. That is fine for
  return-based event studies and wrong for anything needing the price level as
  it actually was. `is_adjusted` is always True and the UI says so.
* **Undocumented rate limits, enforced by banning.** Fetching 4,000 symbols
  individually every day is the fastest way to lose this source
  (ARCHITECTURE §C.3). The daily job reads the bulk archive; per-symbol calls
  are for filling gaps only, and the limiter is set to 0.5/s in
  config/sources.yaml.

Pulled into Phase 2 rather than Phase 7 because Phase 3's "stock already up
>50% in 90 days" contradiction check and all of Phase 8 depend on prices.
"""

from __future__ import annotations

import csv
import io
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from imt.adapters.records import PriceBar
from imt.core.http import HttpClient
from imt.core.logging import get_logger

log = get_logger(__name__)

SOURCE_ID = "stooq"
DAILY_URL = "https://stooq.com/q/d/l/"

#: Stooq suffixes US listings. Index symbols start with ^ and take no suffix.
US_SUFFIX = ".us"


def stooq_symbol(ticker: str) -> str:
    """Map a ticker to Stooq's symbol form.

    Class shares use a dash on Stooq (``BRK-B``), while SEC files use a dot
    (``BRK.B``). Getting this wrong returns an empty CSV rather than an error,
    which is the quiet kind of failure — so the mapping lives here and is
    tested.
    """
    symbol = ticker.strip().upper()
    if symbol.startswith("^"):
        return symbol.lower()
    return symbol.replace(".", "-").lower() + US_SUFFIX


def parse_daily_csv(text: str, *, symbol: str) -> list[PriceBar]:
    """Parse Stooq's daily CSV.

    Header is ``Date,Open,High,Low,Close,Volume``. A missing or unparseable
    close means the row is dropped: a bar without a close is not a bar, and
    interpolating one would fabricate a price (non-negotiable #2).
    """
    stripped = text.strip()
    if not stripped or stripped.lower().startswith("no data"):
        return []

    reader = csv.DictReader(io.StringIO(stripped))
    bars: list[PriceBar] = []
    for row in reader:
        raw_date = (row.get("Date") or "").strip()
        try:
            trade_date = datetime.strptime(raw_date, "%Y-%m-%d").date()  # noqa: DTZ007
        except ValueError:
            continue

        close = _decimal(row.get("Close"))
        if close is None:
            log.info("stooq.row_without_close", symbol=symbol, date=raw_date)
            continue

        volume_raw = _decimal(row.get("Volume"))
        bars.append(
            PriceBar(
                symbol=symbol,
                trade_date=trade_date,
                open=_decimal(row.get("Open")),
                high=_decimal(row.get("High")),
                low=_decimal(row.get("Low")),
                close=close,
                volume=int(volume_raw) if volume_raw is not None else None,
                is_adjusted=True,
            )
        )
    bars.sort(key=lambda bar: bar.trade_date)
    return bars


def _decimal(raw: str | None) -> Decimal | None:
    if raw is None:
        return None
    text = raw.strip()
    if not text or text in {"N/A", "-", "null"}:
        return None
    try:
        return Decimal(text)
    except (InvalidOperation, ValueError):
        return None


class StooqAdapter:
    """Satisfies ``MarketDataProvider``."""

    source_id = SOURCE_ID

    def __init__(self, client: HttpClient) -> None:
        self._client = client

    def daily_bars(self, symbol: str, *, start: date, end: date) -> list[PriceBar]:
        """One symbol's daily bars.

        Use sparingly — see the module docstring. The response is cached on
        disk, so a re-run of a backfill replays rather than re-requesting.
        """
        mapped = stooq_symbol(symbol)
        response = self._client.get(
            SOURCE_ID,
            DAILY_URL,
            params={
                "s": mapped,
                "i": "d",
                "d1": start.strftime("%Y%m%d"),
                "d2": end.strftime("%Y%m%d"),
            },
        )
        bars = parse_daily_csv(response.text(), symbol=symbol)
        if not bars:
            # An empty CSV is Stooq's answer for both "unknown symbol" and
            # "throttled", and telling them apart matters. Log loudly.
            log.warning("stooq.empty_series", symbol=symbol, mapped=mapped)
        return [bar for bar in bars if start <= bar.trade_date <= end]
