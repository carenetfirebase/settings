"""Backtest engine. docs/PHASES.md Phase 8.

Criterion 5 — the baseline report on real insider clusters — is **not** met:
it needs live price data this environment cannot reach. What is tested here is
the machinery that report depends on, and in particular the two properties
that decide whether any backtest number is admissible at all: the entry clock
and the universe reconstruction.
"""

from __future__ import annotations

import itertools
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

import pytest

from imt.backtest.engine import (
    Outcome,
    PriceSeries,
    SignalEntry,
    assert_no_lookahead,
    forward_return,
    run_entry,
)
from imt.backtest.report import (
    MIN_SAMPLE,
    build_report,
    mean_confidence_interval,
    summarize_horizon,
    walk_forward_splits,
)
from imt.backtest.universe import UniverseSnapshotSet, reconstruct_universe


def flat_series(start: date, days: int, price: float = 100.0, drift: float = 0.0) -> PriceSeries:
    """Weekday-only series, so weekend handling is exercised by construction."""
    bars: list[tuple[date, Decimal]] = []
    current = start
    value = Decimal(str(price))
    while len(bars) < days:
        if current.weekday() < 5:
            bars.append((current, value))
            value += Decimal(str(drift))
        current += timedelta(days=1)
    return PriceSeries(bars)


class TestEntryClock:
    """Phase 8 criterion 1. Every look-ahead bug would enter through here."""

    def test_entry_is_never_before_public_availability(self) -> None:
        prices = flat_series(date(2026, 1, 1), 300, drift=0.1)
        entry = SignalEntry(
            cik="0000000001",
            signal="insider_cluster",
            public_available_at=datetime(2026, 3, 2, 9, 30, tzinfo=UTC),
            transaction_date=date(2026, 1, 20),
        )
        result = run_entry(entry, prices=prices)
        assert not result.has_lookahead
        assert result.entry_timestamp >= entry.public_available_at

    def test_a_weekend_availability_enters_on_the_next_session(self) -> None:
        """Saturday news is tradable on Monday, not on Saturday."""
        prices = flat_series(date(2026, 1, 1), 200)
        saturday = datetime(2026, 3, 7, 12, 0, tzinfo=UTC)
        assert saturday.date().weekday() == 5
        result = run_entry(
            SignalEntry(cik="1", signal="s", public_available_at=saturday), prices=prices
        )
        assert result.entry_timestamp.date().weekday() == 0
        assert not result.has_lookahead

    def test_the_assertion_catches_a_planted_violation(self) -> None:
        """A gate that cannot fail is not a gate."""
        from dataclasses import replace

        prices = flat_series(date(2026, 1, 1), 200)
        entry = SignalEntry(
            cik="1", signal="s", public_available_at=datetime(2026, 3, 2, 9, 30, tzinfo=UTC)
        )
        good = run_entry(entry, prices=prices)
        assert_no_lookahead([good])

        planted = replace(good, entry_timestamp=datetime(2026, 1, 5, 9, 30, tzinfo=UTC))
        with pytest.raises(AssertionError, match="precede their public availability"):
            assert_no_lookahead([planted])

    def test_transaction_date_is_carried_but_never_used_for_timing(self) -> None:
        """Phase 8 criterion 2, in the engine.

        A PTR's transaction date is six weeks before its disclosure. Timing off
        it would be trading on information that was not public.
        """
        prices = flat_series(date(2026, 1, 1), 300, drift=0.1)
        entry = SignalEntry(
            cik="1",
            signal="political",
            public_available_at=datetime(2026, 3, 2, 9, 30, tzinfo=UTC),
            transaction_date=date(2026, 1, 15),
        )
        result = run_entry(entry, prices=prices)
        assert entry.disclosure_lag_days == 46
        assert result.entry_timestamp.date() >= entry.public_available_at.date()
        assert result.entry_timestamp.date() > entry.transaction_date


class TestCongressionalTimingDivergence:
    """Phase 8 criterion 2: using the transaction date gives different — and
    inadmissible — results."""

    def test_the_two_clocks_produce_different_returns(self) -> None:
        prices = flat_series(date(2026, 1, 1), 300, drift=0.5)

        honest = run_entry(
            SignalEntry(
                cik="1",
                signal="political",
                public_available_at=datetime(2026, 3, 2, 9, 30, tzinfo=UTC),
                transaction_date=date(2026, 1, 15),
            ),
            prices=prices,
            horizons=(20,),
        )
        # What a transaction-date entry would have looked like. Constructed
        # only to prove it differs; the engine has no code path that does this.
        inadmissible = run_entry(
            SignalEntry(
                cik="1",
                signal="political",
                public_available_at=datetime(2026, 1, 15, 9, 30, tzinfo=UTC),
            ),
            prices=prices,
            horizons=(20,),
        )
        assert honest.entry_price != inadmissible.entry_price
        assert honest.entry_timestamp > inadmissible.entry_timestamp


class TestForwardReturns:
    def test_horizons_are_trading_days_not_calendar_days(self) -> None:
        """250 calendar days is ~170 sessions. Mixing them silently shortens
        every long-horizon result."""
        prices = flat_series(date(2026, 1, 1), 60, price=100.0, drift=1.0)
        index = prices.index_on_or_after(date(2026, 1, 1))
        assert index is not None
        value, outcome = forward_return(prices, entry_index=index, horizon_days=20)
        assert outcome is Outcome.COMPLETE
        # 20 trading days at +1.00 from 100 = 120, a 20% gain.
        assert value == pytest.approx(0.20)

    def test_a_horizon_past_the_data_is_open_not_truncated(self) -> None:
        """Truncating to the last available bar flatters recent signals."""
        prices = flat_series(date(2026, 1, 1), 30)
        index = prices.index_on_or_after(date(2026, 1, 1))
        assert index is not None
        value, outcome = forward_return(prices, entry_index=index, horizon_days=250)
        assert value is None
        assert outcome is Outcome.OPEN

    def test_benchmark_excess_subtracts_the_benchmark(self) -> None:
        stock = flat_series(date(2026, 1, 1), 60, price=100.0, drift=1.0)
        bench = flat_series(date(2026, 1, 1), 60, price=100.0, drift=0.5)
        result = run_entry(
            SignalEntry(
                cik="1", signal="s", public_available_at=datetime(2026, 1, 1, 9, 30, tzinfo=UTC)
            ),
            prices=stock,
            benchmark=bench,
            horizons=(20,),
        )
        assert result.returns[20].raw == pytest.approx(0.20)
        assert result.returns[20].benchmark_excess == pytest.approx(0.10)

    def test_no_price_data_is_reported_not_guessed(self) -> None:
        empty = PriceSeries([])
        result = run_entry(
            SignalEntry(cik="1", signal="s", public_available_at=datetime(2026, 1, 1, tzinfo=UTC)),
            prices=empty,
        )
        assert result.outcome is Outcome.NO_PRICE_DATA
        assert result.entry_price is None


class TestSurvivorship:
    """Phase 8 criteria 3 and 4."""

    SNAPSHOTS = UniverseSnapshotSet(
        [
            ("0000000001", date(2024, 1, 1), None),  # still listed
            ("0000000002", date(2024, 1, 1), date(2025, 6, 30)),  # delisted mid-2025
            ("0000000003", date(2026, 1, 1), None),  # listed later
        ]
    )

    def test_a_company_delisted_in_2025_is_in_the_2024_universe(self) -> None:
        universe = reconstruct_universe(self.SNAPSHOTS, as_of=date(2024, 6, 1))
        assert "0000000002" in universe

    def test_and_not_in_the_2026_universe(self) -> None:
        universe = reconstruct_universe(self.SNAPSHOTS, as_of=date(2026, 6, 1))
        assert "0000000002" not in universe

    def test_a_later_listing_is_absent_from_the_earlier_universe(self) -> None:
        """The other direction of the same bias: including a company before it
        listed would backtest a signal that could not have been acted on."""
        assert "0000000003" not in reconstruct_universe(self.SNAPSHOTS, as_of=date(2024, 6, 1))
        assert "0000000003" in reconstruct_universe(self.SNAPSHOTS, as_of=date(2026, 6, 1))

    def test_delisted_entries_stay_in_results_with_a_terminal_code(self) -> None:
        """Dropping them is survivorship bias; zeroing them is fabrication."""
        prices = flat_series(date(2026, 1, 1), 30)
        result = run_entry(
            SignalEntry(cik="2", signal="s", public_available_at=datetime(2026, 1, 1, tzinfo=UTC)),
            prices=prices,
            horizons=(250,),
            terminal_outcome=Outcome.DELISTED,
        )
        assert result.outcome is Outcome.DELISTED
        assert result.returns[250].outcome is Outcome.DELISTED


class TestReporting:
    def _results(self, n: int, value: float):
        prices = flat_series(date(2026, 1, 1), 60, price=100.0, drift=value)
        return [
            run_entry(
                SignalEntry(
                    cik=f"{i:010d}",
                    signal="insider_cluster",
                    public_available_at=datetime(2026, 1, 1, 9, 30, tzinfo=UTC),
                ),
                prices=prices,
                benchmark=flat_series(date(2026, 1, 1), 60, price=100.0),
                horizons=(20,),
            )
            for i in range(n)
        ]

    def test_small_samples_report_insufficient_rather_than_a_number(self) -> None:
        """A median from n=14 is not a finding, and printing it invites reading
        it as one."""
        stats = summarize_horizon(self._results(5, 1.0), horizon=20)
        assert stats.insufficient_sample
        assert stats.median is None
        assert "insufficient sample" in stats.describe()

    def test_adequate_samples_report_an_interval_not_just_a_point(self) -> None:
        stats = summarize_horizon(self._results(MIN_SAMPLE + 5, 1.0), horizon=20)
        assert not stats.insufficient_sample
        assert stats.ci_low is not None and stats.ci_high is not None
        assert "95% CI" in stats.describe()

    def test_a_null_result_is_reported_as_a_result(self) -> None:
        """Phase 8 criterion 5: publish it even when it is null or negative."""
        report = build_report(self._results(3, 1.0), signal="insider_cluster", horizons=(20, 250))
        rendered = report.render()
        assert "NO CONCLUSION SUPPORTED" in rendered
        assert "published as one" in rendered

    def test_confidence_interval_widens_as_the_sample_shrinks(self) -> None:
        wide = mean_confidence_interval([0.1, -0.2, 0.4, -0.1])
        narrow = mean_confidence_interval([0.1, -0.2, 0.4, -0.1] * 25)
        assert wide is not None and narrow is not None
        assert (wide[1] - wide[0]) > (narrow[1] - narrow[0])

    def test_open_horizons_do_not_count_as_zero(self) -> None:
        """Treating an unfinished horizon as flat drags every estimate toward
        nothing."""
        stats = summarize_horizon(self._results(30, 1.0), horizon=250)
        assert stats.n == 0
        assert stats.insufficient_sample


class TestWalkForward:
    """Phase 8 criterion 6."""

    def test_splits_are_strictly_chronological(self) -> None:
        splits = walk_forward_splits(
            start=date(2024, 1, 1), end=date(2026, 8, 1), train_months=12, validation_months=3
        )
        assert splits
        for split in splits:
            assert split.is_chronological()
            assert split.train_end < split.validation_start

    def test_no_validation_date_precedes_any_training_date(self) -> None:
        """The criterion as written, checked across every split."""
        splits = walk_forward_splits(
            start=date(2024, 1, 1), end=date(2026, 8, 1), train_months=12, validation_months=3
        )
        for split in splits:
            assert split.validation_start > split.train_end
            assert split.validation_start > split.train_start

    def test_windows_do_not_overlap(self) -> None:
        """One shared day lets the weights see the period they are scored on."""
        splits = walk_forward_splits(
            start=date(2024, 1, 1), end=date(2026, 8, 1), train_months=12, validation_months=3
        )
        for earlier, later in itertools.pairwise(splits):
            assert earlier.validation_end <= later.train_end

    def test_too_short_a_window_yields_no_splits(self) -> None:
        assert (
            walk_forward_splits(
                start=date(2026, 1, 1), end=date(2026, 3, 1), train_months=12, validation_months=3
            )
            == []
        )
