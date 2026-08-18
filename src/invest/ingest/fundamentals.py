"""Fundamentals ingestion: EDGAR -> validation gate -> `fundamentals` rows.

Every row carries `filed_date`, which is what makes point-in-time queries
honest downstream.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from invest.db.enums import JobStatus, ValueType
from invest.db.models import Fundamental, WorkflowJob
from invest.providers.base import FundamentalFact, FundamentalsProvider, ProviderError
from invest.security_master import ResolvedSecurity
from invest.validation.gate import Outcome, ValidationGate
from invest.validation.rules import RuleContext

logger = logging.getLogger(__name__)


@dataclass
class FundamentalsIngestResult:
    ticker: str
    written: int
    accepted: int = 0
    flagged: int = 0
    quarantined: int = 0
    skipped: int = 0
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


def _existing_keys(session: Session, entity_id: int) -> set[tuple]:
    """The natural key of every fact we already hold, so re-running is cheap
    and does not collide with the UNIQUE constraint.
    """
    rows = session.execute(
        select(
            Fundamental.metric_name,
            Fundamental.period_end,
            Fundamental.fiscal_period,
            Fundamental.filed_date,
            Fundamental.accession_number,
            Fundamental.source,
        ).where(Fundamental.entity_id == entity_id)
    ).all()
    return {tuple(r) for r in rows}


def ingest_fundamentals_for_security(
    session: Session,
    provider: FundamentalsProvider,
    security: ResolvedSecurity,
    *,
    today: date | None = None,
) -> FundamentalsIngestResult:
    today = today or date.today()

    if not security.cik:
        msg = f"{security.ticker} has no CIK — cannot fetch fundamentals"
        logger.warning(msg)
        return FundamentalsIngestResult(security.ticker, 0, error=msg)

    gate = ValidationGate(session)
    ctx = RuleContext(today=today)

    job = WorkflowJob(
        job_type="ingest_fundamentals",
        target_ref=f"{security.ticker}:{provider.source_name}",
        status=JobStatus.RUNNING,
    )
    session.add(job)
    session.flush()

    try:
        facts: list[FundamentalFact] = provider.fetch_company_facts(security.cik)
    except ProviderError as exc:
        job.status = JobStatus.FAILED
        job.error = str(exc)
        session.flush()
        return FundamentalsIngestResult(security.ticker, 0, error=str(exc))

    seen = _existing_keys(session, security.entity_id)
    result = FundamentalsIngestResult(security.ticker, 0)

    for fact in facts:
        key = (
            fact.metric_name,
            fact.period_end,
            fact.fiscal_period,
            fact.filed_date,
            fact.accession_number,
            fact.source,
        )
        if key in seen:
            result.skipped += 1
            continue

        verdict = gate.check_fundamental_fact(fact, ctx, entity_id=security.entity_id)
        if verdict.outcome == Outcome.ACCEPTED:
            result.accepted += 1
        elif verdict.outcome == Outcome.FLAGGED:
            result.flagged += 1
        elif verdict.outcome == Outcome.QUARANTINED:
            result.quarantined += 1

        if not verdict.should_write:
            continue

        session.add(
            Fundamental(
                entity_id=security.entity_id,
                metric_name=fact.metric_name,
                xbrl_tag=fact.xbrl_tag,
                taxonomy=fact.taxonomy,
                metric_value=fact.value,
                unit=fact.unit,
                period_start=fact.period_start,
                period_end=fact.period_end,
                fiscal_year=fact.fiscal_year,
                fiscal_period=fact.fiscal_period,
                filed_date=fact.filed_date,
                form_type=fact.form_type,
                accession_number=fact.accession_number,
                source=fact.source,
                value_type=ValueType.OBSERVED,
                data_quality_flag=verdict.data_quality_flag,
            )
        )
        seen.add(key)
        result.written += 1

    job.status = JobStatus.SUCCEEDED
    job.rows_written = result.written
    job.rows_quarantined = result.quarantined
    job.stats_json = {
        "accepted": result.accepted,
        "flagged": result.flagged,
        "quarantined": result.quarantined,
        "skipped": result.skipped,
    }
    session.flush()
    return result
