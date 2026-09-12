#!/usr/bin/env bash
# Applies schema.sql to a throwaway database and runs the RLS tests against it.
#
#   packages/db/test.sh                     # uses $PGHOST/$PGPORT or a local socket
#   PGHOST=/tmp PGPORT=5433 packages/db/test.sh
#
# Requires: postgres >= 15 with pgvector and pg_trgm available.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
db="${OPENHOUSE_TEST_DB:-openhouse_test}"
psql_args=(-U "${PGUSER:-postgres}" -v ON_ERROR_STOP=1 -q)

psql "${psql_args[@]}" -d postgres -c "drop database if exists $db" >/dev/null
psql "${psql_args[@]}" -d postgres -c "create database $db" >/dev/null
psql "${psql_args[@]}" -d "$db" -f "$here/tests/supabase-shim.sql" >/dev/null
psql "${psql_args[@]}" -d "$db" -f "$here/schema.sql" >/dev/null
echo "schema migrated clean"

# The catalog seed is generated from packages/fact-catalog, so a drift between
# the TypeScript catalog and the database is a build failure rather than a
# surprise at extraction time.
node "$here/seed.ts" > "$here/seed/001_fact_catalog.sql"
psql "${psql_args[@]}" -d "$db" -f "$here/seed/001_fact_catalog.sql" >/dev/null
echo "catalog seeded: $(psql "${psql_args[@]}" -tAd "$db" -c 'select count(*) from fact_definitions') definitions"
psql "${psql_args[@]}" -d "$db" -f "$here/tests/rls.test.sql"
