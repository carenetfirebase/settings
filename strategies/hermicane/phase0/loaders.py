"""Local ingest for the series Phase 0 needs (§3.1).

The network side of data acquisition lives in `sources`. This module is the
other half: once an export exists on disk — a Dukascopy dump, a FirstRate CSV,
a scraped calendar — these loaders turn it into the two structures the
computation core consumes, `BarSeries` and `MacroEvent`.

The split matters because it is what keeps the harness runnable in an
environment with no egress. Everything downstream of here is offline
arithmetic, so a user who can obtain the files by any means at all gets the
full analysis without touching `sources`.

File formats, all CSV with a header row:

* **bars**     ``timestamp,open,high,low,close[,volume]`` — timestamps UTC.
* **daily**    ``date,value`` — FRED's own ``observation_date,SERIES`` layout is
  also accepted, as that is what a fredgraph download produces.
* **calendar** ``timestamp_utc,event_type,actual,consensus[,consensus_sd]``

Missing values may be empty or ``.`` (FRED's own marker). They become NaN, and
NaN propagates to a flag on the panel row rather than to a zero.
"""

from __future__ import annotations

import bisect
import csv
import math
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

from .beta import DailyObservation
from .sources import SOURCES_BY_KEY, Source, SourceUnavailable

NAN = float("nan")

#: FRED writes a lone period for a missing observation. Treating it as zero
#: would put a fake 0.00% yield into the beta regression.
MISSING_TOKENS = {"", ".", "na", "n/a", "nan", "null", "-"}


class IngestError(ValueError):
    """The file is not what it claims to be. Never a silent half-parse."""


def _to_float(text: str) -> float:
    cleaned = (text or "").strip().replace(",", "")
    if cleaned.lower() in MISSING_TOKENS:
        return NAN
    try:
        return float(cleaned)
    except ValueError:
        return NAN


_TIMESTAMP_FORMATS = (
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%d %H:%M",
    "%Y-%m-%dT%H:%M",
    "%Y.%m.%d %H:%M:%S",
    "%d.%m.%Y %H:%M:%S",
)


def parse_timestamp(text: str) -> datetime:
    """Parse a UTC timestamp, tolerating the handful of layouts exports use.

    A naive timestamp is *assumed UTC* rather than local. That assumption is
    stated loudly here because getting it wrong shifts every event window by
    hours and would not announce itself in the results.
    """
    cleaned = (text or "").strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(cleaned)
        return parsed.astimezone(UTC) if parsed.tzinfo else parsed.replace(tzinfo=UTC)
    except ValueError:
        pass
    for fmt in _TIMESTAMP_FORMATS:
        try:
            return datetime.strptime(cleaned, fmt).replace(tzinfo=UTC)
        except ValueError:
            continue
    raise IngestError(f"unrecognised timestamp: {text!r}")


@dataclass(frozen=True)
class Bar:
    ts: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float = NAN


class BarSeries:
    """An immutable, time-ordered run of bars with window lookups.

    Backed by a parallel list of timestamps so slicing an event window is a
    pair of binary searches rather than a scan. Five years of 1-minute gold is
    around 1.8 million bars; a linear scan per event per horizon is the
    difference between a report that runs and one that does not.
    """

    def __init__(self, symbol: str, bars: list[Bar], timeframe_seconds: int = 60) -> None:
        ordered = sorted(bars, key=lambda b: b.ts)
        self.symbol = symbol
        self.bars = ordered
        self.timeframe_seconds = timeframe_seconds
        self._stamps = [b.ts for b in ordered]

    def __len__(self) -> int:
        return len(self.bars)

    def __bool__(self) -> bool:
        return bool(self.bars)

    @property
    def start(self) -> datetime | None:
        return self._stamps[0] if self._stamps else None

    @property
    def end(self) -> datetime | None:
        return self._stamps[-1] if self._stamps else None

    def index_at_or_after(self, when: datetime) -> int:
        return bisect.bisect_left(self._stamps, when)

    def bar_at_or_after(self, when: datetime, tolerance_minutes: int = 5) -> Bar | None:
        """The first bar at or after `when`, within a tolerance.

        The tolerance stops a lookup landing on a bar hours later across a
        weekend gap and reporting it as the release minute.
        """
        i = self.index_at_or_after(when)
        if i >= len(self.bars):
            return None
        found = self.bars[i]
        if found.ts - when > timedelta(minutes=tolerance_minutes):
            return None
        return found

    def window(self, start: datetime, end: datetime) -> list[Bar]:
        """Bars with `start <= ts < end`."""
        lo = bisect.bisect_left(self._stamps, start)
        hi = bisect.bisect_left(self._stamps, end)
        return self.bars[lo:hi]

    def daily_closes(self) -> list[tuple[date, float]]:
        """Last close of each UTC calendar day.

        Used only when `gold_daily` is unavailable and the operator has chosen
        the documented degradation of resampling the intraday series. The
        substitution is recorded in provenance by the caller, not here.
        """
        by_day: dict[date, float] = {}
        for bar in self.bars:
            by_day[bar.ts.date()] = bar.close
        return sorted(by_day.items())


def load_bars(path: Path | str, symbol: str, timeframe_seconds: int = 60) -> BarSeries:
    path = Path(path)
    if not path.exists():
        raise IngestError(f"no such bar file: {path}")
    bars: list[Bar] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        columns = {name.strip().lower() for name in (reader.fieldnames or [])}
        required = {"timestamp", "open", "high", "low", "close"}
        if not required.issubset(columns):
            raise IngestError(
                f"{path}: bar file needs columns {sorted(required)}, found {sorted(columns)}"
            )
        for row in reader:
            lowered = {k.strip().lower(): v for k, v in row.items() if k}
            bars.append(
                Bar(
                    ts=parse_timestamp(lowered["timestamp"]),
                    open=_to_float(lowered["open"]),
                    high=_to_float(lowered["high"]),
                    low=_to_float(lowered["low"]),
                    close=_to_float(lowered["close"]),
                    volume=_to_float(lowered.get("volume", "")),
                )
            )
    if not bars:
        raise IngestError(f"{path}: no rows")
    return BarSeries(symbol, bars, timeframe_seconds)


def load_daily(path: Path | str) -> list[tuple[date, float]]:
    """Load a two-column daily series, FRED layout included.

    Rows whose value is missing are dropped rather than forward-filled. A
    forward fill would manufacture a zero daily change on every holiday, which
    biases the beta regression toward zero by padding it with non-observations.
    """
    path = Path(path)
    if not path.exists():
        raise IngestError(f"no such daily file: {path}")
    out: list[tuple[date, float]] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        header = next(reader, None)
        if header is None:
            raise IngestError(f"{path}: empty file")
        for row in reader:
            if len(row) < 2:
                continue
            value = _to_float(row[1])
            if math.isnan(value):
                continue
            out.append((parse_timestamp(row[0]).date(), value))
    if not out:
        raise IngestError(f"{path}: no usable observations")
    return sorted(out)


def pair_daily(
    gold: list[tuple[date, float]],
    dgs2: list[tuple[date, float]],
) -> list[DailyObservation]:
    """Inner-join the two daily series on date.

    An inner join, not a merge-and-fill: the regression needs both legs of the
    same day, and a day where only one series traded is not an observation of
    the relationship.
    """
    yields = dict(dgs2)
    return [
        DailyObservation(day, close, yields[day])
        for day, close in gold
        if day in yields and not math.isnan(yields[day]) and close > 0
    ]


@dataclass(frozen=True)
class MacroEvent:
    """One scheduled release, as the market met it."""

    ts_utc: datetime
    event_type: str
    actual: float
    consensus: float
    consensus_sd: float = NAN

    @property
    def has_consensus(self) -> bool:
        return not math.isnan(self.consensus) and not math.isnan(self.actual)

    @property
    def surprise_raw(self) -> float:
        return self.actual - self.consensus if self.has_consensus else NAN


def load_calendar(path: Path | str) -> list[MacroEvent]:
    path = Path(path)
    if not path.exists():
        raise IngestError(f"no such calendar file: {path}")
    events: list[MacroEvent] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        columns = {name.strip().lower() for name in (reader.fieldnames or [])}
        required = {"timestamp_utc", "event_type", "actual"}
        if not required.issubset(columns):
            raise IngestError(
                f"{path}: calendar needs columns {sorted(required)}, found {sorted(columns)}"
            )
        for row in reader:
            lowered = {k.strip().lower(): v for k, v in row.items() if k}
            events.append(
                MacroEvent(
                    ts_utc=parse_timestamp(lowered["timestamp_utc"]),
                    event_type=(lowered["event_type"] or "").strip().upper(),
                    actual=_to_float(lowered["actual"]),
                    consensus=_to_float(lowered.get("consensus", "")),
                    consensus_sd=_to_float(lowered.get("consensus_sd", "")),
                )
            )
    if not events:
        raise IngestError(f"{path}: no rows")
    return sorted(events, key=lambda e: e.ts_utc)


def require_first_print(source_key: str) -> Source:
    """Refuse a revised series where a first print was asked for (§5).

    Called by any path that supplies the `actual` column. It is a three-line
    function guarding the single most expensive mistake available to this
    project, and it is cheap enough to call every time.
    """
    source = SOURCES_BY_KEY.get(source_key)
    if source is None:
        raise SourceUnavailable(
            SOURCES_BY_KEY["actuals_first_print"],
            f"unknown source key {source_key!r} supplied for the actual column",
        )
    if not source.first_print:
        raise SourceUnavailable(
            source,
            "this series publishes revisions and cannot supply the traded actual",
        )
    return source
