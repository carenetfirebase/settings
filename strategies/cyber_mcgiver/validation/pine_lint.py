"""Static checks for the CYBER MCGIVER v1.0 Pine v6 source.

TradingView owns the only Pine compiler, so nothing here proves the script
compiles. What it does prove is that the classes of mistake that survive a
careful read — and that are expensive to find by pasting into a chart — are
absent:

* comma-separated declarations (`var float a = na, var float b = na`), which
  read fine to a Python eye and are a syntax error in Pine;
* a global used before the line that declares it;
* `lookahead_on`, or a `request.security()` with no explicit lookahead, either
  of which silently introduces future data into the 1D/4H/1H regime;
* stateful helpers evaluated inside `request.security()`;
* v5-era removals (`iff`, `security(`, `study(`);
* integer division, which Pine truncates — a win-rate bug that is invisible
  because the same expression is correct in every other language here;
* tabs, or indentation that is not a multiple of four;
* a state-machine constant, funnel counter or diagnostic string from the
  specification that no longer appears in the source.

Run directly: ``python -m validation.pine_lint path/to/CYBER_MCGIVER.pine``
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

#: Pine keywords and built-in namespaces that are never user declarations.
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

#: S61/S62 — every state the machine is specified to occupy.
REQUIRED_STATES = (
    "STATE_WAIT_BOS",
    "STATE_WAIT_P1",
    "STATE_WAIT_P2",
    "STATE_CANDIDATE",
    "STATE_CONFIRMED",
    "STATE_ARMED",
    "STATE_OPEN",
)

#: S64 — the funnel must be able to say where candidates are lost.
REQUIRED_COUNTERS = (
    "fBars", "fLongB", "fShortB", "fBosL", "fBosS", "fP1", "fP2", "fCand",
    "fP3", "fT4", "fRej", "fArm", "fFill", "fTrade",
)

#: S73 — the engine must be able to say why it did not trade.
REQUIRED_DIAGNOSTICS = (
    "CYBER MCGIVER REQUIRES 5m OR 15m",
    "NO TRADE — HTF DISAGREEMENT",
    "NO TRADE — WAITING FOR BREAK OF STRUCTURE",
    "NO TRADE — WAITING FOR P1",
    "NO TRADE — WAITING FOR P2",
    "NO TRADE — LINE NOT CONFIRMED (WAITING FOR P3)",
    "NO TRADE — WAITING FOR TOUCH #4",
)

#: The symmetry requirement (S74): both engines exist, neither is a stub.
REQUIRED_SYMMETRY = ("strategy.long", "strategy.short")

DECL_RE = re.compile(
    r"^(?P<indent>\s*)(?:var\s+|varip\s+)?"
    r"(?:(?:int|float|bool|string|color|line|label|box|table)\s+"
    r"(?:\[\])?\s*|(?:array|matrix|map)<[^>]+>\s+)?"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<op>:?=)(?!=)"
)
TUPLE_RE = re.compile(r"^(?P<indent>\s*)\[(?P<names>[^\]]+)\]\s*=")
FUNC_RE = re.compile(r"^(?P<indent>\s*)(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?P<args>[^)]*)\)\s*=>")
TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*")


@dataclass(frozen=True)
class Finding:
    line: int
    rule: str
    message: str

    def __str__(self) -> str:
        return f"{self.line:>5}  {self.rule:<22} {self.message}"


def _strip_strings_and_comments(line: str) -> str:
    """Blank out string literals and trailing comments so scans see only code."""
    out: list[str] = []
    quote: str | None = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                out.append(" ")
                i += 2
                out.append(" ")
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


def lint(source: str) -> list[Finding]:
    lines = source.splitlines()
    code = [_strip_strings_and_comments(line) for line in lines]
    findings: list[Finding] = []

    # --- header ---------------------------------------------------------
    if not lines or lines[0].strip() != "//@version=6":
        findings.append(Finding(1, "version", "first line must be //@version=6"))

    # --- whitespace and layout ------------------------------------------
    # Lines that continue an open bracket are free-form; Pine only cares about
    # the indentation of statements.
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

    # --- comma-separated declarations (valid Python, invalid Pine) ------
    for n, c in enumerate(code, start=1):
        if re.search(r",\s*(?:var|varip)\s", c):
            findings.append(Finding(n, "comma-decl", "comma-separated `var` declarations are invalid Pine"))
        # `float a = 0.0, b = 0.0` style
        if re.match(r"^\s*(?:int|float|bool|string)\s+[A-Za-z_]\w*\s*=[^,]*,\s*[A-Za-z_]\w*\s*=", c):
            findings.append(Finding(n, "comma-decl", "multiple declarations on one line are invalid Pine"))

    # --- bracket balance over the whole file ----------------------------
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

    # --- repainting hazards ---------------------------------------------
    for n, c in enumerate(code, start=1):
        if "lookahead_on" in c:
            findings.append(Finding(n, "lookahead", "barmerge.lookahead_on introduces future data"))
        if "request.security(" in c and "lookahead" not in c:
            findings.append(Finding(n, "lookahead", "request.security() without an explicit lookahead argument"))
        if re.search(r"[^.\w]security\s*\(", c):
            findings.append(Finding(n, "v5-removal", "bare security() was removed; use request.security()"))
        for removed in ("iff(", "study(", "cross(", "vwap(", "offset="):
            if removed in c and "ta." not in c and "plot(" not in c:
                findings.append(Finding(n, "v5-removal", f"`{removed}` is not valid Pine v6 here"))

    # --- stateful helpers inside request.security() ----------------------
    stateful = {
        m.group("name")
        for m in (FUNC_RE.match(line) for line in lines)
        if m
    }
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
                findings.append(
                    Finding(n, "security-state", f"stateful helper `{fname}()` evaluated inside request.security()")
                )

    # --- integer division ------------------------------------------------
    # Pine evaluates `int / int` as INTEGER division, so `wins / n` is 0 for
    # any win rate below 100%. The bug is invisible on inspection because the
    # same expression is correct in every other language in this repository.
    int_names: set[str] = set()
    for line in code:
        m = re.match(r"^\s*(?:var\s+|varip\s+)?int\s+([A-Za-z_]\w*)\s*=", line)
        if m:
            int_names.add(m.group(1))
    for n, c in enumerate(code, start=1):
        for left, right in re.findall(r"\b([A-Za-z_]\w*)\s*/\s*([A-Za-z_]\w*)\b", c):
            if left in int_names and right in int_names:
                findings.append(
                    Finding(
                        n,
                        "int-division",
                        f"`{left} / {right}` is integer division in Pine; multiply by 1.0 first",
                    )
                )

    # --- descending loops over empty arrays ------------------------------
    # `for k = 0 to array.size(x) - 1` counts DOWN when the array is empty:
    # Pine runs it with k = 0 then k = -1, and array.get(x, 0) throws at
    # runtime on the empty array. Every such loop needs a size guard above it.
    for n, c in enumerate(code, start=1):
        m = re.search(r"for\s+\w+\s*=\s*0\s+to\s+array\.size\((\w+)\)\s*-\s*1", c)
        if not m:
            continue
        name = m.group(1)
        guard = re.compile(rf"array\.size\(\s*{name}\s*\)\s*>\s*0")
        window = code[max(0, n - 5): n - 1]
        if not any(guard.search(line) for line in window):
            findings.append(
                Finding(
                    n,
                    "empty-loop",
                    f"loop over `{name}` has no `array.size({name}) > 0` guard; "
                    "an empty array makes this loop count down to -1",
                )
            )

    # --- declaration ordering -------------------------------------------
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
                    findings.append(
                        Finding(n, "use-before-decl", f"`{token}` is used before its declaration on line {first}")
                    )

    # --- specification coverage -----------------------------------------
    for name in REQUIRED_STATES:
        if not re.search(rf"^int {name}\s*=", source, re.MULTILINE):
            findings.append(Finding(0, "spec", f"state constant `{name}` (S61/S62) is not declared"))
    for name in REQUIRED_COUNTERS:
        if not re.search(rf"^var float {name}\s*=", source, re.MULTILINE):
            findings.append(Finding(0, "spec", f"funnel counter `{name}` (S64) is not declared"))
        elif not re.search(rf"\b{name}\s+\+=", source):
            findings.append(Finding(0, "spec", f"funnel counter `{name}` (S64) is never incremented"))
    for diagnostic in REQUIRED_DIAGNOSTICS:
        if diagnostic not in source:
            findings.append(Finding(0, "spec", f"diagnostic string missing (S73): {diagnostic}"))
    for token in REQUIRED_SYMMETRY:
        if token not in source:
            findings.append(Finding(0, "spec", f"`{token}` missing; the specification is symmetric (S74)"))

    # --- risk sequencing (S48) -------------------------------------------
    # Structure -> stop -> size -> risk. A stop derived from the risk budget
    # inverts the hypothesis, so the stop must be built from P3 alone.
    stop_lines = [line for line in lines if "armStop  :=" in line or "float stopPx" in line]
    if not any("p3Price" in line for line in stop_lines):
        findings.append(Finding(0, "spec", "the structural stop (S35/S43/S48) is not derived from P3"))
    for n, c in enumerate(code, start=1):
        if "stopPx" in c and "riskBudget" in c:
            findings.append(Finding(n, "spec", "stop location computed from the risk budget; S48 forbids this"))

    return sorted(findings, key=lambda f: (f.line, f.rule))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: python -m validation.pine_lint <file.pine>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    findings = lint(path.read_text(encoding="utf-8"))
    for finding in findings:
        print(finding)
    print(f"\n{len(findings)} finding(s) in {path.name}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
