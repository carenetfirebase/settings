"""Government contract features. docs/PHASES.md Phase 6.

Criteria 1 (>=50,000 awards), 2's real numbers, and 5 (a live timeline for a
known defence contractor) need USAspending and are not met here. Criterion 3 —
only >=0.85 matches feed contract momentum — is the one these tests are built
around, because it is the gate that stops the weakest entity resolution in the
system from inventing government business.
"""

from __future__ import annotations

from datetime import date
from typing import ClassVar

import pytest

from imt.features.government import (
    Award,
    build_coverage,
    build_timeline,
    compute_momentum,
    underlying_event_key,
)

AS_OF = date(2026, 8, 1)


def award(
    name: str,
    amount: int,
    when: date,
    *,
    cik: str | None = None,
    confidence: float | None = None,
    award_id: str = "",
) -> Award:
    return Award(
        award_id=award_id or f"{name}-{when.isoformat()}-{amount}",
        recipient_name=name,
        amount_minor=amount,
        action_date=when,
        cik=cik,
        match_confidence=confidence,
        agency="DoD",
    )


class TestConfidenceGate:
    """Phase 6 criterion 3."""

    def test_only_high_confidence_matches_feed_scoring(self) -> None:
        assert award("A", 100, AS_OF, cik="0000000001", confidence=0.94).feeds_scoring
        assert not award("B", 100, AS_OF, cik="0000000002", confidence=0.70).feeds_scoring

    def test_the_boundary_is_inclusive(self) -> None:
        assert award("A", 100, AS_OF, cik="0000000001", confidence=0.85).feeds_scoring
        assert not award("A", 100, AS_OF, cik="0000000001", confidence=0.8499).feeds_scoring

    def test_a_cik_without_a_confidence_does_not_pass(self) -> None:
        """A match with no recorded confidence has not been assessed, and
        treating it as certain is how an unreviewed join reaches a score."""
        assert not award("A", 100, AS_OF, cik="0000000001", confidence=None).feeds_scoring

    def test_below_gate_awards_are_excluded_from_momentum(self) -> None:
        awards = [
            award("Prime", 1_000_000_00, date(2026, 7, 15), cik="0000000001", confidence=0.95),
            award("Maybe", 9_000_000_00, date(2026, 7, 16), cik="0000000001", confidence=0.60),
        ]
        momentum = compute_momentum(awards, cik="0000000001", as_of=AS_OF)
        assert momentum.total_30d_minor == 1_000_000_00


class TestCoverageIsReportedHonestly:
    """Phase 6 criterion 2: stated as it is, not improved by lowering the gate."""

    AWARDS: ClassVar[list[Award]] = [
        award("BIG PRIME CORP", 50_000_000_00, date(2026, 6, 1), cik="0000000001", confidence=0.97),
        award("SMALL LLC", 100_000_00, date(2026, 6, 2)),
        award("ANOTHER PRIVATE CO", 250_000_00, date(2026, 6, 3), confidence=0.40),
        award("SUBSIDIARY HOLDINGS", 3_000_000_00, date(2026, 6, 4), confidence=0.72),
    ]

    def test_recipient_and_dollar_coverage_both_reported(self) -> None:
        """Dollar coverage is usually far higher, because large primes resolve
        and the long tail does not. Reporting only the flattering one would
        misrepresent how complete the data is."""
        report = build_coverage(self.AWARDS)
        assert report.recipient_resolution_pct == 25.0
        assert report.dollar_resolution_pct > report.recipient_resolution_pct

    def test_caveat_quantifies_the_gap(self) -> None:
        """UI_SPEC correction #10, with numbers rather than a vague warning."""
        caveat = build_coverage(self.AWARDS).caveat()
        assert "1 of 4 recipients" in caveat
        assert "Subsidiary awards are undercounted" in caveat
        assert "85% confidence" in caveat

    def test_empty_input_does_not_divide_by_zero(self) -> None:
        report = build_coverage([])
        assert report.recipient_resolution_pct == 0.0
        assert report.dollar_resolution_pct == 0.0


class TestMomentum:
    AWARDS: ClassVar[list[Award]] = [
        award("P", 1_000_000_00, date(2026, 7, 20), cik="0000000001", confidence=0.95),
        award("P", 2_000_000_00, date(2026, 6, 1), cik="0000000001", confidence=0.95),
        award("P", 5_000_000_00, date(2025, 9, 1), cik="0000000001", confidence=0.95),
    ]

    def test_trailing_windows(self) -> None:
        m = compute_momentum(self.AWARDS, cik="0000000001", as_of=AS_OF)
        assert m.total_30d_minor == 1_000_000_00
        assert m.total_90d_minor == 3_000_000_00
        assert m.total_12m_minor == 8_000_000_00

    def test_year_over_year(self) -> None:
        awards = [
            award("P", 2_000_000_00, date(2026, 3, 1), cik="0000000001", confidence=0.95),
            award("P", 1_000_000_00, date(2025, 3, 1), cik="0000000001", confidence=0.95),
        ]
        m = compute_momentum(awards, cik="0000000001", as_of=AS_OF)
        assert m.yoy_pct == pytest.approx(100.0)

    def test_no_prior_year_gives_a_reason_not_infinity(self) -> None:
        """A percentage against a zero base is infinite, and printing a huge
        number would dominate the ranking."""
        awards = [award("P", 2_000_000_00, date(2026, 3, 1), cik="0000000001", confidence=0.95)]
        m = compute_momentum(awards, cik="0000000001", as_of=AS_OF)
        assert m.yoy_pct is None
        assert m.reason_codes["yoy_pct"] == "no_prior_year_awards"

    def test_no_awards_at_all_is_distinguished_from_no_growth(self) -> None:
        m = compute_momentum([], cik="0000000001", as_of=AS_OF)
        assert m.reason_codes["yoy_pct"] == "no_awards_in_window"

    def test_future_awards_are_excluded(self) -> None:
        """An award dated after as_of has not happened yet, and including it
        would be look-ahead in the same class as reading a restatement early."""
        awards = [award("P", 9_000_000_00, date(2026, 12, 1), cik="0000000001", confidence=0.95)]
        assert compute_momentum(awards, cik="0000000001", as_of=AS_OF).total_12m_minor == 0


class TestTimeline:
    def test_awards_and_events_share_one_chronology(self) -> None:
        """SPEC §8: 'the timeline is the product'."""
        events = build_timeline(
            awards=[award("P", 1_000_000_00, date(2026, 6, 1), cik="1", confidence=0.95)],
            corporate_events=[(date(2026, 6, 5), "8-K: contract announced", "https://x")],
            cik="1",
            as_of=AS_OF,
        )
        assert [e.kind for e in events] == ["award", "corporate_event"]
        assert events[0].when < events[1].when

    def test_only_gate_passing_awards_appear(self) -> None:
        events = build_timeline(
            awards=[award("P", 1_000_000_00, date(2026, 6, 1), cik="1", confidence=0.5)],
            cik="1",
            as_of=AS_OF,
        )
        assert events == []


class TestCrossCategoryKey:
    def test_an_award_and_its_announcement_share_a_key(self) -> None:
        """ARCHITECTURE §I: the government and corporate-event categories
        describing the same award are one event, and convergence must not count
        it twice."""
        a = award("P", 1_000_000_00, date(2026, 6, 1), award_id="W911-26-C-0042")
        assert underlying_event_key(a) == "award:W911-26-C-0042"
