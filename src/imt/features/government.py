"""Federal contract features. SPEC §5, §8.

## The coverage problem is the headline, not a footnote

Most federal recipients are private companies or subsidiaries that never
resolve to a listed parent. SPEC §5 puts realistic accuracy at 50–70%, and the
part that does not resolve is not random: large primes with recognisable names
resolve well, while the subsidiary through which a listed company actually
holds a contract usually does not.

So contract momentum is **systematically understated**, and unevenly. UI_SPEC
correction #10 requires the caveat on every panel, and this module carries the
numbers that caveat needs — resolved, unresolved, and the share of dollars
each represents — so the statement is quantified rather than vague.

## Momentum, not level

A company's contract *level* mostly reflects its size. What SPEC §8 asks for
is momentum: 30d/90d/12m and year-over-year, so a small company winning
unusually much is visible next to a large one winning its usual amount.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import date, timedelta
from decimal import Decimal

#: Only matches at or above the SPEC §5 gate feed features. Below it the award
#: is counted in coverage statistics but contributes nothing to a score.
CONFIDENCE_GATE = 0.85


@dataclass(frozen=True, slots=True)
class Award:
    """One federal award, after entity resolution has been attempted."""

    award_id: str
    recipient_name: str
    amount_minor: int
    action_date: date
    cik: str | None = None
    match_confidence: float | None = None
    agency: str | None = None
    naics: str | None = None

    @property
    def feeds_scoring(self) -> bool:
        """The hard gate. A wrong join here invents government business."""
        return (
            self.cik is not None
            and self.match_confidence is not None
            and self.match_confidence >= CONFIDENCE_GATE
        )


@dataclass(frozen=True, slots=True)
class CoverageReport:
    """Phase 6 criterion 2, stated honestly.

    The criterion is explicit that the number is reported as it is and **not
    optimized by lowering the threshold**. Lowering the gate would raise this
    percentage and lower the truth of every score built on it.
    """

    total_recipients: int
    resolved_recipients: int
    total_awards: int
    resolved_awards: int
    total_amount_minor: int
    resolved_amount_minor: int

    @property
    def recipient_resolution_pct(self) -> float:
        if not self.total_recipients:
            return 0.0
        return round(100.0 * self.resolved_recipients / self.total_recipients, 2)

    @property
    def dollar_resolution_pct(self) -> float:
        """Usually much higher than recipient coverage.

        Large primes resolve; the long tail of small private recipients does
        not. Reporting only the dollar figure would flatter the system, so both
        are carried and the panel shows the lower one.
        """
        if not self.total_amount_minor:
            return 0.0
        return round(100.0 * self.resolved_amount_minor / self.total_amount_minor, 2)

    def caveat(self) -> str:
        """The persistent panel line from UI_SPEC correction #10, quantified."""
        return (
            f"Covers awards resolved to a listed parent at ≥85% confidence: "
            f"{self.resolved_recipients} of {self.total_recipients} recipients "
            f"({self.recipient_resolution_pct:.0f}%), "
            f"{self.dollar_resolution_pct:.0f}% of award dollars. "
            f"Subsidiary awards are undercounted."
        )


def build_coverage(awards: Sequence[Award]) -> CoverageReport:
    recipients = {a.recipient_name for a in awards}
    resolved_recipients = {a.recipient_name for a in awards if a.feeds_scoring}
    resolved = [a for a in awards if a.feeds_scoring]
    return CoverageReport(
        total_recipients=len(recipients),
        resolved_recipients=len(resolved_recipients),
        total_awards=len(awards),
        resolved_awards=len(resolved),
        total_amount_minor=sum(a.amount_minor for a in awards),
        resolved_amount_minor=sum(a.amount_minor for a in resolved),
    )


@dataclass(frozen=True, slots=True)
class ContractMomentum:
    """SPEC §8: trailing windows plus year-over-year."""

    cik: str
    total_30d_minor: int
    total_90d_minor: int
    total_12m_minor: int
    prior_12m_minor: int
    award_count_90d: int
    yoy_pct: float | None
    reason_codes: dict[str, str] = field(default_factory=dict)


def compute_momentum(awards: Sequence[Award], *, cik: str, as_of: date) -> ContractMomentum:
    """Trailing totals for one company.

    Only gate-passing awards are included. An award that failed resolution is
    not this company's award, however likely it looks — that judgement belongs
    to the review queue, not to a feature.
    """
    mine = [a for a in awards if a.cik == cik and a.feeds_scoring and a.action_date <= as_of]

    def total(days: int, *, offset: int = 0) -> int:
        end = as_of - timedelta(days=offset)
        start = end - timedelta(days=days)
        return sum(a.amount_minor for a in mine if start < a.action_date <= end)

    total_12m = total(365)
    prior_12m = total(365, offset=365)

    reasons: dict[str, str] = {}
    yoy: float | None = None
    if prior_12m > 0:
        yoy = round(100.0 * (total_12m - prior_12m) / prior_12m, 2)
    elif total_12m > 0:
        # No prior-year base. The growth is real but a percentage against zero
        # is infinite, and printing a huge number would dominate the ranking.
        reasons["yoy_pct"] = "no_prior_year_awards"
    else:
        reasons["yoy_pct"] = "no_awards_in_window"

    return ContractMomentum(
        cik=cik,
        total_30d_minor=total(30),
        total_90d_minor=total(90),
        total_12m_minor=total_12m,
        prior_12m_minor=prior_12m,
        award_count_90d=sum(1 for a in mine if as_of - timedelta(days=90) < a.action_date <= as_of),
        yoy_pct=yoy,
        reason_codes=reasons,
    )


@dataclass(frozen=True, slots=True)
class TimelineEvent:
    """One step in the opportunity → award → announcement chain (SPEC §8)."""

    kind: str
    when: date
    headline: str
    amount_minor: int | None = None
    source_url: str | None = None


def build_timeline(
    *,
    awards: Sequence[Award],
    corporate_events: Sequence[tuple[date, str, str]] = (),
    cik: str,
    as_of: date,
    window_days: int = 365,
) -> list[TimelineEvent]:
    """Awards and 8-K announcements on one chronology.

    "The timeline is the product" (SPEC §8): an award followed by an 8-K
    announcing it is one story, and seeing the gap between them is the point.
    Sorted oldest-first so the sequence reads as a sequence.
    """
    start = as_of - timedelta(days=window_days)
    events: list[TimelineEvent] = [
        TimelineEvent(
            kind="award",
            when=a.action_date,
            headline=f"{a.agency or 'Federal'} award to {a.recipient_name}",
            amount_minor=a.amount_minor,
        )
        for a in awards
        if a.cik == cik and a.feeds_scoring and start < a.action_date <= as_of
    ]
    events.extend(
        TimelineEvent(kind="corporate_event", when=when, headline=headline, source_url=url)
        for when, headline, url in corporate_events
        if start < when <= as_of
    )
    return sorted(events, key=lambda e: (e.when, e.kind, e.headline))


def underlying_event_key(award: Award) -> str:
    """Groups an award with the 8-K that announces it.

    Convergence de-duplicates on this (ARCHITECTURE §I): the corporate-event
    and government categories describing the same award are one event, and
    without the key they inflate convergence exactly where the system should
    be most careful.
    """
    return f"award:{award.award_id}"


def award_dollars(minor: int) -> Decimal:
    return Decimal(minor) / Decimal(100)
