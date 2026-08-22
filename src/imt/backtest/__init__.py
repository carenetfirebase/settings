"""Point-in-time event studies.

Phase 8 is the phase that determines whether the rest of this system is real.
Everything before it is plumbing built on a hypothesis.
"""

from imt.backtest.engine import (
    DEFAULT_HORIZONS,
    EntryResult,
    Outcome,
    PriceSeries,
    SignalEntry,
    assert_no_lookahead,
    run_entry,
)
from imt.backtest.report import BacktestReport, build_report, walk_forward_splits
from imt.backtest.universe import UniverseSnapshotSet, reconstruct_universe

__all__ = [
    "DEFAULT_HORIZONS",
    "BacktestReport",
    "EntryResult",
    "Outcome",
    "PriceSeries",
    "SignalEntry",
    "UniverseSnapshotSet",
    "assert_no_lookahead",
    "build_report",
    "reconstruct_universe",
    "run_entry",
    "walk_forward_splits",
]
