# Example output — synthetic world

A full `phase0` run against `phase0.synthetic`, committed to show the shape of
the Phase 0 deliverable.

**Nothing here is a measurement of gold.** Every number is a property of the
generator in `phase0/synthetic.py`. The report says so on its first screen, the
constants file is named `calibrated_constants.SYNTHETIC.json` rather than
`calibrated_constants.json`, and `python -m phase0.cli verify` refuses it.

Regenerate with:

    python -m phase0.cli run --synthetic --years 5 --out examples/synthetic

`panel.csv` and `panel.parquet` are written by that command and are not
committed — half a megabyte of synthetic rows is not worth versioning.
