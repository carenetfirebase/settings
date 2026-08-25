"""Loading and splitting the Pine trade export (S61, S68, S69).

The CSV comes out of the Pine Logs pane. Reading it is the boring part; the
part that matters is the splitting, because that is where backtests are usually
lost. `chronological_split` is deliberately the only splitter offered, and it
never shuffles: a random split of time-series trades leaks the future into the
training set through nothing more exotic than adjacent days.
"""

from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

#: Columns the Pine export always writes. A file missing any of these is a file
#: from a different version of the strategy, and is rejected rather than
#: silently half-parsed.
REQUIRED_COLUMNS = (
    "ts_entry",
    "ts_exit",
    "realized_R",
    "score",
    "grade",
    "mae_R",
    "mfe_R",
    "exit_type",
)


class TradeExportError(ValueError):
    """The export is not what it claims to be."""


@dataclass(frozen=True)
class Trade:
    ts_entry: datetime
    ts_exit: datetime
    realized_r: float
    score: float
    grade: str
    mae_r: float
    mfe_r: float
    exit_type: str
    session_type: str = ""
    orb_model: str = ""
    ablation: str = ""
    entry_mode: str = ""
    stop_model: str = ""
    vol_mode: str = ""
    risk_usd: float = float("nan")
    hold_bars: int = 0
    raw: dict[str, str] = None  # type: ignore[assignment]

    @property
    def date(self) -> str:
        return self.ts_entry.strftime("%Y-%m-%d")

    @property
    def is_win(self) -> bool:
        return self.realized_r > 0


def _to_float(value: str, default: float = float("nan")) -> float:
    text = (value or "").strip()
    if text in {"", "n/a", "na", "NaN"}:
        return default
    try:
        return float(text)
    except ValueError:
        return default


def _to_dt(value: str) -> datetime:
    text = (value or "").strip()
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    raise TradeExportError(f"unparseable timestamp: {value!r}")


def parse_csv(text: str) -> list[Trade]:
    """Parse an export. Log-pane preamble lines before the header are skipped."""
    lines = text.splitlines()
    start = next(
        (i for i, line in enumerate(lines) if line.lstrip().startswith("ts_entry,")),
        None,
    )
    if start is None:
        raise TradeExportError("no header row starting with 'ts_entry,' was found")
    reader = csv.DictReader(io.StringIO("\n".join(lines[start:])))
    missing = [c for c in REQUIRED_COLUMNS if c not in (reader.fieldnames or [])]
    if missing:
        raise TradeExportError(f"export is missing required columns: {', '.join(missing)}")

    trades: list[Trade] = []
    for row in reader:
        if not (row.get("ts_entry") or "").strip():
            continue
        trades.append(
            Trade(
                ts_entry=_to_dt(row["ts_entry"]),
                ts_exit=_to_dt(row["ts_exit"]),
                realized_r=_to_float(row["realized_R"]),
                score=_to_float(row["score"]),
                grade=(row.get("grade") or "").strip(),
                mae_r=_to_float(row["mae_R"]),
                mfe_r=_to_float(row["mfe_R"]),
                exit_type=(row.get("exit_type") or "").strip(),
                session_type=(row.get("session_type") or "").strip(),
                orb_model=(row.get("orb_model") or "").strip(),
                ablation=(row.get("ablation") or "").strip(),
                entry_mode=(row.get("entry_mode") or "").strip(),
                stop_model=(row.get("stop_model") or "").strip(),
                vol_mode=(row.get("vol_mode") or "").strip(),
                risk_usd=_to_float(row.get("risk_usd", "")),
                hold_bars=int(_to_float(row.get("hold_bars", "0"), 0.0)),
                raw=dict(row),
            )
        )
    bad = [t for t in trades if t.realized_r != t.realized_r]
    if bad:
        raise TradeExportError(f"{len(bad)} row(s) have no realized_R")
    trades.sort(key=lambda t: t.ts_entry)
    return trades


def load(path: str | Path) -> list[Trade]:
    return parse_csv(Path(path).read_text(encoding="utf-8"))


@dataclass(frozen=True)
class Split:
    """S68. Development / validation / final untouched out-of-sample."""

    development: list[Trade]
    validation: list[Trade]
    out_of_sample: list[Trade]

    def describe(self) -> str:
        def window(trades: list[Trade]) -> str:
            if not trades:
                return "empty"
            return f"{trades[0].date} → {trades[-1].date} ({len(trades)} trades)"

        return (
            f"development      {window(self.development)}\n"
            f"validation       {window(self.validation)}\n"
            f"out-of-sample    {window(self.out_of_sample)}"
        )


def chronological_split(
    trades: list[Trade],
    development: float = 0.60,
    validation: float = 0.20,
) -> Split:
    """Split by TIME, never at random, and never across a day boundary.

    Splitting mid-day would put two trades from one session on opposite sides of
    the wall, and they are not independent observations.
    """
    if not trades:
        return Split([], [], [])
    if development + validation >= 1.0:
        raise ValueError("development + validation must leave room for out-of-sample")
    dates = sorted({t.date for t in trades})
    n = len(dates)
    dev_end = dates[max(0, int(n * development) - 1)]
    val_end = dates[max(0, int(n * (development + validation)) - 1)]
    return Split(
        development=[t for t in trades if t.date <= dev_end],
        validation=[t for t in trades if dev_end < t.date <= val_end],
        out_of_sample=[t for t in trades if t.date > val_end],
    )


@dataclass(frozen=True)
class WalkForwardWindow:
    index: int
    train_start: str
    train_end: str
    test_start: str
    test_end: str
    train: list[Trade]
    test: list[Trade]


def walk_forward_windows(
    trades: list[Trade],
    train_months: int = 12,
    test_months: int = 3,
) -> list[WalkForwardWindow]:
    """S69. Rolling train/test windows anchored on calendar months.

    Only the test halves are ever aggregated into a reported result. The train
    halves exist so that a human can see what the parameters were fitted to.
    """
    if not trades:
        return []

    def month_key(trade: Trade) -> int:
        return trade.ts_entry.year * 12 + (trade.ts_entry.month - 1)

    first = month_key(trades[0])
    last = month_key(trades[-1])
    windows: list[WalkForwardWindow] = []
    index = 0
    start = first
    while start + train_months + test_months - 1 <= last:
        train_lo, train_hi = start, start + train_months
        test_lo, test_hi = train_hi, train_hi + test_months
        train = [t for t in trades if train_lo <= month_key(t) < train_hi]
        test = [t for t in trades if test_lo <= month_key(t) < test_hi]
        if test:
            index += 1
            windows.append(
                WalkForwardWindow(
                    index=index,
                    train_start=train[0].date if train else "-",
                    train_end=train[-1].date if train else "-",
                    test_start=test[0].date,
                    test_end=test[-1].date,
                    train=train,
                    test=test,
                )
            )
        start += test_months
    return windows
