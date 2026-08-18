# invest

Zero-cost, institutional-style investment research platform. Plain Python,
free data sources only, deterministic math, point-in-time correctness. See
the build prompt for full ground rules and architecture.

## Status

**Step 1 of the build order**: repo scaffolding, Postgres via Docker
Compose, Alembic wiring, env-driven config, CLI skeleton. No domain schema
yet — that's step 2.

## Setup

```bash
cp .env.example .env        # then fill in EDGAR_USER_AGENT at minimum
pip install -e ".[dev]"
docker compose up -d        # starts Postgres 16 on localhost:5432
invest db check             # verify connectivity
pytest                      # run tests (no Docker required)
```

## Layout

```
src/invest/
  config.py     # env-var driven settings, no hardcoded secrets
  db/
    models.py   # SQLAlchemy declarative Base (domain tables land in step 2)
    session.py  # engine / session factory — the only place that owns the DB URL
  cli.py        # typer entry point (`invest ...`)
alembic/        # migrations, wired to invest.config + invest.db.models
tests/
```
