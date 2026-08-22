"""Declarative base and the provenance mixin.

CLAUDE.md: "Every persisted fact carries source_id, retrieved_at,
effective_date, source_document_url, source_record_id, data_quality. This is a
schema constraint, not a convention."

Making it a mixin means it cannot be forgotten by omission. A test additionally
reflects the metadata and fails if any table holding an external fact is
missing one of the six, which catches the case where someone defines a table
without the mixin.
"""

from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import Date, DateTime, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from imt.db.enums import DataQuality
from imt.db.types import pg_enum


class Base(DeclarativeBase):
    pass


class SourcedMixin:
    """The six provenance columns. Every external fact carries them."""

    source_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    retrieved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    effective_date: Mapped[date] = mapped_column(Date, nullable=False)
    source_document_url: Mapped[str] = mapped_column(Text, nullable=False)
    source_record_id: Mapped[str] = mapped_column(String(255), nullable=False)
    data_quality: Mapped[DataQuality] = mapped_column(
        pg_enum(DataQuality, "data_quality"),
        nullable=False,
        default=DataQuality.CURRENT,
    )


#: Names a table must define to satisfy the provenance rule. Used by the test
#: that reflects the schema, so the list lives next to the mixin it describes.
PROVENANCE_COLUMNS: frozenset[str] = frozenset(
    {
        "source_id",
        "retrieved_at",
        "effective_date",
        "source_document_url",
        "source_record_id",
        "data_quality",
    }
)

#: Tables that legitimately hold no external fact and so are exempt: derived
#: results, operational bookkeeping, and user state.
PROVENANCE_EXEMPT: frozenset[str] = frozenset(
    {
        "alembic_version",
        "companies",
        "universe_snapshots",
        "ticker_map",
        "data_sources",
        "ingestion_runs",
        "raw_documents",
        "entity_matches",
        "entity_review_queue",
        "signal_features",
        "scores",
        "contradiction_items",
        "llm_outputs",
        "watchlists",
        "watchlist_members",
    }
)
