#!/usr/bin/env bash
# Reassign the lab synthetics Fleet agent to the policy in vars.yml (if needed).
#
# Changing fleet_enrollment_token / re-running synthetics-deploy does NOT move an
# already-enrolled agent to a new policy — Fleet keeps the original assignment.
# Use this script after switching fleet_agent_policy_name.
#
# Usage:
#   ./scripts/synthetics/reassign-fleet-agent.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-vars.sh
source "${SCRIPT_DIR}/load-vars.sh"

KIBANA_URL="${KIBANA_URL:?Set kibana_url in vars.yml}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:-${ELASTIC_TOKEN:-}}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:?Set elastic_api_key in vars.yml}"
AGENT_HOSTNAME_PREFIX="${SYNTHETICS_AGENT_HOSTNAME_PREFIX:-elastic-synthetics-agent}"

log() { echo "[reassign-fleet-agent] $*" >&2; }

resolve_policy_id() {
  if [[ -n "${FLEET_AGENT_POLICY_ID:-}" ]]; then
    echo "${FLEET_AGENT_POLICY_ID}"
    return
  fi
  if [[ -z "${FLEET_AGENT_POLICY_NAME:-}" ]]; then
    log "Set fleet_agent_policy_id or fleet_agent_policy_name in vars.yml"
    exit 1
  fi
  curl -sS "${KIBANA_URL}/api/fleet/agent_policies?perPage=200" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true" \
    | jq -r --arg n "${FLEET_AGENT_POLICY_NAME}" '.items[] | select(.name == $n) | .id' | head -n1
}

TARGET_POLICY_ID="$(resolve_policy_id)"
if [[ -z "${TARGET_POLICY_ID}" || "${TARGET_POLICY_ID}" == "null" ]]; then
  log "Could not resolve target Fleet agent policy"
  exit 1
fi

agents_json="$(curl -sS "${KIBANA_URL}/api/fleet/agents?perPage=200" \
  -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true")"

agent_id="$(echo "${agents_json}" | jq -r --arg pfx "${AGENT_HOSTNAME_PREFIX}" '
  [.items[]
    | select((.local_metadata.host.hostname // "") | startswith($pfx))
  ] | sort_by(.enrolled_at) | last | .id // empty')"

if [[ -z "${agent_id}" ]]; then
  log "No Fleet agent found with hostname prefix '${AGENT_HOSTNAME_PREFIX}'"
  log "Deploy the agent first: make synthetics-deploy"
  exit 1
fi

current_policy="$(echo "${agents_json}" | jq -r --arg id "${agent_id}" \
  '.items[] | select(.id == $id) | .policy_id')"
hostname="$(echo "${agents_json}" | jq -r --arg id "${agent_id}" \
  '.items[] | select(.id == $id) | .local_metadata.host.hostname')"

if [[ "${current_policy}" == "${TARGET_POLICY_ID}" ]]; then
  log "Agent ${agent_id} (${hostname}) already on target policy ${TARGET_POLICY_ID}"
  exit 0
fi

log "Reassigning ${agent_id} (${hostname})"
log "  from policy ${current_policy}"
log "  to   policy ${TARGET_POLICY_ID} (${FLEET_AGENT_POLICY_NAME:-id})"

response="$(curl -sS -w '\n__HTTP_CODE__:%{http_code}' -X POST \
  "${KIBANA_URL}/api/fleet/agents/${agent_id}/reassign" \
  -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "{\"policy_id\":\"${TARGET_POLICY_ID}\"}")"
body="${response%__HTTP_CODE__:*}"
code="${response##*__HTTP_CODE__:}"

if [[ "${code}" != "200" ]]; then
  log "Reassign failed (${code}): ${body}"
  exit 1
fi

log "Reassign requested; waiting for agent to report new policy..."
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  policy_now="$(curl -sS "${KIBANA_URL}/api/fleet/agents/${agent_id}" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true" \
    | jq -r '.item.policy_id // empty')"
  if [[ "${policy_now}" == "${TARGET_POLICY_ID}" ]]; then
    log "Agent is now on policy ${TARGET_POLICY_ID}"
    exit 0
  fi
  sleep 5
done

log "Timeout waiting for policy update (agent may still be switching)"
exit 1
