"""API dependencies.

The API is read-only, and that is enforced by the database rather than by
convention: every request runs inside a `SET TRANSACTION READ ONLY`
transaction, so a bug in a route handler cannot write. Discipline that relies
on nobody making a mistake is not discipline.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date

from fastapi import HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from invest.db.session import get_session_factory
from invest.security_master import ResolutionError, ResolvedSecurity, resolve


def get_readonly_session() -> Iterator[Session]:
    """A session whose transaction the database itself refuses to let write.

    `SET TRANSACTION READ ONLY` must be the first statement in the transaction,
    so it is issued before the route handler gets the session.
    """
    session = get_session_factory()()
    try:
        session.execute(text("SET TRANSACTION READ ONLY"))
        yield session
    finally:
        # Never commit. Rolling back also releases the read-only transaction.
        session.rollback()
        session.close()


def as_of_param(
    as_of: date | None = Query(
        None,
        description=(
            "Point-in-time cutoff. Only data that was public on or before this "
            "date is used. Omit for the latest available."
        ),
    ),
) -> date | None:
    """Every data route takes this, so point-in-time is the default posture
    rather than something a caller has to remember to ask for.
    """
    return as_of


def resolve_ticker(session: Session, ticker: str) -> ResolvedSecurity:
    try:
        return resolve(session, ticker)
    except ResolutionError as exc:
        raise HTTPException(
            status_code=404,
            detail=(
                f"{ticker.upper()} is not in the security master. "
                f"Run `invest universe seed`, or add it explicitly."
            ),
        ) from exc
