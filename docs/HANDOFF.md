# Handoff — read this first in a new session

**This file plus `CLAUDE.md` is the memory.** Claude has no recollection of the
conversation that built this. It does not need one: every decision, finding and
open question is written into the repository, which is why the project was
structured this way in the first place.

A new session on any machine starts by reading `CLAUDE.md` (automatic), then
this file, then whichever of `docs/` the current phase needs. There is nothing
in the original conversation that is not in one of these files or in a commit
message.

---

## Getting it onto your machine

Clone it. Do not download a zip — a zip loses the git history, the branch, and
your ability to push changes back.

```powershell
git clone https://github.com/carenetfirebase/settings.git
cd settings
git checkout claude/congressional-trading-dashboard-k85w22
```

**The branch matters.** All of this work is on
`claude/congressional-trading-dashboard-k85w22`, not on `main`. Cloning without
checking out gives you the old `src/invest/` build and none of this.

Then:

```powershell
copy .env.example .env      # set IMT_SEC_CONTACT to your email; the SEC blocks IPs without it
docker compose up -d db
uv sync
uv run alembic upgrade head
cd frontend; npm install; cd ..

# two terminals
uv run uvicorn imt.api.main:app --reload --port 8000
cd frontend; npm run dev

# see it working against committed fixtures, no network needed
uv run imt load-fixtures --yes
uv run imt ingest congress --from-csv tests/fixtures/manual_ptr.csv
uv run imt score run --date today
```

`scripts/gates.ps1` runs the four quality gates. They pass as of the last
commit; if they do not on your machine, that difference is itself information.

---

## State of each phase

| Phase | Built | Not built / not verified |
|---|---|---|
| 0 Architecture | `docs/ARCHITECTURE.md`, sections A–I | — |
| 1 Foundation | 9 of 10 criteria | #7 needs the mockup PNG |
| 2 SEC engine | Parsers, ingest job, feed, KPIs; criteria 3,4,6,7,8,9 | #1,2,5 need live EDGAR. 8-K and 13D/G **ingest jobs** not written (classifiers are) |
| 3 Scoring | **All 10 criteria** | — |
| 4 Congressional | CSV path, resolution gate, donut; criteria 3–8 | #1,2 — the PDF/OCR pipeline is not built (needs Tesseract) |
| 5 Fundamentals | XBRL parser, metrics, point-in-time; criteria 2,3 | #1,4 need live EDGAR. Deep-dive page not built |
| 6 Government | Coverage, momentum, timeline, gate; criterion 3 | #1,2,5 need USAspending. Ingest job not written |
| 7 Macro | Regime, COT, positioning; **criteria 3,4** | #1,2,5 need FRED/CFTC/FINRA. Panels not built |
| 8 Backtest | Engine, look-ahead assertion, walk-forward; criteria 1,2,3,4,6 | **#5 — the baseline report** needs live prices |
| 9 AI analyst | Citation enforcement, section extraction; criteria 1,2,3,5 | #4 needs 10 real 10-Ks. LM Studio client not written |
| 10 UI | — | Not started |

339 Python tests, 6 frontend tests, four gates green.

**Roughly 15 acceptance criteria require your machine.** They are all live-data
criteria. Everything that could be built and tested without network access has
been.

---

## Blocked on you

1. **`docs/design/dashboard-mockup.png`.** Phase 1 #7 and Phase 10 #7 cannot be
   met without it. Everything else was built from UI_SPEC's tokens and
   measurements, which proved sufficient — but "matches the mockup" is
   unverifiable.

2. **The first live EDGAR run.** This is the most important thing to do, and it
   should happen before more phases are built on top:

   ```powershell
   uv run imt universe build              # Phase 2 #1: expect >= 3,500
   uv run imt ingest form4 --since 7d     # Phase 2 #2: expect >= 2,000
   ```

   Every fixture in `tests/fixtures/` is **hand-built to the documented
   schema**, not recorded from EDGAR (see `tests/fixtures/form4/README.md`).
   They prove the parsers handle the spec. They do not prove the parsers handle
   what filers actually send, and filers do things the schema permits but the
   documentation does not lead you to expect. Replace the fixtures with
   recordings from that first run.

3. **API keys.** SAM.gov first — it takes days and blocks Phase 6. Then FINRA,
   FRED, EIA, openFDA. None require a payment method; if one asks, stop.

---

## Findings that changed the spec

These are corrections made to the specification you wrote, each with the
arithmetic in `docs/SPEC.md`:

- **Convergence weights must not be normalized to sum to 1.** At λ=0.55 the
  stated calibration needs `w_i ≈ 0.88` each, summing to ≈8.8. Normalized, three
  strong categories score 15 instead of 75 — silently. The loader now refuses
  to start on either that or a single weight above 1.05 (past which one category
  alone clears the Phase 3 convergence bound).
- **Confidence squared its coverage penalty.** SPEC §6.7 multiplied by
  `CategoryCoverage` and by `DataQuality`, which §10 already defines as
  containing it. Duplicate dropped.
- **Absolute Research Priority is a ranking key, not a percentage.** DataQuality
  multiplies it and is itself a product of coverage terms, so a perfect company
  scored 2.3 with 3 of 13 contradiction checks available. The UI leads with rank
  and captions the score.
- **Contradiction is a registry with three states.** `unavailable` is not
  `clear`: "we looked and found nothing" and "we have not ingested the data to
  look" are different claims, and only the first justifies a high score. All 13
  checks are now implemented; coverage rises as each phase's data lands.
- **Convergence de-duplicates across categories.** An 8-K announcing a contract
  award and the USAspending record of the same award are two categories and one
  event.

---

## What to watch when real data lands

- **Universe size.** The 10-K/10-Q rule is a proxy for "common equity"
  (`ARCHITECTURE.md` §C.2). Far outside 3,500–5,000 means the proxy is wrong;
  `companies.inclusion_reason` records why each name is in.
- **Entity resolution rates.** SPEC §5 predicts ~85% for congressional rows with
  a ticker, ~50–70% for USAspending. Publish what you get. Lowering the 0.85
  gate to improve the number would defeat its purpose.
- **Contradiction coverage.** Currently 3 of 13 with only Phase 2 data ingested.
  Each ingest raises it, and Research Priority rises with it. Absolute scores
  before and after are not comparable; only the ranking is.
- **`uv run imt weights`** prints the convergence calibration. Run it after any
  edit to `config/weights.yaml`: one category must stay under 45.

---

## The one that matters

Phase 8's baseline report is the only thing that tells you whether any of this
is real. Everything upstream is plumbing built on the hypothesis that these
signals precede abnormal returns.

When you run it, the result may well be null or negative. With a 24-month
backfill the 250-day horizon has roughly twelve months of signals, and insider
clusters are not common, so several horizons will report "insufficient sample".
That is a real finding and the report is built to say so in those words.

The failure mode to guard against is not a bad result. It is adjusting
`config/weights.yaml` until the backtest looks better, which produces a system
that confirms whatever it was tuned to confirm. If congressional signals show no
excess return, the honest response is to publish that and set `w_political`
toward zero.

---

## Housekeeping left undone

- `legacy/` holds 73 Python files from the prior `src/invest/` build. Everything
  worth porting has been (`docs/INHERITED.md` records what and why). It can be
  deleted; the history keeps it.
- The scoring job's `CURRENT_PHASE` constant in `src/imt/scoring/job.py` gates
  which contradiction checks may run. Bump it as each ingest lands, or coverage
  will stay understated.
