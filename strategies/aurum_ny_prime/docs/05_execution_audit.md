# F · Execution audit

What a fill actually costs, what the backtest assumes, and where the assumption
could be wrong. S27 and S79.

The short version: **Pine has no bid/ask.** There is no realtime spread filter
in this script and there cannot be one. Everything below is either a modelled
cost or a tester setting, and the two are kept apart deliberately.

---

## 1. The spread filter that does not exist

S27 asks for `Spread = Ask − Bid`, normalised by ATR, where reliable realtime
bid/ask is available. Pine Script exposes no bid or ask, historically or in real
time. A script claiming a spread filter would be reporting a number it invented.

So the strategy separates two things that are easy to conflate:

| Label | What it is | Where it lives |
|---|---|---|
| `REALTIME_SPREAD_FILTER` | reject a fill when the live spread is too wide | **NOT IN PINE.** Must be enforced by the execution bridge / EA / manual trader |
| `BACKTEST_MODELLED_COST` | a configured spread, slippage and commission used in sizing and stop buffers | `i_spreadUSD`, `i_slipUSD`, `i_commUnit` |

The dashboard row is labelled `Spread … MODELLED` for this reason, and the
export column is named `modeled_spread`. The gate
`modelled spread / ATR ≤ 0.20` is a **static sanity check on the assumption**,
not a measurement: it stops the strategy trading when ATR has collapsed so far
that the assumed spread is a large fraction of the range.

**What to do about it in deployment.** Enforce the real filter at the point of
execution: if the live spread exceeds the modelled value used in the backtest,
skip the trade. If that happens often, the backtest's cost assumption was wrong
and the results need re-deriving, not overriding.

---

## 2. Cost model used inside the strategy

```
CostPerUnit = (spread + slippage) · USDperPoint + commission
RiskPerUnit = R · USDperPoint + CostPerUnit
StopBuffer  = max(0.10 · ATR, spread + slippage)
BreakevenPx = Entry + spread + slippage + commission/USDperPoint
```

Defaults, for a retail XAUUSD account:

| Component | Default | Basis |
|---|---|---|
| Spread | 0.30 (30 cents/oz) | typical NY-session raw-spread gold; verify against your broker |
| Slippage | 0.10 per side | stop orders on 5m gold in the first NY hour |
| Commission | 0.07 USD/oz round turn | $7 per 100 oz (1.00 lot) |

Three consequences worth naming:

* The stop buffer is **floored at the cost of trading**, so a structural stop is
  never placed inside the spread.
* Costs enter `RiskPerUnit`, so the position is sized on total risk, not just
  the price distance. A trade risking $500 risks $500 including costs.
* Breakeven is genuinely breakeven — it clears the round trip. Moving to
  "breakeven" at the entry price is a small guaranteed loss.

---

## 3. Strategy Properties — required settings

Pine forbids inputs in the `strategy()` declaration, so commission and slippage
must be set in the Strategy Properties panel. A backtest run without these is
not a backtest of this strategy.

| Property | Value | Why |
|---|---|---|
| Initial capital | 100,000 | must match `i_acctSize`; the dashboard shows `⚠capital` if it does not |
| Base currency | USD | |
| Order size | *ignored* — the script passes explicit `qty` | sizing is the strategy's job (S47) |
| Commission | 0.07 USD per contract (per oz) | matches `i_commUnit` |
| Slippage | 2–4 ticks | on a 0.01 tick, 2 ticks = 0.02; combine with the modelled slippage in sizing |
| Recalculate after order is filled | off | |
| Recalculate on every tick | off | |
| **Bar Magnifier** | **ON** | S79 |
| Fill orders on bar close | off | |

**Bar Magnifier matters more here than in most strategies**, because a position
can carry three exit legs and a trailing stop at once. Without it the emulator
resolves an entire 5-minute bar with one assumption about intrabar order, and
days where the target and the stop are both inside one bar are scored by that
assumption rather than by what happened.

---

## 4. Order mechanics

**Entry.** A stop order at `ConfirmationLevel + tick`, submitted at the close of
the arm bar, cancelled after 2 bars if unfilled. A stop order cannot fill better
than its trigger, so gap risk is one-directional and against the strategy — the
honest direction.

**Brackets.** `strategy.exit` legs are submitted **while the entry order is
still working**, so the position is protected from the instant it fills rather
than from the next bar's evaluation. Each of the three legs carries its own stop
at the same price, so a stop-out closes the whole position.

**Exit ids are never re-issued after filling.** Calling `strategy.exit("TP1", …)`
again after TP1 has filled would place a *new* order for that quantity against
the remainder, silently double-reducing the position. `tp1Done`/`tp2Done` guard
against it, and a test asserts the guards are present.

**Time stop.** `strategy.close_all()` at 12:00 ET (16:00 in runner mode). A
market close at a fixed time is realistic and is what a prop trader actually
does.

---

## 5. Contract specification — verify before deployment

The defaults describe XAUUSD quoted per ounce, where one chart unit is one
ounce:

| Quantity | Default | Verify against |
|---|---|---|
| USD per 1.00 price move, per unit | 1.0 | broker contract spec |
| Unit step | 1.0 oz (= 0.01 lot × 100 oz) | minimum lot step |
| Minimum units | 1.0 | minimum lot |
| Units per lot | 100 | contract size |
| Tick size | `syminfo.mintick` | feed |

If the broker's minimum lot is 0.10 rather than 0.01, `i_unitMin` becomes 10 and
small accounts will fail `sizeOK` on wide stops — correctly. The strategy
declines the trade instead of over-risking, and the reason appears as
`NO TRADE — INVALID POSITION SIZE`.

**Sizing arithmetic worked through**, $100k account, 0.50% risk, $2.10 stop:

```
RiskBudget  = min(100,000 × 0.005, 1,000)          = 500.00 USD
CostPerUnit = (0.30 + 0.10) × 1.0 + 0.07           =   0.47 USD/oz
RiskPerUnit = 2.10 × 1.0 + 0.47                    =   2.57 USD/oz
Units       = floor(500 / 2.57)                    = 194 oz = 1.94 lots
Actual risk = 194 × 2.57                           = 498.58 USD  ≤ 500 ✓
```

Rounding down costs at most one unit of risk and never breaches the budget. A
test asserts both halves of that claim.

---

## 6. What the backtest still cannot model

Stated rather than hidden:

* **Weekend and news gaps.** A stop can be jumped. The strategy flattens before
  the close and blacks out scheduled events, which reduces exposure but does not
  eliminate it.
* **Requotes and rejections.** No retail simulation models a broker declining a
  fill in fast conditions.
* **Variable spread.** The model is a constant. Real gold spreads widen
  dramatically around 08:30 ET releases — which is precisely why the news
  blackout exists and why it must be populated.
* **Swap/financing.** Irrelevant for an intraday strategy that is flat by 12:00
  ET, and it becomes relevant the moment runner mode is enabled.
* **Slippage on the trailing stop.** Modelled as a constant; in a fast reversal
  it is worse.

Every one of these makes real results **worse** than the backtest, not better.
That asymmetry is deliberate: where a modelling choice was available, the
pessimistic one was taken.
