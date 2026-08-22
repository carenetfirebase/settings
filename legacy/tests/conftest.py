"""Shared pytest fixtures.

DB-backed tests run against a real PostgreSQL instance — not SQLite. The schema
uses JSONB, NUMERIC precision and plpgsql triggers, so testing against a
different engine would test something we do not ship.

Point `TEST_DATABASE_URL` at a scratch database. If no server is reachable the
DB-backed tests skip (with a visible reason) rather than fail, so the pure-math
engine tests still run anywhere.
"""

from __future__ import annotations

import os
from collections.abc import Iterator

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

DEFAULT_TEST_URL = "postgresql+psycopg://invest@127.0.0.1:5432/invest_test"


def _test_url() -> str:
    return os.environ.get("TEST_DATABASE_URL", DEFAULT_TEST_URL)


def _ensure_database(url: str) -> None:
    """Create the scratch database if it does not exist."""
    parsed = make_url(url)
    admin = parsed.set(database="postgres")
    engine = create_engine(admin, isolation_level="AUTOCOMMIT")
    with engine.connect() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM pg_database WHERE datname = :n"), {"n": parsed.database}
        ).scalar()
        if not exists:
            conn.execute(text(f'CREATE DATABASE "{parsed.database}"'))
    engine.dispose()


@pytest.fixture(scope="session")
def db_engine() -> Iterator[Engine]:
    url = _test_url()
    try:
        _ensure_database(url)
    except OperationalError as exc:
        pytest.skip(f"No PostgreSQL reachable at {url}: {exc}")

    # Run the real migrations, so the tests exercise the DDL we actually ship
    # rather than metadata.create_all(), which would silently skip the triggers.
    from alembic import command
    from alembic.config import Config

    cfg = Config("alembic.ini")
    cfg.set_main_option("sqlalchemy.url", url)
    cfg.set_main_option("script_location", "alembic")
    command.upgrade(cfg, "head")

    engine = create_engine(url, future=True)
    yield engine
    engine.dispose()


@pytest.fixture(scope="session")
def _tables(db_engine: Engine) -> list[str]:
    with db_engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT tablename FROM pg_tables "
                "WHERE schemaname='public' AND tablename <> 'alembic_version'"
            )
        ).scalars()
        return list(rows)


@pytest.fixture
def db_session(db_engine: Engine, _tables: list[str]) -> Iterator[Session]:
    """A clean database per test.

    TRUNCATE rather than DELETE: the append-only triggers are FOR EACH ROW on
    UPDATE/DELETE, and TRUNCATE does not fire them — which is exactly the
    escape hatch a test harness needs and application code does not have.
    """
    with db_engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {', '.join(_tables)} RESTART IDENTITY CASCADE"))

    factory = sessionmaker(bind=db_engine, expire_on_commit=False, future=True)
    session = factory()
    try:
        yield session
    finally:
        session.rollback()
        session.close()
