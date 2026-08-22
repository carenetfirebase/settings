"""Shared API dependencies.

``source_states`` is the single place the envelope's ``meta.sources`` block is
built. Every route uses it, so a panel's stale and failed states are driven by
the same computation rather than each route inventing its own idea of "stale".
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timedelta
from typing import Annotated

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from imt.api.envelope import SourceState, SourceStatus
from imt.core.clock import utc_now
from imt.core.config import load_sources
from imt.db.models import IngestionRun
from imt.db.session import get_sessionmaker


def get_session() -> Iterator[Session]:
    """Read-only session. The API never writes (docs/ARCHITECTURE.md §A)."""
    session = get_sessionmaker()()
    try:
        yield session
    finally:
        session.close()


SessionDep = Annotated[Session, Depends(get_session)]


def _status_for(last_success: datetime | None, threshold_hours: int, enabled: bool) -> SourceStatus:
    if not enabled or last_success is None:
        return "unavailable"
    age = utc_now() - last_success
    if age <= timedelta(hours=threshold_hours):
        return "current"
    if age <= timedelta(hours=threshold_hours * 2):
        return "delayed"
    return "stale"


def source_states(session: Session) -> list[SourceState]:
    """Per-source health, computed from config plus the last successful run.

    The source list comes from config/sources.yaml, never a hardcoded count
    (UI_SPEC §2).
    """
    configured = load_sources()["sources"]
    last_success: dict[str, datetime] = {}
    rows = session.execute(
        select(IngestionRun.source_id, IngestionRun.finished_at)
        .where(IngestionRun.status == "success")
        .order_by(IngestionRun.source_id, IngestionRun.finished_at.desc())
    ).all()
    for source_id, finished in rows:
        if finished is not None:
            last_success.setdefault(source_id, finished)

    return [
        SourceState(
            id=source_id,
            status=_status_for(
                last_success.get(source_id),
                int(cfg.get("staleness_threshold_hours", 48)),
                bool(cfg.get("enabled", False)),
            ),
            last_success=last_success.get(source_id),
            reason=cfg.get("blocked_reason"),
        )
        for source_id, cfg in sorted(configured.items())
    ]
