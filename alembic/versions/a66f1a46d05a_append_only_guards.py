"""append only guards

Enforces ground rule 6 ("never overwrite a price, fundamental, or score") in
the database itself rather than by convention. Application bugs, a stray psql
session and a future contributor all hit the same wall.

Corrections are expressed as new rows: a restated fundamental arrives with a
later filed_date, a corrected price with a later ingested_at.

Revision ID: a66f1a46d05a
Revises: a6a1ba7748fe
Create Date: 2026-08-18 12:52:14.359671

"""

from collections.abc import Sequence

from alembic import op

revision: str = "a66f1a46d05a"
down_revision: str | None = "ed2dc77df413"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APPEND_ONLY_TABLES = ("price_observations", "fundamentals", "research_snapshots")


def upgrade() -> None:
    op.execute(
        """
        CREATE OR REPLACE FUNCTION invest_reject_mutation() RETURNS trigger AS $$
        BEGIN
            RAISE EXCEPTION
                'Table % is append-only: % is not permitted. '
                'Record the correction as a new row instead.',
                TG_TABLE_NAME, TG_OP
                USING ERRCODE = 'restrict_violation';
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    for table in APPEND_ONLY_TABLES:
        op.execute(
            f"""
            CREATE TRIGGER trg_{table}_append_only
            BEFORE UPDATE OR DELETE ON {table}
            FOR EACH ROW EXECUTE FUNCTION invest_reject_mutation();
            """
        )


def downgrade() -> None:
    for table in APPEND_ONLY_TABLES:
        op.execute(f"DROP TRIGGER IF EXISTS trg_{table}_append_only ON {table};")
    op.execute("DROP FUNCTION IF EXISTS invest_reject_mutation();")
