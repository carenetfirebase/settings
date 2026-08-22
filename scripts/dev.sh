#!/usr/bin/env bash
# Linux dev container: start the native Postgres cluster and export the URL.
# On Windows this is `docker compose up -d db` -- see scripts/dev.ps1.
set -euo pipefail
PGDATA=${PGDATA:-/var/lib/imtpg}
if ! pg_isready -h 127.0.0.1 -q 2>/dev/null; then
  su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D $PGDATA \
    -o '-p 5432 -k /tmp/pgsock -c listen_addresses=127.0.0.1' -l /tmp/pg.log start"
  sleep 2
fi
export IMT_DATABASE_URL="postgresql+psycopg://imt@127.0.0.1:5432/imt"
echo "IMT_DATABASE_URL=$IMT_DATABASE_URL"
