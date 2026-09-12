# Schema

`schema.sql` is the whole thing: 32 tables, every one with row level security
enabled and at least one policy. It targets Postgres 15+ with `pgvector`,
`pg_trgm` and `pgcrypto`, which is what Supabase provides.

Three constraints in here are load-bearing rather than decorative:

- **`claim_document_requires_citation`** — a claim sourced from a document or an
  extraction must carry a page number. If the model cannot point at where it read
  something, it invented it, and the database refuses it rather than trusting the
  pipeline to (§8.1).
- **Disclosures cannot be `agent_only`** — the check constraint makes hiding a
  disclosure impossible rather than merely discouraged. A product that can bury a
  known defect is manufacturing a non-disclosure claim (§12.3).
- **`property_snapshots` is append-only** — no update or delete policy exists,
  and a trigger closes the service-role path too. Immutability that depends on
  nobody using the admin client is not immutability.

`property_facts.version` is bumped by trigger, not by application code, because
the answer ledger records the version used and that reconstruction cannot depend
on every writer remembering to increment it.

## Running the tests

```bash
PGHOST=localhost PGPORT=5432 ./test.sh
```

It drops and recreates `openhouse_test`, applies the Supabase shim and the
schema, generates and loads the catalog seed, then runs 27 assertions covering
agent isolation, anonymous visitor scope, snapshot immutability, the citation
and disclosure constraints, and fact versioning.

Anonymous visitors can read published property chrome and nothing else — not
even verified public facts. "Public" on a fact means "may appear in an answer",
not "may be scraped as a dataset"; the tour reads a fact pack the server built
from a snapshot.

## Seed

`seed.ts` generates `seed/001_fact_catalog.sql` from `packages/fact-catalog`.
The catalog lives in TypeScript because other code depends on it; the database
needs it as rows. Maintaining both by hand would guarantee they drift, so CI
regenerates the file and fails on a diff.
