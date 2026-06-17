#!/usr/bin/env bash
# Shared Telegram deploy notifications. Source from deploy scripts.

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

deploy_notify_format_services() {
  local root_dir="$1"
  shift
  local service repo_dir sha line
  local lines=()

  for service in "$@"; do
    repo_dir="$(deploy_notify_service_repo_dir "$root_dir" "$service")"
    sha="$(deploy_notify_service_sha "$repo_dir")"
    line="• $(deploy_notify_html_escape "$service") — <code>$(deploy_notify_html_escape "$sha")</code> ($(deploy_notify_html_escape "$(deploy_notify_service_repo "$service")"))"
    lines+=("$line")
  done

  local joined=""
  local item
  for item in "${lines[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=$'\n'"$item"
    else
      joined="$item"
    fi
  done
  printf '%s' "$joined"
}

deploy_notify_send() {
  local status="$1"
  local details="$2"
  local root_dir="${3:-}"

  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    return 0
  fi

  local icon title
  case "$status" in
    STARTED) icon="🚀"; title="Деплой запущен" ;;
    OK) icon="✅"; title="Деплой завершён" ;;
    FAILED) icon="❌"; title="Деплой упал" ;;
    *) icon="ℹ️"; title="Статус деплоя" ;;
  esac

  local app env domain host trigger safe_details scope services_block dev_sha
  app="$(deploy_notify_html_escape "$DEPLOY_APP_NAME")"
  env="$(deploy_notify_html_escape "$DEPLOY_ENVIRONMENT")"
  domain="$(deploy_notify_html_escape "$DEPLOY_DOMAIN")"
  host="$(deploy_notify_html_escape "$(hostname)")"
  trigger="$(deploy_notify_html_escape "$DEPLOY_TRIGGER")"
  safe_details="$(deploy_notify_html_escape "$details")"
  scope="$(deploy_notify_html_escape "${DEPLOY_SCOPE:-}")"
  dev_sha="unknown"
  if [[ -n "$root_dir" ]]; then
    dev_sha="$(deploy_notify_html_escape "$(deploy_notify_service_sha "$root_dir")")"
  fi

  if [[ -n "${DEPLOY_SERVICES_BLOCK:-}" ]]; then
    services_block="$DEPLOY_SERVICES_BLOCK"
  elif [[ -n "${DEPLOY_SERVICE:-}" && -n "$root_dir" ]]; then
    local repo_dir sha repo_name
    repo_dir="$(deploy_notify_service_repo_dir "$root_dir" "$DEPLOY_SERVICE")"
    sha="$(deploy_notify_service_sha "$repo_dir")"
    repo_name="$(deploy_notify_service_repo "$DEPLOY_SERVICE")"
    services_block="• $(deploy_notify_html_escape "$DEPLOY_SERVICE") — <code>$(deploy_notify_html_escape "$sha")</code> ($(deploy_notify_html_escape "$repo_name"))"
  else
    services_block=""
  fi

  local text
  text="$(printf '%s <b>%s</b>\n\n' "$icon" "$title")"
  if [[ -n "$scope" ]]; then
    text+="$(printf '<b>Scope:</b> %s\n' "$scope")"
  fi
  if [[ -n "$services_block" ]]; then
    text+="$(printf '<b>Сервисы:</b>\n%s\n' "$services_block")"
  fi
  text+="$(printf '<b>Триггер:</b> <code>%s</code>\n<b>Dev repo:</b> <code>%s</code>\n<b>Проект:</b> %s\n<b>Окружение:</b> <code>%s</code>\n<b>Домен:</b> <a href="https://%s">%s</a>\n<b>Сервер:</b> <code>%s</code>\n\n%s' \
    "$trigger" \
    "$dev_sha" \
    "$app" \
    "$env" \
    "$domain" \
    "$domain" \
    "$host" \
    "$safe_details")"

  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" \
    --data-urlencode "text=${text}" \
    >/dev/null || true
}
