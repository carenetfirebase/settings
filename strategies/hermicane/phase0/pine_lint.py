"""Static checks for HERMICANE_v2.pine.

TradingView owns the only Pine compiler, so nothing here proves the script
compiles. What it proves is that the classes of mistake that survive a careful
read — and that cost a paste-into-chart round trip each to find — are absent.

Two groups of check. The first is generic Pine hazards, and every one of them
is here because it is a *silent* failure or a runtime error rather than
something the editor underlines:

* comma-separated declarations, which read fine to a Python eye and are a
  syntax error in Pine;
* ``lookahead_on``, or a ``request.security()`` with no explicit lookahead;
* a cross-timeframe ``request.security()`` with no inner ``[1]`` offset, which
  returns the last closed bar in a backtest and the forming bar in real time;
* ``ta.*`` called inside a conditional block, where it does not get the
  every-bar evaluation its internal state needs and quietly returns the wrong
  value;
* ``array.get`` guarded by ``and`` rather than a nested ``if`` — Pine does not
  promise short-circuit evaluation, so the bounds check may not save you;
* ``for i = 0 to array.size(x) - 1`` with no size guard, which counts DOWN to
  -1 on an empty array and throws at runtime;
* table writes outside the declared table size, raised on the last bar after
  the whole backtest has run;
* v5-era removals, tabs, and indentation that is not a multiple of four.

The second group is HERMICANE's own audit list — the thirteen v1 defects, as
requirements. Those are in `docs/01_v1_audit.md`, and the point of encoding them
here is that a defect deleted in prose has a way of coming back in code.

It lives in the `phase0` package for the mundane reason that a strategy gets one
Python package here and three sibling packages all called `validation` collide
on the path. It verifies the Phase 1 artefact, not the Phase 0 harness.

Run from ``strategies/hermicane``::

    python -m phase0.pine_lint HERMICANE_v2.pine
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ERROR = "ERROR"
WARN = "WARN"


@dataclass(frozen=True)
class Finding:
    line: int
    level: str
    code: str
    message: str

    def __str__(self) -> str:
        where = f"{self.line}" if self.line else "-"
        return f"{self.level:5} {self.code:14} line {where:>4}  {self.message}"


def _strip(line: str) -> str:
    """Remove string literals and trailing comments, keeping column count sane."""
    out: list[str] = []
    in_string = False
    quote = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            out.append(" ")
            if ch == "\\":
                if i + 1 < len(line):
                    out.append(" ")
                    i += 2
                    continue
            elif ch == quote:
                in_string = False
            i += 1
            continue
        if ch in "\"'":
            in_string = True
            quote = ch
            out.append(" ")
            i += 1
            continue
        if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


#: Every condition the entry gate must contain. A gate silently dropped from the
#: chain is the failure this catches.
REQUIRED_GATES = (
    "useBetaGate",
    "regimeClassic",
    "haveMacro",
    "fImpulse",
    "useAgrees",
    "fMacro",
    "fFive",
    "fTrend",
)

#: docs/01_v1_audit.md, as assertions. Each maps to a numbered defect.
AUDIT_REQUIREMENTS = (
    ("AUDIT-11", "timeframe.in_seconds() != 60", "no 1-minute timeframe guard (audit 11)"),
    ("AUDIT-8", "bar_index > 0", "no bar_index guard on the event trigger (audit 8)"),
    ("AUDIT-9", "close[1] > open[1]", "5-minute confirmation must use close[1]/open[1] inside the security call (audit 9)"),
    ("AUDIT-7", "NO DATA", "the dashboard must distinguish NO DATA from a rejection (audit 7)"),
    ("AUDIT-14", "pointValue", "the point-value / contract assumption must be explicit (audit 14)"),
    ("AUDIT-13", "slippage", "costs must be an input, not a hidden default (audit 13)"),
)

#: v1 scored setups 0-10 and two of the terms were pinned at 10 by the entry
#: gate itself. v2 has no score, and must not grow one.
FORBIDDEN_SCORE_TOKENS = ("breakoutScore", "fiveScore", "impulseScore", "macroScore", "finalScore")


def lint(source: str) -> list[Finding]:
    findings: list[Finding] = []
    raw_lines = source.splitlines()
    code = [_strip(line) for line in raw_lines]

    def add(line: int, level: str, kind: str, message: str) -> None:
        findings.append(Finding(line, level, kind, message))

    # A line that starts while a bracket is still open is a continuation, not a
    # statement: its indentation is free-form and its parentheses balance
    # against an earlier line. Both checks below have to know that.
    continuation: list[bool] = []
    depth = 0
    for line in code:
        continuation.append(depth > 0)
        depth += line.count("(") - line.count(")")
        depth += line.count("[") - line.count("]")
        depth = max(depth, 0)

    # ---- whitespace and layout -------------------------------------------
    for i, line in enumerate(raw_lines, start=1):
        if "\t" in line:
            add(i, ERROR, "TAB", "tab character; Pine indentation must be spaces")
        if line.rstrip() != line:
            add(i, WARN, "TRAILING-WS", "trailing whitespace")
        indent = _indent_of(line)
        if line.strip() and indent % 4 != 0 and not continuation[i - 1]:
            add(i, ERROR, "INDENT", f"indent of {indent} is not a multiple of four")

    # ---- declarations and syntax -----------------------------------------
    decl = re.compile(r"\b(?:var|varip)?\s*(?:float|int|bool|string|color)\s+\w+\s*=.*?,\s*(?:var|varip|float|int|bool|string|color)\s")
    for i, line in enumerate(code, start=1):
        if decl.search(line):
            add(i, ERROR, "COMMA-DECL", "comma-separated declarations are a Pine syntax error")
        for removed in ("iff", "study", "security"):
            if re.search(r"(?<![.\w])" + re.escape(removed) + r"\s*\(", line):
                add(i, ERROR, "V5-REMOVED", f"`{removed}(` was removed in v5; use the v6 form")
        if not continuation[i - 1] and line.count("(") - line.count(")") < 0:
            add(i, ERROR, "PARENS", "more closing than opening parentheses on this line")

    # ---- request.security ------------------------------------------------
    for i, line in enumerate(code, start=1):
        if "request.security(" not in line:
            continue
        if "lookahead_on" in line:
            add(i, ERROR, "LOOKAHEAD", "lookahead_on introduces future data")
        if "lookahead" not in line:
            add(i, ERROR, "LOOKAHEAD", "request.security() with no explicit lookahead argument")
        # A call whose timeframe is not timeframe.period crosses timeframes and
        # needs the inner [1] to read a bar that has actually closed.
        if "timeframe.period" not in line and "[1]" not in line:
            add(i, ERROR, "HTF-OFFSET",
                "cross-timeframe request.security() with no inner [1]; returns the "
                "forming bar in real time and the closed one in backtest")

    # ---- ta.* inside a conditional block ---------------------------------
    block_indent: list[int] = []
    for i, line in enumerate(code, start=1):
        if not line.strip():
            continue
        indent = _indent_of(line)
        while block_indent and indent <= block_indent[-1]:
            block_indent.pop()
        stripped = line.strip()
        uses_ta = bool(re.match(r"\bta\.\w+\(", stripped) or re.search(r"=\s*ta\.\w+\(", stripped))
        if uses_ta and block_indent:
            add(i, ERROR, "TA-IN-BLOCK",
                "ta.* evaluated inside a conditional block; it needs every-bar "
                "evaluation to keep its state. Hoist it to global scope.")
        if re.match(r"^(if|else if|else|for|while)\b", stripped) or stripped.endswith("=>"):
            block_indent.append(indent)

    # ---- array bounds ----------------------------------------------------
    for i, line in enumerate(code, start=1):
        if re.search(r"\b(?:while|if)\b.*<\s*array\.size\([^)]*\)\s*and\b.*array\.get\(", line):
            add(i, ERROR, "SHORTCIRCUIT",
                "array.get guarded by `and`; Pine does not guarantee short-circuit "
                "evaluation, so use a nested if")
        loop = re.match(r"\s*for\s+\w+\s*=\s*0\s+to\s+array\.size\((\w+)\)\s*-\s*1", line)
        if loop:
            name = loop.group(1)
            guarded = any(
                re.search(rf"array\.size\({name}\)\s*>\s*0", code[j])
                for j in range(max(0, i - 6), i - 1)
            )
            inside_n = any(re.search(r"\bn\s*>=\s*\d+", code[j]) for j in range(max(0, i - 12), i - 1))
            if not guarded and not inside_n:
                add(i, ERROR, "EMPTY-LOOP",
                    f"`for 0 to array.size({name}) - 1` counts DOWN on an empty array; "
                    "guard the size first")

    # ---- table bounds ----------------------------------------------------
    declared_rows: dict[str, int] = {}
    for line in code:
        m = re.search(r"(\w+)\s*=\s*table\.new\([^,]+,\s*(\d+)\s*,\s*(\d+)", line)
        if m:
            declared_rows[m.group(1)] = int(m.group(3))
    for i, line in enumerate(code, start=1):
        m = re.search(r"writeRow\((\w+)\s*,\s*(\d+)", line) or re.search(r"table\.cell\(\s*(\w+)\s*,\s*\d+\s*,\s*(\d+)", line)
        if not m:
            continue
        name, row = m.group(1), int(m.group(2))
        limit = declared_rows.get(name)
        if limit is not None and row >= limit:
            add(i, ERROR, "TABLE-BOUNDS",
                f"writes row {row} of a table declared with {limit} rows; Pine raises "
                "this on the last bar, after the whole backtest has run")

    # ---- HERMICANE invariants -------------------------------------------
    joined = "\n".join(code)
    text = source

    for code_name, needle, message in AUDIT_REQUIREMENTS:
        haystack = text if needle in ("NO DATA",) else joined
        if needle not in haystack:
            add(0, ERROR, code_name, message)

    for token in FORBIDDEN_SCORE_TOKENS:
        if token in joined:
            add(0, ERROR, "AUDIT-1",
                f"`{token}` reintroduces v1's weighted score. A condition is either a "
                "hard gate or a score term, never both.")

    for gate in REQUIRED_GATES:
        if gate not in joined:
            add(0, ERROR, "GATE-MISSING", f"entry gate `{gate}` is not referenced anywhere")

    # The protective orders must be placed in the same block as the entry.
    entry_line = next((i for i, line in enumerate(code, start=1) if "strategy.entry(" in line), None)
    exit_line = next((i for i, line in enumerate(code, start=1) if "strategy.exit(" in line), None)
    if entry_line is None or exit_line is None:
        add(0, ERROR, "AUDIT-10", "no strategy.entry/strategy.exit pair found")
    elif exit_line - entry_line > 6:
        add(exit_line, ERROR, "AUDIT-10",
            "strategy.exit is not adjacent to strategy.entry; under "
            "process_orders_on_close that leaves the entry bar unprotected")

    # `if strategy.position_size != 0` wrapped around the protective orders is
    # exactly v1's defect: under process_orders_on_close the position does not
    # exist until the next bar, so the entry bar runs unprotected.
    for i, line in enumerate(code, start=1):
        if "strategy.exit(" not in line:
            continue
        preceding = code[max(0, i - 5):i - 1]
        if any("position_size" in earlier and "if" in earlier for earlier in preceding):
            add(i, ERROR, "AUDIT-10",
                "strategy.exit appears to be gated on strategy.position_size, which "
                "only updates on the bar AFTER the fill; the entry bar is unprotected")

    # Every uncalibrated threshold must say so where the user will see it.
    for i, line in enumerate(raw_lines, start=1):
        if "input.float(" in line or "input.int(" in line:
            named = re.search(r'input\.(?:float|int)\([^,]+,\s*"([^"]*)"', line)
            if not named:
                continue
            title = named.group(1)
            is_threshold = any(
                key in line for key in ("impMin", "impMax", "pbMin", "pbMax", "minR2")
            )
            if is_threshold and "UNCALIBRATED" not in title:
                add(i, ERROR, "UNLABELLED",
                    f'threshold input "{title}" is not labelled UNCALIBRATED')

    # The causality guard must exist: post-entry conditions cannot filter a T+3
    # entry. This is the bug the Phase 0 harness had, and it must not be
    # reintroduced by making these filters available in CONTROL mode.
    if "modeBreakout and (fPullback or fOrigin)" not in joined and "not modeBreakout and (fPullback or fOrigin)" not in joined:
        add(0, ERROR, "CAUSALITY",
            "no guard preventing the pullback and origin-hold filters from being "
            "applied to a T+3 entry, where they would read the future")

    if depth != 0:
        add(len(raw_lines), ERROR, "PARENS", f"file ends with {depth} unclosed bracket(s)")

    return sorted(findings, key=lambda f: (f.line, f.code))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: pine_lint.py <path to .pine>")
        return 2
    path = Path(argv[1])
    if not path.exists():
        print(f"no such file: {path}")
        return 2
    findings = lint(path.read_text(encoding="utf-8"))
    errors = [f for f in findings if f.level == ERROR]
    for finding in findings:
        print(finding)
    print()
    print(f"{len(errors)} error(s), {len(findings) - len(errors)} warning(s) in {path.name}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
