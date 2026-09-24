"""Read-only routes for the V1 signal engine and the Lab.

Same rules as the rest of the API: GET only, every request inside a
read-only transaction, `as_of` everywhere. Scanning here computes signals
but never records them; the ledger is written only by `invest signals record`
and `invest signals evaluate`, so nothing a browser does can alter the record.
"""

from __future__ import annotations

from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from invest.api.deps import as_of_param, get_readonly_session
from invest.config import get_settings
from invest.ledger import attribution, calibration, load_ledger
from invest.signal_runner import market_state, scan
from invest.universe import BENCHMARK_FUND

router = APIRouter()

Origin = Literal["live", "backfill"]

LEDGER_NOTE = (
    "Every candidate is recorded, fired or blocked, so the gates can be tested. "
    "'backfill' rows are point-in-time but scanned over today's universe, so they "
    "carry survivorship bias and are not a track record."
)


@router.get("/signals/gate", tags=["signals"])
def signals_gate(
    as_of: date | None = Depends(as_of_param),
    session: Session = Depends(get_readonly_session),
) -> dict:
    """The market trend gate and volatility scale. Cheap: scans no stocks."""
    state = market_state(session, as_of=as_of)
    payload = state.as_dict()
    return {
        "as_of": payload["as_of"],
        "model_version": payload["model_version"],
        "benchmark": BENCHMARK_FUND,
        "gate": payload["gate"],
        "volatility": payload["volatility"],
        "warnings": payload["warnings"],
    }


@router.get("/signals/scan", tags=["signals"])
def signals_scan(
    as_of: date | None = Depends(as_of_param),
    session: Session = Depends(get_readonly_session),
) -> dict:
    """Run the engine over the universe. Computes; never records."""
    return scan(session, as_of=as_of, equity=get_settings().account_equity).as_dict()


@router.get("/signals/ledger", tags=["signals"])
def signals_ledger(
    origin: Origin | None = Query(None),
    fired_only: bool = Query(False),
    ticker: str | None = Query(None),
    limit: int = Query(500, ge=1, le=5000),
    session: Session = Depends(get_readonly_session),
) -> dict:
    """Recorded signals with their latest outcome, newest first."""
    rows = load_ledger(session, origin=origin, fired_only=fired_only, ticker=ticker, limit=limit)
    return {"count": len(rows), "note": LEDGER_NOTE, "entries": [r.as_dict() for r in rows]}


@router.get("/markets/sectors", tags=["signals"])
def markets_sectors(
    as_of: date | None = Depends(as_of_param),
    session: Session = Depends(get_readonly_session),
) -> dict:
    """Sector funds ranked by 12-1 month momentum relative to the benchmark."""
    payload = market_state(session, as_of=as_of).as_dict()
    return {
        "as_of": payload["as_of"],
        "benchmark": BENCHMARK_FUND,
        "sectors": payload["sectors"],
        "warnings": payload["warnings"],
    }


@router.get("/lab/calibration", tags=["lab"])
def lab_calibration(
    origin: Origin | None = Query(None),
    fired_only: bool = Query(True),
    session: Session = Depends(get_readonly_session),
) -> dict:
    """Outcomes by score bucket: does a higher score earn more?"""
    rows = load_ledger(session, origin=origin, fired_only=fired_only)
    return calibration(rows, origin=origin, fired_only=fired_only).as_dict()


@router.get("/lab/attribution", tags=["lab"])
def lab_attribution(
    origin: Origin | None = Query(None),
    session: Session = Depends(get_readonly_session),
) -> dict:
    """Blocked candidates versus fired ones: does each gate earn its place?"""
    rows = load_ledger(session, origin=origin)
    return attribution(rows, origin=origin).as_dict()
