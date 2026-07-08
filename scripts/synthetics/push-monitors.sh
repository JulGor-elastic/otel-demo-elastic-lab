#!/usr/bin/env bash
# Push lightweight Synthetics monitors via Kibana API.
# Requires: curl, jq, vars.yml (kibana_url, elastic_api_key, synthetics_private_location_name)
#
# Usage:
#   ./scripts/synthetics/push-monitors.sh
#   make synthetics-push

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load-vars.sh
source "${SCRIPT_DIR}/load-vars.sh"

KIBANA_URL="${KIBANA_URL:?Set kibana_url in vars.yml}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:-${ELASTIC_TOKEN:-}}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:?Set elastic_api_key in vars.yml}"
PRIVATE_LOCATION="${SYNTHETICS_PRIVATE_LOCATION_NAME:?Set synthetics_private_location_name in vars.yml}"
MONITORS_FILE="${ROOT}/synthetics/monitors.json"
RETIRED_FILE="${ROOT}/synthetics/retired-monitors.json"
SPACE="${SYNTHETICS_KIBANA_SPACE:-default}"

log() { echo "[push-monitors] $*" >&2; }

if [[ ! -f "${MONITORS_FILE}" ]]; then
  log "Monitor definitions not found: ${MONITORS_FILE}"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log "jq is required (brew install jq / apt install jq)"
  exit 1
fi

kibana_curl() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local tmp http_code
  tmp="$(mktemp)"
  if [[ -n "${body}" ]]; then
    http_code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X "${method}" \
      "${KIBANA_URL}/s/${SPACE}${path}" \
      -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "${body}")"
  else
    http_code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X "${method}" \
      "${KIBANA_URL}/s/${SPACE}${path}" \
      -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
      -H "kbn-xsrf: true")"
  fi
  printf '%s\n' "${http_code}"
  cat "${tmp}"
  rm -f "${tmp}"
}

split_response() {
  local response="$1"
  _HTTP_CODE="$(printf '%s' "${response}" | head -n1)"
  _HTTP_BODY="$(printf '%s' "${response}" | tail -n +2)"
}

delete_monitor_by_name() {
  local name="$1"
  local id
  id="$(echo "${monitors_json}" | jq -r --arg n "${name}" \
    '.monitors[]? | select(.name == $n) | .id' | head -n1)"
  if [[ -z "${id}" || "${id}" == "null" ]]; then
    return 0
  fi
  log "Removing retired monitor: ${name} (${id})"
  split_response "$(kibana_curl DELETE "/api/synthetics/monitors/${id}")"
  if [[ "${_HTTP_CODE}" != "200" && "${_HTTP_CODE}" != "204" ]]; then
    log "Delete failed (${_HTTP_CODE}) for ${name}: ${_HTTP_BODY}"
    return 1
  fi
  sleep 1
  return 0
}

build_payload() {
  local def="$1"
  echo "${def}" | jq \
    --arg loc "${PRIVATE_LOCATION}" \
    '{
      type: (.type // "http"),
      name: .name,
      schedule: .schedule,
      private_locations: [$loc],
      tags: (.tags // [])
    }
    + (if (.type // "http") == "tcp" then {hosts: .hosts} else {urls: .urls} end)'
}

log "Pushing monitors to ${KIBANA_URL} (space: ${SPACE}, location: ${PRIVATE_LOCATION})"

split_response "$(kibana_curl GET "/api/synthetics/monitors?perPage=200")"
if [[ "${_HTTP_CODE}" != "200" ]]; then
  log "List monitors failed (${_HTTP_CODE}): ${_HTTP_BODY}"
  exit 1
fi
monitors_json="${_HTTP_BODY}"

if [[ -f "${RETIRED_FILE}" ]] && [[ "$(jq length "${RETIRED_FILE}")" -gt 0 ]]; then
  while IFS= read -r retired_name; do
    [[ -z "${retired_name}" ]] && continue
    delete_monitor_by_name "${retired_name}" || true
  done < <(jq -r '.[]' "${RETIRED_FILE}")
  split_response "$(kibana_curl GET "/api/synthetics/monitors?perPage=200")"
  monitors_json="${_HTTP_BODY}"
fi

failed=0
count="$(jq length "${MONITORS_FILE}")"
for i in $(seq 0 $((count - 1))); do
  def="$(jq -c ".[${i}]" "${MONITORS_FILE}")"
  name="$(echo "${def}" | jq -r '.name')"
  monitor_type="$(echo "${def}" | jq -r '.type // "http"')"
  payload="$(build_payload "${def}")"

  existing_id="$(echo "${monitors_json}" | jq -r --arg n "${name}" \
    '.monitors[]? | select(.name == $n) | .id' | head -n1)"
  existing_type="$(echo "${monitors_json}" | jq -r --arg n "${name}" \
    '.monitors[]? | select(.name == $n) | .type' | head -n1)"

  if [[ -n "${existing_id}" && "${existing_id}" != "null" && "${existing_type}" != "${monitor_type}" ]]; then
    log "Replacing ${existing_type} monitor with ${monitor_type}: ${name} (${existing_id})"
    split_response "$(kibana_curl DELETE "/api/synthetics/monitors/${existing_id}")"
    if [[ "${_HTTP_CODE}" != "200" && "${_HTTP_CODE}" != "204" ]]; then
      log "Delete failed (${_HTTP_CODE}) for ${name}: ${_HTTP_BODY}"
      failed=$((failed + 1))
      continue
    fi
    sleep 1
    existing_id=""
  fi

  if [[ -n "${existing_id}" && "${existing_id}" != "null" ]]; then
    log "Updating ${monitor_type} monitor: ${name} (${existing_id})"
    split_response "$(kibana_curl PUT "/api/synthetics/monitors/${existing_id}" "${payload}")"
  else
    log "Creating ${monitor_type} monitor: ${name}"
    split_response "$(kibana_curl POST "/api/synthetics/monitors" "${payload}")"
  fi

  if [[ "${_HTTP_CODE}" != "200" ]]; then
    log "Failed (${_HTTP_CODE}) for ${name}: ${_HTTP_BODY}"
    failed=$((failed + 1))
    continue
  fi

  echo "${_HTTP_BODY}" | jq -r \
    '{id, name, type, target: (.url // .urls // .hosts), locations: [.locations[]?.label]}'
done

if [[ "${failed}" -gt 0 ]]; then
  log "${failed} monitor(s) failed"
  exit 1
fi

log "Done (${count} monitor(s)). Kibana → Observability → Synthetics → Monitors"
