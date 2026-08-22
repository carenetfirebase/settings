"""Point-in-time event study. SPEC §7, docs/PHASES.md Phase 8.

> "This is the phase that determines whether any of the above is real."

Everything before this is plumbing built on a hypothesis: that insider
clusters, congressional disclosures and the rest precede abnormal returns.
This module is where that hypothesis meets evidence, and it is built to make
the honest answer reachable — including when the honest answer is "no".

## The entry clock

An entry uses ``public_available_at`` and nothing else. Not the transaction
date, not the filing date printed on a document, not the settlement date. The
engine's signature does not accept an alternative, so the look-ahead bug
cannot be introduced by a caller — only by editing this file, where the
assertion below would catch it.

For a congressional PTR the difference is six weeks of return. Using the
transaction date would produce a backtest that looks far better than reality
and is inadmissible; Phase 8 criterion 2 tests exactly that divergence.

## Survivorship

The universe is reconstructed per entry date from ``universe_snapshots``, and
delisted names stay in the result with a terminal outcome code. Filtering to
companies that still exist today is the classic way to manufacture a positive
backtest out of nothing.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum

DEFAULT_HORIZONS: tuple[int, ...] = (1, 5, 20, 60, 120, 250)


class Outcome(StrEnum):
    """How a position ended.

    ``DELISTED``, ``ACQUIRED`` and ``MERGED`` are distinct from ``OPEN``
    because dropping them would be survivorship bias and treating them as
    zero-return would be a fabrication.
    """

    COMPLETE = "complete"
    OPEN = "open"
    DELISTED = "delisted"
    ACQUIRED = "acquired"
    MERGED = "merged"
    NO_PRICE_DATA = "no_price_data"


@dataclass(frozen=True, slots=True)
class SignalEntry:
    """One backtest entry.

    ``public_available_at`` is mandatory and is the only timestamp the engine
    reads. ``transaction_date`` is carried for reporting the lag, never for
    timing.
    """

    cik: str
    signal: str
    public_available_at: datetime
    transaction_date: date | None = None
    metadata: dict[str, object] = field(default_factory=dict)

    @property
    def entry_date(self) -> date:
        return self.public_available_at.date()

    @property
    def disclosure_lag_days(self) -> int | None:
        if self.transaction_date is None:
            return None
        return (self.entry_date - self.transaction_date).days


@dataclass(frozen=True, slots=True)
class HorizonReturn:
    horizon_days: int
    raw: float | None
    benchmark_excess: float | None
    sector_excess: float | None
    outcome: Outcome


@dataclass(frozen=True, slots=True)
class EntryResult:
    entry: SignalEntry
    entry_timestamp: datetime
    entry_price: Decimal | None
    returns: dict[int, HorizonReturn]
    outcome: Outcome

    @property
    def has_lookahead(self) -> bool:
        """Phase 8 criterion 1, asserted per entry over the full result set."""
        return self.entry_timestamp < self.entry.public_available_at


class PriceSeries:
    """Adjusted daily closes for one security.

    Trading days come from the series itself rather than a calendar: the data
    defines which days exist, and a synthetic calendar would invent bars on
    market holidays.
    """

    def __init__(self, bars: Sequence[tuple[date, Decimal]]) -> None:
        ordered = sorted(bars, key=lambda pair: pair[0])
        self._dates = [d for d, _ in ordered]
        self._closes = {d: c for d, c in ordered}

    def __len__(self) -> int:
        return len(self._dates)

    @property
    def last_date(self) -> date | None:
        return self._dates[-1] if self._dates else None

    def index_on_or_after(self, when: date) -> int | None:
        """First trading day at or after ``when``.

        A filing available on a Saturday is entered on Monday's open, which is
        the first moment it could actually have been acted on.
        """
        for i, day in enumerate(self._dates):
            if day >= when:
                return i
        return None

    def close_at_index(self, index: int) -> tuple[date, Decimal] | None:
        if 0 <= index < len(self._dates):
            day = self._dates[index]
            return day, self._closes[day]
        return None


def forward_return(
    series: PriceSeries, *, entry_index: int, horizon_days: int
) -> tuple[float | None, Outcome]:
    """Return over ``horizon_days`` trading days from ``entry_index``.

    Horizons are counted in **trading** days, not calendar days: 250 calendar
    days is roughly 170 sessions, and mixing the two silently shortens every
    long-horizon result.

    A horizon that runs past the end of the series returns ``None`` with
    ``OPEN`` rather than truncating to the last available bar. Truncating
    would quietly turn a 250-day horizon into whatever data happened to exist,
    which flatters recent signals.
    """
    start = series.close_at_index(entry_index)
    if start is None:
        return None, Outcome.NO_PRICE_DATA

    end = series.close_at_index(entry_index + horizon_days)
    if end is None:
        return None, Outcome.OPEN

    _, entry_price = start
    _, exit_price = end
    if entry_price == 0:
        return None, Outcome.NO_PRICE_DATA

    return float((exit_price - entry_price) / entry_price), Outcome.COMPLETE


def run_entry(
    entry: SignalEntry,
    *,
    prices: PriceSeries,
    benchmark: PriceSeries | None = None,
    sector: PriceSeries | None = None,
    horizons: Sequence[int] = DEFAULT_HORIZONS,
    terminal_outcome: Outcome | None = None,
) -> EntryResult:
    """Evaluate one entry.

    ``terminal_outcome`` records a delisting, acquisition or merger. Those
    entries stay in the results — removing them is survivorship bias, which is
    the most reliable way to manufacture a positive backtest out of nothing.
    """
    # The entry is the first trading day at or after the moment the
    # information became public. Never earlier, by construction.
    entry_index = prices.index_on_or_after(entry.entry_date)
    if entry_index is None:
        return EntryResult(
            entry=entry,
            entry_timestamp=entry.public_available_at,
            entry_price=None,
            returns={
                h: HorizonReturn(h, None, None, None, Outcome.NO_PRICE_DATA) for h in horizons
            },
            outcome=terminal_outcome or Outcome.NO_PRICE_DATA,
        )

    entry_bar = prices.close_at_index(entry_index)
    assert entry_bar is not None
    entry_day, entry_price = entry_bar

    benchmark_index = benchmark.index_on_or_after(entry_day) if benchmark else None
    sector_index = sector.index_on_or_after(entry_day) if sector else None

    returns: dict[int, HorizonReturn] = {}
    for horizon in horizons:
        raw, outcome = forward_return(prices, entry_index=entry_index, horizon_days=horizon)

        benchmark_excess: float | None = None
        if raw is not None and benchmark is not None and benchmark_index is not None:
            bench, bench_outcome = forward_return(
                benchmark, entry_index=benchmark_index, horizon_days=horizon
            )
            if bench is not None and bench_outcome is Outcome.COMPLETE:
                benchmark_excess = raw - bench

        sector_excess: float | None = None
        if raw is not None and sector is not None and sector_index is not None:
            sec, sec_outcome = forward_return(
                sector, entry_index=sector_index, horizon_days=horizon
            )
            if sec is not None and sec_outcome is Outcome.COMPLETE:
                sector_excess = raw - sec

        returns[horizon] = HorizonReturn(
            horizon_days=horizon,
            raw=raw,
            benchmark_excess=benchmark_excess,
            sector_excess=sector_excess,
            outcome=terminal_outcome if (terminal_outcome and raw is None) else outcome,
        )

    return EntryResult(
        entry=entry,
        # The engine enters on the first tradable moment at or after
        # availability, so this is never earlier than public_available_at.
        entry_timestamp=datetime.combine(entry_day, entry.public_available_at.timetz()),
        entry_price=entry_price,
        returns=returns,
        outcome=terminal_outcome or Outcome.COMPLETE,
    )


def assert_no_lookahead(results: Sequence[EntryResult]) -> None:
    """Phase 8 criterion 1, over the full result set.

    Run on every backtest, not once: look-ahead re-enters through repair work
    rather than through the original code — a later "fix" that joins the
    transaction date for convenience reintroduces it invisibly.
    """
    violations = [
        f"{r.entry.cik}/{r.entry.signal}: entered {r.entry_timestamp.isoformat()} "
        f"before available {r.entry.public_available_at.isoformat()}"
        for r in results
        if r.has_lookahead
    ]
    if violations:
        raise AssertionError(
            f"{len(violations)} backtest entries precede their public availability:\n  "
            + "\n  ".join(violations[:10])
        )
