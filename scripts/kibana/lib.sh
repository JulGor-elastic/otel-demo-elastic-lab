#!/usr/bin/env bash
# Shared helpers for Kibana lab object export/deploy.

set -euo pipefail

KIBANA_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

kibana_load_vars() {
  # shellcheck source=../synthetics/load-vars.sh
  source "${KIBANA_REPO_ROOT}/scripts/synthetics/load-vars.sh"
  : "${KIBANA_URL:?Set kibana_url in vars.yml}"
  : "${ELASTIC_API_KEY:?Set elastic_api_key in vars.yml}"
  export ES_URL="${ES_URL:-${elastic_es_endpoint:-}}"
  if [[ -z "${ES_URL}" && -n "${elastic_motlp_endpoint:-}" ]]; then
    ES_URL="${elastic_motlp_endpoint//.ingest./.es.}"
    ES_URL="${ES_URL%:443}"
    ES_URL="${ES_URL%/}"
    export ES_URL
  fi
  export RCA_NOTIFICATION_EMAIL="${RCA_NOTIFICATION_EMAIL:-${rca_notification_email:-}}"
}

kibana_curl() {
  curl -sS -f \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true" \
    "$@"
}

kibana_http_status() {
  curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true" \
    "$@"
}

log() { echo "[kibana-lab] $*" >&2; }

redact_emails() {
  # Replace email addresses with deploy placeholder (never commit personal emails).
  sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/__RCA_NOTIFICATION_EMAIL__/g'
}

substitute_lab_placeholders() {
  local file="$1"
  local email="${RCA_NOTIFICATION_EMAIL:-you@example.com}"
  sed \
    -e "s|__RCA_NOTIFICATION_EMAIL__|${email}|g" \
    -e "s|__GITHUB_HTTP_CONNECTOR_ID__|${GITHUB_HTTP_CONNECTOR_ID:-${github_http_connector_id:-}}|g" \
    -e "s|__GITHUB_REPO_OWNER__|${GITHUB_REPO_OWNER:-${github_repo_owner:-}}|g" \
    -e "s|__GITHUB_REPO_NAME__|${GITHUB_REPO_NAME:-${github_repo_name:-}}|g" \
    -e "s|__GITHUB_REF__|${GITHUB_REF:-${github_ref:-main}}|g" \
    "${file}"
}

ensure_dir() {
  mkdir -p "$1"
}

artifact_missing() {
  local path="$1"
  [[ ! -f "${KIBANA_REPO_ROOT}/${path}" ]] && return 0
  [[ ! -s "${KIBANA_REPO_ROOT}/${path}" ]] && return 0
  return 1
}
