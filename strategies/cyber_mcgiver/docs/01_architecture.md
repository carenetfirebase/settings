# v7 architecture

## 1. Why v6 could not be tuned into v7

v6 asked, in sequence, for a higher-timeframe unanimity, a break of structure,
P1, P2, a slope inside a band, P3, Touch #4, a rejection candle, and an entry
trigger. Each was a binary veto. Writing the base rates optimistically:

```
HTF unanimity  0.20
BOS            0.30
P1 and P2      0.50
slope band     0.40
P3 confirm     0.25
Touch #4       0.30
rejection      0.35
```

The product is about 6 x 10^-4 per opportunity window. That is the eleven
trades. No individual gate is unreasonable; the AND is.

The restructure is therefore not "loosen the trendline". It is: **stop
multiplying probabilities**.

## 2. What stayed mandatory

A condition is a veto in v7 only if breaking it means the risk figure is a lie.
These are not opinions about the market:

| Gate | Why it cannot be a score |
|---|---|
| valid structural stop (`okStop`) | without it there is no R, and no sizing |
| stop ≤ 3 ATR (`okWide`) | a wider stop makes the 0.25–0.50% risk claim false |
| stop ≥ 0.25 ATR (`okTight`) | inside the noise; a coin flip against the spread |
| reward room ≥ 1.5 R (`okRoom`) | a trade into a wall cannot pay for its own costs |
| volatility shock veto (`okShock`) | on a news spike the stop prices off nothing structural |
| trigger close location (`okMom`) | never buy a bar that closed on its low |
| regime floor (`okRegime`) | never buy into an unambiguous higher-timeframe downtrend |
| daily trade cap | the hard 3/day limit |
| daily loss cutoff | the -1.0…-1.5% stand-down |
| anchor / cooldown (`okAnchor`) | otherwise one idea is recycled into three trades |

Everything else became score. Note what left the veto list: HTF **unanimity**,
the slope **band**, the rejection-candle body and close-location **minimums**,
the DXY check, the session filter, VWAP position, and the requirement that
touch #3 be a pivot. All of those are now weighted contributions.

## 3. The score

Ten components, each normalised to 0–1, each with a configurable weight. The
score is `sum(weight x quality) / sum(weights) x 100`, so re-weighting does not
silently move the tier boundaries underneath the model.

| Component | Weight | 1.0 means | 0.0 means |
|---|---|---|---|
| higher-timeframe regime | 15 | 1D, 4H and 1H all aligned | all three opposed |
| VWAP alignment / location | 10 | just above VWAP (≤1 ATR) | far below, or chasing 5 ATR above |
| market structure / BOS | 15 | a fresh, well-displaced break | stale, or a break the other way |
| pullback / trendline quality | 15 | tight touch, well-shaped slope | a graze or a rout |
| liquidity sweep / reclaim | 10 | meaningful penetration, fast reclaim | no sweep at all |
| momentum / rejection candle | 10 | strong body closing on its high | doji closing on its low |
| DXY confluence | 10 | dollar falling into a gold long | dollar rallying |
| ATR / volatility environment | 5 | ordinary session range | dead tape or a shock |
| available reward room | 5 | ≥ 4 R to the next structure | at the 1.5 R floor |
| session / liquidity quality | 5 | London or New York | the rollover hour |

**Components a family cannot measure score neutral (0.50), not zero.** A sweep
setup has no trendline and a trendline setup has no sweep; scoring the missing
component zero would make every family permanently uncompetitive against its own
weights, and the score would collapse into a family-identity indicator.

Tiers and their risk, as specified: **A+ 85–100 → 0.50%**, **A 78–84 → 0.40%**,
**B+ 72–77 → 0.25%**, below 72 no trade. The hard ceiling is 1.00% and is never
reached by the default tiers — it is a ceiling, not a default.

## 4. The four families

Each emits a *candidate*: a direction, a trigger price, a structural stop
reference, an anchor bar, and its own readings for the pullback and sweep
components. Everything downstream is shared.

**1 · Trendline third-touch continuation.** The v6 idea, preserved. BOS → P1 →
P2 defines a line → P3 confirms it → a later touch is the opportunity. What
changed: a failed rejection no longer kills the line, the slope band is scored
rather than vetoed, and the contact tolerance widened from 0.12 to 0.20 ATR
because tolerance is a measurement precision choice, not an edge.

**2 · Liquidity sweep + reclaim.** The nearest of the 20-bar low, the prior day
low and the session low is taken out and reclaimed. Penetration depth is scored
on a tent: a graze is noise, a rout is a breakdown, and the tradable case is in
between. Penetration past 1.5 ATR cancels the setup outright.

**3 · Breakout + retest.** A confirmed close through a 30-bar extreme, then a
controlled return to the broken level, then a continuation trigger. A close
0.6 ATR back inside the old range cancels it rather than leaving it armed to
catch the reversal.

**4 · VWAP / trend continuation pullback.** Directional regime, a real prior
leg, a pullback into whichever of session VWAP and the 20 EMA is *shallower*
(that is the one price reaches first), then a continuation trigger.

Only one entry per bar is ever taken — highest score wins — but **every**
candidate is counted in the funnel and in the score distribution.

## 5. Setup independence

Three conditions, all required, so that a trade cannot be recycled:

1. **Anchor.** Every candidate carries the bar index of the structure that
   produced it: the trendline's P2 bar, the swept low, the breakout bar, the
   pullback leg's swing high. Trading it consumes it for that family.
2. **Cooldown.** At least 4 bars since the last exit.
3. **Structure.** At least one newly confirmed pivot since the last exit.

Without these, entry → exit → immediate re-entry on unchanged structure would
manufacture trade count out of one idea and make every frequency statistic a
lie. On the reference run the anchor rule alone rejects 1,317 candidates.

## 6. Daily frequency and daily risk

* Hard maximum **3 completed entries per day**. Counted on fill.
* Daily loss cutoff **1.25%** of the day's opening equity (research range
  1.0–1.5%). On breach no further entries; open positions still run to their
  own exits.
* The 2nd trade of a day is sized at **0.80x**, the 3rd at **0.60x**.
* A trade is additionally capped at the **unspent daily loss budget**, so the
  cutoff can be reached but never jumped over in a single trade.
* Frequency statistics count **normal trading days only** — a day needs 60 of
  its ~92 bars. A four-bar holiday fragment with no trade is not evidence of an
  over-selective engine, and letting it into the denominator would flatter every
  zero-trade percentage in the report.

## 7. Exits

The v6 rule "+0.25R MFE within 3 bars or leave" is **off**, and deliberately not
replaced. It was an invented number. The EXITS panel reports the MFE and MAE
survival curves so a replacement can be read off the distribution instead:

```
median MFE 1.02 R      share reaching 0.25 R  81.1%
median MAE 1.09 R      share reaching 0.50 R  67.4%
                       share reaching 1.00 R  50.7%
                       share reaching 1.20 R  45.2%
```

The switch (`i_useFollow`) still exists so the old behaviour can be reproduced
for a controlled comparison, but it starts off.

Otherwise unchanged from v6: 50% partial at 1.2R, cost-adjusted breakeven after
a *closed* bar beyond the partial, ATR and structure trail, a 10R ceiling.

## 8. One accounting subtlety worth knowing about

A stop entry cannot fill on the bar it is submitted, but it can fill **and** be
stopped out inside the following bar. The broker reports flat at that bar's
close. v6 treated that as an unfilled order, which silently dropped a real trade
— and it is a losing trade, so the drop is biased. On the reference run **15.6%
of all fills are same-bar round trips**. v7 detects them on the closed-trade
counter and books them, and the funnel reports the count on its own row.

## 9. Known limitation of "Both" mode

Each family keeps one directional tracker. Under the long-only first pass, and
under short-only, that is exactly correct. In "Both" mode a long setup and a
short setup competing for the same family's tracker means the newer one wins and
the older is dropped, so "Both" **under-counts**. It never produces a wrong
trade, only a missing one. Building two trackers per family doubles the state
for a mode that is out of scope until longs are validated.
