"""Congressional PTR ingest.

This is the first source where entity resolution matters. A Form 4 names its
issuer by CIK; a PTR names it in prose — "Apple Inc. (AAPL) Common Stock", or
sometimes just "Apple". SPEC §5 puts the expected accuracy at ~85% with a
ticker present and ~60% without.

**The 0.85 gate is enforced here.** A row that does not resolve confidently
goes to the review queue and never reaches ``signal_events``, so it cannot
contribute to a score. The asymmetry is the reason: a missed row loses one
signal, while a wrong join manufactures convergence that does not exist —
attributing a lawmaker's trade to the wrong company and then reporting that as
independent agreement with an insider purchase at that company.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import date

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from imt.adapters.house_ptr import SOURCE_ID_HOUSE, parse_csv
from imt.adapters.records import PoliticalTradeRecord
from imt.core.clock import utc_now
from imt.core.logging import get_logger
from imt.db.enums import DataQuality, OwnerType, ParseOutcome, SignalCategory
from imt.db.models import (
    Company,
    CongressionalTransaction,
    EntityMatchRow,
    EntityReviewQueue,
    SignalEvent,
    TickerMapRow,
)
from imt.entities import Candidate, EntityResolver, TickerMap
from imt.ingest.base import IngestResult, event_id, ingestion_run, persist_raw

log = get_logger(__name__)


def _build_resolver(session: Session) -> EntityResolver:
    """Resolver over the current universe, with the point-in-time ticker map."""
    companies = session.execute(select(Company.cik, Company.name)).all()
    tickers = session.execute(
        select(
            TickerMapRow.ticker, TickerMapRow.cik, TickerMapRow.valid_from, TickerMapRow.valid_to
        )
    ).all()
    return EntityResolver(
        [Candidate(cik=cik, name=name) for cik, name in companies],
        ticker_map=TickerMap([(t, c, vf, vt) for t, c, vf, vt in tickers]),
    )


def _queue_for_review(
    session: Session,
    record: PoliticalTradeRecord,
    match_confidence: float,
    candidates: list[dict[str, object]],
) -> None:
    """Sub-threshold matches are quarantined, never dropped and never forced.

    The queue keeps the alternatives so a human sees what the resolver was
    choosing between, rather than an unexplained "unresolved".
    """
    session.execute(
        pg_insert(EntityReviewQueue)
        .values(
            source=SOURCE_ID_HOUSE,
            source_key=f"{record.source_record_id}:{record.asset_description}"[:512],
            free_text=record.asset_description,
            candidates={"candidates": candidates},
            best_confidence=round(match_confidence, 3),
            queued_at=utc_now(),
        )
        .on_conflict_do_nothing(constraint="uq_review_queue_identity")
    )


def _upsert_transaction(
    session: Session, record: PoliticalTradeRecord, cik: str | None, confidence: float | None
) -> bool:
    stmt = (
        pg_insert(CongressionalTransaction)
        .values(
            filer_name=record.filer_name,
            filer_id=record.filer_id,
            chamber=record.chamber,
            owner_type=OwnerType(record.owner_type),
            cik=cik,
            asset_description=record.asset_description,
            transaction_type=record.transaction_type,
            transaction_date=record.transaction_date,
            disclosure_date=record.disclosure_date,
            # Computed in Python, stored as an integer. The frontend never
            # subtracts two dates (non-negotiable #8).
            disclosure_lag_days=record.disclosure_lag_days,
            # Brackets. There is no single-amount column and there never will be.
            value_low_minor=record.value_low_minor,
            value_high_minor=record.value_high_minor,
            currency=record.currency,
            parse_outcome=ParseOutcome(record.parse_outcome),
            entity_match_confidence=confidence,
            source_id=SOURCE_ID_HOUSE,
            retrieved_at=utc_now(),
            effective_date=record.transaction_date,
            source_document_url=record.document_url or "manual-import",
            source_record_id=record.source_record_id,
            # A manual import is not a live feed, and the UI says so.
            data_quality=DataQuality.MANUALLY_IMPORTED,
        )
        .on_conflict_do_nothing(constraint="uq_congress_identity")
        .returning(CongressionalTransaction.id)
    )
    return session.execute(stmt).scalar_one_or_none() is not None


def _upsert_event(
    session: Session, record: PoliticalTradeRecord, cik: str, confidence: float
) -> bool:
    """Emit the signal event.

    ``public_available_at`` is the disclosure date — when the filing appeared
    in the index — not the transaction date. SPEC §7.1 is emphatic: timing a
    backtest entry off the transaction date would be trading on information
    that was not public for another six weeks.
    """
    stmt = (
        pg_insert(SignalEvent)
        .values(
            event_id=event_id(
                "ptr",
                record.source_record_id,
                record.filer_id,
                record.transaction_date.isoformat(),
                record.asset_description,
            ),
            category=SignalCategory.POLITICAL,
            cik=cik,
            detected_at=utc_now(),
            transaction_date=record.transaction_date,
            disclosure_date=record.disclosure_date,
            disclosure_lag_days=record.disclosure_lag_days,
            public_available_at=utc_now(),
            headline=f"{record.filer_name} disclosed a {record.transaction_type}",
            # transaction_type is purchase/sale/exchange/other -- never
            # buy/sell, which are banned copy and would render as such.
            value_low_minor=record.value_low_minor,
            value_high_minor=record.value_high_minor,
            currency=record.currency,
            entity_match_confidence=confidence,
            # One lawmaker is one actor, however many lines the PTR has.
            actor_key=f"ptr:{record.filer_id}",
            source_id=SOURCE_ID_HOUSE,
            retrieved_at=utc_now(),
            effective_date=record.transaction_date,
            source_document_url=record.document_url or "manual-import",
            source_record_id=record.source_record_id,
            data_quality=DataQuality.MANUALLY_IMPORTED,
        )
        .on_conflict_do_nothing(index_elements=[SignalEvent.event_id])
        .returning(SignalEvent.event_id)
    )
    return session.execute(stmt).scalar_one_or_none() is not None


def ingest_records(
    session: Session, records: Sequence[PoliticalTradeRecord], result: IngestResult
) -> dict[str, int]:
    """Resolve, gate, and persist. Returns the resolution report."""
    resolver = _build_resolver(session)
    report = {"resolved": 0, "queued_for_review": 0, "total": len(records)}

    for record in records:
        match = resolver.resolve(
            SOURCE_ID_HOUSE,
            record.source_record_id,
            as_of=record.transaction_date,
            free_text=record.asset_description,
        )

        if match.passes_gate and match.resolved_cik is not None:
            report["resolved"] += 1
            session.execute(
                pg_insert(EntityMatchRow)
                .values(
                    source=SOURCE_ID_HOUSE,
                    source_key=record.asset_description[:512],
                    resolved_cik=match.resolved_cik,
                    method=match.method.value,
                    confidence=round(match.confidence, 3),
                    resolved_at=utc_now(),
                )
                .on_conflict_do_nothing(index_elements=["source", "source_key"])
            )
            if _upsert_transaction(session, record, match.resolved_cik, match.confidence):
                result.rows_written += 1
            else:
                result.rows_skipped_duplicate += 1
            if _upsert_event(session, record, match.resolved_cik, match.confidence):
                result.events_written += 1
        else:
            # Below the gate: the transaction is still recorded (it happened,
            # and the disclosure is a fact) but with no CIK, so it cannot reach
            # a score. The review queue holds the candidates.
            report["queued_for_review"] += 1
            _queue_for_review(
                session,
                record,
                match.confidence,
                [{"cik": cik, "score": score} for cik, score in match.runners_up],
            )
            if _upsert_transaction(session, record, None, match.confidence or None):
                result.rows_written += 1
            else:
                result.rows_skipped_duplicate += 1

    return report


def run_from_csv(session: Session, *, csv_text: str, chamber: str = "house") -> IngestResult:
    """``imt ingest congress --from-csv``.

    The path that works when the PDF pipeline does not — and the only path for
    the Senate in V1.
    """
    with ingestion_run(session, job="congress-csv", source_id=SOURCE_ID_HOUSE) as result:
        records, errors = parse_csv(csv_text, default_chamber=chamber)
        result.documents_fetched = len(records) + len(errors)
        result.errors.extend(errors)

        persist_raw(
            session,
            source_id=SOURCE_ID_HOUSE,
            source_record_id=f"manual-import-{utc_now().date().isoformat()}",
            url="manual-import",
            payload=csv_text.encode("utf-8"),
            content_type="text/csv",
        )

        report = ingest_records(session, records, result)
        log.info("congress.resolution_report", **report)
        result.errors.append(
            f"resolution: {report['resolved']}/{report['total']} at >=0.85, "
            f"{report['queued_for_review']} queued for review"
        )
        session.commit()
    return result


def average_disclosure_lag(session: Session, *, since: date) -> float | None:
    """Mean lag over recent disclosures, for the panel caption.

    UI_SPEC §4.7 requires the Congressional Trading panel to state how much
    older the underlying transactions are, and to compute it rather than
    hardcode a number. Returns None when there is nothing to average — the
    caption then says so instead of printing a zero.
    """
    from sqlalchemy import func

    value = session.execute(
        select(func.avg(CongressionalTransaction.disclosure_lag_days)).where(
            CongressionalTransaction.disclosure_date >= since
        )
    ).scalar_one_or_none()
    return round(float(value), 1) if value is not None else None
