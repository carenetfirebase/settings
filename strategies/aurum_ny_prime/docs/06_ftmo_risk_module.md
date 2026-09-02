# G · FTMO risk module

The evaluation is not passed by making money. It is passed by making 10% before
losing 5% in a day or 10% in total. Those are different problems, and the second
one is the constraint. S67 states it plainly: the primary metric is
`P(pass before failure)`, not net profit.

Everything in this module is an input, because FTMO changes its rules and a
strategy with the 2024 numbers welded into it is a liability (S5).

---

## 1. Limits, as configured

| Rule | Input | Default | Modelled how |
|---|---|---|---|
| Maximum daily loss | `i_ftmoDaily` | 5% | against `dayStartEquity`, including floating P/L |
| Maximum total loss | `i_ftmoMax` | 10% | against the static account size |
| Phase 1 target | `i_ftmoTgt1` | 10% | equity, including floating P/L |
| Verification target | `i_ftmoTgt2` | 5% | " |
| Minimum trading days | `i_minDays` | 4 | days with at least one fill |
| Daily reset time | `i_dayReset` | 00:00 ET | set to the firm's server midnight expressed in ET |

`strategy.equity` includes open positions, so a floating drawdown counts against
the daily limit exactly as it does at the firm. A strategy that measures the
daily limit against realised P/L only will pass a backtest and fail an
evaluation.

---

## 2. Internal limits — the ones that actually bind

The firm's limits are a cliff. The strategy operates well inside them, so the
cliff is never approached in normal operation.

| Internal rule | Default | Firm equivalent | Ratio |
|---|---|---|---|
| Risk per trade | 0.50% | — | — |
| Absolute maximum risk | 1.00% | — | — |
| Hard risk cap | $1,000 | — | — |
| Daily loss stop | −1.50% | −5% | 3.3× headroom |
| Trades per day | 1 (2 conditionally) | — | — |

At 0.50% risk and one trade a day, the internal daily stop can only be reached
by a trade that loses about three times its intended risk — which means a gap,
not a normal stop-out. The lock is a circuit breaker for the abnormal case, not
a routine event.

**Risk never increases after a loss.** There is no martingale, no recovery
sizing, no "make it back" mode. `RiskBudget` is a function of current equity and
the schedule only, so it falls after a drawdown and rises only after equity
recovers.

---

## 3. Risk schedule near the target (S8)

```
gain% < 5      →  0.50%
5 ≤ gain% < 8  →  0.40%
8 ≤ gain% < 9  →  0.25%
gain% ≥ 9      →  0.15%
```

At +9% on a $100k account the strategy is risking $150 to make the last $1,000.
It will take longer. That is the point: at +9% the expected value of *finishing*
dominates the expected value of the next trade. The objective near completion is
to protect the pass.

When the target is reached, `hardStop` engages and no further trades are taken
in FTMO modes. The dashboard shows `NO TRADE — TARGET REACHED`. There is no
reason to hold risk in an account whose job is done.

---

## 4. Lockouts and the kill switch

| Trigger | Effect | Reset |
|---|---|---|
| Internal daily stop (−1.50%) | no new trades today | next daily boundary |
| FTMO daily limit (−5%) | no new trades today | next daily boundary |
| FTMO max loss (−10%) | no new trades at all | manual |
| Target reached | no new trades at all | manual (phase complete) |
| Drawdown kill switch | no new trades at all | manual review |
| Data feed stale/missing | no new trades | when the feed recovers |
| First trade won to TP1 | no new trades today | next day |

**The drawdown kill switch is off by default and must be set from evidence**
(S76). Run the Monte Carlo, take the 95th-percentile drawdown, put that number
in `i_ddKill`:

```
python -m validation.aurum_validate montecarlo trades.csv --paths 10000
  ...
  max drawdown  median 1,580   95th 3,908
```

A drawdown beyond the validated 95th percentile means the live distribution is
not the tested distribution. Stopping is the correct response; re-optimising is
not (S75).

---

## 5. Trade frequency rules

**One trade per day by default** (S51). A second is permitted only when all four
hold:

1. the first trade lost;
2. score ≥ 90 (raised from 80);
3. risk ≤ 0.25% (halved);
4. a pivot low has confirmed **after** the previous entry's pivot pair.

Condition 4 is the deterministic reading of "genuinely new setup". Without it,
"second trade" degrades into "re-enter the trade that just stopped out", which
is how a 0.5% day becomes a 1.5% day.

**Stop after a good morning** (S52). If the first trade reaches TP1 and closes
net-positive, trading stops for the day. This costs expectancy in a naive
accounting — some of those forgone trades would have won. It buys variance
reduction, and variance is what fails evaluations. The switch exists so the
trade-off can be *measured* rather than assumed: run it both ways and compare
`P(pass)`, not net profit.

---

## 6. Simulating the evaluation (S65, S66)

Pass probability is estimated externally, because it depends on path order and
Pine cannot resample paths.

```
python -m validation.aurum_validate montecarlo trades.csv \
    --paths 10000 --blocks 3,5,10 \
    --account 100000 --target 10 --daily-loss 5 --max-loss 10 --min-days 4
```

Three modelling decisions:

**The resampling unit is a trading day, not a trade.** Trades within a day share
a regime and are not independent.

**Days are drawn in blocks.** Losses cluster; a regime that breaks the setup
breaks it for days. Moving-block resampling with a default block of 5 trading
days keeps runs intact. Blocks of 3, 5 and 10 are all reported — if the answer
moves a lot with block length, the clustering is doing real work and the
smallest block is the least trustworthy number.

**Floating loss is modelled from MAE.** Each trade's worst excursion is applied
to running equity before its result, so a day that dipped 5.2% and recovered is
scored as a breach. When the export has no MAE column the tool says so and
labels the resulting failure probability as understated.

Reported: `P(pass)`, `P(daily-loss failure)`, `P(max-loss failure)`,
`P(no result within horizon)`, median and 95th-percentile days to pass, and the
drawdown distribution.

---

## 7. Choosing between configurations

Rank by `P(pass before failure)`, subject to adequate expectancy, an adequate
sample, and acceptable drawdown. Do **not** rank by net profit (S67).

The two are not the same. A configuration that risks 1% and makes 14% has a
worse pass probability than one that risks 0.5% and makes 11%, because the
first spends more time near the cliff. The Monte Carlo prices that; the equity
curve does not.

---

## 8. Deployment checklist

- [ ] Strategy Properties initial capital equals `i_acctSize` (no `⚠capital`)
- [ ] Commission and slippage set per `05_execution_audit.md`
- [ ] Contract size, minimum lot, lot step and tick value verified against the
      broker (S47)
- [ ] Daily reset time set to the firm's server midnight expressed in ET
- [ ] Phase selected (Phase 1 or Verification) — they have different targets
- [ ] News calendar populated for the deployment period
- [ ] `i_ddKill` set from the validated 95th-percentile drawdown
- [ ] Forward test completed per `10_forward_testing_protocol.md`, with
      parameters unchanged throughout
