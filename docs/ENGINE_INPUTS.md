# Engine inputs

The trading engine uses **only data points that score 10/10** against the
criteria below. Anything that falls short is either shown as labelled context
(never scored) or cut. This is a deliberately short list: every added input is
another chance to overfit, and the simple core of a multi-factor model tends to
carry most of its edge.

**What 10/10 means, and what it does not.** It means the input is sound, clean,
affordable, testable and used only in the role its evidence supports. It does
**not** mean the engine will make money. Every input still has to prove itself
in our own out-of-sample tests (the Lab), and published effects shrink after
publication, by about 58% on average (McLean & Pontiff 2016). Anything that
fails in the Lab is cut, including items on this list.

## The eight criteria

An input must meet **all eight** to be scored:

1. **Evidence.** Peer-reviewed, replicated evidence that it carries information
   for its role (or, for execution data, that it is the authoritative record).
2. **Point-in-time.** It can be stored as it was known then (filing date,
   release date, vintage), so a backtest never sees the future.
3. **Quality.** Official or exchange-licensed source, checked by the
   validation gate, with failures detected rather than silently absorbed.
4. **Timeliness fits the role.** Its delay is irrelevant at the horizon it is
   used for (swing trades: days to weeks).
5. **Affordable.** Fits the $150–300/month budget.
6. **Testable.** Enough history and events to validate out of sample here.
7. **Correct role.** Used only as what the evidence supports: gate, ranker,
   entry timing, tilt, veto, risk sizing or trade expression.
8. **Licensed for this use.** Personal use, no redistribution.

## The inputs (all 10/10)

| # | Input | Source · cost | Role in the engine | Evidence | Phase |
|---|---|---|---|---|---|
| 1 | **Survivorship-free daily prices**, split- and dividend-adjusted, with delisted stocks and historical index membership | Norgate Platinum · ~$53/mo | The foundation. Every price signal below is derived from it, and it is what makes backtests honest | Delisting bias distorts results that ignore dead stocks (Shumway 1997) | V1 |
| 2 | **Real-time consolidated quotes and minute bars** (SIP), plus order routing | Alpaca Algo Trader Plus · $99/mo | Execution only: entry timing, live stops, fills, paper and live trading. Never a signal | SIP is the official consolidated tape of all US exchanges | V1 |
| 3 | **Trend** (time-series momentum): price vs its 10-month / 200-day average, 12-month return sign | Derived from 1 | **Gate**: new longs only when the S&P 500 is in an uptrend; per-stock trend filter | Moskowitz, Ooi & Pedersen 2012; Hurst, Ooi & Pedersen 2017 (a century of evidence); Faber 2007 | V1 |
| 4 | **Relative strength**: 12-month return skipping the latest month, for sectors and stocks | Derived from 1 | **Ranker**: trade the leaders. Scaled down when momentum volatility rises, which protects against momentum crashes | Jegadeesh & Titman 1993; industry momentum, Moskowitz & Grinblatt 1999; crash control, Barroso & Santa-Clara 2015 and Daniel & Moskowitz 2016 | V1 |
| 5 | **Short-term pullback**: 1-week to 1-month decline inside a long-term uptrend | Derived from 1 | **Entry timing** for names already chosen by 3 and 4. The Lab compares it with simply buying at once | Short-term reversal, Jegadeesh 1990 and Lehmann 1990 | V1 |
| 6 | **Volatility**: ATR and realised volatility | Derived from 1 | **Risk**: position size, stop distance, portfolio heat | Volatility clusters, so recent volatility predicts near-term volatility (Engle 1982); volatility-managed exposure, Moreira & Muir 2017 | V1 |
| 7 | **Scheduled event calendar**: FOMC, CPI, jobs report, PCE, and each company's earnings dates | Fed / BLS / BEA published schedules; past earnings dates from SEC 8-K Item 2.02 · free | **Veto**: no new entries into a known binary event inside the holding window | A large share of the equity premium arrives on scheduled announcement days (Savor & Wilson 2013, 2016; Lucca & Moench 2015) | V1 |
| 8 | **Fundamental quality**: F-score, profitability, earnings-manipulation flags | SEC XBRL filings · free · already built | **Veto**: no trades in the weakest-quality names | Piotroski 2000; Novy-Marx 2013; Beneish, Lee & Nichols 2013 | Built |
| 9 | **Insider open-market purchases** (Form 4), buys only, opportunistic insiders only | SEC EDGAR · free · already ingested | **Tilt**: a small bonus. Absence is neutral, and sales are ignored | Lakonishok & Lee 2001; Cohen, Malloy & Pomorski 2012 | V1 |
| 10 | **Implied volatility and IV rank** | Alpaca OPRA (live) + Massive options history · $29–79/mo | **Expression**: shares or a spread, never direction. High IV rank means no long premium | Implied volatility exceeds realised volatility on average (variance risk premium, Carr & Wu 2009); retail overpays for it (de Silva, Smith & So 2026) | V2 |
| 11 | **Customer–supplier links**, dated, from 10-K major-customer disclosures | SEC EDGAR · free | **Lead-lag**: find linked stocks that have not yet reacted to news. It does not confirm trades | Cohen & Frazzini 2008; Menzly & Ozbas 2010 | V2 |

**Monthly cost:** V1 about **$152** (Alpaca + Norgate, everything else free).
V2 about **$181–231** with options history. Both are inside the budget.

## How they combine on a trade card

- **Gates and vetoes (pass/fail, never points):** the trend gate (3), the event
  veto (7) and the quality veto (8). If any fails, there is no trade, whatever
  the score.
- **Score (0–100):** trend strength (3), relative strength (4), pullback entry
  (5) and ecosystem lead-lag (11, from V2). Every component is shown, with
  equal weights until the Lab shows that different weights hold up out of
  sample (DeMiguel, Garlappi & Uppal 2009).
- **Tilt:** insider buying (9) adds a small bonus. Its absence costs nothing.
- **Size:** volatility (6) sets shares and stop distance, subject to the
  portfolio heat cap.
- **Expression:** IV rank (10) chooses shares or a spread.

## Where the existing scores stand

The research platform predates this list, so not everything already built
complies yet:

- **Trade Setup score (built): does not comply yet.** It uses RSI, MACD and
  52-week range position alongside trend, relative strength, volatility and
  insider data. RSI, MACD and 52-week position are not on the list. V1
  replaces this score with one built only from inputs 3–6 and 9, and the site
  labels the current one as legacy until then.
- **Investment Quality score (built): a research view, not a trade input.**
  Only its F-score, profitability and Beneish parts feed the engine, as the
  quality veto (8). Its DCF and growth parts stay in the research report.
- **Confidence score (built): complies.** It measures data coverage and
  freshness, not market direction.

## Shown as context, never scored

These are displayed, clearly labelled, because a person reading the market
should see them. None of them can move a score.

| Input | Why it is not 10/10 |
|---|---|
| Market breadth (% above averages, advance/decline) | No strong peer-reviewed evidence that it adds information beyond index trend. It is a Lab candidate, and it enters the score only if it earns it |
| Macro regime (yield curve, credit spreads, Sahm rule, inflation) | Forecasts recessions, not tradable timing, and about a dozen recessions cannot validate a rule. The existing regime classifier already treats it this way |
| Prediction-market odds (Kalshi, Polymarket) | Accurate expectations (Diercks, Katz & Wright 2026), but far too little history to test as an engine input |
| VIX | Realised volatility (6) already does the sizing job, with better evidence |
| Dollar, oil, gold, crypto | No evidence that they time equity trades at this horizon |
| News headlines | Worth reading. LLM-scored sentiment cannot be backtested honestly, because the model already knows what happened next (Glasserman & Lin 2023) |
| Congressional disclosures | No outperformance, 2012–2020 (Belmont et al. 2022). Already firewalled from every score in code |

## Cut

| Input | Reason |
|---|---|
| Earnings surprise / post-earnings drift | Gone in large caps since 2006 (Martineau 2022) |
| Analyst estimate revisions | Point-in-time history is far outside the budget |
| Unusual options flow | The documented effect needs non-public data on who opened each trade (Pan & Poteshman 2006) |
| Dark-pool / ATS volume | Published 2–4 weeks late |
| 13F holdings | Up to 45 days late |
| ETF flows | No reliable, affordable, point-in-time source |
| Social sentiment (X, StockTwits) | The best-known result did not replicate (Lachanski & Pav 2017); X is pay-per-read |
| Chart-image pattern recognition | Adds nothing that the price data itself does not carry |
| EIA inventories, CME FedWatch | Not equity-timing inputs; FedWatch is redundant with free sources |
| Yahoo / YFinance, free Alpha Vantage, NewsAPI, Marketstack, Bloomberg, Reuters | Unreliable, redundant with 1–2, or far outside the budget |

## Candidate under review

**Short interest** has strong evidence: heavily shorted stocks underperform
(Asquith, Pathak & Ritter 2005), and aggregate short interest predicts market
returns (Rapach, Ringgenberg & Zhou 2016). It is **not** on the list yet,
because I have not verified that affordable point-in-time history exists for
the full backtest period. It joins as input 12 only if that checks out.

## References

- Asquith, Pathak & Ritter (2005), *Journal of Financial Economics*
- Barroso & Santa-Clara (2015), *Journal of Financial Economics*
- Beneish, Lee & Nichols (2013), *Financial Analysts Journal*
- Belmont, Sacerdote, Sehgal & Van Hoek (2022), *Journal of Public Economics*
- Carr & Wu (2009), *Review of Financial Studies*
- Cohen & Frazzini (2008), *Journal of Finance*
- Cohen, Malloy & Pomorski (2012), *Journal of Finance*
- Daniel & Moskowitz (2016), *Journal of Financial Economics*
- de Silva, Smith & So (2026), *Review of Finance*
- DeMiguel, Garlappi & Uppal (2009), *Review of Financial Studies*
- Diercks, Katz & Wright (2026), Federal Reserve FEDS Working Paper 2026-010
- Engle (1982), *Econometrica*
- Faber (2007), *Journal of Wealth Management*
- Glasserman & Lin (2023), SSRN working paper
- Hurst, Ooi & Pedersen (2017), *Journal of Portfolio Management*
- Jegadeesh (1990), *Journal of Finance*
- Jegadeesh & Titman (1993), *Journal of Finance*
- Lachanski & Pav (2017), *Econ Journal Watch*
- Lakonishok & Lee (2001), *Review of Financial Studies*
- Lehmann (1990), *Quarterly Journal of Economics*
- Lucca & Moench (2015), *Journal of Finance*
- Martineau (2022), *Critical Finance Review*
- McLean & Pontiff (2016), *Journal of Finance*
- Menzly & Ozbas (2010), *Journal of Finance*
- Moreira & Muir (2017), *Journal of Finance*
- Moskowitz & Grinblatt (1999), *Journal of Finance*
- Moskowitz, Ooi & Pedersen (2012), *Journal of Financial Economics*
- Novy-Marx (2013), *Journal of Financial Economics*
- Pan & Poteshman (2006), *Review of Financial Studies*
- Piotroski (2000), *Journal of Accounting Research*
- Rapach, Ringgenberg & Zhou (2016), *Journal of Financial Economics*
- Savor & Wilson (2013), *Journal of Financial and Quantitative Analysis*
- Savor & Wilson (2016), *Journal of Finance*
- Shumway (1997), *Journal of Finance*
