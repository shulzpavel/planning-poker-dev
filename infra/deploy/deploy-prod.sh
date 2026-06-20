#!/usr/bin/env bash
# Full-stack production deploy: rebuilds backend services AND web.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"
# shellcheck disable=SC1091
source "$ROOT_DIR/infra/deploy/deploy-notify.sh"

SERVICES=(voting-service jira-service web)

cd "$ROOT_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE in $ROOT_DIR" >&2
  exit 1
fi

deploy_notify_load_env "$ROOT_DIR"

DEPLOY_SCOPE="full stack"
export DEPLOY_SCOPE
DEPLOY_SERVICES_BLOCK="$(deploy_notify_format_services "$ROOT_DIR" "${SERVICES[@]}")"
export DEPLOY_SERVICES_BLOCK

notify_failure() {
  local exit_code=$?
  deploy_maintenance_disable "$ROOT_DIR" "$COMPOSE_FILE" "$ENV_FILE"
  deploy_notify_send "FAILED" "Полный деплой (${SERVICES[*]}). Exit code: ${exit_code}" "$ROOT_DIR"
  exit "$exit_code"
}

trap notify_failure ERR

deploy_acquire_lock "$ROOT_DIR"

deploy_notify_send "STARTED" "Полный деплой: ${SERVICES[*]}." "$ROOT_DIR"

echo "Pulling latest main from all microservice repos..."
"$ROOT_DIR/infra/deploy/pull-all.sh"

DEPLOY_SERVICES_BLOCK="$(deploy_notify_format_services "$ROOT_DIR" "${SERVICES[@]}")"
export DEPLOY_SERVICES_BLOCK

deploy_maintenance_enable "$ROOT_DIR" "full stack" "$COMPOSE_FILE" "$ENV_FILE"

echo "Building images: ${SERVICES[*]}..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build "${SERVICES[@]}"

echo "Restarting containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "${SERVICES[@]}"

echo "Waiting for voting-service health..."
for attempt in $(seq 1 30); do
  status="$(docker inspect --format '{{.State.Health.Status}}' voting-service 2>/dev/null || echo unknown)"
  if [[ "$status" == "healthy" ]]; then
    echo "voting-service is healthy."
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    echo "voting-service did not become healthy in time (status: $status)" >&2
    exit 1
  fi
  sleep 5
done

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps "${SERVICES[@]}"

echo "Reloading caddy (Caddyfile is bind-mounted from the host)..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --force-recreate caddy

deploy_maintenance_disable "$ROOT_DIR" "$COMPOSE_FILE" "$ENV_FILE"

deploy_notify_send "OK" "Образы собраны, контейнеры перезапущены, health-check пройден." "$ROOT_DIR"
echo "Done."
