#!/usr/bin/env bash
# Refuses any Firebase deploy that is not aimed at a Chefii project.
#
# Chefii shares a Google account with Referai, the owner's primary app.
# Deploying this repo to the wrong project would overwrite Referai's
# security rules, functions and hosting. This guard runs before every
# deploy target (see firebase.json "predeploy") and fails closed.
#
# Allowed: chefii, chefii-<suffix> (e.g. chefii-dev, chefii-prod, chefii-a1b2c), demo-chefii.
set -euo pipefail

project="${1:-${GCLOUD_PROJECT:-}}"
lower="$(printf '%s' "$project" | tr '[:upper:]' '[:lower:]')"

if [[ -z "$lower" ]]; then
  echo "BLOCKED: no Firebase project selected. Use: firebase deploy --project <chefii-project-id>" >&2
  exit 1
fi
if [[ "$lower" == *referai* ]]; then
  echo "BLOCKED: '$project' is the Referai project. Chefii must never be deployed there." >&2
  exit 1
fi
if [[ ! "$lower" =~ ^(chefii|chefii-[a-z0-9-]+|demo-chefii)$ ]]; then
  echo "BLOCKED: '$project' is not a Chefii project. Chefii deploys only to projects named chefii or chefii-*." >&2
  exit 1
fi
echo "Firebase project check passed: $project"
