# Where the funnel dies — measured, not guessed

Two rounds of zero trades were diagnosed by reading code and both diagnoses
were incomplete. This round the state machine was ported to Python
(`validation/simulate.py`) and run directly, because a funnel you can execute
settles in seconds what argument does not settle at all.

## Is the engine broken?

No. Three fixtures, in increasing order of realism:

| Fixture | Bars | Fills |
| ------- | ---: | ----: |
| Textbook series — every 10th bar touches a rising line exactly and closes near its high, regime forced LONG | 387 | **6** |
| Drifting random walk, regime forced LONG | 39,987 | **18** |
| Drifting random walk, real unanimous 1D/4H/1H gate | 39,987 | **2** |

The textbook fixture converts 6 candidate lines into 6 fills — every stage at
100%. The engine can trade the setup the specification describes. What it
cannot do is find that setup often.

## What the funnel says (fixture 3, the realistic one)

```
candidate lines         176
P3 tested               208
  missed tolerance      195   ← 94% of touches miss the 0.12 ATR band
  closest miss (ATR)    0.002
P3 confirmed             13   ← 7% of candidates survive
T4 contact                8
valid rejections          3
FILLED                    2   ← 1.1% of candidates
```

The choke is **P3**, and it is not close: 94% of every touch tested against a
confirmed line misses the tolerance band. Everything downstream is working on
whatever few structures get through.

## The two levers, measured

40,000 bars, full regime gate, one change at a time:

| Variant | cand | P3 | T4 | rej | fill |
| ------- | ---: | -: | -: | --: | ---: |
| v2 baseline · P3 = pivot, tolerance 0.12 | 176 | 13 | 8 | 3 | **2** |
| v3 default · P3 = any-bar touch, tolerance 0.12 | 165 | 54 | 40 | 8 | **5** |
| P3 = pivot, tolerance 0.25 | 171 | 24 | 40 | 10 | **7** |
| P3 = any-bar touch, tolerance 0.25 | 149 | 85 | 129 | 30 | **25** |
| … plus body 0.25 / close-location 0.55 | 149 | 85 | 126 | 37 | **26** |
| … plus line expiry 40 bars | 124 | 74 | 162 | 34 | **18** |
| … plus slope ceiling 0.40 | 163 | 96 | 132 | 31 | **26** |

Read the rows carefully — they say different things about who is at fault.

### Lever 1 — my bug, now fixed

S31 never says Touch #3 must be a confirmed pivot. S32 tests Touch #4 on *any*
bar that returns to the line. v1 and v2 tested Touch #3 on pivot bars only,
which is internally inconsistent: it asks the pivot bar and the line to
coincide, a far narrower event than a touch. **That single restriction cost 60%
of all fills** (2 → 5) and is a defect, not a parameter.

Fixed. `Touch #3 must be a confirmed pivot` remains as an input, default off,
so the strict reading stays measurable.

### Lever 2 — a real parameter, and the operator's call

The 0.12 ATR contact tolerance is specified (S31, S39). Widening it to 0.25
multiplies fills by roughly five on top of the fix. **This is not mine to
change**, and it is exactly the single next calibration experiment S72-K asks
for. The rejection thresholds, line expiry and slope ceiling are all
second-order by comparison — loosening the rejection candle adds one fill in
26, and lengthening expiry *reduces* fills by keeping dead lines alive.

## Honest limits of this instrument

* The walk is a drifting Gaussian, not gold. Real XAUUSD trends and mean-reverts
  in ways that change every count. **Ratios between rows travel; absolute
  numbers do not.**
* The regime approximation resamples closes rather than calling
  `request.security`, so its bar alignment is close but not identical.
* Fills are idealised: no costs, no intrabar sequencing, no partials. Nothing
  here is an expectancy estimate, and nothing here should be quoted as one.

Its one job is telling us which gate rejects a candidate. On that it is
authoritative, because it runs the same gates in the same order as the Pine.
