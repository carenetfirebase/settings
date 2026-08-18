"""Provider contracts.

Ground rule 5: the calculation engines read from Postgres only and must never
import a vendor module. The boundary is here — a provider's single job is to
turn a remote response into validated pydantic records. It does not touch the
database, does not decide what is good data, and does not know what a score is.

Swapping a free source for a paid one later means writing one new class that
satisfies these Protocols. Nothing downstream changes.

Every record type carries `source` so the validation gate can compare providers
against each other, and every provider declares `source_name` once.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Protocol, runtime_checkable

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class ProviderError(RuntimeError):
    """Transport or parsing failure. Providers raise this instead of leaking
    vendor-specific exception types to the ingestion layer.
    """


class ProviderUnavailable(ProviderError):
    """The source could not be reached (network, rate limit, outage).

    Distinct from ProviderError because the caller may reasonably fall back to
    a secondary source — but must never fabricate the value.
    """


# --------------------------------------------------------------------------
# Record schemas — validated at the boundary, before anything reaches the DB
# --------------------------------------------------------------------------


class PriceBar(BaseModel):
    """One day of OHLCV as published by a source, before the validation gate."""

    model_config = ConfigDict(frozen=True)

    symbol: str
    obs_date: date
    open: Decimal | None = None
    high: Decimal | None = None
    low: Decimal | None = None
    close: Decimal | None = None
    adj_close: Decimal | None = None
    volume: int | None = None
    currency: str = "USD"
    source: str
    is_split_adjusted: bool | None = None
    is_dividend_adjusted: bool | None = None

    @field_validator("open", "high", "low", "close", "adj_close")
    @classmethod
    def _no_negative_prices(cls, v: Decimal | None) -> Decimal | None:
        if v is not None and v < 0:
            raise ValueError("price may not be negative")
        return v

    @field_validator("volume")
    @classmethod
    def _no_negative_volume(cls, v: int | None) -> int | None:
        if v is not None and v < 0:
            raise ValueError("volume may not be negative")
        return v

    @model_validator(mode="after")
    def _high_low_consistency(self) -> PriceBar:
        """A bar whose high is below its low is corrupt, not merely odd."""
        if self.high is not None and self.low is not None and self.high < self.low:
            raise ValueError(f"high {self.high} < low {self.low}")
        for name in ("open", "close"):
            value = getattr(self, name)
            if value is None:
                continue
            if self.high is not None and value > self.high:
                raise ValueError(f"{name} {value} above high {self.high}")
            if self.low is not None and value < self.low:
                raise ValueError(f"{name} {value} below low {self.low}")
        return self


class FundamentalFact(BaseModel):
    """One normalized XBRL fact, carrying its own point-in-time key."""

    model_config = ConfigDict(frozen=True)

    cik: str
    metric_name: str
    xbrl_tag: str | None = None
    taxonomy: str | None = None
    value: Decimal | None = None
    unit: str
    period_start: date | None = None
    period_end: date
    fiscal_year: int | None = None
    fiscal_period: str | None = None
    filed_date: date  # mandatory — no fact without a filing date
    form_type: str | None = None
    accession_number: str | None = None
    source: str

    @model_validator(mode="after")
    def _period_order(self) -> FundamentalFact:
        if self.period_start is not None and self.period_start > self.period_end:
            raise ValueError("period_start after period_end")
        return self


class MacroPoint(BaseModel):
    model_config = ConfigDict(frozen=True)

    series_id: str
    obs_date: date
    value: Decimal | None = None
    unit: str | None = None
    realtime_start: date | None = None
    source: str


class FilingRecord(BaseModel):
    model_config = ConfigDict(frozen=True)

    cik: str
    accession_number: str
    form_type: str
    filed_date: date
    acceptance_datetime: str | None = None
    period_of_report: date | None = None
    primary_doc_url: str | None = None
    items: str | None = None
    source: str


class InsiderTransactionRecord(BaseModel):
    model_config = ConfigDict(frozen=True)

    cik: str
    insider_name: str
    insider_cik: str | None = None
    is_director: bool | None = None
    is_officer: bool | None = None
    is_ten_pct_owner: bool | None = None
    officer_title: str | None = None
    transaction_date: date
    filed_date: date
    transaction_code: str | None = None
    acquired_disposed: str | None = None
    shares: Decimal | None = None
    price_per_share: Decimal | None = None
    shares_owned_after: Decimal | None = None
    is_derivative: bool = False
    accession_number: str | None = None
    source: str


class PoliticalTradeRecord(BaseModel):
    """FIREWALLED. Research context only — never a score contributor."""

    model_config = ConfigDict(frozen=True)

    politician_name: str
    chamber: str | None = None
    state: str | None = None
    ticker_raw: str | None = None
    asset_description: str | None = None
    transaction_type: str | None = None
    transaction_date: date
    disclosure_date: date
    amount_range_low: Decimal | None = None
    amount_range_high: Decimal | None = None
    source: str
    source_url: str | None = None

    @model_validator(mode="after")
    def _disclosure_after_transaction(self) -> PoliticalTradeRecord:
        if self.disclosure_date < self.transaction_date:
            raise ValueError("disclosure_date precedes transaction_date")
        return self


# --------------------------------------------------------------------------
# Protocols
# --------------------------------------------------------------------------


@runtime_checkable
class PriceProvider(Protocol):
    source_name: str

    def fetch_daily_bars(
        self, symbol: str, start: date | None = None, end: date | None = None
    ) -> list[PriceBar]:
        """Daily OHLCV, ascending by date. Raises ProviderUnavailable on
        transport failure — never returns a partial series silently.
        """
        ...


@runtime_checkable
class FundamentalsProvider(Protocol):
    source_name: str

    def fetch_company_facts(self, cik: str) -> list[FundamentalFact]: ...


@runtime_checkable
class FilingsProvider(Protocol):
    source_name: str

    def fetch_filings(self, cik: str, forms: list[str] | None = None) -> list[FilingRecord]: ...


@runtime_checkable
class MacroProvider(Protocol):
    source_name: str

    def fetch_series(
        self, series_id: str, start: date | None = None, end: date | None = None
    ) -> list[MacroPoint]: ...


@runtime_checkable
class PoliticalDisclosureProvider(Protocol):
    source_name: str

    def fetch_disclosures(
        self, start: date | None = None, end: date | None = None
    ) -> list[PoliticalTradeRecord]: ...


#: Field name used consistently for the "this many days old is too old" check.
DEFAULT_STALENESS_DAYS = 7
