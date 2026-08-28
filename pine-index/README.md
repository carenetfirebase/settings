# Pine strategy shelf

A single self-contained HTML page indexing every TradingView (Pine Script v6)
strategy in this repository. Each entry expands to the complete, line-numbered
source, with a copy button for pasting into the TradingView Pine editor.

Open `strategies.html` in a browser — it needs no server and no build step.

## What it contains, and where each source came from

| Strategy | Branch | Path |
|---|---|---|
| AURUM-NY PRIME v2.0 | `claude/aurum-ny-prime-pinescript-f75vws` | `strategies/aurum_ny_prime/AURUM_NY_PRIME.pine` |
| CYBER MCGIVER v7 | `claude/aurum-ny-prime-pinescript-f75vws` | `strategies/cyber_mcgiver/CYBER_MCGIVER_v7.pine` |
| CYBER MCGIVER v6 (baseline) | `claude/aurum-ny-prime-pinescript-f75vws` | `strategies/cyber_mcgiver/baseline/CYBER_MCGIVER_v6_BASELINE.pine` |
| CYBER MCGIVER v1.0 | `claude/responsiveness-issue-4mdsqx` | `strategies/cyber_mcgiver/CYBER_MCGIVER.pine` |
| XAUUSD 08:30 NY ORB 1m v2.0 | `claude/pinescript-daily-1m-orb-lezvd3` | `pine/XAUUSD_0830_NY_ORB_1m_v2.pine` |
| XAUUSD 08:30 NY ORB v1.0 | `claude/pinescript-daily-1m-orb-lezvd3` | `pine/XAUUSD_0830_NY_ORB_v1_original.pine` |

The sources are embedded verbatim; the page is a reader, not a second copy to
edit. Change a strategy on its own branch, then regenerate this page.

Not included: the "ORB scalp strategy Pine Script review" script, which was
delivered as a download and whose branch was never pushed. It is not in git.
