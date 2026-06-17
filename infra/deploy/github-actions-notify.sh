#!/usr/bin/env bash
# Send Telegram alerts for GitHub Actions CI/CD events via server-side .deploy.env.
set -euo pipefail

STATUS="${1:?usage: github-actions-notify.sh <STARTED|OK|FAILED> [details]}"
DETAILS="${2:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/infra/deploy/deploy-notify.sh"

deploy_notify_load_env "$ROOT_DIR"

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-unknown}"
GITHUB_SHA="${GITHUB_SHA:-unknown}"
GITHUB_REF_NAME="${GITHUB_REF_NAME:-unknown}"
GITHUB_ACTOR="${GITHUB_ACTOR:-unknown}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
GITHUB_EVENT_NAME="${GITHUB_EVENT_NAME:-push}"
SERVICE_LABEL="${SERVICE_LABEL:-${DEPLOY_SERVICE:-}}"
NOTIFY_EVENT="${NOTIFY_EVENT:-pipeline_result}"

export DEPLOY_TRIGGER="github:${GITHUB_REPOSITORY}@${GITHUB_SHA}"
export DEPLOY_SERVICE="${DEPLOY_SERVICE:-}"
export DEPLOY_SCOPE="${DEPLOY_SCOPE:-CI pipeline}"

RUN_URL=""
if [[ -n "$GITHUB_RUN_ID" && "$GITHUB_REPOSITORY" != "unknown" ]]; then
  RUN_URL="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

deploy_notify_html_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

build_ci_message() {
  local icon title
  case "$STATUS" in
    STARTED) icon="🚀"; title="CI pipeline запущен" ;;
    OK) icon="✅"; title="CI pipeline успешен" ;;
    FAILED) icon="❌"; title="CI pipeline упал" ;;
    *) icon="ℹ️"; title="CI pipeline" ;;
  esac

  local repo sha branch actor service event safe_details run_link
  repo="$(deploy_notify_html_escape "$GITHUB_REPOSITORY")"
  sha="$(deploy_notify_html_escape "${GITHUB_SHA:0:7}")"
  branch="$(deploy_notify_html_escape "$GITHUB_REF_NAME")"
  actor="$(deploy_notify_html_escape "$GITHUB_ACTOR")"
  service="$(deploy_notify_html_escape "${SERVICE_LABEL:-—}")"
  event="$(deploy_notify_html_escape "$GITHUB_EVENT_NAME")"
  safe_details="$(deploy_notify_html_escape "$DETAILS")"

  local text
  text="$(printf '%s <b>%s</b>\n' "$icon" "$title")"
  text+=$'\n'"<b>Репозиторий:</b> <code>${repo}</code>"
  if [[ -n "$SERVICE_LABEL" ]]; then
    text+=$'\n'"<b>Сервис:</b> <code>${service}</code>"
  fi
  text+=$'\n'"<b>Событие:</b> <code>${event}</code>"
  text+=$'\n'"<b>Ветка:</b> <code>${branch}</code>"
  text+=$'\n'"<b>Коммит:</b> <code>${sha}</code>"
  text+=$'\n'"<b>Автор:</b> ${actor}"

  if [[ -n "${CI_TEST_RESULT:-}" || -n "${CI_DOCKER_RESULT:-}" || -n "${CI_DEPLOY_RESULT:-}" || -n "${CI_COMPOSE_RESULT:-}" ]]; then
    text+=$'\n\n'"<b>Jobs:</b>"
    [[ -n "${CI_TEST_RESULT:-}" ]] && text+=$'\n'"• test: <code>$(deploy_notify_html_escape "$CI_TEST_RESULT")</code>"
    [[ -n "${CI_DOCKER_RESULT:-}" ]] && text+=$'\n'"• docker: <code>$(deploy_notify_html_escape "$CI_DOCKER_RESULT")</code>"
    [[ -n "${CI_COMPOSE_RESULT:-}" ]] && text+=$'\n'"• compose: <code>$(deploy_notify_html_escape "$CI_COMPOSE_RESULT")</code>"
    [[ -n "${CI_DEPLOY_RESULT:-}" ]] && text+=$'\n'"• deploy: <code>$(deploy_notify_html_escape "$CI_DEPLOY_RESULT")</code>"
  fi

  if [[ -n "$safe_details" ]]; then
    text+=$'\n\n'"${safe_details}"
  fi

  if [[ -n "$RUN_URL" ]]; then
    text+=$'\n\n'"<a href=\"${RUN_URL}\">Открыть GitHub Actions</a>"
  fi

  deploy_notify_post "$text"
}

build_ci_message
