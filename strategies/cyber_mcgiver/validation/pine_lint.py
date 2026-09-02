"""Static checks for the CYBER MCGIVER v7 Pine v6 source.

TradingView owns the only Pine compiler, so nothing here proves the script
compiles. What it does prove is that the classes of mistake that survive a
careful read — and that cost a paste-into-chart round trip each to find — are
absent:

* comma-separated declarations, which read fine to a Python eye and are a
  syntax error in Pine;
* a global used before the line that declares it;
* ``lookahead_on``, or a ``request.security()`` with no explicit lookahead;
* stateful helpers evaluated inside ``request.security()``;
* v5-era removals (``iff``, bare ``security(``, ``study(``);
* tabs, trailing whitespace, or indentation that is not a multiple of four;
* ``int / int``, which Pine evaluates as INTEGER division, so ``wins / n`` is
  0 for every win rate below 100%;
* ``for k = 0 to array.size(x) - 1`` with no size guard, which counts DOWN to
  -1 on an empty array and throws at runtime;
* **table writes outside the declared table size** — ``table.new(pos, 3, 27)``
  followed by a loop writing row 28. Pine raises this at runtime, on the last
  bar, after the whole backtest has run;
* **``array.from`` literals shorter than the loop that reads them**, the same
  failure one level down;
* the v7 architecture invariants: the mandatory risk gates are all present in
  the pipeline, the funnel counts every stage, and no stage is silently
  dropped from the dashboard.

Run directly::

    python strategies/cyber_mcgiver/validation/pine_lint.py CYBER_MCGIVER_v7.pine
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

BUILTIN_PREFIXES = (
    "math.", "str.", "ta.", "array.", "table.", "strategy.", "request.", "input.",
    "color.", "label.", "line.", "box.", "plot.", "shape.", "location.", "size.",
    "text.", "barmerge.", "alert.", "syminfo.", "timeframe.", "session.", "log.",
    "currency.", "dayofweek.", "position.", "extend.", "order.", "display.",
    "format.", "scale.", "xloc.", "yloc.", "matrix.", "map.", "runtime.", "chart.",
)

KEYWORDS = {
    "var", "varip", "if", "else", "for", "to", "by", "while", "switch", "and",
    "or", "not", "true", "false", "na", "int", "float", "bool", "string", "color",
    "line", "label", "box", "table", "array", "matrix", "map", "series", "simple",
    "const", "input", "export", "import", "method", "type", "enum", "break",
    "continue", "in", "return",
}

BUILTIN_VARS = {
    "open", "high", "low", "close", "volume", "hl2", "hlc3", "ohlc4", "hlcc4",
    "time", "time_close", "time_tradingday", "bar_index", "last_bar_index",
    "barstate", "syminfo", "timeframe", "strategy", "dayofweek", "dayofmonth",
    "weekofyear", "month", "year", "hour", "minute", "second", "nz", "na",
    "plot", "plotshape", "plotchar", "plotarrow", "fill", "hline", "bgcolor",
    "barcolor", "alert", "alertcondition", "timestamp", "input", "request",
    "math", "str", "ta", "array", "table", "label", "line", "box", "color",
    "log", "int", "float", "bool", "string", "max_bars_back", "runtime",
    "fixnan", "sign", "abs",
}

#: Conditions v7 declares MANDATORY. Losing one of these silently turns a risk
#: control into a scored preference, which is exactly the failure the score
#: model is designed to make impossible to introduce by accident.
MANDATORY_GATES = (
    "okScore",
    "okRegime",
    "okMom",
    "okShock",
    "okSess",
    "okStop",
    "okWide",
    "okTight",
    "okRoom",
    "okAnchor",
)

#: Every funnel stage the dashboard promises to show. A stage that exists in
#: the engine but not in the counters is a hidden rejection, and hiding
#: rejections is the one thing the funnel exists to prevent.
FUNNEL_COUNTERS = (
    "fRaw", "fCand", "fPass", "fTaken", "fScoreFail", "fStopBad", "fStopWide",
    "fStopTight", "fRoomShort", "fSizeSmall", "fMarginCut", "fBudgetOut",
    "fBlockAnchor", "fBlockRegime", "fBlockMom", "fBlockShock", "fBlockSess",
    "fBlockOpen", "fBlockCap", "fBlockLoss", "fBlockCool", "fArmed", "fFilled",
    "fArmExpired", "fArmVoided", "fTrades", "fSameBar",
)

#: The ten score components, every one of which must be a configurable input.
SCORE_WEIGHTS = (
    "i_wHtf", "i_wVwap", "i_wStruct", "i_wPull", "i_wSweep", "i_wMom",
    "i_wDxy", "i_wAtr", "i_wRoom", "i_wSessQ",
)

REQUIRED_DIAGNOSTICS = (
    "STOOD DOWN — DAILY TRADE CAP",
    "STOOD DOWN — DAILY LOSS CUTOFF",
    "STOOD DOWN — WAITING FOR AN INDEPENDENT SETUP",
    "NO TRADE — VOLATILITY SHOCK",
    "NO QUALIFYING CANDIDATE",
)

DECL_RE = re.compile(
    r"^(?P<indent>\s*)(?:var\s+|varip\s+)?"
    r"(?:(?:int|float|bool|string|color|line|label|box|table)\s+"
    r"(?:\[\])?\s*|(?:array|matrix|map)<[^>]+>\s+)?"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<op>:?=)(?!=)"
)
TUPLE_RE = re.compile(r"^(?P<indent>\s*)\[(?P<names>[^\]]+)\]\s*=")
FUNC_RE = re.compile(r"^(?P<indent>\s*)(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?P<args>[^)]*)\)\s*=>")
TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*")
FOR_RE = re.compile(r"^(?P<indent>\s*)for\s+(?P<var>[A-Za-z_]\w*)\s*=\s*(?P<lo>[^\s]+)\s+to\s+(?P<hi>.+?)\s*$")
TABLE_NEW_RE = re.compile(r"(?:var\s+)?table\s+(?P<name>\w+)\s*=\s*table\.new\(\s*[^,]+,\s*(?P<cols>\d+)\s*,\s*(?P<rows>\d+)")
TABLE_CELL_RE = re.compile(r"table\.cell\(\s*(?P<name>\w+)\s*,\s*(?P<col>[^,]+?)\s*,\s*(?P<row>[^,]+?)\s*,")
ARRAY_FROM_RE = re.compile(r"array<(?P<kind>\w+)>\s+(?P<name>\w+)\s*=\s*array\.from\((?P<body>.*)\)\s*$")


@dataclass(frozen=True)
class Finding:
    line: int
    rule: str
    message: str

    def __str__(self) -> str:
        return f"{self.line:>5}  {self.rule:<20} {self.message}"


def _strip_strings_and_comments(line: str) -> str:
    """Blank out string literals and trailing comments so scans see only code."""
    out: list[str] = []
    quote: str | None = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                out.append("  ")
                i += 2
                continue
            if ch == quote:
                quote = None
            out.append(" ")
        elif ch in "\"'":
            quote = ch
            out.append(" ")
        elif ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def _split_top_level(body: str) -> list[str]:
    """Split an argument list on commas that are not inside brackets or strings."""
    parts: list[str] = []
    depth = 0
    quote: str | None = None
    current: list[str] = []
    i = 0
    while i < len(body):
        ch = body[i]
        if quote:
            current.append(ch)
            if ch == "\\":
                if i + 1 < len(body):
                    current.append(body[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            current.append(ch)
        elif ch in "([":
            depth += 1
            current.append(ch)
        elif ch in ")]":
            depth -= 1
            current.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
        i += 1
    if body.strip() or parts:
        # The tail is appended even when empty: string literals are blanked
        # before this runs, so the last element of a list of strings IS empty,
        # and dropping it makes every count one short.
        parts.append("".join(current).strip())
    return parts


def _enclosing_loops(code: list[str]) -> list[dict[str, int]]:
    """For each line, the loop variables in scope and their maximum value.

    Only loops whose upper bound is an integer literal are tracked; a bound of
    ``array.size(x) - 1`` cannot be resolved statically and is left out rather
    than guessed at.
    """
    scopes: list[dict[str, int]] = []
    stack: list[tuple[int, str, int]] = []  # indent, var, max value
    for raw in code:
        stripped = raw.lstrip(" ")
        indent = len(raw) - len(stripped)
        if stripped:
            while stack and indent <= stack[-1][0]:
                stack.pop()
        scopes.append({var: hi for _, var, hi in stack})
        m = FOR_RE.match(raw)
        if m:
            hi = m.group("hi").strip()
            if re.fullmatch(r"-?\d+", hi):
                stack.append((indent, m.group("var"), int(hi)))
    return scopes


def _max_index(expr: str, loops: dict[str, int]) -> int | None:
    """Largest value an index expression can take, or None if not decidable."""
    expr = expr.strip()
    if re.fullmatch(r"-?\d+", expr):
        return int(expr)
    m = re.fullmatch(r"([A-Za-z_]\w*)\s*\+\s*(\d+)", expr)
    if m and m.group(1) in loops:
        return loops[m.group(1)] + int(m.group(2))
    m = re.fullmatch(r"(\d+)\s*-\s*([A-Za-z_]\w*)", expr)
    if m and m.group(2) in loops:
        return int(m.group(1))
    if expr in loops:
        return loops[expr]
    return None


def lint(source: str) -> list[Finding]:
    lines = source.splitlines()
    code = [_strip_strings_and_comments(line) for line in lines]
    findings: list[Finding] = []

    if not lines or lines[0].strip() != "//@version=6":
        findings.append(Finding(1, "version", "first line must be //@version=6"))

    # --- whitespace and layout ------------------------------------------
    open_depth = 0
    for n, raw in enumerate(lines, start=1):
        if "\t" in raw:
            findings.append(Finding(n, "tabs", "tab character; Pine indentation must be spaces"))
        stripped = raw.lstrip(" ")
        indent = len(raw) - len(stripped)
        if stripped and indent % 4 != 0 and open_depth == 0:
            findings.append(Finding(n, "indent", f"indent {indent} is not a multiple of 4"))
        if raw.rstrip() != raw:
            findings.append(Finding(n, "trailing-space", "trailing whitespace"))
        c = code[n - 1]
        open_depth += c.count("(") + c.count("[") - c.count(")") - c.count("]")
        open_depth = max(open_depth, 0)

    # --- comma-separated declarations -----------------------------------
    for n, c in enumerate(code, start=1):
        if re.search(r",\s*(?:var|varip)\s", c):
            findings.append(Finding(n, "comma-decl", "comma-separated `var` declarations are invalid Pine"))
        if re.match(r"^\s*(?:int|float|bool|string)\s+[A-Za-z_]\w*\s*=[^,]*,\s*[A-Za-z_]\w*\s*=", c):
            findings.append(Finding(n, "comma-decl", "multiple declarations on one line are invalid Pine"))

    # --- bracket balance -------------------------------------------------
    depth = {"(": 0, "[": 0, "{": 0}
    closers = {")": "(", "]": "[", "}": "{"}
    for n, c in enumerate(code, start=1):
        for ch in c:
            if ch in depth:
                depth[ch] += 1
            elif ch in closers:
                depth[closers[ch]] -= 1
                if depth[closers[ch]] < 0:
                    findings.append(Finding(n, "brackets", f"unbalanced '{ch}'"))
                    depth[closers[ch]] = 0
    for opener, remaining in depth.items():
        if remaining:
            findings.append(Finding(len(lines), "brackets", f"{remaining} unclosed '{opener}'"))

    # --- repainting hazards ----------------------------------------------
    for n, c in enumerate(code, start=1):
        if "lookahead_on" in c:
            findings.append(Finding(n, "lookahead", "barmerge.lookahead_on introduces future data"))
        if "request.security(" in c and "lookahead" not in c:
            findings.append(Finding(n, "lookahead", "request.security() without an explicit lookahead argument"))
        if re.search(r"[^.\w]security\s*\(", c):
            findings.append(Finding(n, "v5-removal", "bare security() was removed; use request.security()"))
        for removed in ("iff(", "study("):
            if removed in c:
                findings.append(Finding(n, "v5-removal", f"`{removed}` is not valid Pine v6"))

    # --- stateful helpers inside request.security() -----------------------
    stateful = {m.group("name") for m in (FUNC_RE.match(line) for line in lines) if m}
    stateful_bodies: dict[str, bool] = {}
    current: str | None = None
    for line in lines:
        m = FUNC_RE.match(line)
        if m and m.group("indent") == "":
            current = m.group("name")
            stateful_bodies.setdefault(current, False)
            continue
        if current and line and not line.startswith((" ", "\t")):
            current = None
        if current and re.search(r"\bvar\b", _strip_strings_and_comments(line)):
            stateful_bodies[current] = True
    for n, c in enumerate(code, start=1):
        if "request.security(" not in c:
            continue
        for fname in stateful:
            if stateful_bodies.get(fname) and re.search(rf"\b{fname}\s*\(", c):
                findings.append(Finding(n, "security-state", f"stateful helper `{fname}()` inside request.security()"))

    # --- integer division -------------------------------------------------
    int_names: set[str] = set()
    for line in code:
        m = re.match(r"^\s*(?:var\s+|varip\s+)?int\s+([A-Za-z_]\w*)\s*=", line)
        if m:
            int_names.add(m.group(1))
    for n, c in enumerate(code, start=1):
        for left, right in re.findall(r"\b([A-Za-z_]\w*)\s*/\s*([A-Za-z_]\w*)\b", c):
            if left in int_names and right in int_names:
                findings.append(
                    Finding(n, "int-division", f"`{left} / {right}` is integer division in Pine; multiply by 1.0 first")
                )

    # --- descending loops over empty arrays --------------------------------
    for n, c in enumerate(code, start=1):
        m = re.search(r"for\s+\w+\s*=\s*0\s+to\s+array\.size\((\w+)\)\s*-\s*1", c)
        if not m:
            continue
        name = m.group(1)
        guard = re.compile(rf"array\.size\(\s*{name}\s*\)\s*>\s*0")
        window = code[max(0, n - 6): n - 1]
        if not any(guard.search(line) for line in window):
            findings.append(
                Finding(n, "empty-loop", f"loop over `{name}` has no `array.size({name}) > 0` guard within 5 lines")
            )

    # --- table writes outside the declared table -------------------------
    loops = _enclosing_loops(code)
    tables: dict[str, tuple[int, int, int]] = {}
    for n, c in enumerate(code, start=1):
        m = TABLE_NEW_RE.search(c)
        if m:
            tables[m.group("name")] = (int(m.group("cols")), int(m.group("rows")), n)
    for n, c in enumerate(code, start=1):
        m = TABLE_CELL_RE.search(c)
        if not m or m.group("name") not in tables:
            continue
        cols, rows, decl = tables[m.group("name")]
        scope = loops[n - 1]
        col = _max_index(m.group("col"), scope)
        row = _max_index(m.group("row"), scope)
        if col is not None and col >= cols:
            findings.append(
                Finding(n, "table-bounds", f"column {col} written to `{m.group('name')}` declared with {cols} columns on line {decl}")
            )
        if row is not None and row >= rows:
            findings.append(
                Finding(n, "table-bounds", f"row {row} written to `{m.group('name')}` declared with {rows} rows on line {decl}")
            )

    # --- array.from literals shorter than the loops that read them --------
    literals: dict[str, list[tuple[int, int]]] = {}
    for n, c in enumerate(code, start=1):
        m = ARRAY_FROM_RE.search(c.strip())
        if m:
            literals.setdefault(m.group("name"), []).append((n, len(_split_top_level(m.group("body")))))
    for n, c in enumerate(code, start=1):
        for name, idx in re.findall(r"array\.get\(\s*(\w+)\s*,\s*([^)]+?)\s*\)", c):
            # A name like `vals` is re-declared in every dashboard block, so the
            # binding that matters is the nearest one above this read.
            prior = [(d, sz) for d, sz in literals.get(name, []) if d < n]
            if not prior:
                continue
            decl, size = prior[-1]
            top = _max_index(idx, loops[n - 1])
            if top is not None and top >= size:
                findings.append(
                    Finding(n, "array-bounds", f"index {top} read from `{name}`, an array.from of {size} elements on line {decl}")
                )

    # --- declaration ordering ---------------------------------------------
    declared: dict[str, int] = {}
    func_names: dict[str, int] = {}
    local_names: set[str] = set()
    for n, line in enumerate(lines, start=1):
        c = code[n - 1]
        fm = FUNC_RE.match(c)
        if fm:
            if fm.group("indent") == "":
                func_names.setdefault(fm.group("name"), n)
                for arg in fm.group("args").split(","):
                    token = arg.strip().split(" ")[-1]
                    if token:
                        local_names.add(token)
            continue
        tm = TUPLE_RE.match(c)
        if tm:
            indent = len(tm.group("indent"))
            for name in tm.group("names").split(","):
                name = name.strip()
                if not name:
                    continue
                if indent == 0:
                    declared.setdefault(name, n)
                else:
                    local_names.add(name)
            continue
        dm = DECL_RE.match(c)
        if dm:
            name = dm.group("name")
            if name in KEYWORDS:
                continue
            indent = len(dm.group("indent"))
            if indent == 0 and dm.group("op") == "=":
                declared.setdefault(name, n)
            else:
                local_names.add(name)

    known = set(declared) | set(func_names)
    for n, c in enumerate(code, start=1):
        dm = DECL_RE.match(c)
        declared_here = dm.group("name") if dm else None
        for token in TOKEN_RE.findall(c):
            if token.startswith(BUILTIN_PREFIXES) or "." in token:
                continue
            if token in KEYWORDS or token in BUILTIN_VARS or token in local_names:
                continue
            if token == declared_here:
                continue
            if token in known:
                first = declared.get(token, func_names.get(token, 0))
                if n < first:
                    findings.append(Finding(n, "use-before-decl", f"`{token}` is used before its declaration on line {first}"))

    # --- v7 architecture invariants ----------------------------------------
    # A gate has to be BOTH computed and consumed. Checking only that the name
    # appears somewhere would be satisfied by the rejection branch alone, which
    # is exactly the half that survives when the definition is renamed away.
    defined = {m.group(1) for m in (re.match(r"\s*bool\s+(ok\w+)\s*=", line) for line in code) if m}
    consumed = " ".join(line for line in code if re.match(r"\s*(?:else\s+)?if\s+not\s+ok\w+", line))
    for gate in MANDATORY_GATES:
        if gate not in defined:
            findings.append(Finding(0, "spec", f"mandatory gate `{gate}` is never computed in the candidate pipeline"))
        elif not re.search(rf"\bnot {gate}\b", consumed):
            findings.append(Finding(0, "spec", f"mandatory gate `{gate}` is computed but never rejects a candidate"))
    for counter in FUNNEL_COUNTERS:
        if not re.search(rf"\b{counter}\b", source):
            findings.append(Finding(0, "spec", f"funnel counter `{counter}` is not declared"))
        elif "fuVal" in source and counter.startswith("fBlock") and counter not in source.split("fuVal")[1][:2000]:
            findings.append(Finding(0, "spec", f"funnel counter `{counter}` is never shown in the funnel table"))
    for weight in SCORE_WEIGHTS:
        if not re.search(rf"{weight}\s*=\s*input\.float", source):
            findings.append(Finding(0, "spec", f"score weight `{weight}` is not a configurable input"))
    for diagnostic in REQUIRED_DIAGNOSTICS:
        if diagnostic not in source:
            findings.append(Finding(0, "spec", f"diagnostic string missing: {diagnostic}"))
    if "i_maxPerDay" not in source or "dayTrades >= i_maxPerDay" not in source:
        findings.append(Finding(0, "spec", "the hard daily trade cap is not enforced"))
    if "math.min(tierRisk * nScale, i_riskCeil)" not in source:
        findings.append(Finding(0, "spec", "per-trade risk is not clamped to the hard ceiling"))

    return sorted(findings, key=lambda f: (f.line, f.rule))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: python pine_lint.py <file.pine>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    findings = lint(path.read_text(encoding="utf-8"))
    for finding in findings:
        print(finding)
    print(f"\n{len(findings)} finding(s) in {path.name}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
