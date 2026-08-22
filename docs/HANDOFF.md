# Handoff — what to run, what is blocked, what to check

Everything below was built without network access to any data host. This
document is the boundary between what has been verified and what has not.

## Run it on your machine

```powershell
copy .env.example .env      # set IMT_SEC_CONTACT to your email -- the SEC blocks IPs without it
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

`scripts/gates.ps1` runs the four quality gates.

## What is verified, and how

| Phase | State | Evidence |
|---|---|---|
| 0 Architecture | done | `docs/ARCHITECTURE.md` |
| 1 Foundation | done except mockup | 9 of 10 criteria; #7 needs the PNG |
| 2 SEC engine | parsers done, live ingest unrun | criteria 3, 4, 6, 7, 8, 9 |
| 3 Scoring | **done** | all 10 criteria, output in the commit message |
| 4 Congressional | CSV path done, PDF/OCR not built | criteria 3–8; 1 and 2 unmet |
| 8 Backtest | engine done, report not produced | criteria 1, 2, 3, 4, 6; 5 unmet |
| 5, 6, 7, 9, 10 | not started | — |

241 Python tests, 6 frontend tests, four gates green.

## Blocked on you

1. **`docs/design/dashboard-mockup.png`** — Phase 1 #7 and Phase 10 #7 cannot
   be met without it. Everything else was built from UI_SPEC's tokens and
   measurements, which turned out to be sufficient, but "matches the mockup"
   is unverifiable.

2. **Live-ingestion criteria.** The development environment's network policy
   rejects `sec.gov`, `stooq.com`, `cftc.gov` and
   `disclosures-clerk.house.gov`. These have never been run:

   ```powershell
   uv run imt universe build              # Phase 2 #1: expect >= 3,500
   uv run imt ingest form4 --since 7d     # Phase 2 #2: expect >= 2,000
   uv run imt ingest eightk --since 7d    # Phase 2 #5: expect >= 200
   ```

   The **first live run is the real test of the parsers.** Fixtures are
   hand-built to the documented schema (`tests/fixtures/form4/README.md`), so
   they prove the parser handles the schema, not that it handles what filers
   actually send. Replace them with recordings from that first run.

3. **API keys.** SAM.gov first — it takes days and blocks Phase 6. Then FINRA,
   FRED, EIA, openFDA. None require a payment method; if one asks, stop.

## Watch these when real data lands

- **Universe size.** The 10-K/10-Q rule is a proxy for "common equity"
  (ARCHITECTURE §C.2). If the count lands far outside 3,500–5,000, the proxy
  is wrong; `companies.inclusion_reason` records why each name is in.
- **Entity resolution rates.** SPEC §5 predicts ~85% for congressional rows
  with a ticker and ~50–70% for USAspending. Publish the number you get.
  Lowering the 0.85 gate to improve it would defeat the point.
- **Contradiction coverage.** Currently 3 of 13 checks. Each phase raises it,
  and DataQuality — hence Research Priority — rises with it. Absolute scores
  before and after are not comparable; only the ranking is.
- **`imt weights`** prints the convergence calibration. If someone edits
  `config/weights.yaml`, run it: 1 category must stay under 45.

## The one that matters

Phase 8's baseline report is the only thing that tells you whether any of this
is real. Everything upstream is plumbing built on the hypothesis that these
signals precede abnormal returns.

When you run it, the result may well be null or negative — with a 24-month
backfill the 250-day horizon has roughly twelve months of signals, and insider
clusters are not common, so several horizons will likely report "insufficient
sample". That is a real finding.

The failure mode to guard against is not a bad result. It is adjusting
`config/weights.yaml` until the backtest looks better, which produces a system
that confirms whatever it was tuned to confirm. If congressional signals show
no excess return, the honest response is to publish that and set
`w_political` toward zero.
