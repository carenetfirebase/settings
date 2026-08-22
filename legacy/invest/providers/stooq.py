"""Stooq — primary daily OHLCV source.

Free CSV endpoint, no key, no registration:
    https://stooq.com/q/d/l/?s=aapl.us&i=d

Characteristics that matter downstream:

* Prices are **split-adjusted but not dividend-adjusted**. We record that on
  every row (`is_split_adjusted=True`, `is_dividend_adjusted=False`) rather
  than leaving the next reader to guess, because total-return maths must not
  silently use a price-return series.
* There is no separate adjusted-close column, so `adj_close` stays NULL. NULL
  means "not provided", never "same as close".
* An unknown symbol returns the literal body "No data" with HTTP 200, so the
  status code alone is not a success check.
"""

from __future__ import annotations

import csv
import io
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from invest.providers.base import PriceBar, ProviderError, ProviderUnavailable
from invest.providers.http import HttpClient

SOURCE_NAME = "stooq"
BASE_URL = "https://stooq.com/q/d/l/"

EXPECTED_HEADER = ["Date", "Open", "High", "Low", "Close", "Volume"]


def _decimal(raw: str | None) -> Decimal | None:
    """Missing values stay None. Never coerce a blank to zero — a zero price
    is a claim about the market, and blank is a claim about our data.
    """
    if raw is None:
        return None
    text = raw.strip()
    if text in ("", "N/A", "null", "-"):
        return None
    try:
        return Decimal(text)
    except InvalidOperation as exc:
        raise ProviderError(f"{SOURCE_NAME}: unparseable number {raw!r}") from exc


def _int(raw: str | None) -> int | None:
    value = _decimal(raw)
    return None if value is None else int(value)


def parse_csv(text: str, symbol: str) -> list[PriceBar]:
    """Parse a Stooq daily CSV body into validated bars.

    Split out from the fetch so it is testable without a network round-trip.
    """
    stripped = text.strip()
    if not stripped:
        raise ProviderUnavailable(f"{SOURCE_NAME}: empty response for {symbol!r}")
    if stripped.lower().startswith("no data"):
        raise ProviderUnavailable(f"{SOURCE_NAME}: no data for symbol {symbol!r}")

    reader = csv.reader(io.StringIO(stripped))
    try:
        header = next(reader)
    except StopIteration as exc:  # pragma: no cover - guarded by the empty check
        raise ProviderUnavailable(f"{SOURCE_NAME}: no header for {symbol!r}") from exc

    header = [h.strip() for h in header]
    if header[: len(EXPECTED_HEADER)] != EXPECTED_HEADER:
        raise ProviderError(
            f"{SOURCE_NAME}: unexpected CSV header {header!r}. "
            f"The feed format changed — refusing to guess column meanings."
        )

    bars: list[PriceBar] = []
    for lineno, row in enumerate(reader, start=2):
        if not row or not any(cell.strip() for cell in row):
            continue
        if len(row) < len(EXPECTED_HEADER):
            raise ProviderError(f"{SOURCE_NAME}: short row at line {lineno}: {row!r}")
        try:
            obs_date = datetime.strptime(row[0].strip(), "%Y-%m-%d").date()
        except ValueError as exc:
            raise ProviderError(f"{SOURCE_NAME}: bad date at line {lineno}: {row[0]!r}") from exc

        bars.append(
            PriceBar(
                symbol=symbol,
                obs_date=obs_date,
                open=_decimal(row[1]),
                high=_decimal(row[2]),
                low=_decimal(row[3]),
                close=_decimal(row[4]),
                adj_close=None,  # Stooq publishes no separate adjusted close
                volume=_int(row[5]),
                currency="USD",
                source=SOURCE_NAME,
                is_split_adjusted=True,
                is_dividend_adjusted=False,
            )
        )

    bars.sort(key=lambda b: b.obs_date)
    return bars


class StooqProvider:
    """Satisfies the PriceProvider protocol."""

    source_name = SOURCE_NAME

    def __init__(self, client: HttpClient | None = None) -> None:
        # Stooq publishes no documented rate limit; 5 rps is a courteous ceiling.
        self.client = client or HttpClient(
            source_name=SOURCE_NAME,
            user_agent="invest-research-platform",
            rate_per_second=5.0,
        )

    def fetch_daily_bars(
        self, symbol: str, start: date | None = None, end: date | None = None
    ) -> list[PriceBar]:
        params: dict[str, str] = {"s": symbol, "i": "d"}
        if start is not None:
            params["d1"] = start.strftime("%Y%m%d")
        if end is not None:
            params["d2"] = end.strftime("%Y%m%d")

        response = self.client.get(BASE_URL, params=params)
        bars = parse_csv(response.text, symbol)

        # Server-side date filters are honoured inconsistently; enforce locally
        # so the caller always gets exactly the window it asked for.
        if start is not None:
            bars = [b for b in bars if b.obs_date >= start]
        if end is not None:
            bars = [b for b in bars if b.obs_date <= end]
        return bars

    def close(self) -> None:
        self.client.close()
