#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(dirname "$ROOT")"
clone() {
  local name="$1"
  if [[ -d "$PARENT/$name" ]]; then
    echo "exists: $PARENT/$name"
  else
    git clone "https://github.com/shulzpavel/$name.git" "$PARENT/$name"
  fi
}
clone planning-poker-jira-service
clone planning-poker-voting-service
clone planning-poker-web
clone planning-poker-python-lib
clone planning-poker-dev
