# OPENHOUSE AI

An AI guide that answers buyers' questions at an open house and **cannot invent
a property fact**. The architecture is in [`docs/architecture.md`](docs/architecture.md);
this repository is the part of it that has been built.

The organising idea, from §0.1 of that document: the speech model is a mouth and
ears, not a brain. Hallucination in real estate is not a UX annoyance — an AI
that invents a furnace age is the listing agent making a material
misrepresentation. So every property-specific claim comes out of a deterministic
Truth Engine, and every generated sentence is checked against the payload it was
allowed to draw from before anyone hears it.

```
$ npm run demo

123 Maple Crescent, Calgary · $899,900
DEMO PROPERTY — FICTIONAL DATA

  V  How old is the furnace?
  A  The furnace was installed in 2019.
     structured · 0ms · mechanical.furnace.install_year

  V  How old is the fridge?
  A  The refrigerator was installed in 2023.
     structured · 0ms · kitchen.appliance.refrigerator.install_year

  V  What about the dishwasher?
  A  The seller doesn't have a record of the dishwasher installation year.
     unknown · 0ms · kitchen.appliance.dishwasher.install_year

  V  Is the basement suite legal?
  A  Basement suite status: Not legal.
     structured · 0ms · basement.suite_status

  V  Is this a safe neighbourhood?
  A  That's not something I can assess. I can tell you the property's location
     and the amenities nearby, and public crime statistics are published by the
     city — Sarah Thompson can also point you to local resources.
     boundary_refusal · 1ms
```

## What is built

Following §19 of the architecture — *"voice on top of a weak truth engine is
just a confident liar with a nice accent"* — this is phases 1, 4 and 6 plus the
compliance layer and the adversarial harness. Voice, document ingestion and the
web applications are not built; the seams they attach to are.

| Package | What it does | Architecture |
|---|---|---|
| `packages/db` | Full Postgres schema, RLS on all 32 tables, generated catalog seed, policy tests | §6, §2, §14 |
| `packages/fact-catalog` | 384 canonical fact definitions across sections A–L, applicability predicates, question templates | §6.2, §7.4 |
| `packages/truth-engine` | Fact resolution, conflict detection, two-number coverage, gap ranking, fact-pack build | §7 |
| `packages/compliance` | Fair-housing and licensed-advice boundaries as reviewable templates | §12 |
| `packages/answer-pipeline` | The 13-step grounded answer pipeline, the conversation frame, and the validator | §11 |
| `packages/ai-gateway` | Provider interfaces, failover, voice session config, extraction guard | §1.2, §8.1, §10.2, §14.3 |
| `packages/ui` | Design tokens | §15.1 |
| `packages/analytics` | Typed event catalog, engagement tiers, retention policy | §13 |
| `tooling/eval` | 100-question answer-quality and hallucination harness | §16 phase 6 |
| `fixtures/demo-property` | 123 Maple Crescent, seeded through the real claim → confirm path | §17 |

## Running it

Node 22.18 or newer. TypeScript runs directly — there is no build step.

```bash
npm install

npm test              # 96 unit tests
npm run typecheck
npm run eval          # the zero-hallucination measurement
npm run demo          # walk the demo property in the terminal
npm run demo:agent    # coverage, conflicts, publish blockers, gaps
npm run db:test       # migrate the schema and run the RLS policy tests
```

`npm run db:test` needs a Postgres 15+ with `pgvector` and `pg_trgm` available.
Point it at one with `PGHOST` / `PGPORT` / `PGUSER`; it creates and drops its own
database. Supabase supplies `auth.users` and `auth.uid()` in production, and
`packages/db/tests/supabase-shim.sql` stands in for them locally so the same
policies that ship are the policies under test.

## The measurement

`npm run eval` runs 100 questions against the demo property and exits non-zero
if any threshold slips. The hallucination check is deliberately independent of
the pipeline: it gathers every number the property actually contains straight
from storage, and flags any property-shaped number in an answer that is not
among them. Checking the pipeline against its own grounding payload would prove
nothing.

```
Questions              100
Correct                100 (100.0%)  target ≥ 95.0%
Hallucinated facts     0 (0.0%)  target 0%
Unknowns identified    100.0%  target 100%
Boundaries enforced    100.0%  target 100%
p95 latency            2ms  target ≤ 50ms
```

The set includes the questions that are easy to answer *wrongly*: nine facts the
agent marked unknown, ten facts nobody ever entered, the roof year that two
documents disagree about, ten steering questions, ten advice questions, and the
disclosed basement leak. The eval caught four real defects the unit tests had
missed, which is the argument for building it before the pipeline rather than
after.

## Four decisions worth understanding

**Facts are two-tier.** A `fact_claim` is "this source asserts this value". A
`property_fact` is "the agent has confirmed this is the truth". Conflicts are not
a feature that had to be built — they are the natural state of two claims with
different values, so detection is nearly free and provenance is exact. A
higher-ranked source never wins automatically: the engine proposes, the agent
disposes.

**UNKNOWN is a stored state.** An unanswered fact and a fact explicitly marked
unknown are different things. The first is a gap in the agent's to-do list; the
second produces *"The seller doesn't have a record of when the windows were
replaced"* — which reads as candour rather than as a hole. The reason enum costs
one column and changes the trust outcome entirely.

**Coverage is two numbers.** Preparation (what has been reviewed) and answer
coverage (what can be answered). A property can be 100% prepared and 70%
answerable, and that is a legitimate finished state. Collapsing them into one
number pressures agents to guess, which breaks the zero-hallucination policy at
the data-entry layer. Facts blocked on an unanswered setup question ("does this
home have a garage?") are excluded from both ratios and surfaced as setup
questions instead, so a condo never shows a permanently broken score.

**The validator is what makes the policy real.** The system instructions tell
the model never to state a fact outside the payload (§10.2), and models drift
anyway. So every generated answer is parsed for numbers, years and measurements,
each of which must appear in the grounding payload or be a trivially derived
value with the derivation logged — a unit conversion, a sum, an age from a year.
Anything else blocks the answer, falls back to the unknown template, and writes
a flag to the ledger. Prompts are requests; validators are guarantees.

## What is deliberately not here

- **The Next.js applications.** The visitor PWA and agent console are §3–§5 and
  are not started. Every screen they need is backed by a function that exists.
- **Realtime voice.** The provider interface, tool definitions, system
  instructions, barge-in truncation and VAD tuning are built and tested; no
  vendor is wired, since §18 leaves that choice open.
- **Document ingestion.** The extraction *guard* — catalog scoping, citation
  enforcement, injection resistance — is built and tested against the attack in
  §14.3. OCR and the extraction model behind it are not.
- **An LLM-backed completion provider.** `TemplateCompletionProvider` composes
  answers from the grounding payload without a model. It is the floor of the
  fallback ladder and a real implementation of "the model's job is to phrase,
  not to decide", which is what lets the eval run offline. An LLM provider
  implements the same interface and passes through the same validator; the
  difference is phrasing quality, not permitted content.
- **Seller role, teams, MLS integration.** Deferred in the architecture; the
  schema carries the columns so adding them stays additive.

## Open questions

§18 of the architecture asks six questions that are not the implementation's to
answer — pilot geography, pricing model, voice provider, brokerage compliance
review, design partner, and native app timing. Two of them shape code soon:
the pricing model decides whether usage metering is built now (§18.2), and the
voice provider decides what the bake-off in phase 7 measures (§18.3).
