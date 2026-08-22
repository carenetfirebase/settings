"""Source health and data quality. Feeds the top bar and the sidebar ring."""

from __future__ import annotations

from fastapi import APIRouter

from imt.api.deps import SessionDep, source_states
from imt.api.envelope import Envelope, Meta, SourceState
from imt.core.clock import utc_now

router = APIRouter(tags=["system"])


@router.get("/system/sources", response_model=Envelope[list[SourceState]])
def list_sources(session: SessionDep) -> Envelope[list[SourceState]]:
    """KPI card 6 and the sidebar coverage ring read this.

    The source count is computed from config/sources.yaml -- UI_SPEC §2 is
    explicit that "15/15" must never be hardcoded.
    """
    states = source_states(session)
    return Envelope(data=states, meta=Meta(generated_at=utc_now(), sources=states))
