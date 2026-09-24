"""Calibration and attribution maths, on hand-built ledger rows."""

from __future__ import annotations

from datetime import date

import pytest

from invest.ledger import (
    MIN_CLOSED,
    LedgerRow,
    _stderr,
    attribution,
    calibration,
    clustered_stderr,
    group_stats,
)


def row(
    score: float | None,
    r: float | None,
    *,
    status: str = "card",
    outcome: str = "target",
    bonus: float = 0.0,
    checks: list[dict] | None = None,
    first: str | None = "up",
) -> LedgerRow:
    return LedgerRow(
        signal_id=1,
        ticker="T",
        as_of_date=date(2026, 1, 2),
        origin="backfill",
        status=status,
        fired=status == "card",
        final_score=score,
        insider_bonus=bonus,
        entry=100,
        stop=95,
        target=110,
        model_version="SIG-v1.0",
        checks=checks or [],
        reasons=[],
        outcome_status=outcome,
        evaluated_through=date(2026, 1, 20),
        trigger_date=date(2026, 1, 5) if outcome not in ("expired", "pending") else None,
        exit_date=date(2026, 1, 15) if outcome in ("target", "stop", "time") else None,
        r_net=r,
        r_gross=r,
        mfe_r=1.0,
        mae_r=-0.5,
        bars_held=5,
        first_touch=first,
    )


def test_group_stats_counts_only_closed_trades() -> None:
    rows = [
        row(80, 2.0),
        row(80, -1.0, outcome="stop", first="down"),
        row(80, 0.4, outcome="open"),
        row(80, None, outcome="expired", first=None),
    ]
    stats = group_stats("g", rows)
    assert stats.signals == 4 and stats.triggered == 3 and stats.closed == 2
    assert stats.mean_r == pytest.approx(0.5)
    assert stats.win_rate == pytest.approx(0.5)
    assert stats.first_up_rate == pytest.approx(2 / 3)
    assert not stats.enough and "too few" in stats.notes[0]


def test_iid_stderr() -> None:
    assert _stderr([1.0]) is None
    assert _stderr([1.0, -1.0]) == pytest.approx(1.0)  # sd = sqrt(2), / sqrt(2)


def test_clustered_stderr_needs_two_clusters() -> None:
    same_week = [((2026, 1), 1.0), ((2026, 1), -1.0)]
    assert clustered_stderr(same_week) is None
    assert group_stats("g", [row(80, 1.0), row(80, -1.0, outcome="stop")]).stderr_r is None


def test_clustering_widens_the_error_when_weeks_move_together() -> None:
    """Twenty trades that are really two draws must not look like twenty."""
    pairs = [((2026, 1), 1.0)] * 10 + [((2026, 2), -1.0)] * 10
    iid = _stderr([v for _, v in pairs])
    clustered = clustered_stderr(pairs)
    assert clustered > 3 * iid
    independent = [((2026, w), v) for w, (_, v) in enumerate(pairs)]
    assert clustered_stderr(independent) == pytest.approx(iid, rel=0.1)


def test_calibration_buckets_and_monotonicity() -> None:
    low = [row(65, -0.2)] * MIN_CLOSED
    high = [row(85, 0.6)] * MIN_CLOSED
    cal = calibration(low + high, origin="backfill", fired_only=True)
    by_label = {b.label: b for b in cal.buckets}
    assert by_label["60–70"].closed == MIN_CLOSED and by_label["80–90"].closed == MIN_CLOSED
    assert by_label["90–100"].signals == 0
    assert cal.monotonic is True
    inverted = calibration(
        [row(65, 0.6)] * MIN_CLOSED + [row(85, -0.2)] * MIN_CLOSED, origin=None, fired_only=False
    )
    assert inverted.monotonic is False


def test_calibration_refuses_to_judge_small_buckets() -> None:
    cal = calibration([row(65, 1.0), row(85, 2.0)], origin=None, fired_only=False)
    assert cal.monotonic is None


def test_a_score_of_100_lands_in_the_top_bucket() -> None:
    cal = calibration([row(100.0, 1.0)], origin=None, fired_only=False)
    assert cal.buckets[-1].signals == 1


def spread(rows: list[LedgerRow]) -> list[LedgerRow]:
    """Give each row its own week, so trades are independent draws."""
    from dataclasses import replace
    from datetime import timedelta

    return [
        replace(r, as_of_date=date(2024, 1, 1) + timedelta(weeks=i)) for i, r in enumerate(rows)
    ]


def test_attribution_compares_blocked_to_fired() -> None:
    fired = [row(80, 0.5 + (i % 2) * 0.2) for i in range(30)]
    vetoed = [
        row(
            80,
            -0.5 - (i % 2) * 0.2,
            status="vetoed",
            checks=[{"name": "quality_veto", "passed": False}],
        )
        for i in range(30)
    ]
    result = attribution(spread(fired) + spread(vetoed), origin="backfill")
    quality = next(g for g in result.groups if "quality" in g.label)
    assert quality.closed == 30
    assert quality.diff_vs_reference == pytest.approx(-1.2)
    assert quality.t_vs_reference < -3  # the veto clearly earns its place here
    gate = next(g for g in result.groups if "trend gate" in g.label)
    assert gate.signals == 0 and gate.t_vs_reference is None
