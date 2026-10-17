#!/usr/bin/env bash
# PreToolUse hook. See CLAUDE.md: nothing from this repository may touch the
# Referai project (the owner's primary app, same Google account).
#
# Blocks:
#  - any connector (MCP) call that mentions Referai
#  - any shell command that runs a Google/Firebase CLI (firebase, gcloud,
#    flutterfire, gsutil, bq) with Referai anywhere in the command
input="$(cat)"
tool="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)"
lower="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

block() {
  echo "Blocked: this action targets Referai. Chefii work must never touch the Referai project (see CLAUDE.md). Ask the owner first." >&2
  exit 2
}

case "$lower" in *referai*) ;; *) exit 0 ;; esac

if [[ "$tool" == mcp__* ]]; then block; fi
if printf '%s' "$lower" | grep -Eq '(^|[^a-z0-9_./-])(npx +)?(firebase|gcloud|flutterfire|gsutil|bq)( |$)'; then block; fi
exit 0
