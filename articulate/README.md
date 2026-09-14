# ARTICULATE

A case desk for dental laboratories that **cannot invent a value about a device
it made**.

A lab fabricates patient-matched medical devices to a clinician's prescription.
So an AI that guesses a shade, a tooth number or a material lot is not giving a
poor answer — it is the lab making a false statement about a device that is
already in someone's mouth. And a lab answering *"should I prep deeper?"* is
practising dentistry without a licence.

Both problems have the same shape, and the same solution:

> **The AI is a mouth for the Device History Record, and it declines clinical
> judgment by design.**

The lab may state what it made, from what, to what specification, when, and
what the material manufacturer instructs. It may not state what should be done
in a mouth. That line is not a tone of voice — it is `packages/compliance`, and
it is enforced twice: once before retrieval and once on the generated sentence.

```
$ npm run ask

  24418  Q  Where is my case?
         A  Case 24418 is on hold pending practice. It's waiting on you: The
            prescription and the scan file disagree on the tooth number, so we
            have stopped the case until you confirm which one is correct.
            status · 2ms

  24418  Q  Which tooth is it?
         A  Two sources disagree on the tooth number(s): #19 on the rx document,
            and #20 on the scan metadata. We've held the case rather than choose
            one — can you confirm which is correct?
            blocked_on_practice · 1ms

  24423  Q  What is the stump shade?
         A  We don't have the stump shade — it hasn't come through from your
            office yet.
            unknown · 0ms

  24418  Q  Just use e.max instead, go ahead.
         A  We can't change the prescribed material on our own — a substitution
            needs your written authorisation on the case, and then we will make
            it exactly as you specify. Shall I put that request through to your
            technician?
            boundary_refusal · escalated to a person · 1ms
```

## What is here

| Package | What it does |
|---|---|
| `packages/case-catalog` | 208 canonical case-fact definitions across sections A–L, with restoration-type applicability and the questions practices actually ask |
| `packages/truth-engine` | Fact resolution with provenance, conflict detection, readiness and record scoring, the outstanding-ask list, the sealed case pack |
| `packages/traceability` | Lot genealogy and recall search; Device History Record assembly |
| `packages/compliance` | The clinical boundary and PHI minimisation, as fixed templates a regulatory adviser can read |
| `packages/answer-pipeline` | The grounded answer pipeline, the access model, and the validator |
| `tooling/eval` | 65-question harness with an independent, per-case invention oracle |
| `fixtures/demo-lab.ts` | Eight cases in the states a real bench holds them in |
| `app/` | The working board — the real engine, bundled and running in a browser |

## Running it

Node 22.18 or newer. TypeScript runs directly; there is no build step for the
library or the tests.

```bash
npm install

npm test           # 62 unit tests
npm run typecheck
npm run eval       # the invention measurement
npm run bench      # the bench board, in a terminal
npm run ask        # a scripted walkthrough of the case desk
node tools/bench.ts 24418          # one case in full
node tools/recall.ts ZR-24-0881    # the three-second recall answer
```

The browser app bundles the same packages:

```bash
npx esbuild app/main.ts --bundle --format=iife --minify \
  --outfile=app/dist/articulate.js
```

## Five decisions that define this

**Facts are two-tier, and conflicts are the natural state.** A `CaseClaim` is
"this source asserts this value" — the written Rx, the scan file's own
metadata, a technician at the bench, a supplier's certificate. A `CaseFact` is
"a named person at the lab stands behind this." When the prescription says #19
and the scan shows a preparation on #20, that is not a data-quality nit to
reconcile silently; it is a wrong-site manufacturing risk, and the engine stops
the case and asks. Nothing in this system picks a winner between two sources.

**Getting it wrong hurts someone, or it doesn't.** Every definition carries a
safety class. A tooth number is `patient_safety` and a disagreement stops
production; a cement space is `remake_risk` and a 5µm difference is measurement
noise that would train technicians to ignore the queue. The thresholds are in
`materiallyDiffers`, and they are where the domain actually lives.

**"Blocking" is not one thing.** A case cannot start without a tooth number,
and it is perfectly normal for it to sit in design without a material lot,
because nobody has opened a puck yet. Blockers carry the phase they hold up, so
readiness answers exactly one question — *can the bench start?* — and a board
where everything is red is a board nobody reads.

**Outstanding work has an owner.** A missing stump shade is the practice's to
send; a missing lot number is the bench's to record. Asking a dentist "what lot
number was used?" makes the lab look like it does not know its own job, so
`asks()` takes an audience and the two lists never mix.

**PHI is an asset to hold less of.** A case number, initials and a tooth run a
laboratory perfectly well. Patient identifiers never enter a case pack — the
builder excludes them, so a leak needs a bug in the builder rather than a
clever question — and the refusal for another practice's case is byte-identical
to the refusal for a case that does not exist, so the boundary cannot be used
to enumerate case numbers.

## The measurement

`npm run eval` runs 65 questions across the demo lab and exits non-zero if any
threshold slips.

```
Questions                65
Correct                  65 (100.0%)  target ≥ 95.0%
Invented values          0 (0.0%)  target 0%
Unknowns identified      100.0%  target 100%
Boundaries held          100.0%  target 100%
p95 latency              2ms  target ≤ 50ms
```

The invention oracle is deliberately independent of the pipeline and **scoped
per case**: it gathers every value that case actually contains, straight from
storage, and flags any lot, shade, tooth number or measurement in an answer
that is not among them. Per-case scoping is the part that matters — it catches
a value bleeding across from a different patient's case, which a lab-wide check
would wave through.

The harness found five real defects that the unit tests had missed, including a
catch-all that answered unrelated questions with a list of unrelated requests,
and a fallback that asked dentists for lot numbers.

## Two things the validator checks that a general one would not

Most generated text is checked for numbers. Two token classes here are checked
**exactly**, with no derivation permitted, because for these "close" and
"wrong" are the same thing:

- **lot numbers** — a recall notice names an exact string
- **tooth numbers** — the wrong one is a wrong-site device

It also checks the inverse failure, which costs more trust than people expect:
a fact the lab *does* know, hedged. *"I think it shipped Tuesday"* is a worse
answer than the record it came from.

## What is deliberately not here

- **Persistence, auth, multi-tenancy.** The store is in-memory and the state
  machine in `InMemoryCaseStore` is the specification Postgres would implement.
- **File ingestion.** No STL/PLY parsing, no OCR of a scanned prescription. The
  claim model and the citation requirement are built; the extraction behind
  them is not.
- **Lab management system integrations.** The real ones — LabStar, Evident,
  3Shape Unite, iTero and Medit exports — are the hard, unglamorous work, and
  they are a per-vendor negotiation rather than a weekend.
- **An LLM.** `phrase()` composes answers from the grounding payload without a
  model, which is why the eval runs offline and why it cannot invent. A
  model-backed provider implements the same signature and passes through the
  same validator: the difference is how it reads, not what it may say.
- **HIPAA hosting, a BAA, a validated quality system.** Nothing here should
  touch real patient data until those exist.

## A word on the eval's perfect score

It is 100% partly because `phrase()` is structurally incapable of inventing a
value. Treat that as a working harness rather than a proven model. The number
starts meaning something on the day a language model sits behind that
interface — it will drop, the validator will start blocking answers, and the
flags it writes to the ledger are the actual signal.
