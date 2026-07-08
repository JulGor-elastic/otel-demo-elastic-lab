#!/usr/bin/env bash
# Create a Synthetics Private Location via Kibana API (idempotent by label).
#
# Required (vars.yml):
#   kibana_url, elastic_api_key
#   synthetics_private_location_name
#   fleet_agent_policy_id OR fleet_agent_policy_name
#
# Usage:
#   source scripts/synthetics/load-vars.sh && ./scripts/synthetics/create-private-location.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-vars.sh
source "${SCRIPT_DIR}/load-vars.sh"

KIBANA_URL="${KIBANA_URL:?Set kibana_url in vars.yml}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:-${ELASTIC_TOKEN:-}}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:?Set elastic_api_key in vars.yml}"
LABEL="${SYNTHETICS_PRIVATE_LOCATION_NAME:?Set synthetics_private_location_name in vars.yml}"
TAGS="${SYNTHETICS_PRIVATE_LOCATION_TAGS:-otel-demo,lab}"

log() { echo "[create-private-location] $*" >&2; }

resolve_policy_id() {
  if [[ -n "${FLEET_AGENT_POLICY_ID:-}" ]]; then
    echo "${FLEET_AGENT_POLICY_ID}"
    return
  fi
  if [[ -z "${FLEET_AGENT_POLICY_NAME:-}" ]]; then
    log "Set fleet_agent_policy_id or fleet_agent_policy_name in vars.yml"
    exit 1
  fi
  local response body code
  response="$(curl -sS -w '\n__HTTP_CODE__:%{http_code}' \
    "${KIBANA_URL}/api/fleet/agent_policies?perPage=200" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true")"
  body="${response%__HTTP_CODE__:*}"
  code="${response##*__HTTP_CODE__:}"
  if [[ "${code}" != "200" ]]; then
    log "Fleet API error (${code}): ${body}"
    exit 1
  fi
  echo "${body}" | jq -r --arg n "${FLEET_AGENT_POLICY_NAME}" \
    '.items[] | select(.name == $n) | .id' | head -n1
}

POLICY_ID="$(resolve_policy_id)"
if [[ -z "${POLICY_ID}" || "${POLICY_ID}" == "null" ]]; then
  log "Could not resolve Fleet agent policy ID"
  exit 1
fi

log "Checking existing private locations (label: ${LABEL})"
list_response="$(curl -sS -w '\n__HTTP_CODE__:%{http_code}' \
  "${KIBANA_URL}/api/synthetics/private_locations" \
  -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
  -H "kbn-xsrf: true")"
list_body="${list_response%__HTTP_CODE__:*}"
list_code="${list_response##*__HTTP_CODE__:}"

if [[ "${list_code}" == "200" ]]; then
  existing_id="$(echo "${list_body}" | jq -r --arg lbl "${LABEL}" \
    '.[]? | select(.label == $lbl) | .id' 2>/dev/null | head -n1 || true)"
  if [[ -n "${existing_id}" && "${existing_id}" != "null" ]]; then
    log "Private location already exists: ${existing_id} (${LABEL})"
    echo "${existing_id}"
    exit 0
  fi
fi

IFS=',' read -r -a tag_array <<< "${TAGS}"
tags_json="$(printf '%s\n' "${tag_array[@]}" | jq -R . | jq -s .)"

payload="$(jq -n \
  --arg label "${LABEL}" \
  --arg policy "${POLICY_ID}" \
  --argjson tags "${tags_json}" \
  '{label: $label, agentPolicyId: $policy, tags: $tags}')"

log "Creating private location '${LABEL}' → policy ${POLICY_ID}"
response="$(curl -sS -w '\n__HTTP_CODE__:%{http_code}' -X POST \
  "${KIBANA_URL}/api/synthetics/private_locations" \
  -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "${payload}")"
body="${response%__HTTP_CODE__:*}"
code="${response##*__HTTP_CODE__:}"

if [[ "${code}" == "200" ]]; then
  loc_id="$(echo "${body}" | jq -r '.id // empty')"
  log "Created private location: ${loc_id}"
  echo "${loc_id}"
  exit 0
fi

if [[ "${code}" == "400" ]] && echo "${body}" | grep -qi "Invalid spaces"; then
  log "FAILED: Fleet space_ids mismatch (known Elastic 9.4.x issue)."
  log "Policy ${POLICY_ID} has space_ids=[] — new Private Locations cannot be created."
  log "Run: ./scripts/synthetics/diagnose-private-location.sh"
  log "Workaround: reuse an existing Private Location + re-enroll agent on that policy."
  log "Details: https://discuss.elastic.co/t/unable-to-create-private-location/386864"
  exit 2
fi

if [[ "${code}" == "400" ]] && echo "${body}" | grep -qi "already exists"; then
  log "Private location label already exists (400); reusing"
  echo "${list_body}" | jq -r --arg lbl "${LABEL}" '.[]? | select(.label == $lbl) | .id' | head -n1
  exit 0
fi

log "Failed (${code}): ${body}"
if [[ "${code}" == "500" ]]; then
  log "HTTP 500 often means: options.namespaces cannot be an empty array"
  log "This happens when Fleet policies have space_ids=[] (Elastic 9.4.x, no Fleet Space Awareness)."
  log "Run: ./scripts/synthetics/diagnose-private-location.sh"
fi
exit 1
