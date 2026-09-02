"""Validation tooling for CYBER MCGIVER v7.

`pine_lint` checks the Pine source statically. `synthetic` generates XAUUSD-like
15-minute bars. `reference` is the engine written a second time, in Python, from
the same rules, so the candidate logic can be executed and counted outside
TradingView. `frequency` runs the two together and prints the funnel.

Nothing here is a backtest. See docs/03_what_the_synthetic_run_proves.md.
"""
