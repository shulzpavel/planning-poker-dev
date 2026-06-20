#!/usr/bin/env bash
# Deploy a single production service and notify Telegram with repo + commit.
set -euo pipefail

SERVICE="${1:-}"
if [[ -z "$SERVICE" ]]; then
  echo "Usage: $0 <jira-service|voting-service|web>" >&2
  exit 1
fi

case "$SERVICE" in
  jira-service|voting-service|web) ;;
  *)
    echo "Unsupported service: $SERVICE" >&2
    exit 1
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env"
# shellcheck disable=SC1091
source "$ROOT_DIR/infra/deploy/deploy-notify.sh"

cd "$ROOT_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE in $ROOT_DIR" >&2
  exit 1
fi

deploy_notify_load_env "$ROOT_DIR"

REPO_NAME="$(deploy_notify_service_repo "$SERVICE")"
REPO_DIR="$(deploy_notify_service_repo_dir "$ROOT_DIR" "$SERVICE")"

DEPLOY_SERVICE="$SERVICE"
DEPLOY_SCOPE="single service"
export DEPLOY_SERVICE DEPLOY_SCOPE

notify_failure() {
  local exit_code=$?
  deploy_maintenance_disable "$ROOT_DIR" "$COMPOSE_FILE" "$ENV_FILE"
  deploy_notify_send "FAILED" "Сервис: ${SERVICE}. Exit code: ${exit_code}" "$ROOT_DIR"
  exit "$exit_code"
}

trap notify_failure ERR

deploy_acquire_lock "$ROOT_DIR"

echo "Updating deploy scripts from planning-poker-dev..."
deploy_sync_repo_main "$ROOT_DIR"

deploy_notify_send "STARTED" "Сборка и перезапуск ${SERVICE}." "$ROOT_DIR"

echo "Pulling ${REPO_NAME}..."
deploy_sync_repo_main "$REPO_DIR"

deploy_maintenance_enable "$ROOT_DIR" "$SERVICE" "$COMPOSE_FILE" "$ENV_FILE"

echo "Building ${SERVICE}..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build "$SERVICE"

echo "Restarting ${SERVICE}..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "$SERVICE"

if [[ "$SERVICE" == "voting-service" || "$SERVICE" == "jira-service" ]]; then
  echo "Waiting for ${SERVICE} health..."
  for attempt in $(seq 1 30); do
    status="$(docker inspect --format '{{.State.Health.Status}}' "$SERVICE" 2>/dev/null || echo unknown)"
    if [[ "$status" == "healthy" ]]; then
      echo "${SERVICE} is healthy."
      break
    fi
    if [[ "$attempt" -eq 30 ]]; then
      echo "${SERVICE} did not become healthy in time (status: $status)" >&2
      exit 1
    fi
    sleep 5
  done
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps "$SERVICE"

deploy_maintenance_disable "$ROOT_DIR" "$COMPOSE_FILE" "$ENV_FILE"

deploy_notify_send "OK" "Образ собран, контейнер ${SERVICE} перезапущен." "$ROOT_DIR"
echo "Done."
