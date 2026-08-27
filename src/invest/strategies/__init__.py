"""Trading-strategy models that can be simulated bar-by-bar.

These are *logic* models. They exist so a rule set written for a charting
platform can be executed here, deterministically, against bars we control —
which is how you find out what the rules actually do before risking money on
them.

A simulation over constructed bars proves behaviour, never profitability. The
platform rule that nothing is fabricated applies with full force: no result
from this package may be presented as a performance record.
"""
