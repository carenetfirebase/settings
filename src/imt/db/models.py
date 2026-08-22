"""The schema. docs/ARCHITECTURE.md §D.

Three conventions run through all of it:

* **Money is ``BigInteger`` minor units plus a currency column.** Never float,
  never numeric. ``numeric`` is reserved for ratios and scores.
* **``public_available_at`` is the backtest clock.** It is NOT NULL wherever an
  event can be entered on, so there is no code path that can time an entry off
  the underlying transaction date (SPEC §7.1).
* **Missing is NULL plus a reason code**, never zero and never an estimate.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from imt.db.base import Base, SourcedMixin
from imt.db.enums import (
    CompanyStatus,
    ContradictionStatus,
    DataQuality,
    IngestionStatus,
    NormalizationMethod,
    OwnerType,
    ParseOutcome,
    SignalCategory,
)
from imt.db.types import pg_enum

CIK = String(10)


def _category_enum(name: str = "signal_category") -> Enum:
    return pg_enum(SignalCategory, name)


# ─────────────────────────── identity and time ────────────────────────────


class Company(Base):
    """One row per CIK. Append-only: a delisted name is marked, never deleted."""

    __tablename__ = "companies"

    cik: Mapped[str] = mapped_column(CIK, primary_key=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    sic: Mapped[str | None] = mapped_column(String(4))
    sector_code: Mapped[str] = mapped_column(String(32), nullable=False, default="unknown")
    status: Mapped[CompanyStatus] = mapped_column(
        pg_enum(CompanyStatus, "company_status"),
        nullable=False,
        default=CompanyStatus.ACTIVE,
    )
    first_seen: Mapped[date] = mapped_column(Date, nullable=False)
    last_seen: Mapped[date] = mapped_column(Date, nullable=False)
    delisted_date: Mapped[date | None] = mapped_column(Date)
    # Why this company is in the universe. The 10-K/10-Q proxy for "common
    # equity" is wrong at the margins in both directions (ARCHITECTURE §C.2),
    # so the reason is recorded and the errors stay auditable.
    inclusion_reason: Mapped[str | None] = mapped_column(Text)

    __table_args__ = (Index("ix_companies_sector", "sector_code"),)


class TickerMapRow(Base):
    """Point-in-time ticker → CIK. Tickers are reused; joins need a date."""

    __tablename__ = "ticker_map"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), nullable=False)
    ticker: Mapped[str] = mapped_column(String(16), nullable=False)
    exchange: Mapped[str | None] = mapped_column(String(32))
    valid_from: Mapped[date] = mapped_column(Date, nullable=False)
    valid_to: Mapped[date | None] = mapped_column(Date)

    __table_args__ = (
        UniqueConstraint("cik", "ticker", "valid_from", name="uq_ticker_map_period"),
        Index("ix_ticker_map_lookup", "ticker", "valid_from"),
        CheckConstraint("valid_to IS NULL OR valid_to >= valid_from", name="ck_ticker_map_order"),
    )


class UniverseSnapshot(Base):
    """One row per security per month. Backtests reconstruct from here.

    A month not captured cannot be recreated later, so this starts writing in
    Phase 2, not Phase 8 (ARCHITECTURE §I).
    """

    __tablename__ = "universe_snapshots"

    snapshot_month: Mapped[date] = mapped_column(Date, primary_key=True)
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    ticker: Mapped[str | None] = mapped_column(String(16))
    in_universe: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[CompanyStatus] = mapped_column(
        pg_enum(CompanyStatus, "company_status", create_type=False),
        nullable=False,
    )


# ───────────────────────── raw and operational ────────────────────────────


class RawDocument(Base):
    """Append-only bedrock. Everything downstream is derivable from here.

    The primary key includes the content hash, so a changed response writes a
    new row rather than overwriting one. A database trigger additionally
    rejects UPDATE and DELETE (CLAUDE.md non-negotiable #3) — without it,
    "append-only" is a comment rather than a guarantee.
    """

    __tablename__ = "raw_documents"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    source_id: Mapped[str] = mapped_column(String(64), nullable=False)
    source_record_id: Mapped[str] = mapped_column(String(255), nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    url: Mapped[str] = mapped_column(Text, nullable=False)
    content_type: Mapped[str] = mapped_column(
        String(128), nullable=False, default="application/octet-stream"
    )
    payload: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    retrieved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    __table_args__ = (
        UniqueConstraint(
            "source_id", "source_record_id", "content_hash", name="uq_raw_documents_identity"
        ),
        Index("ix_raw_documents_source", "source_id", "retrieved_at"),
    )


class DataSource(Base):
    """Mirrors config/sources.yaml. The UI's source counts read from here."""

    __tablename__ = "data_sources"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    tier: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    blocked_reason: Mapped[str | None] = mapped_column(Text)
    staleness_threshold_hours: Mapped[int] = mapped_column(Integer, nullable=False, default=48)
    automation: Mapped[str] = mapped_column(String(16), nullable=False, default="full")


class IngestionRun(Base):
    """Drives every ``meta.sources`` block in the API envelope."""

    __tablename__ = "ingestion_runs"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    source_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("data_sources.id"), nullable=False
    )
    job: Mapped[str] = mapped_column(String(64), nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    status: Mapped[IngestionStatus] = mapped_column(
        pg_enum(IngestionStatus, "ingestion_status"), nullable=False
    )
    records_written: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error: Mapped[str | None] = mapped_column(Text)

    __table_args__ = (Index("ix_ingestion_runs_source_time", "source_id", "started_at"),)


# ──────────────────────────────  evidence  ─────────────────────────────────


class Filing(Base):
    __tablename__ = "filings"

    accession: Mapped[str] = mapped_column(String(25), primary_key=True)
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), nullable=False)
    form_type: Mapped[str] = mapped_column(String(16), nullable=False)
    filed_date: Mapped[date] = mapped_column(Date, nullable=False)
    # SPEC §7.1: EDGAR acceptance, and the first moment it could be acted on.
    acceptance_datetime: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    public_available_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    primary_doc_url: Mapped[str] = mapped_column(Text, nullable=False)
    items: Mapped[list[str] | None] = mapped_column(ARRAY(Text))

    __table_args__ = (
        Index("ix_filings_cik_form", "cik", "form_type", "filed_date"),
        Index("ix_filings_available", "public_available_at"),
    )


class InsiderTransaction(Base, SourcedMixin):
    """Form 4 / Form 144. SPEC §8 — transaction codes are not interchangeable."""

    __tablename__ = "insider_transactions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    filing_accession: Mapped[str] = mapped_column(
        String(25), ForeignKey("filings.accession"), nullable=False
    )
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), nullable=False)
    insider_cik: Mapped[str | None] = mapped_column(CIK)
    insider_name: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[str | None] = mapped_column(String(64))
    is_officer: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_director: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_ten_percent_owner: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    transaction_code: Mapped[str] = mapped_column(String(1), nullable=False)
    transaction_date: Mapped[date] = mapped_column(Date, nullable=False)
    shares: Mapped[float | None] = mapped_column(Numeric(20, 4))
    price_minor: Mapped[int | None] = mapped_column(BigInteger)
    value_minor: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")
    shares_owned_after: Mapped[float | None] = mapped_column(Numeric(20, 4))
    is_10b5_1: Mapped[bool | None] = mapped_column(Boolean)
    is_amendment: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    # Why a value is missing, when it is. Never a zero standing in for unknown.
    reason_code: Mapped[str | None] = mapped_column(String(64))

    __table_args__ = (
        UniqueConstraint(
            "filing_accession",
            "insider_name",
            "transaction_code",
            "transaction_date",
            "shares",
            "price_minor",
            name="uq_insider_transaction_identity",
        ),
        Index("ix_insider_cik_date", "cik", "transaction_date"),
        Index("ix_insider_code", "transaction_code"),
    )


class CongressionalTransaction(Base, SourcedMixin):
    """House PTR / Senate eFD.

    **There is no single-amount column and there never will be.** Disclosures
    report brackets; a midpoint is an estimate, and storing an estimate in a
    column named ``amount`` is how it later gets read as a fact. The midpoint
    exists only as a derived feature carrying the reason code
    ``derived_bracket_midpoint`` (SPEC §8). Phase 4 criterion 8 asserts this.
    """

    __tablename__ = "congressional_transactions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    filer_name: Mapped[str] = mapped_column(Text, nullable=False)
    filer_id: Mapped[str] = mapped_column(String(64), nullable=False)
    chamber: Mapped[str] = mapped_column(String(8), nullable=False)
    owner_type: Mapped[OwnerType] = mapped_column(
        pg_enum(OwnerType, "owner_type"),
        nullable=False,
        default=OwnerType.UNKNOWN,
    )
    cik: Mapped[str | None] = mapped_column(CIK, ForeignKey("companies.cik"))
    asset_description: Mapped[str] = mapped_column(Text, nullable=False)
    transaction_type: Mapped[str] = mapped_column(String(16), nullable=False)

    transaction_date: Mapped[date] = mapped_column(Date, nullable=False)
    disclosure_date: Mapped[date] = mapped_column(Date, nullable=False)
    disclosure_lag_days: Mapped[int] = mapped_column(Integer, nullable=False)

    value_low_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    value_high_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")

    parse_outcome: Mapped[ParseOutcome] = mapped_column(
        pg_enum(ParseOutcome, "parse_outcome"), nullable=False
    )
    entity_match_confidence: Mapped[float | None] = mapped_column(Numeric(4, 3))

    __table_args__ = (
        CheckConstraint("disclosure_lag_days >= 0", name="ck_congress_lag_nonneg"),
        CheckConstraint("value_high_minor >= value_low_minor", name="ck_congress_bracket_order"),
        CheckConstraint("disclosure_date >= transaction_date", name="ck_congress_date_order"),
        UniqueConstraint(
            "filer_id",
            "transaction_date",
            "asset_description",
            "transaction_type",
            "value_low_minor",
            name="uq_congress_identity",
        ),
        Index("ix_congress_cik_date", "cik", "transaction_date"),
        Index("ix_congress_disclosure", "disclosure_date"),
    )


class ActivistPosition(Base, SourcedMixin):
    """13D vs 13G. Conflating them is a correctness bug (SPEC §8)."""

    __tablename__ = "activist_positions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    filing_accession: Mapped[str] = mapped_column(
        String(25), ForeignKey("filings.accession"), nullable=False
    )
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), nullable=False)
    filer_name: Mapped[str] = mapped_column(Text, nullable=False)
    # True for 13D (active intent), False for 13G (passive). Never inferred.
    is_activist: Mapped[bool] = mapped_column(Boolean, nullable=False)
    pct_of_class: Mapped[float | None] = mapped_column(Numeric(8, 4))
    shares: Mapped[float | None] = mapped_column(Numeric(20, 4))
    item4_categories: Mapped[list[str] | None] = mapped_column(ARRAY(Text))

    __table_args__ = (
        UniqueConstraint("filing_accession", "filer_name", name="uq_activist_identity"),
        Index("ix_activist_cik", "cik", "effective_date"),
    )


class GovernmentContract(Base, SourcedMixin):
    __tablename__ = "government_contracts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    cik: Mapped[str | None] = mapped_column(CIK, ForeignKey("companies.cik"))
    recipient_uei: Mapped[str | None] = mapped_column(String(16))
    recipient_name: Mapped[str] = mapped_column(Text, nullable=False)
    award_id: Mapped[str] = mapped_column(String(128), nullable=False)
    award_amount_minor: Mapped[int] = mapped_column(BigInteger, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")
    action_date: Mapped[date] = mapped_column(Date, nullable=False)
    agency: Mapped[str | None] = mapped_column(Text)
    naics: Mapped[str | None] = mapped_column(String(8))
    entity_match_confidence: Mapped[float | None] = mapped_column(Numeric(4, 3))

    __table_args__ = (
        UniqueConstraint(
            "award_id", "action_date", "award_amount_minor", name="uq_contract_identity"
        ),
        Index("ix_contract_cik_date", "cik", "action_date"),
    )


class XbrlFact(Base, SourcedMixin):
    """Append-only. A restatement inserts a row; it never updates one.

    A backtest asks "what was known on date D", which is a query over
    ``filed_date <= D`` — that only works if the original figure is still here.
    """

    __tablename__ = "xbrl_facts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), nullable=False)
    tag: Mapped[str] = mapped_column(String(128), nullable=False)
    unit: Mapped[str] = mapped_column(String(32), nullable=False)
    period_start: Mapped[date | None] = mapped_column(Date)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    fiscal_period: Mapped[str | None] = mapped_column(String(8))
    filed_date: Mapped[date] = mapped_column(Date, nullable=False)
    value: Mapped[float] = mapped_column(Numeric(28, 6), nullable=False)
    accession: Mapped[str | None] = mapped_column(String(25))

    __table_args__ = (
        UniqueConstraint(
            "cik",
            "tag",
            "unit",
            "period_end",
            "filed_date",
            "accession",
            name="uq_xbrl_fact_identity",
        ),
        Index("ix_xbrl_asof", "cik", "tag", "filed_date"),
    )


class PriceDaily(Base, SourcedMixin):
    """Adjusted EOD series. SPEC §4: adjusted-only, so a split restates history."""

    __tablename__ = "prices_daily"

    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    trade_date: Mapped[date] = mapped_column(Date, primary_key=True)
    open: Mapped[float | None] = mapped_column(Numeric(18, 6))
    high: Mapped[float | None] = mapped_column(Numeric(18, 6))
    low: Mapped[float | None] = mapped_column(Numeric(18, 6))
    close: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)
    volume: Mapped[int | None] = mapped_column(BigInteger)
    is_adjusted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    __table_args__ = (Index("ix_prices_date", "trade_date"),)


class BenchmarkPriceDaily(Base, SourcedMixin):
    """Index and sector-ETF series, keyed by symbol rather than CIK."""

    __tablename__ = "benchmark_prices_daily"

    symbol: Mapped[str] = mapped_column(String(16), primary_key=True)
    trade_date: Mapped[date] = mapped_column(Date, primary_key=True)
    close: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False)


class ShortInterest(Base, SourcedMixin):
    """Bi-monthly settlement figures. NOT short volume — see ShortVolume."""

    __tablename__ = "short_interest"

    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    settlement_date: Mapped[date] = mapped_column(Date, primary_key=True)
    publication_date: Mapped[date] = mapped_column(Date, nullable=False)
    shares_short: Mapped[int] = mapped_column(BigInteger, nullable=False)
    # SPEC §4: free float is not available, so this is against shares
    # outstanding and the column name says so. There is no float column.
    pct_shares_outstanding: Mapped[float | None] = mapped_column(Numeric(8, 4))
    days_to_cover: Mapped[float | None] = mapped_column(Numeric(10, 4))


class ShortVolume(Base, SourcedMixin):
    """Daily short-sale volume. A different quantity from short interest.

    Deliberately a separate table with no foreign key relationship to
    ``short_interest``. Phase 7 criterion 3 asserts no view joins them into a
    single "short" figure.
    """

    __tablename__ = "short_volume"

    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    trade_date: Mapped[date] = mapped_column(Date, primary_key=True)
    short_volume: Mapped[int] = mapped_column(BigInteger, nullable=False)
    total_volume: Mapped[int] = mapped_column(BigInteger, nullable=False)


class MacroObservation(Base, SourcedMixin):
    """SPEC §7.1: the clock is the release timestamp, not the reference period."""

    __tablename__ = "macro_observations"

    series_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    reference_period: Mapped[date] = mapped_column(Date, primary_key=True)
    release_timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), primary_key=True)
    value: Mapped[float | None] = mapped_column(Numeric(24, 6))
    reason_code: Mapped[str | None] = mapped_column(String(64))


# ─────────────────── resolution, signals, and scores ──────────────────────


class EntityMatchRow(Base):
    __tablename__ = "entity_matches"

    source: Mapped[str] = mapped_column(String(64), primary_key=True)
    source_key: Mapped[str] = mapped_column(String(512), primary_key=True)
    resolved_cik: Mapped[str | None] = mapped_column(CIK, ForeignKey("companies.cik"))
    method: Mapped[str] = mapped_column(String(32), nullable=False)
    confidence: Mapped[float] = mapped_column(Numeric(4, 3), nullable=False)
    resolved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    reviewed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    __table_args__ = (
        CheckConstraint("confidence >= 0 AND confidence <= 1", name="ck_entity_confidence_range"),
        # Partial index: the review queue reads exactly this slice.
        Index(
            "ix_entity_matches_below_gate",
            "source",
            postgresql_where=text("confidence < 0.85"),
        ),
    )


class EntityReviewQueue(Base):
    """Sub-0.85 matches. Never dropped, never force-matched (SPEC §5.2)."""

    __tablename__ = "entity_review_queue"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    source: Mapped[str] = mapped_column(String(64), nullable=False)
    source_key: Mapped[str] = mapped_column(String(512), nullable=False)
    free_text: Mapped[str | None] = mapped_column(Text)
    candidates: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    best_confidence: Mapped[float] = mapped_column(Numeric(4, 3), nullable=False)
    queued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    resolved_cik: Mapped[str | None] = mapped_column(CIK)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (UniqueConstraint("source", "source_key", name="uq_review_queue_identity"),)


class SignalEvent(Base, SourcedMixin):
    """The unification point. Every evidence-bearing fact writes one row.

    Without this, ``GET /feed`` is an eight-way UNION that must be edited for
    every new source, and the two-dates rule has to be re-enforced in eight
    places. With it, the rule is a CHECK constraint in one table.
    """

    __tablename__ = "signal_events"

    event_id: Mapped[str] = mapped_column(String(40), primary_key=True)
    category: Mapped[SignalCategory] = mapped_column(_category_enum(), nullable=False)
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), nullable=False)

    detected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    transaction_date: Mapped[date | None] = mapped_column(Date)
    disclosure_date: Mapped[date | None] = mapped_column(Date)
    disclosure_lag_days: Mapped[int | None] = mapped_column(Integer)
    # SPEC §7.1. The only clock a backtest is allowed to use.
    public_available_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    headline: Mapped[str] = mapped_column(Text, nullable=False)
    value_low_minor: Mapped[int | None] = mapped_column(BigInteger)
    value_high_minor: Mapped[int | None] = mapped_column(BigInteger)
    value_exact_minor: Mapped[int | None] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")
    entity_match_confidence: Mapped[float | None] = mapped_column(Numeric(4, 3))
    # Groups events that describe the same underlying occurrence across
    # categories -- an 8-K announcing an award and the USAspending record of
    # that award. Convergence de-duplicates on this (ARCHITECTURE §I).
    underlying_event_key: Mapped[str | None] = mapped_column(String(128))
    actor_key: Mapped[str | None] = mapped_column(String(128))

    __table_args__ = (
        CheckConstraint(
            "(category NOT IN ('political','corporate_insider','institutional')) "
            "OR (transaction_date IS NOT NULL AND disclosure_date IS NOT NULL)",
            name="ck_signal_events_two_dates",
        ),
        CheckConstraint(
            "(value_exact_minor IS NOT NULL)::int "
            "+ (value_low_minor IS NOT NULL AND value_high_minor IS NOT NULL)::int <= 1",
            name="ck_signal_events_value_exclusive",
        ),
        CheckConstraint(
            "value_high_minor IS NULL OR value_low_minor IS NULL "
            "OR value_high_minor >= value_low_minor",
            name="ck_signal_events_range_order",
        ),
        Index("ix_signal_events_cik_available", "cik", "public_available_at"),
        Index("ix_signal_events_category_time", "category", "detected_at"),
        Index("ix_signal_events_underlying", "underlying_event_key"),
    )


class SignalFeature(Base):
    """Raw computed quantities with units. Never displayed as a score (SPEC §6.1).

    A missing value is NULL plus ``reason_code``. Zero is a measurement.
    """

    __tablename__ = "signal_features"

    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    as_of: Mapped[date] = mapped_column(Date, primary_key=True)
    feature_key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[float | None] = mapped_column(Numeric(24, 6))
    unit: Mapped[str] = mapped_column(String(24), nullable=False)
    reason_code: Mapped[str | None] = mapped_column(String(64))
    category: Mapped[SignalCategory] = mapped_column(
        _category_enum("signal_category_feature"), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            "value IS NOT NULL OR reason_code IS NOT NULL",
            name="ck_signal_features_missing_has_reason",
        ),
    )


class Score(Base):
    """One row per company per as-of date. SPEC §6.7."""

    __tablename__ = "scores"

    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    as_of: Mapped[date] = mapped_column(Date, primary_key=True)

    research_priority: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False)
    confidence: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False)
    convergence: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False)
    contradiction: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False)
    freshness: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False)
    data_quality: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False)
    base: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False)

    category_scores: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    categories_cleared: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    categories_total: Mapped[int] = mapped_column(SmallInteger, nullable=False)

    # SPEC §6.8 — non-nullable by design. A score without its provenance is
    # indistinguishable from a magic number.
    weights_version: Mapped[str] = mapped_column(String(32), nullable=False)
    normalization: Mapped[NormalizationMethod] = mapped_column(
        pg_enum(NormalizationMethod, "normalization_method"), nullable=False
    )
    weights_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    __table_args__ = (
        Index("ix_scores_ranking", "as_of", "research_priority"),
        CheckConstraint("categories_cleared <= categories_total", name="ck_scores_cleared_bound"),
    )


class ContradictionItem(Base):
    """One row per check per company per date.

    ``UNAVAILABLE`` is distinct from ``CLEAR`` on purpose: "we looked and found
    nothing" and "we have not ingested the data to look" are different claims,
    and only the first one justifies a high score.
    """

    __tablename__ = "contradiction_items"

    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    as_of: Mapped[date] = mapped_column(Date, primary_key=True)
    check_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    status: Mapped[ContradictionStatus] = mapped_column(
        pg_enum(ContradictionStatus, "contradiction_status"), nullable=False
    )
    severity: Mapped[float] = mapped_column(Numeric(6, 3), nullable=False, default=0)
    detail: Mapped[str | None] = mapped_column(Text)
    source_url: Mapped[str | None] = mapped_column(Text)


class LlmOutput(Base):
    """SPEC §9. The LLM writes here and nowhere else.

    A test asserts no module under ``imt/llm`` writes a numeric column
    anywhere. Everything is stored with enough provenance to reproduce it.
    """

    __tablename__ = "llm_outputs"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), nullable=False)
    as_of: Mapped[date] = mapped_column(Date, nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    model: Mapped[str] = mapped_column(String(128), nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(32), nullable=False)
    temperature: Mapped[float] = mapped_column(Float, nullable=False)
    fact_set_hash: Mapped[str] = mapped_column(String(80), nullable=False)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    __table_args__ = (Index("ix_llm_outputs_lookup", "cik", "as_of", "kind"),)


class Watchlist(Base):
    __tablename__ = "watchlists"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class WatchlistMember(Base):
    __tablename__ = "watchlist_members"

    watchlist_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("watchlists.id"), primary_key=True
    )
    cik: Mapped[str] = mapped_column(CIK, ForeignKey("companies.cik"), primary_key=True)
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


__all__ = [
    "ActivistPosition",
    "BenchmarkPriceDaily",
    "Company",
    "CongressionalTransaction",
    "ContradictionItem",
    "DataQuality",
    "DataSource",
    "EntityMatchRow",
    "EntityReviewQueue",
    "Filing",
    "GovernmentContract",
    "IngestionRun",
    "InsiderTransaction",
    "LlmOutput",
    "MacroObservation",
    "PriceDaily",
    "RawDocument",
    "Score",
    "ShortInterest",
    "ShortVolume",
    "SignalEvent",
    "SignalFeature",
    "TickerMapRow",
    "UniverseSnapshot",
    "Watchlist",
    "WatchlistMember",
    "XbrlFact",
]
