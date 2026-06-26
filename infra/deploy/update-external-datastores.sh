#!/usr/bin/env bash
# Point voting-service at external Postgres (CNPG) and Redis; recreate service.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"

cd "$ROOT_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

POSTGRES_DSN="${POSTGRES_DSN:-}"
REDIS_URL="${REDIS_URL:-}"

if [[ -z "$POSTGRES_DSN" || -z "$REDIS_URL" ]]; then
  echo "Set POSTGRES_DSN and REDIS_URL in the environment before running." >&2
  exit 1
fi

backup="${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$ENV_FILE" "$backup"
echo "Backup: $backup"

upsert_env() {
  local key="$1"
  local value="$2"
  python3 - "$key" "$value" "$ENV_FILE" <<'PY'
import pathlib
import sys

key, value, path = sys.argv[1:4]
lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
out = []
found = False
for line in lines:
    if line.startswith(f"{key}="):
        out.append(f"{key}={value}")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={value}")
pathlib.Path(path).write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

upsert_env POSTGRES_DSN "$POSTGRES_DSN"
upsert_env REDIS_URL "$REDIS_URL"

echo "Updated POSTGRES_DSN and REDIS_URL in $ENV_FILE"

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --force-recreate voting-service
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps voting-service

echo "Done."
