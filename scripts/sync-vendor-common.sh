#!/usr/bin/env bash
# Keep vendored planning_poker_common identical in jira-service and voting-service.
#
# Usage:
#   ./scripts/sync-vendor-common.sh
#   SRC=../planning-poker-voting-service/vendor/planning-poker-common ./scripts/sync-vendor-common.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(dirname "$ROOT")"
SRC="${SRC:-$PARENT/planning-poker-jira-service/vendor/planning-poker-common}"

if [[ ! -d "$SRC/planning_poker_common" ]]; then
  echo "error: planning_poker_common not found under $SRC" >&2
  echo "Edit vendor/ in one backend service, then run with SRC pointing at that copy." >&2
  exit 1
fi

for svc in planning-poker-jira-service planning-poker-voting-service; do
  dest="$PARENT/$svc/vendor/planning-poker-common"
  mkdir -p "$dest"
  rm -rf "$dest/planning_poker_common"
  cp -R "$SRC/planning_poker_common" "$dest/"
  if [[ -f "$SRC/pyproject.toml" ]]; then
    cp "$SRC/pyproject.toml" "$dest/"
  fi
  echo "synced -> $dest"
done

echo "Done. Run make backend-test from planning-poker-dev to verify."
