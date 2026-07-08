#!/usr/bin/env bash
# Wait until at least one Fleet agent enrolled under the Synthetics policy is online.
#
# Required (from vars.yml via load-vars.sh or env):
#   KIBANA_URL, ELASTIC_API_KEY
#   FLEET_AGENT_POLICY_ID or FLEET_AGENT_POLICY_NAME
#
# Usage:
#   source scripts/synthetics/load-vars.sh && ./scripts/synthetics/wait-fleet-agent.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-vars.sh
source "${SCRIPT_DIR}/load-vars.sh"

KIBANA_URL="${KIBANA_URL:?Set kibana_url in vars.yml}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:-${ELASTIC_TOKEN:-}}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:?Set elastic_api_key in vars.yml}"
TIMEOUT_SEC="${FLEET_AGENT_WAIT_TIMEOUT:-300}"
INTERVAL_SEC="${FLEET_AGENT_WAIT_INTERVAL:-10}"

log() { echo "[wait-fleet-agent] $*" >&2; }

resolve_policy_id() {
  if [[ -n "${FLEET_AGENT_POLICY_ID:-}" ]]; then
    echo "${FLEET_AGENT_POLICY_ID}"
    return
  fi
  if [[ -z "${FLEET_AGENT_POLICY_NAME:-}" ]]; then
    log "Set fleet_agent_policy_id or fleet_agent_policy_name in vars.yml"
    exit 1
  fi
  local response body
  response="$(curl -sS -w '\n__HTTP_CODE__:%{http_code}' \
    "${KIBANA_URL}/api/fleet/agent_policies?perPage=200" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true")"
  body="${response%__HTTP_CODE__:*}"
  local code="${response##*__HTTP_CODE__:}"
  if [[ "${code}" != "200" ]]; then
    log "Fleet API error (${code}): ${body}"
    exit 1
  fi
  local policy_id
  policy_id="$(echo "${body}" | jq -r --arg n "${FLEET_AGENT_POLICY_NAME}" \
    '.items[] | select(.name == $n) | .id' | head -n1)"
  if [[ -z "${policy_id}" || "${policy_id}" == "null" ]]; then
    log "Agent policy not found: ${FLEET_AGENT_POLICY_NAME}"
    exit 1
  fi
  echo "${policy_id}"
}

POLICY_ID="$(resolve_policy_id)"
log "Waiting for Fleet agent (policy ${POLICY_ID}) — timeout ${TIMEOUT_SEC}s"

deadline=$((SECONDS + TIMEOUT_SEC))
while (( SECONDS < deadline )); do
  response="$(curl -sS -w '\n__HTTP_CODE__:%{http_code}' \
    "${KIBANA_URL}/api/fleet/agents?perPage=200" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true")"
  body="${response%__HTTP_CODE__:*}"
  code="${response##*__HTTP_CODE__:}"
  if [[ "${code}" != "200" ]]; then
    log "Fleet agents API error (${code}): ${body}"
    sleep "${INTERVAL_SEC}"
    continue
  fi

  online="$(echo "${body}" | jq -r --arg pid "${POLICY_ID}" '
    [.items[]
      | select(.policy_id == $pid)
      | select(.status == "online" or .active == true)
    ] | length')"

  if [[ "${online}" -gt 0 ]]; then
    agent_id="$(echo "${body}" | jq -r --arg pid "${POLICY_ID}" \
      '.items[] | select(.policy_id == $pid) | .id' | head -n1)"
    log "Agent online: ${agent_id}"
    exit 0
  fi

  log "No online agent yet; retry in ${INTERVAL_SEC}s..."
  sleep "${INTERVAL_SEC}"
done

log "Timeout: no online Fleet agent for policy ${POLICY_ID}"
log "Check Fleet → Agents and pod logs: kubectl logs -n otel-demo -l app=elastic-synthetics-agent"
exit 1
