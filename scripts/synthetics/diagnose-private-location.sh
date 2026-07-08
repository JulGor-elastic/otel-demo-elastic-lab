#!/usr/bin/env bash
# Diagnose why Synthetics Private Location creation fails on this cluster.
#
# Usage:
#   ./scripts/synthetics/diagnose-private-location.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-vars.sh
source "${SCRIPT_DIR}/load-vars.sh"

KIBANA_URL="${KIBANA_URL:?Set kibana_url in vars.yml}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:-${ELASTIC_TOKEN:-}}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:?Set elastic_api_key in vars.yml}"

POLICY_ID="${FLEET_AGENT_POLICY_ID:-}"
if [[ -z "${POLICY_ID}" && -n "${FLEET_AGENT_POLICY_NAME:-}" ]]; then
  POLICY_ID="$(curl -sS "${KIBANA_URL}/api/fleet/agent_policies?perPage=200" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true" \
    | jq -r --arg n "${FLEET_AGENT_POLICY_NAME}" '.items[] | select(.name == $n) | .id' | head -n1)"
fi

log() { echo "[diagnose] $*" >&2; }

log "Kibana: ${KIBANA_URL}"
log "Target policy: ${FLEET_AGENT_POLICY_NAME:-<unset>} (${POLICY_ID:-unknown})"
echo

if [[ -n "${POLICY_ID}" ]]; then
  policy_json="$(curl -sS "${KIBANA_URL}/api/fleet/agent_policies/${POLICY_ID}" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true")"
  space_ids="$(echo "${policy_json}" | jq -c '.item.space_ids // []')"
  pkg_count="$(curl -sS "${KIBANA_URL}/api/fleet/package_policies?perPage=200" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true" \
    | jq --arg pid "${POLICY_ID}" '[.items[] | select(.policy_id == $pid)] | length')"
  agent_count="$(echo "${policy_json}" | jq -r '.item.agents // 0')"

  echo "Policy space_ids: ${space_ids}"
  echo "Package policies on policy: ${pkg_count}"
  echo "Enrolled agents: ${agent_count}"
  echo
fi

echo "Existing private locations:"
curl -sS "${KIBANA_URL}/api/synthetics/private_locations" \
  -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true" \
  | jq -r '.[] | "  - \(.label) (policy \(.agentPolicyId), spaces \(.spaces | join(",")))"'

echo
if [[ "${space_ids:-[]}" == "[]" || "${space_ids:-null}" == "null" ]]; then
  log "LIKELY ROOT CAUSE: Fleet agent policy has empty space_ids."
  log "Elastic 9.4.x returns HTTP 500 when creating a Private Location without"
  log "explicit spaces, and HTTP 400 if spaces=[default] (policy spaces are [])."
  log "See: https://discuss.elastic.co/t/unable-to-create-private-location/386864"
  echo
  log "WORKAROUND for this lab:"
  log "  1. Reuse an existing Private Location (if you have one from before 9.4.2)."
  log "  2. Re-enroll the synthetics agent on THAT policy (new enrollment token)."
  log "  3. Set synthetics_private_location_name to the existing label."
  log "  4. Run: make synthetics-push"
  echo
  log "Your cluster already has location 'Private' on policy 'My private location'."
fi

if [[ -n "${POLICY_ID}" ]]; then
  echo
  log "API probe (omit spaces — expect 500 on affected clusters):"
  probe="$(curl -sS -w '\n__HTTP_CODE__:%{http_code}' -X POST "${KIBANA_URL}/api/synthetics/private_locations" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{\"label\":\"__diagnose-probe-delete-me\",\"agentPolicyId\":\"${POLICY_ID}\"}")"
  probe_body="${probe%__HTTP_CODE__:*}"
  probe_code="${probe##*__HTTP_CODE__:}"
  echo "  HTTP ${probe_code}: ${probe_body}"
fi
