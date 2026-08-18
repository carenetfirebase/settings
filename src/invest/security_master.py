"""Entity resolution: ticker -> CIK -> entity_id.

Everything downstream keys off `entity_id`, never off a ticker string. Tickers
are recycled between companies and reassigned after mergers; the CIK is stable
for the life of the registrant. Resolving once, here, means the ingestion and
scoring code never has to think about it again.
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from invest.db.enums import DataQualityFlag, EntityType
from invest.db.models import Entity, Security
from invest.universe import SEED_UNIVERSE, SeedEntry

SEED_SOURCE = "seed_bootstrap"
EDGAR_SOURCE = "sec_edgar"


class ResolutionError(LookupError):
    """Raised when a ticker cannot be resolved to a security in the master."""


@dataclass(frozen=True)
class ResolvedSecurity:
    """Flat handle passed around by ingestion and the engines."""

    security_id: int
    entity_id: int
    ticker: str
    cik: str | None
    name: str
    stooq_symbol: str | None
    currency: str
    is_financial: bool


def normalize_cik(raw: str | int) -> str:
    """EDGAR quotes CIKs in half a dozen shapes ('320193', 'CIK0000320193',
    0000320193 as an int). Normalize to the 10-digit zero-padded form.
    """
    text = str(raw).strip().upper().removeprefix("CIK").lstrip("-")
    if not text.isdigit():
        raise ValueError(f"Not a valid CIK: {raw!r}")
    return text.zfill(10)


def normalize_ticker(raw: str) -> str:
    return raw.strip().upper()


# --------------------------------------------------------------------------
# Lookups
# --------------------------------------------------------------------------


def find_security(session: Session, ticker: str) -> Security | None:
    stmt = select(Security).where(Security.ticker == normalize_ticker(ticker))
    return session.scalars(stmt).first()


def find_entity_by_cik(session: Session, cik: str) -> Entity | None:
    stmt = select(Entity).where(Entity.cik == normalize_cik(cik))
    return session.scalars(stmt).first()


def resolve(session: Session, ticker: str) -> ResolvedSecurity:
    """Resolve a ticker to the handle everything else uses.

    Raises rather than returning None: an unresolvable ticker is a caller bug
    or an unseeded universe, and silently returning nothing would let an
    ingestion run write rows against the wrong company.
    """
    security = find_security(session, ticker)
    if security is None:
        raise ResolutionError(
            f"Ticker {normalize_ticker(ticker)!r} is not in the security master. "
            f"Run `invest universe seed` or add it explicitly."
        )
    entity = session.get(Entity, security.entity_id)
    if entity is None:  # pragma: no cover - FK makes this unreachable
        raise ResolutionError(f"Security {security.id} has no entity row.")
    return ResolvedSecurity(
        security_id=security.id,
        entity_id=entity.id,
        ticker=security.ticker,
        cik=entity.cik,
        name=entity.name,
        stooq_symbol=security.stooq_symbol,
        currency=security.currency,
        is_financial=entity.is_financial,
    )


# --------------------------------------------------------------------------
# Writes
# --------------------------------------------------------------------------


def upsert_entity(
    session: Session,
    *,
    name: str,
    cik: str | None,
    source: str,
    sector: str | None = None,
    is_financial: bool = False,
    data_quality_flag: str = DataQualityFlag.OK,
    entity_type: str = EntityType.COMPANY,
) -> Entity:
    """`entities` is a mutable reference table, not an observation log — a
    company legitimately changes name and sector, so updating in place is
    correct here (unlike prices and fundamentals, which are append-only).
    """
    entity: Entity | None = None
    if cik is not None:
        cik = normalize_cik(cik)
        entity = find_entity_by_cik(session, cik)
    if entity is None:
        entity = session.scalars(select(Entity).where(Entity.name == name)).first()

    if entity is None:
        entity = Entity(
            name=name,
            cik=cik,
            sector=sector,
            is_financial=is_financial,
            source=source,
            entity_type=entity_type,
            data_quality_flag=data_quality_flag,
        )
        session.add(entity)
        session.flush()
        return entity

    entity.name = name
    if cik is not None:
        entity.cik = cik
    if sector is not None:
        entity.sector = sector
    entity.is_financial = is_financial
    entity.source = source
    entity.data_quality_flag = data_quality_flag
    session.flush()
    return entity


def upsert_security(
    session: Session,
    *,
    entity_id: int,
    ticker: str,
    exchange: str | None,
    stooq_symbol: str | None = None,
    currency: str = "USD",
    security_type: str = "common_stock",
    data_quality_flag: str = DataQualityFlag.OK,
) -> Security:
    ticker = normalize_ticker(ticker)
    security = find_security(session, ticker)
    if security is None:
        security = Security(
            entity_id=entity_id,
            ticker=ticker,
            exchange=exchange,
            stooq_symbol=stooq_symbol,
            currency=currency,
            security_type=security_type,
            is_active=True,
            data_quality_flag=data_quality_flag,
        )
        session.add(security)
        session.flush()
        return security

    security.entity_id = entity_id
    security.exchange = exchange
    if stooq_symbol is not None:
        security.stooq_symbol = stooq_symbol
    security.currency = currency
    security.data_quality_flag = data_quality_flag
    session.flush()
    return security


def seed_entry(session: Session, entry: SeedEntry) -> ResolvedSecurity:
    """Write one seed row, flagged unverified until EDGAR confirms the CIK."""
    entity = upsert_entity(
        session,
        name=entry.name,
        cik=entry.cik,
        source=SEED_SOURCE,
        sector=entry.sector,
        is_financial=entry.is_financial,
        data_quality_flag=DataQualityFlag.UNVERIFIED_BOOTSTRAP,
    )
    security = upsert_security(
        session,
        entity_id=entity.id,
        ticker=entry.ticker,
        exchange=entry.exchange,
        stooq_symbol=entry.stooq_symbol,
        data_quality_flag=DataQualityFlag.UNVERIFIED_BOOTSTRAP,
    )
    return ResolvedSecurity(
        security_id=security.id,
        entity_id=entity.id,
        ticker=security.ticker,
        cik=entity.cik,
        name=entity.name,
        stooq_symbol=security.stooq_symbol,
        currency=security.currency,
        is_financial=entity.is_financial,
    )


def seed_universe(session: Session) -> list[ResolvedSecurity]:
    """Idempotent: re-running updates in place rather than duplicating."""
    return [seed_entry(session, entry) for entry in SEED_UNIVERSE]


# --------------------------------------------------------------------------
# Verification against the authoritative source
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class CikVerification:
    ticker: str
    seeded_cik: str | None
    authoritative_cik: str | None
    status: str  # confirmed | corrected | missing_from_authority | not_seeded


def verify_ciks(session: Session, authority: dict[str, str]) -> list[CikVerification]:
    """Reconcile seeded CIKs against an authoritative ticker->CIK mapping
    (SEC EDGAR's `company_tickers.json`).

    A mismatch is corrected in place and the flag cleared to 'ok'. A ticker the
    authority does not know keeps its unverified flag — we do not promote a
    guess to a fact just because nothing contradicted it.
    """
    authority_norm = {normalize_ticker(t): normalize_cik(c) for t, c in authority.items()}
    results: list[CikVerification] = []

    for security in session.scalars(select(Security)).all():
        entity = session.get(Entity, security.entity_id)
        if entity is None:  # pragma: no cover
            continue
        seeded = entity.cik
        truth = authority_norm.get(security.ticker)

        if truth is None:
            results.append(
                CikVerification(security.ticker, seeded, None, "missing_from_authority")
            )
            continue

        if seeded == truth:
            status = "confirmed"
        else:
            entity.cik = truth
            status = "corrected"

        entity.data_quality_flag = DataQualityFlag.OK
        security.data_quality_flag = DataQualityFlag.OK
        results.append(CikVerification(security.ticker, seeded, truth, status))

    session.flush()
    return results
