#!/usr/bin/env bash
# The four quality gates from CLAUDE.md, in order. All must pass before any
# phase is called done.
set -uo pipefail
fail=0
run() { echo "=== $1 ==="; shift; "$@" || fail=1; echo; }
run "ruff format" uv run ruff format --check .
run "ruff check"  uv run ruff check .
run "mypy"        uv run mypy src/imt
run "pytest"      uv run pytest -q
run "frontend"    bash -c "cd frontend && npx vitest run"
exit $fail
