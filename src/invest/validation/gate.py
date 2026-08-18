"""The validation gate.

Every ingestion path calls this before any write. There is exactly one of it
so that "did this data get checked?" has exactly one answer.

Outcomes, and what each means:

    ACCEPTED    — clean, written with data_quality_flag='ok'
    FLAGGED     — written, but with a non-ok flag and a data_conflicts row.
                  Usable, with reduced confidence.
    QUARANTINED — written with data_quality_flag='quarantined' and a conflict
                  row. Engines must exclude it. Kept rather than dropped so the
                  failure is auditable.
    SKIPPED     — already stored; no new row.

Note what is absent: there is no outcome that silently discards a record and
none that silently accepts one. A rejected value is never replaced with an
interpolation, an average, or a carried-forward figure.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal
from enum import StrEnum

from sqlalchemy.orm import Session

from invest.db.enums import DataQualityFlag
from invest.db.models import DataConflict
from invest.providers.base import FundamentalFact, PriceBar
from invest.validation import rules
from invest.validation.rules import Finding, RuleContext


class Outcome(StrEnum):
    ACCEPTED = "accepted"
    FLAGGED = "flagged"
    QUARANTINED = "quarantined"
    SKIPPED = "skipped"


@dataclass
class GateResult:
    """The verdict on one record."""

    outcome: Outcome
    findings: list[Finding] = field(default_factory=list)
    data_quality_flag: str = DataQualityFlag.OK

    @property
    def should_write(self) -> bool:
        return self.outcome in (Outcome.ACCEPTED, Outcome.FLAGGED, Outcome.QUARANTINED)

    @property
    def is_usable(self) -> bool:
        """Whether the engines may consume this row."""
        return self.outcome in (Outcome.ACCEPTED, Outcome.FLAGGED)


@dataclass
class GateReport:
    """Aggregate outcome for a batch — what the CLI prints and what
    `workflow_jobs.stats_json` records.
    """

    accepted: int = 0
    flagged: int = 0
    quarantined: int = 0
    skipped: int = 0
    findings: list[Finding] = field(default_factory=list)

    def record(self, result: GateResult) -> None:
        setattr(self, result.outcome.value, getattr(self, result.outcome.value) + 1)
        self.findings.extend(result.findings)

    @property
    def total(self) -> int:
        return self.accepted + self.flagged + self.quarantined + self.skipped

    @property
    def conflict_count(self) -> int:
        return len(self.findings)

    def as_dict(self) -> dict:
        return {
            "accepted": self.accepted,
            "flagged": self.flagged,
            "quarantined": self.quarantined,
            "skipped": self.skipped,
            "conflicts": self.conflict_count,
        }


def _flag_for(findings: list[Finding]) -> tuple[Outcome, str]:
    if any(f.is_critical for f in findings):
        return Outcome.QUARANTINED, DataQualityFlag.QUARANTINED
    if not findings:
        return Outcome.ACCEPTED, DataQualityFlag.OK

    # Pick the flag that best describes why this row is imperfect, so a reader
    # of the table learns something without opening data_conflicts.
    by_rule = {f.conflict_type for f in findings}
    from invest.db.enums import ConflictType

    if ConflictType.CROSS_SOURCE_DISAGREEMENT in by_rule:
        return Outcome.FLAGGED, DataQualityFlag.CONFLICTED
    if ConflictType.STALENESS in by_rule:
        return Outcome.FLAGGED, DataQualityFlag.STALE
    if ConflictType.UNIT_MISMATCH in by_rule:
        return Outcome.FLAGGED, DataQualityFlag.SUSPECT_UNIT
    return Outcome.FLAGGED, DataQualityFlag.CONFLICTED


class ValidationGate:
    """Stateless apart from the session it writes conflicts to."""

    def __init__(self, session: Session) -> None:
        self.session = session

    # -- prices ----------------------------------------------------------

    def check_price_bar(
        self,
        bar: PriceBar,
        ctx: RuleContext,
        *,
        security_id: int | None = None,
        extra_findings: list[Finding] | None = None,
    ) -> GateResult:
        duplicate = rules.check_duplicate(bar, ctx)
        if duplicate:
            return GateResult(Outcome.SKIPPED, duplicate, DataQualityFlag.OK)

        findings: list[Finding] = []
        findings += rules.check_timestamp_sanity(bar, ctx)
        findings += rules.check_impossible_values(bar, ctx)
        findings += rules.check_currency_consistency(bar, ctx)
        findings += rules.check_cross_source_agreement(bar, ctx)
        if extra_findings:
            findings += extra_findings

        outcome, flag = _flag_for(findings)
        self._persist(findings, table_name="price_observations", security_id=security_id)
        return GateResult(outcome, findings, flag)

    def check_price_series(self, bars: list[PriceBar], ctx: RuleContext) -> list[Finding]:
        """Series-level checks that no single bar can perform on its own."""
        findings: list[Finding] = []
        findings += rules.check_adjustment_consistency(bars)
        findings += rules.check_series_staleness(bars, ctx)
        return findings

    # -- fundamentals ----------------------------------------------------

    def check_fundamental_fact(
        self,
        fact: FundamentalFact,
        ctx: RuleContext,
        *,
        entity_id: int | None = None,
    ) -> GateResult:
        findings: list[Finding] = []
        findings += rules.check_fact_timestamps(fact, ctx)
        findings += rules.check_fact_units(fact, ctx)
        findings += rules.check_fact_plausibility(fact, ctx)

        outcome, flag = _flag_for(findings)
        self._persist(findings, table_name="fundamentals", entity_id=entity_id)
        return GateResult(outcome, findings, flag)

    # -- persistence -----------------------------------------------------

    def _persist(
        self,
        findings: list[Finding],
        *,
        table_name: str,
        security_id: int | None = None,
        entity_id: int | None = None,
    ) -> None:
        """Nothing the gate notices is forgotten."""
        for finding in findings:
            self.session.add(
                DataConflict(
                    table_name=table_name,
                    security_id=security_id,
                    entity_id=entity_id,
                    metric_name=finding.metric_name,
                    obs_date=finding.obs_date,
                    conflict_type=finding.conflict_type.value,
                    severity=finding.severity.value,
                    source_a=finding.source_a,
                    value_a=finding.value_a,
                    source_b=finding.source_b,
                    value_b=finding.value_b,
                    pct_difference=finding.pct_difference,
                    detail=f"[{finding.rule}] {finding.detail}",
                )
            )

    def persist_series_findings(
        self, findings: list[Finding], *, table_name: str, security_id: int | None = None
    ) -> None:
        self._persist(findings, table_name=table_name, security_id=security_id)


def build_price_context(
    session: Session,
    *,
    security_id: int,
    source: str,
    today: date,
    expected_currency: str | None = None,
    staleness_days: int | None = None,
) -> RuleContext:
    """Load what the rules need to judge incoming bars against what we hold:
    which dates this source already covers, and what other sources say.
    """
    from sqlalchemy import select

    from invest.db.models import PriceObservation

    rows = session.execute(
        select(
            PriceObservation.obs_date,
            PriceObservation.source,
            PriceObservation.close,
            PriceObservation.is_split_adjusted,
        ).where(PriceObservation.security_id == security_id)
    ).all()

    known: set[date] = set()
    existing: dict[date, dict[str, Decimal]] = {}
    bases: dict[date, dict[str, bool | None]] = {}
    for obs_date, row_source, close, split_adjusted in rows:
        if row_source == source:
            known.add(obs_date)
        if close is not None:
            existing.setdefault(obs_date, {})[row_source] = Decimal(close)
            bases.setdefault(obs_date, {})[row_source] = split_adjusted

    return RuleContext(
        today=today,
        known_dates=known,
        existing_closes=existing,
        existing_bases=bases,
        staleness_days=staleness_days,
        expected_currency=expected_currency,
    )
