"""Shared ingestion machinery: run tracking, raw retention, idempotency.

Every job follows the same shape — fetch, persist raw, normalize, emit events —
and each of those steps has a rule attached:

* **Raw first, always.** The payload lands in ``raw_documents`` before anything
  parses it. When a parser bug is found six weeks in, the fix is a re-parse of
  what is already on disk, not 350,000 fresh requests to an API that
  rate-limits at 10/s and bans on excess.
* **Idempotent by construction.** Re-running the same window writes zero
  duplicate rows (Phase 2 criterion 4). This is enforced by natural-key
  conflict clauses in the database, not by the job remembering what it did —
  a job that crashes halfway must be safe to re-run.
* **Every run is recorded.** ``ingestion_runs`` is what the API's
  ``meta.sources`` block reads, which is what drives the UI's stale and failed
  states. A job that fails silently would leave a panel claiming to be current.
"""

from __future__ import annotations

import hashlib
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from imt.core.clock import utc_now
from imt.core.config import load_sources
from imt.core.logging import get_logger
from imt.db.enums import IngestionStatus
from imt.db.models import DataSource, IngestionRun, RawDocument

log = get_logger(__name__)


@dataclass
class IngestResult:
    """What a job did. Printed by the CLI and stored on the run."""

    job: str
    source_id: str
    documents_fetched: int = 0
    rows_written: int = 0
    rows_skipped_duplicate: int = 0
    events_written: int = 0
    errors: list[str] = field(default_factory=list)

    def summary(self) -> str:
        return (
            f"{self.job}: {self.documents_fetched} documents, "
            f"{self.rows_written} rows written, "
            f"{self.rows_skipped_duplicate} duplicates skipped, "
            f"{self.events_written} events"
            + (f", {len(self.errors)} errors" if self.errors else "")
        )


def sync_data_sources(session: Session) -> int:
    """Mirror config/sources.yaml into ``data_sources``.

    The UI's source count is computed from this table, so it must reflect the
    config rather than a hand-maintained list — UI_SPEC §2 is explicit that
    "15/15" is never hardcoded.
    """
    configured = load_sources()["sources"]
    for source_id, cfg in configured.items():
        session.execute(
            pg_insert(DataSource)
            .values(
                id=source_id,
                name=cfg["name"],
                tier=int(cfg["tier"]),
                enabled=bool(cfg.get("enabled", False)),
                blocked_reason=cfg.get("blocked_reason"),
                staleness_threshold_hours=int(cfg.get("staleness_threshold_hours", 48)),
                automation=cfg.get("automation", "full"),
            )
            .on_conflict_do_update(
                index_elements=[DataSource.id],
                set_={
                    "name": cfg["name"],
                    "tier": int(cfg["tier"]),
                    "enabled": bool(cfg.get("enabled", False)),
                    "blocked_reason": cfg.get("blocked_reason"),
                    "staleness_threshold_hours": int(cfg.get("staleness_threshold_hours", 48)),
                    "automation": cfg.get("automation", "full"),
                },
            )
        )
    return len(configured)


@contextmanager
def ingestion_run(session: Session, *, job: str, source_id: str) -> Iterator[IngestResult]:
    """Record a run, whatever its outcome.

    A failure writes ``FAILED`` with the error rather than leaving no row: the
    API distinguishes "never ran" from "ran and failed", and the UI renders
    those as different panel states.
    """
    sync_data_sources(session)
    run = IngestionRun(
        source_id=source_id,
        job=job,
        started_at=utc_now(),
        status=IngestionStatus.RUNNING,
    )
    session.add(run)
    session.flush()

    result = IngestResult(job=job, source_id=source_id)
    try:
        yield result
    except Exception as exc:
        run.status = IngestionStatus.FAILED
        run.error = f"{type(exc).__name__}: {exc}"
        run.finished_at = utc_now()
        session.flush()
        session.commit()
        log.error("ingest.failed", job=job, source=source_id, error=str(exc))
        raise
    else:
        run.status = IngestionStatus.PARTIAL if result.errors else IngestionStatus.SUCCESS
        run.records_written = result.rows_written
        run.error = "; ".join(result.errors[:5]) if result.errors else None
        run.finished_at = utc_now()
        session.flush()
        log.info(
            "ingest.finished",
            job=job,
            source=source_id,
            rows=result.rows_written,
            duplicates=result.rows_skipped_duplicate,
        )


def persist_raw(
    session: Session,
    *,
    source_id: str,
    source_record_id: str,
    url: str,
    payload: bytes,
    content_type: str = "application/octet-stream",
    retrieved_at: datetime | None = None,
) -> tuple[int | None, bool]:
    """Append-only raw retention. Returns ``(id, was_new)``.

    Keyed by content hash, so re-fetching an unchanged document is a no-op and
    a *changed* document writes a second row rather than replacing the first.
    A database trigger rejects UPDATE and DELETE on this table, so the
    guarantee does not depend on every caller behaving.
    """
    content_hash = hashlib.sha256(payload).hexdigest()
    stmt = (
        pg_insert(RawDocument)
        .values(
            source_id=source_id,
            source_record_id=source_record_id,
            content_hash=content_hash,
            url=url,
            content_type=content_type,
            payload=payload,
            retrieved_at=retrieved_at or utc_now(),
        )
        .on_conflict_do_nothing(index_elements=["source_id", "source_record_id", "content_hash"])
        .returning(RawDocument.id)
    )
    new_id = session.execute(stmt).scalar_one_or_none()
    if new_id is not None:
        return new_id, True

    existing = session.execute(
        select(RawDocument.id).where(
            RawDocument.source_id == source_id,
            RawDocument.source_record_id == source_record_id,
            RawDocument.content_hash == content_hash,
        )
    ).scalar_one_or_none()
    return existing, False


def event_id(*parts: str) -> str:
    """Deterministic event identifier.

    Derived from the natural key rather than random, so re-running an ingest
    produces the same ids and the conflict clause can do its job. A UUID here
    would make every re-run look like new events.
    """
    digest = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
    return f"evt_{digest[:32]}"


def as_utc(value: datetime) -> datetime:
    return value.astimezone(UTC) if value.tzinfo else value.replace(tzinfo=UTC)
