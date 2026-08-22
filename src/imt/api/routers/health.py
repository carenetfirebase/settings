"""Liveness and database reachability."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from sqlalchemy import text

from imt.core.logging import get_logger
from imt.db.session import get_engine

router = APIRouter(tags=["system"])
log = get_logger(__name__)


def health_payload() -> dict[str, Any]:
    """Phase 1 criterion 2 expects exactly {"status":"ok","db":"ok"}."""
    db_state = "ok"
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as exc:
        # Report the failure rather than 500ing: the top bar's status dot
        # needs to distinguish "API down" from "database down".
        db_state = "error"
        log.error("health.db_unreachable", error=str(exc))
    return {"status": "ok", "db": db_state}


@router.get("/health")
def health() -> dict[str, Any]:
    return health_payload()
