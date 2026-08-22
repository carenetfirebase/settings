"""Macro ingestion: FRED -> macro_observations.

Unlike prices and fundamentals, `macro_observations` is not append-only at the
database level — but revisions still arrive as new rows, keyed by
`realtime_start`, so the vintage history is preserved rather than overwritten.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from invest.db.enums import DataQualityFlag, JobStatus, ValueType
from invest.db.models import MacroObservation, WorkflowJob
from invest.providers.base import MacroPoint, ProviderError

logger = logging.getLogger(__name__)


@dataclass
class MacroIngestResult:
    series_id: str
    written: int = 0
    skipped: int = 0
    null_values: int = 0
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


def ingest_series(
    session: Session,
    provider,
    series_id: str,
    *,
    start: date | None = None,
    end: date | None = None,
    today: date | None = None,
) -> MacroIngestResult:
    today = today or date.today()
    result = MacroIngestResult(series_id)

    job = WorkflowJob(job_type="ingest_macro", target_ref=series_id, status=JobStatus.RUNNING)
    session.add(job)
    session.flush()

    try:
        points: list[MacroPoint] = provider.fetch_series(series_id, start=start, end=end)
    except ProviderError as exc:
        job.status = JobStatus.FAILED
        job.error = str(exc)
        session.flush()
        result.error = str(exc)
        return result

    existing = {
        (obs_date, source)
        for obs_date, source in session.execute(
            select(MacroObservation.obs_date, MacroObservation.source).where(
                MacroObservation.series_id == series_id
            )
        ).all()
    }

    for point in points:
        if point.obs_date > today:
            result.skipped += 1
            continue
        key = (point.obs_date, point.source)
        if key in existing:
            result.skipped += 1
            continue

        if point.value is None:
            result.null_values += 1

        session.add(
            MacroObservation(
                series_id=point.series_id,
                obs_date=point.obs_date,
                value=point.value,
                unit=point.unit,
                realtime_start=point.realtime_start,
                source=point.source,
                value_type=ValueType.OBSERVED,
                # A published-as-unavailable point is flagged so the regime
                # classifier can see the gap rather than inferring from silence.
                data_quality_flag=(
                    DataQualityFlag.MISSING if point.value is None else DataQualityFlag.OK
                ),
            )
        )
        existing.add(key)
        result.written += 1

    job.status = JobStatus.SUCCEEDED
    job.rows_written = result.written
    job.stats_json = {
        "written": result.written,
        "skipped": result.skipped,
        "null_values": result.null_values,
    }
    session.flush()
    return result


def get_macro_series(
    session: Session,
    series_id: str,
    *,
    as_of: date | None = None,
    limit: int | None = None,
) -> list[tuple[date, float]]:
    """Usable observations for a series, oldest first.

    NULL-valued points are excluded: a gap in the data is not a data point.
    `as_of` filters on the observation date and, where a vintage is recorded,
    on `realtime_start` — so a figure first published after the cutoff is
    invisible even if it describes an earlier period.
    """
    stmt = select(MacroObservation.obs_date, MacroObservation.value).where(
        MacroObservation.series_id == series_id,
        MacroObservation.value.is_not(None),
        MacroObservation.data_quality_flag != DataQualityFlag.QUARANTINED,
    )
    if as_of is not None:
        stmt = stmt.where(MacroObservation.obs_date <= as_of)
        stmt = stmt.where(
            (MacroObservation.realtime_start.is_(None))
            | (MacroObservation.realtime_start <= as_of)
        )
    stmt = stmt.order_by(MacroObservation.obs_date)

    rows = session.execute(stmt).all()
    series = [(obs_date, float(value)) for obs_date, value in rows]
    if limit is not None:
        series = series[-limit:]
    return series


def latest_macro_value(
    session: Session, series_id: str, *, as_of: date | None = None
) -> tuple[date, float] | None:
    """Most recent usable value, or None. Never a stale carry-forward that
    pretends to be current — the caller gets the observation date too and can
    decide whether it is fresh enough.
    """
    series = get_macro_series(session, series_id, as_of=as_of)
    return series[-1] if series else None
