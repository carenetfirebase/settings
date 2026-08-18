"""FRED — Federal Reserve Economic Data.

Free API key, registered at https://fred.stlouisfed.org/docs/api/api_key.html
and supplied via the `FRED_API_KEY` environment variable.

## Vintages, and why they matter here more than anywhere else

Most macro series are **revised**, sometimes substantially and sometimes years
later. GDP is revised three times in its first quarter of life; payrolls are
revised for two months and then again annually.

That makes naive macro backtesting one of the most reliable ways to produce a
spectacular fake result: a strategy conditioned on "GDP growth was negative"
using today's revised figures is trading on numbers nobody had at the time.

FRED exposes this through `realtime_start` / `realtime_end` — the ALFRED
vintage system. This provider requests vintage-aware responses and stores
`realtime_start` on every observation, so the regime classifier can filter to
what was actually published as of a simulated date. Series that were never
revised simply carry their original date.
"""

from __future__ import annotations

import logging
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from invest.providers.base import MacroPoint, ProviderError
from invest.providers.http import HttpClient

logger = logging.getLogger(__name__)

SOURCE_NAME = "fred"
BASE_URL = "https://api.stlouisfed.org/fred/series/observations"

#: FRED asks for courtesy; it does not publish a hard ceiling. 5 rps is polite.
FRED_RATE_LIMIT = 5.0


#: The series the regime classifier uses, with what each one is for.
#: Keeping this list here rather than in the classifier means the ingestion
#: CLI and the classifier cannot drift apart.
CORE_SERIES: dict[str, str] = {
    "DGS10": "10-year Treasury constant maturity yield",
    "DGS2": "2-year Treasury constant maturity yield",
    "DGS3MO": "3-month Treasury bill yield",
    "T10Y2Y": "10-year minus 2-year Treasury spread (yield curve)",
    "T10Y3M": "10-year minus 3-month Treasury spread",
    "BAMLH0A0HYM2": "ICE BofA US high-yield option-adjusted spread",
    "BAMLC0A0CM": "ICE BofA US corporate option-adjusted spread",
    "UNRATE": "Civilian unemployment rate",
    "CPIAUCSL": "CPI for all urban consumers",
    "FEDFUNDS": "Effective federal funds rate",
    "GDPC1": "Real gross domestic product",
    "VIXCLS": "CBOE volatility index",
    "UMCSENT": "University of Michigan consumer sentiment",
    "INDPRO": "Industrial production index",
    "PAYEMS": "All employees, total nonfarm payrolls",
}

#: Series where FRED reports a percentage as a whole number (4.25 meaning
#: 4.25%). Recorded so downstream code never has to guess a scale.
PERCENT_SERIES = frozenset(
    {
        "DGS10", "DGS2", "DGS3MO", "T10Y2Y", "T10Y3M",
        "BAMLH0A0HYM2", "BAMLC0A0CM", "UNRATE", "FEDFUNDS", "VIXCLS",
    }
)


def _parse_date(raw: str | None) -> date | None:
    if not raw:
        return None
    try:
        return datetime.strptime(raw[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def parse_observations(payload: dict, series_id: str) -> list[MacroPoint]:
    """Parse a FRED observations response.

    FRED encodes a missing value as the string "." — that becomes None, never
    zero. A zero unemployment rate and an unpublished unemployment rate are
    very different claims.
    """
    observations = payload.get("observations")
    if not isinstance(observations, list):
        raise ProviderError(f"{SOURCE_NAME}: no 'observations' array for {series_id!r}")

    points: list[MacroPoint] = []
    for entry in observations:
        if not isinstance(entry, dict):
            continue
        obs_date = _parse_date(entry.get("date"))
        if obs_date is None:
            continue

        raw_value = (entry.get("value") or "").strip()
        value: Decimal | None
        if raw_value in (".", "", "NA", "N/A"):
            value = None  # published as unavailable — not zero
        else:
            try:
                value = Decimal(raw_value)
            except (InvalidOperation, ValueError):
                logger.info("%s: unparseable value %r in %s", SOURCE_NAME, raw_value, series_id)
                value = None

        points.append(
            MacroPoint(
                series_id=series_id,
                obs_date=obs_date,
                value=value,
                unit="percent" if series_id in PERCENT_SERIES else None,
                realtime_start=_parse_date(entry.get("realtime_start")),
                source=SOURCE_NAME,
            )
        )

    points.sort(key=lambda p: p.obs_date)
    return points


class FredProvider:
    """Satisfies the MacroProvider protocol."""

    source_name = SOURCE_NAME

    def __init__(self, api_key: str | None = None, client: HttpClient | None = None) -> None:
        if api_key is None:
            from invest.config import get_settings

            api_key = get_settings().fred_api_key
        if not api_key and client is None:
            raise ValueError(
                "FRED_API_KEY is not set. Get a free key at "
                "https://fred.stlouisfed.org/docs/api/api_key.html and put it in .env"
            )
        self.api_key = api_key
        self.client = client or HttpClient(
            source_name=SOURCE_NAME,
            user_agent="invest-research-platform",
            rate_per_second=FRED_RATE_LIMIT,
        )

    def fetch_series(
        self,
        series_id: str,
        start: date | None = None,
        end: date | None = None,
        *,
        vintage_date: date | None = None,
    ) -> list[MacroPoint]:
        """Fetch one series.

        `vintage_date` asks FRED for the data **as it stood on that date** —
        the honest way to backtest a macro signal. Without it you get today's
        revised figures, which nobody had at the time.
        """
        params: dict[str, str] = {
            "series_id": series_id,
            "api_key": self.api_key or "",
            "file_type": "json",
        }
        if start is not None:
            params["observation_start"] = start.isoformat()
        if end is not None:
            params["observation_end"] = end.isoformat()
        if vintage_date is not None:
            params["realtime_start"] = vintage_date.isoformat()
            params["realtime_end"] = vintage_date.isoformat()

        response = self.client.get(BASE_URL, params=params)
        try:
            payload = response.json()
        except ValueError as exc:
            raise ProviderError(f"{SOURCE_NAME}: non-JSON response for {series_id}") from exc
        if not isinstance(payload, dict):
            raise ProviderError(f"{SOURCE_NAME}: unexpected response shape for {series_id}")

        return parse_observations(payload, series_id)

    def close(self) -> None:
        self.client.close()
