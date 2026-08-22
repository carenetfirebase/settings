"""append-only guards

Revision ID: 801576cbe276
Revises: b7ef09a83aff
Create Date: 2026-08-22 14:27:15.507387
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = '801576cbe276'
down_revision: str | None = 'b7ef09a83aff'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# CLAUDE.md non-negotiable #3: "Never overwrite a raw source record. Raw
# payloads are append-only. Backtests depend on it."
#
# A convention cannot enforce that -- one careless UPDATE in a repair script
# silently rewrites history that a backtest has already relied on. So the
# database refuses. `xbrl_facts` gets the same treatment because SPEC §7.2
# requires restatements to INSERT rather than UPDATE: a backtest asking "what
# was known on date D" only works if the original figure is still there.
GUARD_FN = """
CREATE OR REPLACE FUNCTION imt_reject_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION
        'Table % is append-only. % is not permitted. See CLAUDE.md non-negotiable #3.',
        TG_TABLE_NAME, TG_OP;
END;
$$ LANGUAGE plpgsql;
"""

GUARDED_TABLES = ("raw_documents", "xbrl_facts")


def upgrade() -> None:
    op.execute(GUARD_FN)
    for table in GUARDED_TABLES:
        op.execute(
            f"CREATE TRIGGER {table}_append_only "
            f"BEFORE UPDATE OR DELETE ON {table} "
            f"FOR EACH ROW EXECUTE FUNCTION imt_reject_mutation()"
        )


def downgrade() -> None:
    for table in GUARDED_TABLES:
        op.execute(f"DROP TRIGGER IF EXISTS {table}_append_only ON {table}")
    op.execute("DROP FUNCTION IF EXISTS imt_reject_mutation()")
