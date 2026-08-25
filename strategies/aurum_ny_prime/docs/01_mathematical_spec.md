# B · Mathematical specification

Every formula the strategy evaluates, in the order the engine evaluates it.
Section numbers (S*) match the comments in `AURUM_NY_PRIME.pine` and the master
instruction. Where the master instruction left a rule ambiguous, this document
states the deterministic definition that was chosen and why — per S90, an
ambiguity is converted into arithmetic **before** it is implemented, not after.

Notation: `H, L, O, C, V` are the current bar's high, low, open, close, volume.
`ATR` is `ta.atr(14)` on the chart timeframe (5m) unless subscripted. All times
are wall-clock `America/New_York`; DST is handled by the platform's timezone
database, never by a hard-coded offset.

---

## 1. Time base (S9)

```
etMin  = hour(time, ET) · 60 + minute(time, ET)
etDate = year·10000 + month·100 + day          (ET calendar day)
newDay = etDate ≠ etDate[1]
```

Window membership wraps past midnight:

```
inWindow(m, a, b) = a ≤ b ? (a ≤ m < b) : (m ≥ a ∨ m < b)
```

The end of every window is **exclusive**. A bar stamped 08:35 is therefore the
first bar *after* the 08:20–08:35 opening range, which is what makes the range
lockable (§4).

| Window | Default | Wraps midnight |
|---|---|---|
| Asia | 20:00 → 02:00 | yes |
| London | 02:00 → 08:20 | no |
| NY opening range | 08:20 → 08:35 | no |
| Entry window | 08:35 → 11:30 | no |
| Flatten | ≥ 12:00 | — |

---

## 2. Session ranges (S10, S11)

For session *s* with window `[a, b)`, accumulate forward and **freeze on the
first bar outside the window**:

```
if inWindow ∧ ¬inWindow[1]:  H_s ← H,  L_s ← L
elif inWindow:               H_s ← max(H_s, H),  L_s ← min(L_s, L),  C_s ← C
if ¬inWindow ∧ inWindow[1]:  publish (H_s, L_s, C_s);  ready_s ← true
```

```
M_s     = (H_s + L_s) / 2
Range_s = H_s − L_s
```

Nothing reads `H_s`, `L_s`, `M_s` before `ready_s`. This is the single most
important anti-repainting property in the session layer: a session's range does
not exist until the session is over.

---

## 3. Liquidity map (S12, S44)

Previous-day and previous-week levels are computed **internally on ET calendar
boundaries** rather than requested from the daily feed:

```
on newDay:   PDH ← runningDayHigh,  PDL ← runningDayLow,  PDC ← runningDayClose
             runningDayHigh ← H,    runningDayLow ← L,    DO ← O
```

*Why not `request.security(..., "D", ...)`?* Because a broker's daily bar for
XAUUSD starts at its own server rollover (17:00 or 18:00 New York, varying by
feed and by DST), so "the previous day's high" would silently mean a different
window on different feeds. Computing it here makes the level reproducible and
identical across feeds.

Overhead resistance for the reward-space rule:

```
NearestResistance = min{ Level_i : Level_i > Entry },
    Level ∈ { AsiaH, LondonH, PDH, PWH, PivotHigh₁₅ₘ, PivotHigh₁ₕ }
Room  = NearestResistance − Entry
RoomR = Room / R
```

**Deterministic choice:** when the map contains no level above the entry, `Room`
is *unmeasured*, not infinite. The gate passes only if the map itself is
populated:

```
RoomOK = MapPopulated ∧ (NearestResistance = ∅ ∨ RoomR ≥ 1.5)
```

Without that clause, the very first day of a dataset — when no level exists
yet — would trade with no clearance check at all.

---

## 4. NY opening range (S17–S21)

```
ORH = max H over [08:20, 08:35)
ORL = min L over [08:20, 08:35)
ORW = ORH − ORL
```

Locked at the first bar with `etMin ≥ 08:35`; immutable for the rest of the day.

**Breakout**

```
ORBBuffer = 0.05 · ATR
Breakout  = C > ORH + ORBBuffer
```

**Acceptance model A — momentum (S19).** Evaluated on the single bar
immediately after the breakout bar:

```
AcceptMomentum = (index = breakIndex + 1) ∧ (C > ORH)
HoldTight      = AcceptMomentum ∧ (L ≥ ORH − 0.10·ATR)      [scored, not required]
```

The master instruction marks the low condition "prefer", so it contributes
score rather than gating. Making a preference mandatory is how a filter that
was never tested becomes a filter that cannot be tested.

**Acceptance model B — retest (S20).**

```
AcceptRetest = |L − ORH| ≤ 0.10·ATR ∧ C > ORH ∧ C > O
```

**Acceptance** `ORBAccepted = Broke ∧ (AcceptMomentum ∨ AcceptRetest) ∧ ¬Failed`

**Failure (S21).**

```
Failed = (C < ORL)  ∨  (N consecutive completed closes < ORH),  N = 2
```

---

## 5. Anchored VWAP (S22, S23, S25)

Anchored at 08:20 ET, reset daily:

```
TP_i    = (H_i + L_i + C_i) / 3
w_i     = volumeMode = price-only ∨ V_i ≤ 0 ? 1 : V_i
VWAP_t  = Σ TP_i·w_i / Σ w_i           over i ∈ [anchor, t]
```

```
AboveVWAP = C > VWAP
Slope     = (VWAP_t − VWAP_{t−3}) / ATR          require Slope > 0
Extension = (C − VWAP) / ATR                     require 0 < Extension ≤ 1.25
```

**On XAUUSD volume (S23).** Spot gold has no consolidated tape; a broker's
"volume" is that broker's tick count. `XAUVolumeMode` therefore selects the
weighting explicitly, the fallback `w_i = 1` (a price-only VWAP) is used
whenever volume is absent or non-positive, and the mode in force is written
into every exported trade row so no result can be quoted without it.

---

## 6. Higher-timeframe regime (S16)

Evaluated on **completed** HTF candles only (see `04_repainting_audit.md`):

```
Bull₄ₕ = C₄ₕ[1] > EMA50₄ₕ[1] ∧ EMA50₄ₕ[1] > EMA50₄ₕ[1+3]
Bull₁ₕ = EMA20₁ₕ[1] > EMA50₁ₕ[1] ∧ C₁ₕ[1] > EMA20₁ₕ[1]
Strength₁ₕ = C₁ₕ[1] > PivotHigh₁ₕ                       [scored, not required]
GoldBull = Bull₄ₕ ∧ Bull₁ₕ
```

---

## 7. Asia → London models (S13–S15)

**Model A — continuation**

```
Continuation = LondonH > AsiaH ∧ LondonL > AsiaL ∧ LondonC > LondonM
Strong       = Continuation ∧ LondonC > AsiaH
```

**Model B — sweep and reclaim**

```
Sweep       = ∃ bar ∈ London : L < AsiaL
SweepLow    = min L over those bars
SweepDepth  = (AsiaL − SweepLow) / ATR₁₅                require ≤ 0.50
Reclaim     = C > AsiaL within 3 completed bars of the sweep
SweepBull   = Sweep ∧ Reclaim ∧ SweepDepth ≤ 0.50 ∧ C > AsiaM
Strong      = SweepBull ∧ C > AsiaH
```

```
SessionBull = Continuation ∨ SweepBull
```

The subtype is stored per trade so continuation and sweep/reclaim can be
compared as separate populations later (S15) — they may not have the same edge,
and pooling them would hide that.

---

## 8. Confirmed pivots and the trendline (S28–S32)

`ta.pivotlow(3, 3)` reports the pivot at `index − 3`, three bars after it
printed. The value is used from that bar onward and never earlier.

```
P₁ = (i₁, L₁)      previous confirmed pivot low
P₂ = (i₂, L₂)      most recent confirmed pivot low
```

Validity:

```
PivotStructure = L₂ > L₁
               ∧ L₂ − L₁ ≥ 0.10·ATR
               ∧ 4 ≤ i₂ − i₁ ≤ 36
StrictStructure = PivotStructure ∧ HH₂ > HH₁
```

`HH₁` is the confirmed pivot high between P₁ and P₂; `HH₂` is a confirmed pivot
high after P₂. Strict mode (`HL₁ → HH₁ → HL₂ → HH₂`) is off by default and adds
score when present.

**Trendline**

```
m       = (L₂ − L₁) / (i₂ − i₁)
TL(j)   = L₂ + m·(j − i₂)
m_N     = m / ATR                      require 0 < m_N ≤ 0.25
```

An upper slope bound is a fade filter: a support line rising faster than a
quarter of an ATR per bar is a parabolic move, and the third touch of a
parabola is not a pullback.

**Third interaction (S31)**

```
Tolerance = 0.12·ATR
Touch₃    = TrendlineValid
          ∧ (index − i₂) > 3                 [P₂ already confirmed]
          ∧ |L − TL(index)| ≤ Tolerance
          ∧ C > TL(index)
Touch₃Strong = Touch₃ ∧ L > L₂                [candidate HL₁ < HL₂ < HL₃]
```

**Anti-lookahead third pivot (S32).** Touch #3 is never required to be a
*confirmed* pivot. Requiring confirmation would need three future bars, and the
trade would then be entered three bars after the information that justified it.
It is treated as a **candidate** higher low that price must prove by breaking
the confirmation level (§10).

---

## 9. Rejection candle (S33)

```
Range = H − L
BR    = |C − O| / Range          require ≥ 0.35
CLV   = (C − L) / Range          require ≥ 0.70
LWR   = (min(O,C) − L) / Range   preferred ≥ 0.15   [scored, not required]
Rejection = C > O ∧ BR ≥ 0.35 ∧ CLV ≥ 0.70
```

---

## 10. Entry trigger (S34, S35)

```
MPH              = most recent CONFIRMED micro pivot high, ta.pivothigh(1,1)
ConfirmationLevel = Conservative ? max(H₃, MPH) : H₃
Entry             = ConfirmationLevel + tick
```

The order is a **stop** order placed at the close of the arm bar and living for
2 bars. If it is not filled it is cancelled. The fill IS the microstructure
break: there is no separate confirmation step, and no bar of delay between the
break and the entry.

---

## 11. Stop, size, targets (S45–S48)

```
Buffer = max(0.10·ATR, spread + slippage)
SL_A   = L₃ − Buffer                    (model A, default)
SL_B   = L₂ − Buffer                    (model B)
R      = Entry − SL                     require 0.20·ATR ≤ R ≤ 1.25·ATR
```

Rejecting a setup whose stop falls outside the band is deliberate: resizing to
fit an oversized stop would hold risk constant while quietly changing the trade
being taken.

```
RiskPct_t   = schedule(gain%)                       (§13)
RiskBudget  = min(Equity · RiskPct_t, $1,000)
CostPerUnit = (spread + slippage)·USDperPoint + commission
RiskPerUnit = R · USDperPoint + CostPerUnit
Units       = ⌊ RiskBudget / RiskPerUnit ⌋ down to the unit step
```

Always rounded **down**. Rounding up would breach the risk budget by up to one
step on every trade, which compounds into a materially different strategy.

```
TP₁ = Entry + 1.5R    (50% of position)
TP₂ = Entry + 3.0R    (25%)
Runner ≤ Entry + 7.0R (25%)
```

Leg quantities are floored to the unit step and the runner absorbs the
remainder, so the three legs sum to the position exactly.

**Breakeven (S49).** Requires a completed candle close, never a wick:

```
if C ≥ Entry + 1.0R:   SL ← max(SL, Entry + spread + slippage + commission)
```

**Trailing runner (S50).** After TP1:

```
SL_structure = LatestConfirmedHigherLow − 0.10·ATR
SL_ATR       = HighestHighSinceEntry − 2·ATR
SL_t         = max(SL_{t−1}, SL_structure, SL_ATR, Breakeven)
```

The stop is monotone non-decreasing by construction.

---

## 12. Intermarket (S24, S36–S40)

**DXY (S36)** — three intraday conditions, each on the DXY feed at the chart
timeframe:

```
D₁ = DXY_C < DXY_VWAP        (price-only VWAP: index feeds carry no volume)
D₂ = ROC₃₀(DXY) < 0
D₃ = EMA20(DXY) < EMA50(DXY)
DXYScore = D₁ + D₂ + D₃                require ≥ 2
```

**Correlation awareness (S37).** The DXY reading is only worth its weight while
the usual inverse relationship holds:

```
ρ_GD = Corr( ln(G_t/G_{t−1}), ln(D_t/D_{t−1}), 60 daily observations )

corrFactor = 1.00   if ρ_GD ≤ −0.20
             0.50   if −0.20 < ρ_GD < 0
             0.25   if ρ_GD ≥ 0
ScoreDXY ← ScoreDXY · corrFactor
```

The gate stays mandatory; only the *score contribution* is discounted. The
alternative — pretending a broken relationship is intact — is exactly what S37
forbids.

**COMEX gold (S24).**

```
G₁ = GC_C > GC_VWAP
G₂ = GC_VWAP rising over 3 bars
G₃ = ROC₃₀(GC) > 0
G₄ = GC_V > SMA(GC_V, 20)              [not mandatory until ablation earns it]
GCConfirmCount = G₁+G₂+G₃+G₄           require ≥ 2 (strong ≥ 3)
```

**VIX (S38)** — secondary, contributes score, never vetoes:

```
ρ_GV       = Corr(r_G, r_V, 60)
M_V        = ln(VIX_t / VIX_{t−5})
VIXSupport = ρ_GV · M_V
```

**Rates (S39).**

```
RYMomentum = RY_t − RY_{t−5}           supportive if < 0
```

Nominal yields are available but **off by default**: they are highly correlated
with real yields, and double-counting them without testing is the S39 failure
mode.

---

## 13. Risk state (S6–S8, S51, S52)

```
gain%   = (Equity − Account) / Account · 100

RiskPct = 0.50%   if gain% < 5
          0.40%   if 5 ≤ gain% < 8
          0.25%   if 8 ≤ gain% < 9
          0.15%   if gain% ≥ 9            capped at 1.00% absolute
```

```
DayPnL%          = (Equity − DayStartEquity) / DayStartEquity · 100
InternalDailyHit = DayPnL% ≤ −1.50%        → lock the day
FTMODailyHit     = DayPnL% ≤ −5.00%        → lock the day
FTMOMaxHit       = Equity ≤ Account·0.90   → hard stop
TargetHit        = Equity ≥ Account·(1+target) → hard stop (protect the pass)
```

`Equity` is `strategy.equity`, which includes open positions, so floating loss
counts against both limits — as it does at the firm.

**Second trade (S51).** Permitted only when all hold: the first trade lost;
score ≥ 90; risk ≤ 0.25%; and a pivot low has been confirmed **after** the
previous entry's pivot pair. That last clause is the deterministic reading of
"genuinely new setup": re-arming on the same structure is a re-entry.

**Stop after a good morning (S52).** If the first trade reaches TP1 and closes
net-positive, no further trading that day. Configurable, on by default.

---

## 14. Confluence score (S53, S54)

Each block is scored on a natural scale, normalised, and weighted:

```
Score = 100 · Σ_b [ min(raw_b / cap_b, 1) · w_b ] / Σ_b w_b     over ENABLED blocks
```

| Block | w | Raw components (cap) |
|---|---|---|
| HTF gold regime | 10 | 4H bull 5, 1H bull 4, 1H strength 1 (10) |
| Asia/London | 12 | SessionBull 8, strong variant 2, price > AsiaM 2 (12) |
| ORB | 12 | broke 4, accepted 4, retest 2, held tight 1, not failed 1 (12) |
| XAU VWAP | 10 | above 5, rising 3, extension ≤ 0.75 ATR 2 (10) |
| DXY | 14 | (D₁ 5 + D₂ 5 + D₃ 4) × corrFactor (14) |
| COMEX GC | 8 | 2 per confirmation (8) |
| Rates | 8 | real yield falling 5, nominal falling 3 (8) |
| VIX | 4 | supportive 4, neutral 2, unsupportive 0 (4) |
| Pivot structure | 8 | valid 5, strict 3 (8) |
| Third touch | 7 | touch 4, candidate HL 3 (7) |
| Rejection + micro | 7 | body/CLV 4, wick 1, volume strength 2 (7) |

Threshold: **80** by default; research 75 / 80 / 85 / 90. A disabled block is
removed from **both** the numerator and the denominator, so the threshold keeps
its meaning under ablation.

Grades (S56): `A` ≥ 80 with all mandatory conditions; `A+` ≥ 85 with strict
structure, ORB acceptance, GC confirmation, normal volatility and ≥ 1.5R
clearance; `A++` ≥ 90 with DXY 3/3, supportive rates, GC confirmation, an ideal
session model, a strong rejection wick, no blackout, normal execution and ≥ 2R
clearance.

---

## 15. Final entry equation (S55, S82)

```
TechnicalValid   = GoldBull ∧ SessionBull ∧ ORBAccepted ∧ AboveVWAP ∧ VWAPRising
                 ∧ ExtensionOK ∧ PivotStructure ∧ TrendlineValid ∧ Touch₃
                 ∧ Rejection
IntermarketValid = DXYScore ≥ 2 ∧ GCConfirmCount ≥ 2
ExecutionValid   = VolatilityNormal ∧ SpreadAcceptable ∧ RoomR ≥ 1.5
                 ∧ StopDistanceValid ∧ ¬NewsBlackout
RiskValid        = SizeValid ∧ DailyLimitClear ∧ TotalLimitClear ∧ TradeSlotFree

ARMED = TechnicalValid ∧ IntermarketValid ∧ ExecutionValid ∧ RiskValid
      ∧ Score ≥ threshold ∧ InEntryWindow ∧ Flat

LONG  = ARMED ∧ Price > ConfirmationLevel        (the resting stop order fills)
```

Volatility and news are unconditional: they are not ablated away in any preset,
because "the market is behaving abnormally" is a reason not to trade regardless
of which signal component is under test.

```
ATRShock = ATR₁₄ / median(ATR₁₄, 50)             require ≤ 1.75
```

Taking zero trades on any given day is a valid outcome (S84).
