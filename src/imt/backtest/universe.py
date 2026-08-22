"""Universe reconstruction. SPEC §7.3, Phase 8 criteria 3 and 4.

A backtest over a historical window must use the universe **as it was on that
date**. Screening today's listed companies against 2024 data is survivorship
bias in its purest form: every company that failed between then and now has
been silently removed, and the surviving sample will show a positive result
for almost any signal.

Reconstruction reads `universe_snapshots`, which is why SPEC §2 makes that
table append-only and monthly, and why ARCHITECTURE §I flags that it must
start being written in Phase 2 rather than Phase 8 — a month that was never
captured cannot be recreated afterwards.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from imt.db.models import UniverseSnapshot


class UniverseSnapshotSet:
    """Membership intervals: ``(cik, first_seen, delisted_date)``.

    ``delisted_date`` of None means still listed. Testable without a database,
    which matters because the properties being checked here are about time
    rather than about storage.
    """

    def __init__(self, rows: Iterable[tuple[str, date, date | None]]) -> None:
        self._rows = list(rows)

    def members_on(self, as_of: date) -> frozenset[str]:
        return frozenset(
            cik
            for cik, first_seen, delisted in self._rows
            if first_seen <= as_of and (delisted is None or as_of <= delisted)
        )


def reconstruct_universe(snapshots: UniverseSnapshotSet, *, as_of: date) -> frozenset[str]:
    """Who was in the universe on ``as_of``. Not who is in it now."""
    return snapshots.members_on(as_of)


def load_snapshot_set(
    session: Session, *, ciks: Sequence[str] | None = None
) -> UniverseSnapshotSet:
    """Build the interval set from `universe_snapshots`.

    Membership is derived from the months a security actually appears in, so a
    gap in the snapshots shows up as a gap in membership rather than being
    smoothed over.
    """
    stmt = select(
        UniverseSnapshot.cik,
        UniverseSnapshot.snapshot_month,
        UniverseSnapshot.in_universe,
    ).order_by(UniverseSnapshot.cik, UniverseSnapshot.snapshot_month)
    if ciks:
        stmt = stmt.where(UniverseSnapshot.cik.in_(ciks))

    first_seen: dict[str, date] = {}
    last_seen: dict[str, date] = {}
    for cik, month, in_universe in session.execute(stmt):
        if not in_universe:
            continue
        first_seen.setdefault(cik, month)
        last_seen[cik] = month

    # A security whose most recent snapshot is the latest month overall is
    # still listed; one that stopped appearing earlier left the universe then.
    latest = max(last_seen.values(), default=None)
    rows = [
        (cik, first_seen[cik], None if last_seen[cik] == latest else last_seen[cik])
        for cik in sorted(first_seen)
    ]
    return UniverseSnapshotSet(rows)
