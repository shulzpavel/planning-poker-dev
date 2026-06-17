#!/usr/bin/env bash
# Pull latest main from all Planning Poker microservice repos.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARENT_DIR="$(dirname "$ROOT_DIR")"

REPOS=(
  planning-poker-jira-service
  planning-poker-voting-service
  planning-poker-web
  planning-poker-dev
)

for repo in "${REPOS[@]}"; do
  dir="$PARENT_DIR/$repo"
  if [[ ! -d "$dir/.git" ]]; then
    echo "Missing git repo: $dir" >&2
    exit 1
  fi
  echo "Pulling $repo..."
  git -C "$dir" pull --ff-only origin main
done

echo "All repos updated."
