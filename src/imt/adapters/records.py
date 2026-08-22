"""Typed records returned by adapters.

These are the boundary between "what a source said" and "what the system
stores". They are frozen dataclasses rather than ORM objects so parsing can be
tested without a database, and so an adapter cannot accidentally write.

**Money is integer minor units throughout** (API_CONTRACT). A price of $61.20
is ``6120``. Floats are not used for money anywhere in this system: 0.1 + 0.2
is a rounding error in a report and a wrong number in a backtest.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import ROUND_HALF_UP, Decimal


def to_minor(amount: Decimal | None, *, exponent: int = 2) -> int | None:
    """Decimal dollars to integer minor units, half-up.

    Half-up rather than banker's rounding because these are money amounts a
    human will reconcile against a filing, and .5 rounding down surprises
    people reading a document that says $2.5M.
    """
    if amount is None:
        return None
    quantum = Decimal(1).scaleb(-exponent)
    return int(
        (amount.quantize(quantum, rounding=ROUND_HALF_UP) * (10**exponent)).to_integral_value()
    )


@dataclass(frozen=True, slots=True)
class FilingRef:
    """One filing, as the index describes it — before its document is fetched."""

    accession: str
    cik: str
    form_type: str
    filed_date: date
    primary_doc_url: str
    acceptance_datetime: datetime | None = None
    company_name: str | None = None

    @property
    def is_amendment(self) -> bool:
        return self.form_type.endswith("/A")


@dataclass(frozen=True, slots=True)
class InsiderTransactionRecord:
    """One row of a Form 4 or Form 144.

    ``actor_key`` identifies the *decision maker*, not the document. A joint
    filing by a trust and its trustee is one decision; three amendments by one
    officer are one actor. Cluster detection counts distinct ``actor_key``
    values, which is what SPEC §8's "independent insiders" means.
    """

    cik: str
    accession: str
    insider_name: str
    insider_cik: str | None
    actor_key: str
    transaction_code: str
    transaction_date: date
    filed_date: date
    shares: Decimal | None
    price_minor: int | None
    value_minor: int | None
    shares_owned_after: Decimal | None
    is_officer: bool
    is_director: bool
    is_ten_percent_owner: bool
    role: str | None
    is_derivative: bool
    is_amendment: bool
    is_10b5_1: bool | None
    acquired_disposed: str | None
    currency: str = "USD"
    reason_code: str | None = None

    @property
    def is_open_market_purchase(self) -> bool:
        """Code P only. Grants, exercises and tax withholding are not buying."""
        return self.transaction_code == "P"

    @property
    def is_open_market_sale(self) -> bool:
        return self.transaction_code == "S"


@dataclass(frozen=True, slots=True)
class ActivistRecord:
    """13D or 13G. The distinction is load-bearing and never inferred."""

    cik: str
    accession: str
    filer_name: str
    is_activist: bool  # True = 13D (active intent), False = 13G (passive)
    pct_of_class: Decimal | None
    shares: Decimal | None
    item4_categories: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class PoliticalTradeRecord:
    """A congressional PTR line.

    Carries ``value_low_minor`` and ``value_high_minor`` and no single amount.
    Disclosures report brackets; a midpoint is an estimate, and an estimate
    stored in a column called ``amount`` is read as a fact six months later.
    """

    filer_name: str
    filer_id: str
    chamber: str
    owner_type: str
    asset_description: str
    transaction_type: str
    transaction_date: date
    disclosure_date: date
    value_low_minor: int
    value_high_minor: int
    parse_outcome: str
    source_record_id: str
    document_url: str
    currency: str = "USD"

    @property
    def disclosure_lag_days(self) -> int:
        return (self.disclosure_date - self.transaction_date).days


@dataclass(frozen=True, slots=True)
class PriceBar:
    symbol: str
    trade_date: date
    open: Decimal | None
    high: Decimal | None
    low: Decimal | None
    close: Decimal
    volume: int | None
    is_adjusted: bool = True


@dataclass(frozen=True, slots=True)
class FundamentalFact:
    cik: str
    tag: str
    unit: str
    period_start: date | None
    period_end: date
    filed_date: date
    value: Decimal
    fiscal_period: str | None = None
    accession: str | None = None


@dataclass(frozen=True, slots=True)
class ContractRecord:
    recipient_name: str
    recipient_uei: str | None
    award_id: str
    award_amount_minor: int
    action_date: date
    agency: str | None = None
    naics: str | None = None
    currency: str = "USD"


@dataclass(frozen=True, slots=True)
class MacroPoint:
    series_id: str
    reference_period: date
    release_timestamp: datetime
    value: Decimal | None
    reason_code: str | None = None


@dataclass(frozen=True, slots=True)
class EightKRecord:
    """An 8-K with its classified items.

    Item numbers are the SEC's own taxonomy, so classification by item is
    deterministic. Content classification beyond that is a keyword pass, and
    anything it cannot place stays ``unclassified`` rather than being guessed
    into the nearest bucket.
    """

    cik: str
    accession: str
    items: tuple[str, ...]
    categories: tuple[str, ...] = field(default_factory=tuple)
