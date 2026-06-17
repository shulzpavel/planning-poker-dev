#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEPLOY_TRIGGER="${DEPLOY_TRIGGER:-manual (deploy-web-prod.sh)}"
exec "$ROOT_DIR/infra/deploy/deploy-service-prod.sh" web
