"""API response models.

Two conventions run through all of these, both inherited from the ground rules:

* **Missing is `null`, and says why.** A field that could not be computed is
  `null`, and wherever a reason exists it travels alongside the value rather
  than being dropped. A consumer must be able to tell "we looked and it was
  zero" from "we could not find out".
* **Every value declares its kind.** `value_type` carries observed /
  calculated / estimated through to the wire, so a client cannot accidentally
  present a modelled DCF the same way it presents a filed revenue figure.
"""

from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, Field

INSUFFICIENT_DATA = "INSUFFICIENT DATA"


class Meta(BaseModel):
    """Envelope metadata present on every data response."""

    as_of: date | None = Field(
        None, description="Point-in-time cutoff applied to this response."
    )
    generated_at: datetime
    model_version: str | None = None
    note: str | None = None


class HealthResponse(BaseModel):
    status: str
    database: str
    version: str
    read_only: bool = True


class SecuritySummary(BaseModel):
    ticker: str
    name: str
    cik: str | None
    exchange: str | None
    sector: str | None
    currency: str
    is_financial: bool
    entity_id: int
    security_id: int
    data_quality_flag: str


class UniverseResponse(BaseModel):
    meta: Meta
    count: int
    securities: list[SecuritySummary]


class PriceBarOut(BaseModel):
    obs_date: date
    open: float | None
    high: float | None
    low: float | None
    close: float | None
    volume: int | None
    source: str


class PriceResponse(BaseModel):
    meta: Meta
    ticker: str
    count: int
    #: Recorded because Stooq is split-adjusted but NOT dividend-adjusted;
    #: a client computing total returns needs to know.
    adjustment_note: str
    bars: list[PriceBarOut]


class FundamentalOut(BaseModel):
    metric_name: str
    value: float | None
    unit: str
    period_start: date | None
    period_end: date
    fiscal_year: int | None
    fiscal_period: str | None
    filed_date: date
    form_type: str | None
    accession_number: str | None
    data_quality_flag: str
    value_type: str = "observed"


class FundamentalsResponse(BaseModel):
    meta: Meta
    ticker: str
    metrics_available: dict[str, int]
    metrics_missing: list[str]
    series: dict[str, list[FundamentalOut]]


class ScoreComponentOut(BaseModel):
    name: str
    value: float | None
    weight: float
    detail: str
    unavailable_reason: str | None = None


class ScoreOut(BaseModel):
    name: str
    value: float | None
    coverage: float
    reliable: bool
    warnings: list[str]
    components: list[ScoreComponentOut]


class AnalysisResponse(BaseModel):
    meta: Meta
    ticker: str
    name: str
    cik: str | None
    price: float | None
    investment_quality: ScoreOut
    trade_setup: ScoreOut
    confidence: ScoreOut
    components: dict
    inputs: dict
    warnings: list[str]
    premium_data_dependent: list[str]


class SnapshotOut(BaseModel):
    id: int
    ticker: str | None
    snapshot_date: date
    as_of_date: date
    model_version: str
    investment_quality_score: float | None
    trade_setup_score: float | None
    confidence_score: float | None
    created_at: datetime


class SnapshotsResponse(BaseModel):
    meta: Meta
    count: int
    snapshots: list[SnapshotOut]


class SnapshotDetailResponse(BaseModel):
    meta: Meta
    snapshot: SnapshotOut
    components: dict
    inputs: dict
    warnings: dict | None
    report_text: str | None


class ConflictOut(BaseModel):
    id: int
    table_name: str
    metric_name: str | None
    obs_date: date | None
    conflict_type: str
    severity: str
    source_a: str | None
    value_a: float | None
    source_b: str | None
    value_b: float | None
    detail: str | None
    resolved: bool
    detected_at: datetime


class ConflictsResponse(BaseModel):
    meta: Meta
    count: int
    conflicts: list[ConflictOut]


class InsiderTransactionOut(BaseModel):
    insider_name: str
    officer_title: str | None
    is_director: bool | None
    is_officer: bool | None
    transaction_date: date
    filed_date: date
    disclosure_lag_days: int
    transaction_code: str | None
    code_meaning: str
    is_discretionary: bool
    acquired_disposed: str | None
    shares: float | None
    price_per_share: float | None
    is_derivative: bool


class InsiderResponse(BaseModel):
    meta: Meta
    ticker: str
    total_filings: int
    discretionary_trades: int
    buys: int
    sells: int
    buy_value: float
    sell_value: float
    net_buy_ratio: float | None
    interpretation_note: str
    transactions: list[InsiderTransactionOut]


class DisclosureOut(BaseModel):
    politician_name: str
    chamber: str | None
    transaction_type: str | None
    transaction_date: date
    disclosure_date: date
    disclosure_lag_days: int
    amount_range_low: float | None
    amount_range_high: float | None
    ticker_raw: str | None
    asset_description: str | None


class DisclosuresResponse(BaseModel):
    meta: Meta
    ticker: str
    #: Always 'investigate_only'. Restated on the wire so a client cannot
    #: reasonably claim it did not know.
    firewall_status: str
    firewall_note: str
    count: int
    median_disclosure_lag_days: float | None
    disclosures: list[DisclosureOut]


class RegimeSignalOut(BaseModel):
    name: str
    value: float | None
    direction: int | None
    detail: str
    unavailable_reason: str | None = None


class RegimeResponse(BaseModel):
    meta: Meta
    regime: str
    risk_score: float | None
    coverage: float
    reliable: bool
    signals: list[RegimeSignalOut]
    note: str


class ErrorResponse(BaseModel):
    detail: str
