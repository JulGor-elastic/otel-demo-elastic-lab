#!/usr/bin/env bash
# Create a Kibana HTTP connector (.http) for the GitHub API (Workflows / Phase 4).
#
# Uses connector_type_id ".http" (supported_feature_ids: workflows), NOT ".webhook".
# GitHub PAT is stored as the "password" in basic auth (GitHub REST API accepts this).
#
# Required:
#   KIBANA_URL       — https://<project>.kb.<region>.aws.elastic.cloud
#   ELASTIC_API_KEY  — API key with permission to create connectors
#   GITHUB_PAT       — PAT with repo + workflow scopes
#
# Usage:
#   export KIBANA_URL="https://..."
#   export ELASTIC_API_KEY="..."
#   export GITHUB_PAT="ghp_..."
#   ./scripts/workflows/create-github-connector.sh
#
# Optional:
#   CONNECTOR_ID=otel-demo-github
#   CONNECTOR_NAME="OTel Demo GitHub API"

set -euo pipefail

KIBANA_URL="${KIBANA_URL:?Set KIBANA_URL}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:-${elastic_token:-}}"
GITHUB_PAT="${GITHUB_PAT:?Set GITHUB_PAT}"
CONNECTOR_ID="${CONNECTOR_ID:-otel-demo-github}"
CONNECTOR_NAME="${CONNECTOR_NAME:-OTel Demo GitHub API}"

if [[ -z "${ELASTIC_API_KEY}" ]]; then
  echo "Set ELASTIC_API_KEY or elastic_token" >&2
  exit 1
fi

payload="$(jq -n \
  --arg name "${CONNECTOR_NAME}" \
  --arg pat "${GITHUB_PAT}" \
  '{
    name: $name,
    connector_type_id: ".http",
    config: {
      url: "https://api.github.com",
      hasAuth: true,
      authType: "webhook-authentication-basic",
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json"
      }
    },
    secrets: {
      user: "github",
      password: $pat
    }
  }')"

api_call() {
  local method="$1"
  curl -sS -w '\n__HTTP_CODE__:%{http_code}' -X "${method}" \
    "${KIBANA_URL}/api/actions/connector/${CONNECTOR_ID}" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "${payload}"
}

log() { echo "[create-github-connector] $*" >&2; }

response="$(api_call POST)"
http_code="${response##*__HTTP_CODE__:}"
body="${response%__HTTP_CODE__:*}"

if [[ "${http_code}" == "200" ]]; then
  echo "${body}" | jq -r '.id // empty'
  log "Created connector: ${CONNECTOR_ID}"
elif [[ "${http_code}" == "409" ]]; then
  log "Connector exists; updating with PUT"
  response="$(api_call PUT)"
  http_code="${response##*__HTTP_CODE__:}"
  body="${response%__HTTP_CODE__:*}"
  if [[ "${http_code}" == "200" ]]; then
    echo "${body}" | jq -r '.id // empty'
    log "Updated connector: ${CONNECTOR_ID}"
  else
    log "Update failed (HTTP ${http_code})"
    echo "${body}" | jq . 2>/dev/null || echo "${body}"
    exit 1
  fi
else
  log "Create failed (HTTP ${http_code})"
  echo "${body}" | jq . 2>/dev/null || echo "${body}"
  log ""
  log "If the API keeps failing, create the connector in Kibana UI:"
  log "  Stack Management → Connectors → Create connector → HTTP"
  log "  URL: https://api.github.com"
  log "  Auth: Basic — user: github — password: <your PAT>"
  log "  Headers: Accept=application/vnd.github+json, X-GitHub-Api-Version=2022-11-28"
  log "  Connector ID: ${CONNECTOR_ID}"
  exit 1
fi

log "Add to vars.yml: github_http_connector_id: \"${CONNECTOR_ID}\""
