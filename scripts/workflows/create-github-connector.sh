#!/usr/bin/env bash
# Create a Kibana HTTP connector for GitHub API (stores PAT securely).
#
# Reads from environment or vars.yml (via ansible-style vars if sourced):
#   KIBANA_URL              — e.g. https://project.kb.region.aws.elastic.cloud
#   ELASTIC_API_KEY         — API key with connector write privileges
#   GITHUB_PAT              — Personal access token (repo + workflow scope)
#
# Usage:
#   export KIBANA_URL="https://..."
#   export ELASTIC_API_KEY="..."
#   export GITHUB_PAT="ghp_..."
#   ./scripts/workflows/create-github-connector.sh
#
# Prints the connector ID to stdout.

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
    connector_type_id: ".webhook",
    config: {
      url: "https://api.github.com",
      method: "post",
      hasAuth: true,
      authType: "webhook",
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
      }
    },
    secrets: {
      authToken: $pat
    }
  }')"

response="$(curl -fsSL -X POST "${KIBANA_URL}/api/actions/connector/${CONNECTOR_ID}" \
  -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "${payload}" 2>&1)" || {
  echo "Connector create failed (may already exist). Try PUT or use Stack Management UI." >&2
  echo "${response}" >&2
  exit 1
}

echo "${response}" | jq -r '.id // empty'
echo "Connector ID: ${CONNECTOR_ID}" >&2
echo "Add to vars.yml: github_http_connector_id: \"${CONNECTOR_ID}\"" >&2
