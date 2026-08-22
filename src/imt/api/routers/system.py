"""Source health and data quality. Feeds the top bar and the sidebar ring."""

from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter
from sqlalchemy import select

from imt.api.envelope import Envelope, Meta, SourceState, SourceStatus
from imt.core.clock import utc_now
from imt.core.config import load_sources
from imt.db.models import IngestionRun
from imt.db.session import session_scope

router = APIRouter(tags=["system"])


def _status_for(
    last_success: datetime | None, threshold_hours: int, enabled: bool, blocked: str | None
) -> SourceStatus:
    """Map last-success age onto the five states the UI knows how to render.

    A disabled source and an enabled source that has never run are both
    "unavailable" to the user, but they are different situations and the
    ``reason`` field carries the distinction -- the panel says "awaiting API
    key" rather than implying something broke.
    """
    if not enabled or last_success is None:
        return "unavailable"
    age = utc_now() - last_success
    if age <= timedelta(hours=threshold_hours):
        return "current"
    if age <= timedelta(hours=threshold_hours * 2):
        return "delayed"
    return "stale"


@router.get("/system/sources", response_model=Envelope[list[SourceState]])
def list_sources() -> Envelope[list[SourceState]]:
    """KPI card 6 and the sidebar coverage ring read this.

    The source count is computed from config/sources.yaml -- UI_SPEC §2 is
    explicit that "15/15" must never be hardcoded.
    """
    configured = load_sources()["sources"]
    last_success: dict[str, datetime] = {}
    with session_scope() as session:
        rows = session.execute(
            select(IngestionRun.source_id, IngestionRun.finished_at)
            .where(IngestionRun.status == "success")
            .order_by(IngestionRun.source_id, IngestionRun.finished_at.desc())
        ).all()
        for source_id, finished in rows:
            last_success.setdefault(source_id, finished)

    states = [
        SourceState(
            id=source_id,
            status=_status_for(
                last_success.get(source_id),
                int(cfg.get("staleness_threshold_hours", 48)),
                bool(cfg.get("enabled", False)),
                cfg.get("blocked_reason"),
            ),
            last_success=last_success.get(source_id),
            reason=cfg.get("blocked_reason"),
        )
        for source_id, cfg in sorted(configured.items())
    ]
    return Envelope(data=states, meta=Meta(generated_at=utc_now(), sources=states))
