"""XBRL Company Facts ingest.

Facts land in `xbrl_facts`, which carries a database trigger rejecting UPDATE
and DELETE. That is deliberate and load-bearing: SPEC §7.2 requires a
restatement to INSERT a new row, because a backtest asking "what was known on
date D" only works if the original figure is still there. An ingest that
"corrected" a prior fact in place would silently destroy the ability to
reconstruct history.
"""

from __future__ import annotations

from collections.abc import Sequence
from decimal import Decimal

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from imt.adapters.records import FundamentalFact
from imt.adapters.sec_xbrl import SOURCE_ID, parse_company_facts
from imt.core.clock import utc_now
from imt.core.logging import get_logger
from imt.db.enums import DataQuality
from imt.db.models import XbrlFact
from imt.ingest.base import IngestResult, ingestion_run, persist_raw

log = get_logger(__name__)


def persist_facts(
    session: Session, facts: Sequence[FundamentalFact], *, document_url: str, result: IngestResult
) -> None:
    """Insert facts, skipping ones already present.

    The conflict target is the full natural key including `filed_date`, so a
    restatement -- same company, same tag, same period, different filing --
    does not collide and lands as a new row.
    """
    for fact in facts:
        inserted = session.execute(
            pg_insert(XbrlFact)
            .values(
                cik=fact.cik,
                tag=fact.tag,
                unit=fact.unit,
                period_start=fact.period_start,
                period_end=fact.period_end,
                fiscal_period=fact.fiscal_period,
                filed_date=fact.filed_date,
                value=fact.value,
                accession=fact.accession,
                source_id=SOURCE_ID,
                retrieved_at=utc_now(),
                effective_date=fact.period_end,
                source_document_url=document_url,
                source_record_id=fact.accession or f"{fact.cik}:{fact.tag}:{fact.period_end}",
                data_quality=DataQuality.CURRENT,
            )
            .on_conflict_do_nothing(constraint="uq_xbrl_fact_identity")
            .returning(XbrlFact.id)
        ).scalar_one_or_none()
        if inserted is not None:
            result.rows_written += 1
        else:
            result.rows_skipped_duplicate += 1


def ingest_company_facts(
    session: Session, *, payload: bytes, cik: str, document_url: str, result: IngestResult
) -> None:
    """Persist raw, parse, store facts. Re-parseable without re-fetching."""
    persist_raw(
        session,
        source_id=SOURCE_ID,
        source_record_id=f"companyfacts:{cik}",
        url=document_url,
        payload=payload,
        content_type="application/json",
    )
    result.documents_fetched += 1

    import json

    facts = parse_company_facts(json.loads(payload))
    persist_facts(session, facts, document_url=document_url, result=result)


def load_facts(session: Session, cik: str) -> list[FundamentalFact]:
    """Read a company's facts back out for feature computation."""
    from sqlalchemy import select

    rows = (
        session.execute(
            select(XbrlFact).where(XbrlFact.cik == cik).order_by(XbrlFact.tag, XbrlFact.period_end)
        )
        .scalars()
        .all()
    )
    return [
        FundamentalFact(
            cik=row.cik,
            tag=row.tag,
            unit=row.unit,
            period_start=row.period_start,
            period_end=row.period_end,
            filed_date=row.filed_date,
            value=Decimal(str(row.value)),
            fiscal_period=row.fiscal_period,
            accession=row.accession,
        )
        for row in rows
    ]


def run(session: Session, *, ciks: Sequence[str]) -> IngestResult:
    """Fetch and store Company Facts for each CIK.

    Not runnable in the development environment -- `data.sec.gov` is
    unreachable there -- so this path is exercised by
    `ingest_company_facts` against fixtures instead.
    """
    from imt.adapters.sec_xbrl import COMPANY_FACTS_URL
    from imt.core.http import HttpClient

    with ingestion_run(session, job="xbrl", source_id=SOURCE_ID) as result, HttpClient() as client:
        for cik in ciks:
            url = COMPANY_FACTS_URL.format(cik=cik)
            try:
                response = client.get(SOURCE_ID, url)
            except Exception as exc:
                result.errors.append(f"{cik}: {exc}")
                continue
            ingest_company_facts(
                session, payload=response.body, cik=cik, document_url=url, result=result
            )
        session.commit()
    return result
