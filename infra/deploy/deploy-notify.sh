#!/usr/bin/env bash
# Shared Telegram deploy notifications. Source from deploy scripts.

deploy_sync_repo_main() {
  local repo_dir="${1:?repo dir required}"
  local repo_name
  repo_name="$(basename "$repo_dir")"

  if [[ ! -d "$repo_dir/.git" ]]; then
    echo "Missing git repo: $repo_dir" >&2
    return 1
  fi

  echo "Syncing ${repo_name} to origin/main..."
  git -C "$repo_dir" fetch --prune origin main
  git -C "$repo_dir" reset --hard origin/main
}

deploy_acquire_lock() {
  local root_dir="${1:?root dir required}"
  local lock_file="${root_dir}/.deploy.lock"
  exec {DEPLOY_LOCK_FD}>"$lock_file"
  if ! flock -w 900 "$DEPLOY_LOCK_FD"; then
    echo "Timed out waiting for deploy lock ($lock_file)" >&2
    return 1
  fi
}

deploy_notify_load_env() {
  local root_dir="${1:?root dir required}"
  local notify_file="${DEPLOY_NOTIFY_ENV_FILE:-$root_dir/.deploy.env}"

  DEPLOY_APP_NAME="${DEPLOY_APP_NAME:-Planning Poker}"
  DEPLOY_ENVIRONMENT="${DEPLOY_ENVIRONMENT:-production}"
  DEPLOY_DOMAIN="${DEPLOY_DOMAIN:-planning.shults-sync.com}"
  DEPLOY_TRIGGER="${DEPLOY_TRIGGER:-manual}"

  if [[ -f "$notify_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$notify_file"
    set +a
  fi
}

deploy_notify_html_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

deploy_notify_service_repo() {
  case "$1" in
    jira-service) echo "planning-poker-jira-service" ;;
    voting-service) echo "planning-poker-voting-service" ;;
    web) echo "planning-poker-web" ;;
    dev) echo "planning-poker-dev" ;;
    *) echo "$1" ;;
  esac
}

deploy_notify_service_repo_dir() {
  local root_dir="$1"
  local service="$2"
  local parent
  parent="$(dirname "$root_dir")"
  echo "$parent/$(deploy_notify_service_repo "$service")"
}

deploy_notify_service_sha() {
  local repo_dir="$1"
  git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

deploy_notify_short_trigger() {
  local trigger="$1"
  if [[ "$trigger" =~ ^github:([^@]+)@([0-9a-f]{7,40})$ ]]; then
    printf 'github:%s@%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]:0:7}"
    return
  fi
  if ((${#trigger} > 72)); then
    printf '%s…' "${trigger:0:71}"
    return
  fi
  printf '%s' "$trigger"
}

deploy_notify_format_services() {
  local root_dir="$1"
  shift
  local service repo_dir sha repo_name
  local lines=()

  for service in "$@"; do
    repo_dir="$(deploy_notify_service_repo_dir "$root_dir" "$service")"
    sha="$(deploy_notify_service_sha "$repo_dir")"
    repo_name="$(deploy_notify_service_repo "$service")"
    lines+=("• $(deploy_notify_html_escape "$service") — <code>$(deploy_notify_html_escape "$sha")</code>")
    lines+=("  $(deploy_notify_html_escape "$repo_name")")
  done

  local joined="" item
  for item in "${lines[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=$'\n'"$item"
    else
      joined="$item"
    fi
  done
  printf '%s' "$joined"
}

deploy_notify_post() {
  local text="$1"

  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    return 0
  fi

  DEPLOY_NOTIFY_TEXT="$text" TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID" python3 - <<'PY'
import json
import os
import sys
import urllib.request

text = os.environ["DEPLOY_NOTIFY_TEXT"]
payload = {
    "chat_id": os.environ["TELEGRAM_CHAT_ID"],
    "text": text,
    "parse_mode": "HTML",
    "disable_web_page_preview": True,
}
req = urllib.request.Request(
    f"https://api.telegram.org/bot{os.environ['TELEGRAM_BOT_TOKEN']}/sendMessage",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=20)
except Exception as exc:
    print(f"deploy_notify_post failed: {exc}", file=sys.stderr)
PY
}

deploy_maintenance_compose() {
  local root_dir="${1:?root dir required}"
  local compose_file="${2:-docker-compose.prod.yml}"
  local env_file="${3:-.env}"
  docker compose -f "$root_dir/$compose_file" --env-file "$root_dir/$env_file"
}

deploy_maintenance_enable() {
  local root_dir="${1:?root dir required}"
  local service="${2:?service required}"
  local compose_file="${3:-docker-compose.prod.yml}"
  local env_file="${4:-.env}"

  local payload
  payload="$(SERVICE="$service" python3 - <<'PY'
import json
import os

print(json.dumps({"active": True, "service": os.environ["SERVICE"]}, ensure_ascii=False))
PY
)"

  echo "Enabling maintenance banner for ${service}..."
  if ! deploy_maintenance_compose "$root_dir" "$compose_file" "$env_file" exec -T redis \
    redis-cli SET system:maintenance "$payload" EX 1800 >/dev/null; then
    echo "Warning: failed to enable maintenance banner in Redis" >&2
    return 0
  fi
}

deploy_maintenance_disable() {
  local root_dir="${1:?root dir required}"
  local compose_file="${2:-docker-compose.prod.yml}"
  local env_file="${3:-.env}"

  echo "Disabling maintenance banner..."
  deploy_maintenance_compose "$root_dir" "$compose_file" "$env_file" exec -T redis \
    redis-cli DEL system:maintenance >/dev/null 2>&1 || true
}

deploy_notify_send() {
  local status="$1"
  local details="$2"
  local root_dir="${3:-}"

  local icon title
  case "$status" in
    STARTED) icon="🚀"; title="Деплой запущен" ;;
    OK) icon="✅"; title="Деплой завершён" ;;
    FAILED) icon="❌"; title="Деплой упал" ;;
    *) icon="ℹ️"; title="Статус деплоя" ;;
  esac

  local app env domain host trigger safe_details scope dev_sha
  app="$(deploy_notify_html_escape "$DEPLOY_APP_NAME")"
  env="$(deploy_notify_html_escape "$DEPLOY_ENVIRONMENT")"
  domain="$(deploy_notify_html_escape "$DEPLOY_DOMAIN")"
  host="$(deploy_notify_html_escape "$(hostname)")"
  trigger="$(deploy_notify_html_escape "$(deploy_notify_short_trigger "$DEPLOY_TRIGGER")")"
  safe_details="$(deploy_notify_html_escape "$details")"
  scope="$(deploy_notify_html_escape "${DEPLOY_SCOPE:-}")"
  dev_sha="unknown"
  if [[ -n "$root_dir" ]]; then
    dev_sha="$(deploy_notify_html_escape "$(deploy_notify_service_sha "$root_dir")")"
  fi

  local text
  text="$(printf '%s <b>%s</b>\n' "$icon" "$title")"

  if [[ -n "${DEPLOY_SERVICE:-}" && -n "$root_dir" ]]; then
    local repo_dir sha repo_name
    repo_dir="$(deploy_notify_service_repo_dir "$root_dir" "$DEPLOY_SERVICE")"
    sha="$(deploy_notify_service_sha "$repo_dir")"
    repo_name="$(deploy_notify_service_repo "$DEPLOY_SERVICE")"
    text+=$'\n'"<b>Сервис:</b> $(deploy_notify_html_escape "$DEPLOY_SERVICE")"
    text+=$'\n'"<b>Репозиторий:</b> $(deploy_notify_html_escape "$repo_name")"
    text+=$'\n'"<b>Коммит:</b> <code>$(deploy_notify_html_escape "$sha")</code>"
  elif [[ -n "${DEPLOY_SERVICES_BLOCK:-}" ]]; then
    text+=$'\n\n'"<b>Сервисы:</b>"
    text+=$'\n'"${DEPLOY_SERVICES_BLOCK}"
  fi

  text+=$'\n\n'"<b>Триггер:</b> <code>${trigger}</code>"
  text+=$'\n'"<b>Dev repo:</b> <code>${dev_sha}</code>"
  if [[ -n "$scope" ]]; then
    text+=$'\n'"<b>Scope:</b> <code>${scope}</code>"
  fi
  text+=$'\n\n'"<b>Проект:</b> ${app}"
  text+=$'\n'"<b>Окружение:</b> <code>${env}</code>"
  text+=$'\n'"<b>Домен:</b> <a href=\"https://${domain}\">${domain}</a>"
  text+=$'\n'"<b>Сервер:</b> <code>${host}</code>"

  if [[ -n "$safe_details" ]]; then
    text+=$'\n\n'"${safe_details}"
  fi

  deploy_notify_post "$text"
}
