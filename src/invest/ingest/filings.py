"""Filings watcher and insider (Form 4) ingestion.

`filings` is a plain index of what the company has filed — useful on its own
as a "what changed" watch list, and the source of the accession numbers the
Form 4 parser needs.

`insider_transactions` stores `transaction_date` and `filed_date` separately.
Only `filed_date` may be used for point-in-time work: an insider has two
business days to file, so a transaction dated the 1st may not be public until
the 3rd, and a backtest that used the transaction date would be trading on
information nobody had.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from invest.db.enums import JobStatus, ValueType
from invest.db.models import Filing, InsiderTransaction, WorkflowJob
from invest.providers.base import (
    FilingRecord,
    InsiderTransactionRecord,
    ProviderError,
)
from invest.security_master import ResolvedSecurity

logger = logging.getLogger(__name__)

#: Forms worth indexing by default. 10-K/10-Q are the fundamentals source,
#: 8-K is material events, 4 is insider activity.
WATCHED_FORMS = ("10-K", "10-Q", "8-K", "4")


@dataclass
class FilingsIngestResult:
    ticker: str
    filings_written: int = 0
    filings_skipped: int = 0
    insider_written: int = 0
    insider_skipped: int = 0
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


def ingest_filings_for_security(
    session: Session,
    provider,
    security: ResolvedSecurity,
    *,
    forms: tuple[str, ...] = WATCHED_FORMS,
) -> FilingsIngestResult:
    """Index the company's recent filings.

    `filings.accession_number` is UNIQUE, so re-running is idempotent without
    needing a separate dedup pass.
    """
    result = FilingsIngestResult(security.ticker)

    if not security.cik:
        result.error = f"{security.ticker} has no CIK — cannot fetch filings"
        return result

    job = WorkflowJob(
        job_type="ingest_filings", target_ref=security.ticker, status=JobStatus.RUNNING
    )
    session.add(job)
    session.flush()

    try:
        records: list[FilingRecord] = provider.fetch_filings(security.cik, forms=list(forms))
    except ProviderError as exc:
        job.status = JobStatus.FAILED
        job.error = str(exc)
        session.flush()
        result.error = str(exc)
        return result

    existing = set(
        session.scalars(
            select(Filing.accession_number).where(Filing.entity_id == security.entity_id)
        ).all()
    )

    for record in records:
        if record.accession_number in existing:
            result.filings_skipped += 1
            continue
        session.add(
            Filing(
                entity_id=security.entity_id,
                accession_number=record.accession_number,
                form_type=record.form_type,
                filed_date=record.filed_date,
                period_of_report=record.period_of_report,
                primary_doc_url=record.primary_doc_url,
                items=record.items,
                source=record.source,
            )
        )
        existing.add(record.accession_number)
        result.filings_written += 1

    job.status = JobStatus.SUCCEEDED
    job.rows_written = result.filings_written
    job.stats_json = {
        "written": result.filings_written,
        "skipped": result.filings_skipped,
    }
    session.flush()
    return result


def _insider_key(record: InsiderTransactionRecord) -> tuple:
    """Matches the UNIQUE constraint on insider_transactions."""
    return (
        record.accession_number,
        record.insider_cik,
        record.transaction_date,
        record.transaction_code,
        record.shares,
        record.is_derivative,
    )


def ingest_insider_for_security(
    session: Session,
    provider,
    security: ResolvedSecurity,
    *,
    limit: int = 50,
    today: date | None = None,
) -> FilingsIngestResult:
    """Fetch, parse and store Form 4 transactions."""
    result = FilingsIngestResult(security.ticker)
    today = today or date.today()

    if not security.cik:
        result.error = f"{security.ticker} has no CIK — cannot fetch Form 4 filings"
        return result

    job = WorkflowJob(
        job_type="ingest_insider", target_ref=security.ticker, status=JobStatus.RUNNING
    )
    session.add(job)
    session.flush()

    try:
        records = provider.fetch_form4_documents(security.cik, limit=limit)
    except ProviderError as exc:
        job.status = JobStatus.FAILED
        job.error = str(exc)
        session.flush()
        result.error = str(exc)
        return result

    existing = {
        tuple(row)
        for row in session.execute(
            select(
                InsiderTransaction.accession_number,
                InsiderTransaction.insider_cik,
                InsiderTransaction.transaction_date,
                InsiderTransaction.transaction_code,
                InsiderTransaction.shares,
                InsiderTransaction.is_derivative,
            ).where(InsiderTransaction.entity_id == security.entity_id)
        ).all()
    }

    for record in records:
        # A filing dated in the future is nonsense; a transaction dated after
        # its own filing likewise. Both are dropped rather than stored.
        if record.filed_date > today:
            logger.info(
                "skipping Form 4 %s: filed_date %s is in the future",
                record.accession_number,
                record.filed_date,
            )
            continue
        if record.transaction_date > record.filed_date:
            logger.info(
                "skipping Form 4 %s: transaction dated after the filing",
                record.accession_number,
            )
            continue

        key = _insider_key(record)
        if key in existing:
            result.insider_skipped += 1
            continue

        session.add(
            InsiderTransaction(
                entity_id=security.entity_id,
                security_id=security.security_id,
                insider_name=record.insider_name,
                insider_cik=record.insider_cik,
                is_director=record.is_director,
                is_officer=record.is_officer,
                is_ten_pct_owner=record.is_ten_pct_owner,
                officer_title=record.officer_title,
                transaction_date=record.transaction_date,
                filed_date=record.filed_date,
                transaction_code=record.transaction_code,
                acquired_disposed=record.acquired_disposed,
                shares=record.shares,
                price_per_share=record.price_per_share,
                shares_owned_after=record.shares_owned_after,
                is_derivative=record.is_derivative,
                accession_number=record.accession_number,
                source=record.source,
                value_type=ValueType.OBSERVED,
            )
        )
        existing.add(key)
        result.insider_written += 1

    job.status = JobStatus.SUCCEEDED
    job.rows_written = result.insider_written
    job.stats_json = {
        "written": result.insider_written,
        "skipped": result.insider_skipped,
    }
    session.flush()
    return result
