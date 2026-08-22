"""Alpha Vantage — second price source, with delayed intraday.

Chosen over the alternatives for one reason: it publishes explicit terms for
its free tier. The project's ground rules permit "free tiers within their
terms", and a source whose terms you can read and point at is worth more than
a marginally better endpoint you are quietly hoping nobody minds you using.

Requires a free key from https://www.alphavantage.co/support/#api-key,
supplied via `ALPHAVANTAGE_API_KEY`.

## Two traps this adapter exists to handle

**Rate limits arrive as HTTP 200.** When you exceed the quota, Alpha Vantage
returns a perfectly successful response whose body is `{"Note": "..."}` or
`{"Information": "..."}` — no error status, no error field. Code that checks
`response.status_code` and then looks for its data key sees an empty result and
concludes the security has no prices. That is the exact failure this project
exists to prevent: a wrong answer that looks like a real one. Every response is
inspected for these keys and raises `ProviderUnavailable` instead.

**Intraday is delayed, and the delay is the point.** No free tier carries
real-time consolidated US equity quotes; exchanges license that feed. Alpha
Vantage's free intraday is delayed, and `QUOTE_DELAY_SECONDS` states the
assumption in one place so nothing downstream has to guess. Every bar this
adapter produces carries that number, and the database column it lands in is
NOT NULL.

## Verify before you rely on it

Free-tier quotas and delay terms change, and this adapter was written without
network access to confirm the current ones. `QUOTE_DELAY_SECONDS` and
`FREE_TIER_DAILY_LIMIT` are the two values to check against their docs before
trusting anything built on them.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from typing import Any

from invest.providers.base import (
    IntradayBar,
    PriceBar,
    ProviderError,
    ProviderUnavailable,
)
from invest.providers.http import HttpClient

logger = logging.getLogger(__name__)

SOURCE_NAME = "alphavantage"
BASE_URL = "https://www.alphavantage.co/query"

#: Publisher-stated delay on the free intraday feed. Verify against current
#: docs — see the module docstring.
QUOTE_DELAY_SECONDS = 15 * 60

#: Free-tier request budget. Used to size the token bucket so we fail politely
#: rather than being cut off mid-backfill.
FREE_TIER_DAILY_LIMIT = 25

#: Keys Alpha Vantage uses to say "no" inside a 200 response.
_SOFT_ERROR_KEYS = ("Note", "Information", "Error Message")

#: Their intraday interval vocabulary, keyed by seconds.
_INTERVALS = {60: "1min", 300: "5min", 900: "15min", 1800: "30min", 3600: "60min"}

#: Alpha Vantage timestamps are US/Eastern exchange local time, without an
#: offset. Stored as a fixed -05:00/-04:00 is wrong across DST, so we attach
#: the zone properly.
_EXCHANGE_TZ = "America/New_York"


def _decimal(raw: Any) -> Decimal | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if text in ("", "None", "-", "N/A"):
        return None
    try:
        return Decimal(text)
    except InvalidOperation:
        return None


def _int(raw: Any) -> int | None:
    value = _decimal(raw)
    return None if value is None else int(value)


def _check_soft_error(payload: dict, symbol: str) -> None:
    """Alpha Vantage says no with HTTP 200. Catch it here or never."""
    for key in _SOFT_ERROR_KEYS:
        if key in payload:
            message = str(payload[key])[:300]
            if key == "Error Message":
                raise ProviderError(f"{SOURCE_NAME}: rejected {symbol!r} — {message}")
            raise ProviderUnavailable(
                f"{SOURCE_NAME}: quota or throttle response for {symbol!r} — {message}"
            )


def _exchange_zone():
    """Resolve the exchange timezone, falling back to fixed UTC-5 only if the
    platform has no tz database — and saying so, because that is wrong half
    the year.
    """
    try:
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

        return ZoneInfo(_EXCHANGE_TZ)
    except (ImportError, ZoneInfoNotFoundError):  # pragma: no cover
        logger.warning(
            "%s: no tz database for %s; falling back to fixed UTC-5, which is "
            "incorrect during daylight saving",
            SOURCE_NAME,
            _EXCHANGE_TZ,
        )
        return timezone(timedelta(hours=-5))


def parse_daily(payload: dict, symbol: str) -> list[PriceBar]:
    """Parse a TIME_SERIES_DAILY response into daily bars."""
    _check_soft_error(payload, symbol)

    series = payload.get("Time Series (Daily)")
    if not isinstance(series, dict):
        raise ProviderError(
            f"{SOURCE_NAME}: no 'Time Series (Daily)' object for {symbol!r}; "
            f"keys were {sorted(payload)[:6]}"
        )

    bars: list[PriceBar] = []
    for day, row in series.items():
        try:
            obs_date = datetime.strptime(day, "%Y-%m-%d").date()
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        try:
            bars.append(
                PriceBar(
                    symbol=symbol,
                    obs_date=obs_date,
                    open=_decimal(row.get("1. open")),
                    high=_decimal(row.get("2. high")),
                    low=_decimal(row.get("3. low")),
                    close=_decimal(row.get("4. close")),
                    adj_close=None,  # only on the premium adjusted endpoint
                    volume=_int(row.get("5. volume")),
                    currency="USD",
                    source=SOURCE_NAME,
                    # TIME_SERIES_DAILY is raw, not adjusted. Recording that
                    # matters: comparing it against Stooq's split-adjusted
                    # series across a split would flag a false conflict.
                    is_split_adjusted=False,
                    is_dividend_adjusted=False,
                )
            )
        except ValueError as exc:
            logger.info("%s: rejected %s %s: %s", SOURCE_NAME, symbol, day, exc)

    bars.sort(key=lambda b: b.obs_date)
    return bars


def parse_intraday(
    payload: dict, symbol: str, *, interval_seconds: int, delay_seconds: int
) -> list[IntradayBar]:
    """Parse a TIME_SERIES_INTRADAY response.

    Timestamps are exchange-local and offset-free on the wire; they are
    localised here so nothing downstream has to guess a zone.
    """
    _check_soft_error(payload, symbol)

    label = _INTERVALS.get(interval_seconds)
    if label is None:
        raise ProviderError(
            f"{SOURCE_NAME}: unsupported interval {interval_seconds}s; "
            f"supported: {sorted(_INTERVALS)}"
        )

    series = payload.get(f"Time Series ({label})")
    if not isinstance(series, dict):
        raise ProviderError(
            f"{SOURCE_NAME}: no 'Time Series ({label})' object for {symbol!r}"
        )

    zone = _exchange_zone()
    bars: list[IntradayBar] = []
    for stamp, row in series.items():
        try:
            naive = datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        try:
            bars.append(
                IntradayBar(
                    symbol=symbol,
                    observed_at=naive.replace(tzinfo=zone),
                    interval_seconds=interval_seconds,
                    open=_decimal(row.get("1. open")),
                    high=_decimal(row.get("2. high")),
                    low=_decimal(row.get("3. low")),
                    close=_decimal(row.get("4. close")),
                    volume=_int(row.get("5. volume")),
                    currency="USD",
                    source=SOURCE_NAME,
                    delay_seconds=delay_seconds,
                )
            )
        except ValueError as exc:
            logger.info("%s: rejected intraday %s %s: %s", SOURCE_NAME, symbol, stamp, exc)

    bars.sort(key=lambda b: b.observed_at)
    return bars


def parse_global_quote(
    payload: dict, symbol: str, *, delay_seconds: int
) -> IntradayBar | None:
    """Parse GLOBAL_QUOTE — the latest print, not a live one.

    The endpoint reports a trading *day*, not a timestamp. Rather than invent
    a time, the bar is stamped at the exchange close for that day and carries
    the feed's delay. Fabricating a plausible-looking minute would be exactly
    the kind of small lie this project is built to avoid.
    """
    _check_soft_error(payload, symbol)

    quote = payload.get("Global Quote")
    if not isinstance(quote, dict) or not quote:
        return None

    day_raw = quote.get("07. latest trading day")
    try:
        day = datetime.strptime(str(day_raw), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None

    zone = _exchange_zone()
    # 16:00 exchange local — the close of the session being reported.
    observed_at = datetime(day.year, day.month, day.day, 16, 0, tzinfo=zone)

    price = _decimal(quote.get("05. price"))
    if price is None:
        return None

    return IntradayBar(
        symbol=symbol,
        observed_at=observed_at,
        interval_seconds=None,
        open=_decimal(quote.get("02. open")),
        high=_decimal(quote.get("03. high")),
        low=_decimal(quote.get("04. low")),
        close=price,
        volume=_int(quote.get("06. volume")),
        currency="USD",
        source=SOURCE_NAME,
        delay_seconds=delay_seconds,
    )


class AlphaVantageProvider:
    """Satisfies PriceProvider and IntradayProvider."""

    source_name = SOURCE_NAME
    quote_delay_seconds = QUOTE_DELAY_SECONDS

    def __init__(
        self,
        api_key: str | None = None,
        client: HttpClient | None = None,
        *,
        quote_delay_seconds: int = QUOTE_DELAY_SECONDS,
    ) -> None:
        if api_key is None:
            from invest.config import get_settings

            api_key = get_settings().alphavantage_api_key
        if not api_key and client is None:
            raise ValueError(
                "ALPHAVANTAGE_API_KEY is not set. Get a free key at "
                "https://www.alphavantage.co/support/#api-key and put it in .env"
            )
        self.api_key = api_key
        self.quote_delay_seconds = quote_delay_seconds
        # Well under the free tier's per-minute allowance: this source is a
        # cross-check, not a bulk feed, and being cut off mid-run is worse
        # than being slow.
        self.client = client or HttpClient(
            source_name=SOURCE_NAME,
            user_agent="invest-research-platform",
            rate_per_second=0.5,
        )

    def _get(self, params: dict[str, str], symbol: str) -> dict:
        params = {**params, "apikey": self.api_key or ""}
        response = self.client.get(BASE_URL, params=params)
        try:
            payload = response.json()
        except ValueError as exc:
            raise ProviderError(f"{SOURCE_NAME}: non-JSON response for {symbol!r}") from exc
        if not isinstance(payload, dict):
            raise ProviderError(f"{SOURCE_NAME}: unexpected response shape for {symbol!r}")
        return payload

    # -- PriceProvider ---------------------------------------------------

    def fetch_daily_bars(
        self, symbol: str, start: date | None = None, end: date | None = None
    ) -> list[PriceBar]:
        payload = self._get(
            {
                "function": "TIME_SERIES_DAILY",
                "symbol": symbol,
                # 'compact' is the last 100 sessions; 'full' is 20+ years and
                # a much larger response, so only ask when the window needs it.
                "outputsize": "full" if start else "compact",
            },
            symbol,
        )
        bars = parse_daily(payload, symbol)
        if start is not None:
            bars = [b for b in bars if b.obs_date >= start]
        if end is not None:
            bars = [b for b in bars if b.obs_date <= end]
        return bars

    # -- IntradayProvider ------------------------------------------------

    def fetch_intraday(
        self, symbol: str, *, interval_seconds: int = 300, limit: int = 100
    ) -> list[IntradayBar]:
        label = _INTERVALS.get(interval_seconds)
        if label is None:
            raise ProviderError(
                f"{SOURCE_NAME}: unsupported interval {interval_seconds}s; "
                f"supported: {sorted(_INTERVALS)}"
            )
        payload = self._get(
            {
                "function": "TIME_SERIES_INTRADAY",
                "symbol": symbol,
                "interval": label,
                "outputsize": "compact",
            },
            symbol,
        )
        bars = parse_intraday(
            payload,
            symbol,
            interval_seconds=interval_seconds,
            delay_seconds=self.quote_delay_seconds,
        )
        return bars[-limit:] if limit else bars

    def fetch_latest_quote(self, symbol: str) -> IntradayBar | None:
        payload = self._get({"function": "GLOBAL_QUOTE", "symbol": symbol}, symbol)
        return parse_global_quote(payload, symbol, delay_seconds=self.quote_delay_seconds)

    def close(self) -> None:
        self.client.close()
