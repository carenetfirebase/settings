"""SQLAlchemy 2.x ORM models — the full V1 schema.

Design notes that apply across the schema:

* **Append-only.** `price_observations`, `fundamentals` and `research_snapshots`
  are protected by database triggers that reject UPDATE and DELETE (see the
  initial migration). New observations are new rows; corrections are new rows
  with a later `ingested_at` / `filed_date`.
* **Point-in-time.** `fundamentals.filed_date` is NOT NULL and is the key every
  backtest filters on. A fact is only visible to a simulation dated on or after
  the date it was actually filed with the SEC.
* **Numeric, never float.** Money and ratios are `NUMERIC` so ingestion and
  storage are exact. Conversion to float happens only inside the quant engines,
  where numpy/scipy need it.
* **Tables that V1 cannot populate still exist** (analyst estimates, options)
  so downstream code can report them as PREMIUM-DATA DEPENDENT rather than
  pretending they are zero. They are declared at the end of this module.
"""

from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

from invest.db.enums import (
    ConflictType,
    DataQualityFlag,
    EntityType,
    FirewallStatus,
    JobStatus,
    Severity,
    ValueType,
    values,
)


class Base(DeclarativeBase):
    pass


def _check(column: str, enum_cls: type, name: str) -> CheckConstraint:
    allowed = ", ".join(f"'{v}'" for v in values(enum_cls))
    return CheckConstraint(f"{column} IN ({allowed})", name=name)


# Money / large magnitudes: revenue in the hundreds of billions still fits.
MONEY = Numeric(28, 4)
RATIO = Numeric(20, 10)
PRICE = Numeric(20, 6)


# --------------------------------------------------------------------------
# Security master
# --------------------------------------------------------------------------


class Entity(Base):
    """The issuing legal entity. CIK is the join key to everything SEC."""

    __tablename__ = "entities"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    entity_type: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=EntityType.COMPANY.value
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    # 10-digit zero-padded CIK. Nullable: not every entity is an SEC filer.
    cik: Mapped[str | None] = mapped_column(String(10), unique=True)
    lei: Mapped[str | None] = mapped_column(String(20))
    country: Mapped[str | None] = mapped_column(String(2))
    sector: Mapped[str | None] = mapped_column(Text)
    industry: Mapped[str | None] = mapped_column(Text)
    sic_code: Mapped[str | None] = mapped_column(String(8))
    fiscal_year_end: Mapped[str | None] = mapped_column(String(4))  # MMDD
    # Is this a financial-sector company? Selects the Altman Z variant.
    is_financial: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    data_quality_flag: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=DataQualityFlag.OK.value
    )
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    securities: Mapped[list[Security]] = relationship(back_populates="entity")

    __table_args__ = (
        _check("entity_type", EntityType, "ck_entities_entity_type"),
        _check("data_quality_flag", DataQualityFlag, "ck_entities_dq_flag"),
        Index("ix_entities_cik", "cik"),
    )


class Security(Base):
    """A tradable line item belonging to an entity. Ticker is NOT the key —
    tickers get reused and reassigned, so `entity_id` is what everything else
    hangs off.
    """

    __tablename__ = "securities"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    entity_id: Mapped[int] = mapped_column(
        ForeignKey("entities.id", ondelete="RESTRICT"), nullable=False
    )
    ticker: Mapped[str] = mapped_column(String(24), nullable=False)
    exchange: Mapped[str | None] = mapped_column(String(24))
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="USD")
    security_type: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default="common_stock"
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    # Stooq needs a suffixed symbol (aapl.us); keep the vendor form out of `ticker`.
    stooq_symbol: Mapped[str | None] = mapped_column(String(32))
    data_quality_flag: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=DataQualityFlag.OK.value
    )
    first_seen: Mapped[date | None] = mapped_column(Date)
    last_seen: Mapped[date | None] = mapped_column(Date)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    entity: Mapped[Entity] = relationship(back_populates="securities")

    __table_args__ = (
        UniqueConstraint("ticker", "exchange", name="uq_securities_ticker_exchange"),
        _check("data_quality_flag", DataQualityFlag, "ck_securities_dq_flag"),
        Index("ix_securities_ticker", "ticker"),
        Index("ix_securities_entity_id", "entity_id"),
    )


class EntityRelationship(Base):
    """Parent/subsidiary, share-class siblings, index membership."""

    __tablename__ = "entity_relationships"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    parent_entity_id: Mapped[int] = mapped_column(ForeignKey("entities.id"), nullable=False)
    child_entity_id: Mapped[int] = mapped_column(ForeignKey("entities.id"), nullable=False)
    relationship_type: Mapped[str] = mapped_column(String(32), nullable=False)
    ownership_pct: Mapped[float | None] = mapped_column(RATIO)
    effective_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "parent_entity_id",
            "child_entity_id",
            "relationship_type",
            "effective_date",
            name="uq_entity_rel",
        ),
        CheckConstraint("parent_entity_id <> child_entity_id", name="ck_entity_rel_not_self"),
    )


# --------------------------------------------------------------------------
# Market data
# --------------------------------------------------------------------------


class PriceObservation(Base):
    """Daily OHLCV. UNIQUE(security_id, obs_date, source) so several providers
    coexist for the same day and can be compared against each other by the
    validation gate.
    """

    __tablename__ = "price_observations"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    security_id: Mapped[int] = mapped_column(
        ForeignKey("securities.id", ondelete="RESTRICT"), nullable=False
    )
    obs_date: Mapped[date] = mapped_column(Date, nullable=False)
    open: Mapped[float | None] = mapped_column(PRICE)
    high: Mapped[float | None] = mapped_column(PRICE)
    low: Mapped[float | None] = mapped_column(PRICE)
    close: Mapped[float | None] = mapped_column(PRICE)
    adj_close: Mapped[float | None] = mapped_column(PRICE)
    volume: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="USD")
    # Stooq daily CSV is split-adjusted but not dividend-adjusted.
    is_split_adjusted: Mapped[bool | None] = mapped_column(Boolean)
    is_dividend_adjusted: Mapped[bool | None] = mapped_column(Boolean)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    value_type: Mapped[str] = mapped_column(
        String(24), nullable=False, server_default=ValueType.OBSERVED.value
    )
    data_quality_flag: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=DataQualityFlag.OK.value
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("security_id", "obs_date", "source", name="uq_price_sec_date_source"),
        _check("value_type", ValueType, "ck_price_value_type"),
        _check("data_quality_flag", DataQualityFlag, "ck_price_dq_flag"),
        CheckConstraint(
            "(open IS NULL OR open >= 0) AND (high IS NULL OR high >= 0) "
            "AND (low IS NULL OR low >= 0) AND (close IS NULL OR close >= 0) "
            "AND (adj_close IS NULL OR adj_close >= 0)",
            name="ck_price_non_negative",
        ),
        CheckConstraint("volume IS NULL OR volume >= 0", name="ck_price_volume_non_negative"),
        Index("ix_price_sec_date", "security_id", "obs_date"),
    )


# --------------------------------------------------------------------------
# Fundamentals and filings
# --------------------------------------------------------------------------


class Fundamental(Base):
    """One normalized XBRL fact.

    Long/narrow rather than one-column-per-metric: XBRL tags vary by filer and
    by year, and a wide table would need a migration every time a new concept
    shows up.

    `filed_date` is the point-in-time key and is mandatory. An amended filing
    restating a period arrives as a NEW row with a later `filed_date` and a
    different `accession_number` — the original is never modified.
    """

    __tablename__ = "fundamentals"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entity_id: Mapped[int] = mapped_column(
        ForeignKey("entities.id", ondelete="RESTRICT"), nullable=False
    )
    metric_name: Mapped[str] = mapped_column(String(128), nullable=False)
    xbrl_tag: Mapped[str | None] = mapped_column(String(128))
    taxonomy: Mapped[str | None] = mapped_column(String(24))  # us-gaap, ifrs-full, dei
    metric_value: Mapped[float | None] = mapped_column(MONEY)
    unit: Mapped[str] = mapped_column(String(24), nullable=False)
    period_start: Mapped[date | None] = mapped_column(Date)  # NULL for instant facts
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    fiscal_year: Mapped[int | None] = mapped_column(Integer)
    fiscal_period: Mapped[str | None] = mapped_column(String(8))  # FY, Q1..Q4
    # THE point-in-time key. Never nullable.
    filed_date: Mapped[date] = mapped_column(Date, nullable=False)
    form_type: Mapped[str | None] = mapped_column(String(16))
    accession_number: Mapped[str | None] = mapped_column(String(32))
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    value_type: Mapped[str] = mapped_column(
        String(24), nullable=False, server_default=ValueType.OBSERVED.value
    )
    data_quality_flag: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=DataQualityFlag.OK.value
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "entity_id",
            "metric_name",
            "period_end",
            "fiscal_period",
            "filed_date",
            "accession_number",
            "source",
            name="uq_fundamentals_fact",
        ),
        _check("value_type", ValueType, "ck_fundamentals_value_type"),
        _check("data_quality_flag", DataQualityFlag, "ck_fundamentals_dq_flag"),
        CheckConstraint(
            "period_start IS NULL OR period_start <= period_end",
            name="ck_fundamentals_period_order",
        ),
        Index("ix_fundamentals_pit", "entity_id", "metric_name", "filed_date"),
        Index("ix_fundamentals_period", "entity_id", "metric_name", "period_end"),
    )


class Filing(Base):
    __tablename__ = "filings"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entity_id: Mapped[int] = mapped_column(ForeignKey("entities.id"), nullable=False)
    accession_number: Mapped[str] = mapped_column(String(32), nullable=False, unique=True)
    form_type: Mapped[str] = mapped_column(String(16), nullable=False)
    filed_date: Mapped[date] = mapped_column(Date, nullable=False)
    # EDGAR exposes an acceptance timestamp separately from the filing date;
    # for intraday point-in-time work the timestamp is the honest cutoff.
    acceptance_datetime: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    period_of_report: Mapped[date | None] = mapped_column(Date)
    primary_doc_url: Mapped[str | None] = mapped_column(Text)
    items: Mapped[str | None] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        Index("ix_filings_entity_filed", "entity_id", "filed_date"),
        Index("ix_filings_form", "form_type"),
    )


class InsiderTransaction(Base):
    """Form 4. `transaction_date` and `filed_date` are stored separately —
    the gap between them is itself signal, and only `filed_date` is legitimate
    for point-in-time use.
    """

    __tablename__ = "insider_transactions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entity_id: Mapped[int] = mapped_column(ForeignKey("entities.id"), nullable=False)
    security_id: Mapped[int | None] = mapped_column(ForeignKey("securities.id"))
    insider_name: Mapped[str] = mapped_column(Text, nullable=False)
    insider_cik: Mapped[str | None] = mapped_column(String(10))
    is_director: Mapped[bool | None] = mapped_column(Boolean)
    is_officer: Mapped[bool | None] = mapped_column(Boolean)
    is_ten_pct_owner: Mapped[bool | None] = mapped_column(Boolean)
    officer_title: Mapped[str | None] = mapped_column(Text)
    transaction_date: Mapped[date] = mapped_column(Date, nullable=False)
    filed_date: Mapped[date] = mapped_column(Date, nullable=False)
    transaction_code: Mapped[str | None] = mapped_column(String(4))  # P, S, A, M, F...
    acquired_disposed: Mapped[str | None] = mapped_column(String(1))  # A or D
    shares: Mapped[float | None] = mapped_column(MONEY)
    price_per_share: Mapped[float | None] = mapped_column(PRICE)
    shares_owned_after: Mapped[float | None] = mapped_column(MONEY)
    is_derivative: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    accession_number: Mapped[str | None] = mapped_column(String(32))
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    value_type: Mapped[str] = mapped_column(
        String(24), nullable=False, server_default=ValueType.OBSERVED.value
    )
    data_quality_flag: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=DataQualityFlag.OK.value
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "accession_number",
            "insider_cik",
            "transaction_date",
            "transaction_code",
            "shares",
            "is_derivative",
            name="uq_insider_txn",
        ),
        _check("value_type", ValueType, "ck_insider_value_type"),
        Index("ix_insider_entity_filed", "entity_id", "filed_date"),
    )


class PoliticalTrade(Base):
    """Congressional / Senate disclosures.

    FIREWALLED. `firewall_status` defaults to 'investigate_only' and the
    scoring engine is forbidden — in code and by test — from reading this
    table as a score contributor. It is research context, nothing more.
    """

    __tablename__ = "political_trades"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    politician_name: Mapped[str] = mapped_column(Text, nullable=False)
    chamber: Mapped[str | None] = mapped_column(String(8))  # house | senate
    state: Mapped[str | None] = mapped_column(String(2))
    security_id: Mapped[int | None] = mapped_column(ForeignKey("securities.id"))
    ticker_raw: Mapped[str | None] = mapped_column(String(32))
    asset_description: Mapped[str | None] = mapped_column(Text)
    transaction_type: Mapped[str | None] = mapped_column(String(32))
    # Deliberately separate: the disclosure lag is the whole story.
    transaction_date: Mapped[date] = mapped_column(Date, nullable=False)
    disclosure_date: Mapped[date] = mapped_column(Date, nullable=False)
    amount_range_low: Mapped[float | None] = mapped_column(MONEY)
    amount_range_high: Mapped[float | None] = mapped_column(MONEY)
    firewall_status: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=FirewallStatus.INVESTIGATE_ONLY.value
    )
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    source_url: Mapped[str | None] = mapped_column(Text)
    value_type: Mapped[str] = mapped_column(
        String(24), nullable=False, server_default=ValueType.OBSERVED.value
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        _check("firewall_status", FirewallStatus, "ck_political_firewall_status"),
        CheckConstraint(
            "disclosure_date >= transaction_date", name="ck_political_disclosure_after_txn"
        ),
        Index("ix_political_disclosure", "disclosure_date"),
    )


# --------------------------------------------------------------------------
# Macro
# --------------------------------------------------------------------------


class IntradayObservation(Base):
    """A price observed at a point in *time*, not merely on a date.

    Separate from `price_observations` on purpose. A daily bar is a settled,
    revisable summary of a session; an intraday print is a moment. Keying them
    the same way would force one of the two to lie about what it is.

    ## Delay is not optional metadata

    No free source provides real-time consolidated US equity quotes — exchanges
    license that feed, and a vendor giving it away would be breaching their own
    agreement. What free tiers provide is delayed, typically by 15 minutes.

    So `delay_seconds` is NOT NULL with no default. A caller writing a row must
    state how stale the print was, because a number nobody has labelled will
    eventually be read as live. `is_delayed` is derived and stored alongside so
    a reader scanning the table sees it without doing arithmetic.

    `observed_at` is when the price was true. `ingested_at` is when we learned
    it. The gap between them is the delay, and both are recorded rather than
    inferred.
    """

    __tablename__ = "intraday_observations"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    security_id: Mapped[int] = mapped_column(
        ForeignKey("securities.id", ondelete="RESTRICT"), nullable=False
    )
    #: The instant the price was true at the venue.
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    #: Bar interval in seconds (60, 300, 900...). NULL for a point quote.
    interval_seconds: Mapped[int | None] = mapped_column(Integer)

    open: Mapped[float | None] = mapped_column(PRICE)
    high: Mapped[float | None] = mapped_column(PRICE)
    low: Mapped[float | None] = mapped_column(PRICE)
    close: Mapped[float | None] = mapped_column(PRICE)
    volume: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="USD")

    #: How far behind real time this print was, as published by the source.
    #: Mandatory. There is no honest default.
    delay_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    is_delayed: Mapped[bool] = mapped_column(Boolean, nullable=False)

    source: Mapped[str] = mapped_column(String(32), nullable=False)
    value_type: Mapped[str] = mapped_column(
        String(24), nullable=False, server_default=ValueType.OBSERVED.value
    )
    data_quality_flag: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=DataQualityFlag.OK.value
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "security_id", "observed_at", "interval_seconds", "source",
            name="uq_intraday_sec_time_source",
        ),
        _check("value_type", ValueType, "ck_intraday_value_type"),
        _check("data_quality_flag", DataQualityFlag, "ck_intraday_dq_flag"),
        CheckConstraint("delay_seconds >= 0", name="ck_intraday_delay_non_negative"),
        # Keeps the derived flag honest: it must agree with the number.
        CheckConstraint(
            "(delay_seconds = 0 AND is_delayed = false) "
            "OR (delay_seconds > 0 AND is_delayed = true)",
            name="ck_intraday_delay_agrees",
        ),
        CheckConstraint(
            "(open IS NULL OR open >= 0) AND (high IS NULL OR high >= 0) "
            "AND (low IS NULL OR low >= 0) AND (close IS NULL OR close >= 0)",
            name="ck_intraday_non_negative",
        ),
        Index("ix_intraday_sec_time", "security_id", "observed_at"),
    )


class MacroObservation(Base):
    __tablename__ = "macro_observations"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    series_id: Mapped[str] = mapped_column(String(64), nullable=False)
    obs_date: Mapped[date] = mapped_column(Date, nullable=False)
    value: Mapped[float | None] = mapped_column(MONEY)
    unit: Mapped[str | None] = mapped_column(String(32))
    # FRED revises series; the vintage is what makes macro point-in-time honest.
    realtime_start: Mapped[date | None] = mapped_column(Date)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    value_type: Mapped[str] = mapped_column(
        String(24), nullable=False, server_default=ValueType.OBSERVED.value
    )
    data_quality_flag: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=DataQualityFlag.OK.value
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("series_id", "obs_date", "source", name="uq_macro_series_date_source"),
        _check("value_type", ValueType, "ck_macro_value_type"),
        Index("ix_macro_series_date", "series_id", "obs_date"),
    )


# --------------------------------------------------------------------------
# Data quality and provenance
# --------------------------------------------------------------------------


class DataConflict(Base):
    """Everything the validation gate rejects or flags lands here. Nothing is
    ever silently dropped and nothing is ever silently accepted.
    """

    __tablename__ = "data_conflicts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    table_name: Mapped[str] = mapped_column(String(64), nullable=False)
    entity_id: Mapped[int | None] = mapped_column(ForeignKey("entities.id"))
    security_id: Mapped[int | None] = mapped_column(ForeignKey("securities.id"))
    metric_name: Mapped[str | None] = mapped_column(String(128))
    obs_date: Mapped[date | None] = mapped_column(Date)
    conflict_type: Mapped[str] = mapped_column(String(48), nullable=False)
    severity: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=Severity.WARNING.value
    )
    source_a: Mapped[str | None] = mapped_column(String(32))
    value_a: Mapped[float | None] = mapped_column(MONEY)
    source_b: Mapped[str | None] = mapped_column(String(32))
    value_b: Mapped[float | None] = mapped_column(MONEY)
    pct_difference: Mapped[float | None] = mapped_column(RATIO)
    detail: Mapped[str | None] = mapped_column(Text)
    resolved: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    resolution_note: Mapped[str | None] = mapped_column(Text)
    detected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        _check("conflict_type", ConflictType, "ck_conflicts_type"),
        _check("severity", Severity, "ck_conflicts_severity"),
        Index("ix_conflicts_unresolved", "resolved", "detected_at"),
        Index("ix_conflicts_security", "security_id"),
    )


class ResearchSnapshot(Base):
    """An immutable record of one scoring run.

    `inputs_json` records exactly which data fed the scores so any number in a
    report can be reproduced months later. Protected by an append-only trigger.
    """

    __tablename__ = "research_snapshots"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entity_id: Mapped[int] = mapped_column(ForeignKey("entities.id"), nullable=False)
    security_id: Mapped[int | None] = mapped_column(ForeignKey("securities.id"))
    snapshot_date: Mapped[date] = mapped_column(Date, nullable=False)
    # The point-in-time cutoff the run was executed under.
    as_of_date: Mapped[date] = mapped_column(Date, nullable=False)
    model_version: Mapped[str] = mapped_column(String(32), nullable=False)

    investment_quality_score: Mapped[float | None] = mapped_column(RATIO)
    trade_setup_score: Mapped[float | None] = mapped_column(RATIO)
    confidence_score: Mapped[float | None] = mapped_column(RATIO)

    # Sub-component breakdowns — a score is never stored without its parts.
    components_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    inputs_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    warnings_json: Mapped[dict | None] = mapped_column(JSONB)
    report_text: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        Index("ix_snapshots_entity_date", "entity_id", "as_of_date"),
        CheckConstraint(
            "investment_quality_score IS NULL OR "
            "(investment_quality_score >= 0 AND investment_quality_score <= 100)",
            name="ck_snapshot_iq_range",
        ),
        CheckConstraint(
            "trade_setup_score IS NULL OR (trade_setup_score >= 0 AND trade_setup_score <= 100)",
            name="ck_snapshot_ts_range",
        ),
        CheckConstraint(
            "confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 100)",
            name="ck_snapshot_conf_range",
        ),
    )


class WorkflowJob(Base):
    __tablename__ = "workflow_jobs"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    job_type: Mapped[str] = mapped_column(String(48), nullable=False)
    target_ref: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=JobStatus.PENDING.value
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rows_written: Mapped[int | None] = mapped_column(Integer)
    rows_quarantined: Mapped[int | None] = mapped_column(Integer)
    error: Mapped[str | None] = mapped_column(Text)
    stats_json: Mapped[dict | None] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        _check("status", JobStatus, "ck_jobs_status"),
        Index("ix_jobs_type_status", "job_type", "status"),
    )


# --------------------------------------------------------------------------
# Premium-data-dependent tables
#
# Created empty and deliberately NOT populated in V1. Code that needs them
# must report PREMIUM-DATA DEPENDENT rather than substituting a guess.
# --------------------------------------------------------------------------


class AnalystEstimate(Base):
    """PREMIUM-DATA DEPENDENT — no free source in V1. Never populated."""

    __tablename__ = "analyst_estimates"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entity_id: Mapped[int] = mapped_column(ForeignKey("entities.id"), nullable=False)
    metric_name: Mapped[str] = mapped_column(String(64), nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    estimate_date: Mapped[date] = mapped_column(Date, nullable=False)
    mean_estimate: Mapped[float | None] = mapped_column(MONEY)
    analyst_count: Mapped[int | None] = mapped_column(Integer)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    value_type: Mapped[str] = mapped_column(
        String(24), nullable=False, server_default=ValueType.ESTIMATED.value
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class OptionsChainObservation(Base):
    """PREMIUM-DATA DEPENDENT — no free source in V1. Never populated."""

    __tablename__ = "options_chain_observations"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"), nullable=False)
    obs_date: Mapped[date] = mapped_column(Date, nullable=False)
    expiry: Mapped[date] = mapped_column(Date, nullable=False)
    strike: Mapped[float] = mapped_column(PRICE, nullable=False)
    option_type: Mapped[str] = mapped_column(String(4), nullable=False)
    implied_volatility: Mapped[float | None] = mapped_column(RATIO)
    open_interest: Mapped[int | None] = mapped_column(BigInteger)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


#: Tables the scoring engine must never treat as a score contributor.
FIREWALLED_TABLES: frozenset[str] = frozenset({PoliticalTrade.__tablename__})

#: Tables that exist but have no free data source in V1.
PREMIUM_DEPENDENT_TABLES: frozenset[str] = frozenset(
    {AnalystEstimate.__tablename__, OptionsChainObservation.__tablename__}
)

#: Append-only: protected by DB triggers rejecting UPDATE/DELETE.
APPEND_ONLY_TABLES: frozenset[str] = frozenset(
    {
        PriceObservation.__tablename__,
        Fundamental.__tablename__,
        IntradayObservation.__tablename__,
        ResearchSnapshot.__tablename__,
    }
)
