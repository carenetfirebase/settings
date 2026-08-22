# Form 4 fixtures

**These are hand-constructed, not recorded from EDGAR.** This development
environment cannot reach `sec.gov` (the network policy rejects it), so they were
written against the Form 4 XML schema rather than captured from live responses.

They are faithful to the schema's shapes — including the awkward ones: the
`<value>` wrapper that some filing agents omit, elements carrying only a
`<footnoteId>`, booleans as `1`/`true`/`Y`, and documents with and without a
default namespace.

**Replace them with real recordings on first live run.** A hand-written fixture
proves the parser handles the schema as documented; only a recording proves it
handles what filers actually send. Until then, the coverage claim in Phase 2
criterion 8 is "the documented schema", not "the wild".

| File | Covers |
|---|---|
| `multi_transaction.xml` | Several transactions in one filing, namespaced, P and S codes |
| `footnoted_10b5_1.xml` | 10b5-1 declared only in footnote text, no explicit flag |
| `amendment.xml` | A `4/A` restating an earlier filing |
| `joint_owners.xml` | Two reporting owners — one decision, not two insiders |
| `holdings_only.xml` | Valid filing with no transactions; must parse to zero rows |
| `footnote_only_price.xml` | Price element carries a footnote reference and no value |
