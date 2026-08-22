"""Form 4 ingest: EDGAR → raw_documents → insider_transactions → signal_events.

The full vertical slice for one source. Every other evidence source follows
this shape, so the decisions here are the ones that get copied:

* both dates are carried through to ``signal_events`` and the lag is computed
  in Python, never in the frontend (non-negotiable #8);
* ``public_available_at`` comes from the filing's acceptance timestamp, which
  is the only clock a backtest may use (SPEC §7.1);
* re-running writes zero duplicates, enforced by natural-key conflict clauses.
"""

from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from imt.adapters.records import FilingRef, InsiderTransactionRecord
from imt.adapters.sec_edgar import SOURCE_ID, SecEdgarAdapter, public_available_at
from imt.adapters.sec_form4 import Form4ParseError, describe_code, parse_form4
from imt.core.clock import utc_now
from imt.core.logging import get_logger
from imt.db.enums import DataQuality, SignalCategory
from imt.db.models import Company, Filing, InsiderTransaction, SignalEvent
from imt.ingest.base import IngestResult, event_id, ingestion_run, persist_raw

log = get_logger(__name__)

FORM_TYPES = frozenset({"4", "4/A"})


def _headline(record: InsiderTransactionRecord) -> str:
    """Plain description. No trading language (UI_SPEC §5)."""
    who = record.role or ("insider" if not record.is_ten_percent_owner else "10% owner")
    action = describe_code(record.transaction_code)
    return f"{who} — {action}"


def _upsert_filing(session: Session, ref: FilingRef) -> None:
    """Record the filing itself before its transactions reference it.

    ``filings`` is the point-in-time anchor: it holds ``acceptance_datetime``
    and ``public_available_at``, and every derived row hangs off it by
    accession. The foreign key from ``insider_transactions`` makes that
    ordering mandatory rather than merely intended.
    """
    session.execute(
        pg_insert(Filing)
        .values(
            accession=ref.accession,
            cik=ref.cik,
            form_type=ref.form_type,
            filed_date=ref.filed_date,
            acceptance_datetime=ref.acceptance_datetime,
            public_available_at=public_available_at(ref.filed_date, ref.acceptance_datetime),
            primary_doc_url=ref.primary_doc_url,
        )
        .on_conflict_do_nothing(index_elements=[Filing.accession])
    )


def _upsert_transaction(session: Session, record: InsiderTransactionRecord, ref: FilingRef) -> bool:
    """Insert one transaction. Returns True if it was new.

    The conflict target is the natural key from the schema, so a re-run of the
    same filing collides and does nothing rather than duplicating the row.
    """
    stmt = (
        pg_insert(InsiderTransaction)
        .values(
            filing_accession=record.accession,
            cik=record.cik,
            insider_cik=record.insider_cik,
            insider_name=record.insider_name,
            role=record.role,
            is_officer=record.is_officer,
            is_director=record.is_director,
            is_ten_percent_owner=record.is_ten_percent_owner,
            transaction_code=record.transaction_code,
            transaction_date=record.transaction_date,
            shares=record.shares,
            price_minor=record.price_minor,
            value_minor=record.value_minor,
            currency=record.currency,
            shares_owned_after=record.shares_owned_after,
            is_10b5_1=record.is_10b5_1,
            is_amendment=record.is_amendment,
            reason_code=record.reason_code,
            # The six provenance columns. Schema constraint, not convention.
            source_id=SOURCE_ID,
            retrieved_at=utc_now(),
            effective_date=record.transaction_date,
            source_document_url=ref.primary_doc_url,
            source_record_id=record.accession,
            data_quality=DataQuality.CURRENT,
        )
        .on_conflict_do_nothing(constraint="uq_insider_transaction_identity")
        .returning(InsiderTransaction.id)
    )
    return session.execute(stmt).scalar_one_or_none() is not None


def _upsert_event(session: Session, record: InsiderTransactionRecord, ref: FilingRef) -> bool:
    """Emit the unified signal event.

    Both dates and the lag go in here. A Form 4 is normally filed within two
    business days, so the lag is small — but it is computed and stored the same
    way as a congressional PTR's 44 days, because the UI renders them with the
    same component and the difference should be visible, not assumed.
    """
    available = public_available_at(ref.filed_date, ref.acceptance_datetime)
    lag = (ref.filed_date - record.transaction_date).days

    stmt = (
        pg_insert(SignalEvent)
        .values(
            event_id=event_id(
                "form4",
                record.accession,
                record.actor_key,
                record.transaction_code,
                record.transaction_date.isoformat(),
                str(record.shares),
            ),
            category=SignalCategory.CORPORATE_INSIDER,
            cik=record.cik,
            detected_at=utc_now(),
            transaction_date=record.transaction_date,
            disclosure_date=ref.filed_date,
            disclosure_lag_days=max(lag, 0),
            public_available_at=available,
            headline=_headline(record),
            value_exact_minor=record.value_minor,
            currency=record.currency,
            # A Form 4 names its issuer by CIK, so resolution is exact.
            entity_match_confidence=1.0,
            actor_key=record.actor_key,
            source_id=SOURCE_ID,
            retrieved_at=utc_now(),
            effective_date=record.transaction_date,
            source_document_url=ref.primary_doc_url,
            source_record_id=record.accession,
            data_quality=DataQuality.CURRENT,
        )
        .on_conflict_do_nothing(index_elements=[SignalEvent.event_id])
        .returning(SignalEvent.event_id)
    )
    return session.execute(stmt).scalar_one_or_none() is not None


def ingest_filing(
    session: Session,
    *,
    payload: bytes,
    ref: FilingRef,
    result: IngestResult,
) -> None:
    """Persist raw, parse, write transactions and events for one filing."""
    persist_raw(
        session,
        source_id=SOURCE_ID,
        source_record_id=ref.accession,
        url=ref.primary_doc_url,
        payload=payload,
        content_type="application/xml",
    )
    result.documents_fetched += 1

    try:
        records = parse_form4(payload, ref=ref)
    except Form4ParseError as exc:
        # The raw document is already stored, so this is recoverable by
        # re-parsing later rather than re-fetching.
        result.errors.append(f"{ref.accession}: {exc}")
        log.warning("form4.parse_failed", accession=ref.accession, error=str(exc))
        return

    if session.get(Company, ref.cik) is None:
        # A filing for a company outside the universe. Skipped rather than
        # inserted, because the universe defines what this system covers and
        # silently widening it would break the backtest's reconstruction.
        log.info("form4.company_not_in_universe", cik=ref.cik, accession=ref.accession)
        return

    _upsert_filing(session, ref)

    for record in records:
        if _upsert_transaction(session, record, ref):
            result.rows_written += 1
        else:
            result.rows_skipped_duplicate += 1
        if _upsert_event(session, record, ref):
            result.events_written += 1


def run(
    session: Session,
    adapter: SecEdgarAdapter,
    *,
    since_days: int,
    today: date,
) -> IngestResult:
    """Ingest Form 4 filings discovered in the daily index."""
    with ingestion_run(session, job="form4", source_id=SOURCE_ID) as result:
        for offset in range(since_days):
            day = today - timedelta(days=offset)
            for ref in adapter.daily_index(day):
                if ref.form_type not in FORM_TYPES:
                    continue
                try:
                    payload = adapter.document(ref.primary_doc_url)
                except Exception as exc:
                    result.errors.append(f"{ref.accession}: fetch failed: {exc}")
                    continue
                ingest_filing(session, payload=payload, ref=ref, result=result)
        session.commit()
    return result
