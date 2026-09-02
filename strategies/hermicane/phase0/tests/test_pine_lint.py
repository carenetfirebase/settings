"""Tests for the Pine lint.

A lint that reports nothing is indistinguishable from a lint that checks
nothing, and this one is the only verification the Pine source gets — nobody
here has a Pine compiler. So every check is fed a snippet that should trip it,
and the real strategy file is asserted clean at the end.
"""

from __future__ import annotations

from pathlib import Path

from phase0.pine_lint import ERROR, lint

STRATEGY = Path(__file__).resolve().parents[2] / "HERMICANE_v2.pine"


def codes(source: str) -> set[str]:
    return {finding.code for finding in lint(source)}


def test_ta_inside_a_conditional_block_is_caught():
    bad = "if someCondition\n    float priorHigh = ta.highest(high, 3)[1]"
    assert "TA-IN-BLOCK" in codes(bad)


def test_ta_at_global_scope_is_fine():
    assert "TA-IN-BLOCK" not in codes("float priorHigh = ta.highest(high, 3)[1]")


def test_array_get_guarded_by_and_is_caught():
    bad = "while nextEvent < array.size(eventTimes) and array.get(eventTimes, nextEvent) < time"
    assert "SHORTCIRCUIT" in codes(bad)


def test_unguarded_loop_over_an_array_is_caught():
    assert "EMPTY-LOOP" in codes("for i = 0 to array.size(lines) - 1\n    x = 1")


def test_a_guarded_loop_is_accepted():
    good = (
        "if array.size(lines) > 0\n"
        "    for i = 0 to array.size(lines) - 1\n"
        "        x = 1"
    )
    assert "EMPTY-LOOP" not in codes(good)


def test_cross_timeframe_security_without_an_offset_is_caught():
    bad = 'float a = request.security(syminfo.tickerid, "D", close, lookahead = barmerge.lookahead_off)'
    assert "HTF-OFFSET" in codes(bad)


def test_same_timeframe_security_needs_no_offset():
    good = "float a = request.security(sym, timeframe.period, close, lookahead = barmerge.lookahead_off)"
    assert "HTF-OFFSET" not in codes(good)


def test_missing_and_forward_looking_lookahead_are_both_caught():
    assert "LOOKAHEAD" in codes('float a = request.security(s, timeframe.period, close)')
    assert "LOOKAHEAD" in codes(
        'float a = request.security(s, timeframe.period, close, lookahead = barmerge.lookahead_on)'
    )


def test_comma_separated_declarations_are_caught():
    assert "COMMA-DECL" in codes("float a = na, float b = na")


def test_v5_removals_are_caught():
    assert "V5-REMOVED" in codes('a = security(sym, "D", close)')
    assert "V5-REMOVED" in codes("b = iff(x > 1, 2, 3)")


def test_a_table_write_past_the_declared_size_is_caught():
    bad = (
        "var table dash = table.new(position.top_right, 2, 4, border_width = 1)\n"
        "writeRow(dash, 7, 'a', 'b', TXT)"
    )
    assert "TABLE-BOUNDS" in codes(bad)


def test_a_table_write_inside_the_declared_size_is_accepted():
    good = (
        "var table dash = table.new(position.top_right, 2, 8, border_width = 1)\n"
        "writeRow(dash, 7, 'a', 'b', TXT)"
    )
    assert "TABLE-BOUNDS" not in codes(good)


def test_a_reintroduced_score_term_is_caught():
    assert "AUDIT-1" in codes("float breakoutScore = 10.0")
    assert "AUDIT-1" in codes("float fiveScore = 10.0")


def test_an_unlabelled_threshold_input_is_caught():
    bad = 'float pbMax = input.float(0.60, "pullback max", minval = 0.0)'
    assert "UNLABELLED" in codes(bad)
    good = 'float pbMax = input.float(0.60, "UNCALIBRATED · pullback max", minval = 0.0)'
    assert "UNLABELLED" not in codes(good)


def test_a_missing_causality_guard_is_caught():
    assert "CAUSALITY" in codes("// nothing here")


def test_tabs_and_odd_indentation_are_caught():
    assert "TAB" in codes("if x\n\ty = 1")
    assert "INDENT" in codes("if x\n  y = 1")


def test_continuation_lines_may_be_indented_freely():
    source = "strategy(\n     title = 'x',\n     overlay = true)"
    assert "INDENT" not in codes(source)
    assert "PARENS" not in codes(source)


def test_an_unclosed_bracket_is_caught():
    assert "PARENS" in codes("a = math.max(1, 2")


def test_exit_far_from_entry_is_caught():
    bad = "\n".join(
        ["strategy.entry('LONG', strategy.long, qty = 1)"]
        + [f"x{i} = {i}" for i in range(10)]
        + ["strategy.exit('X', 'LONG', stop = s, limit = t)"]
    )
    assert "AUDIT-10" in codes(bad)


# --- the real thing -------------------------------------------------------

def test_the_strategy_file_exists():
    assert STRATEGY.exists(), f"missing {STRATEGY}"


def test_the_strategy_file_is_clean():
    findings = lint(STRATEGY.read_text(encoding="utf-8"))
    errors = [f for f in findings if f.level == ERROR]
    assert not errors, "\n".join(str(f) for f in errors)


def test_the_strategy_declares_pine_v6_and_a_timeframe_guard():
    text = STRATEGY.read_text(encoding="utf-8")
    assert "//@version=6" in text
    assert "timeframe.in_seconds() != 60" in text


def test_the_strategy_ships_every_filter_disabled():
    """The control rule is the default. A filter switched on by default would be
    an uncalibrated constant doing load-bearing work."""
    text = STRATEGY.read_text(encoding="utf-8")
    for name in ("fImpulse", "fMacro", "fFive", "fTrend", "fPullback", "fOrigin", "fAgrees"):
        line = next(ln for ln in text.splitlines() if ln.startswith(f"bool {name} ="))
        assert "input.bool(false" in line, f"{name} does not default to off: {line}"


def test_exit_gated_on_position_size_is_caught():
    """v1's defect: under process_orders_on_close the position does not exist
    until the bar after the fill, so the entry bar runs unprotected."""
    bad = (
        "if strategy.position_size != 0\n"
        "    strategy.exit('X', 'LONG', stop = s, limit = t)"
    )
    assert "AUDIT-10" in codes(bad)


def test_exit_placed_with_the_entry_is_accepted():
    good = (
        "if wantEntry\n"
        "    strategy.entry('LONG', strategy.long, qty = q)\n"
        "    strategy.exit('X', 'LONG', stop = s, limit = t)"
    )
    assert "AUDIT-10" not in codes(good)
