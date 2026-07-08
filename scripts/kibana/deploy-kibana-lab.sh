#!/usr/bin/env bash
# Deploy optional Kibana lab objects (transform, workflows, RCA, Agent Builder, dashboards).
#
# Optional by design: skips components that already exist unless KIBANA_DEPLOY_OVERWRITE=1.
#
# Prerequisites (vars.yml):
#   kibana_url, elastic_api_key, elastic_es_endpoint (or elastic_motlp_endpoint)
#   rca_notification_email — recipient for RCA workflow notifications
#   github_* — for scenario workflows (see demo-scenarios-setup.md)
#
# Usage:
#   ./scripts/kibana/deploy-kibana-lab.sh
#   KIBANA_DEPLOY_OVERWRITE=1 ./scripts/kibana/deploy-kibana-lab.sh
#
# Steps (order): transform → otel-demo workflows → RCA workflow → AB tools →
#                AB skills → assign skills to elastic-ai-agent → saved objects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

kibana_load_vars

SKIP_EXISTING="${KIBANA_DEPLOY_SKIP_EXISTING:-1}"
OVERWRITE="${KIBANA_DEPLOY_OVERWRITE:-0}"
RCA_ID="automatic-ai-based-rca-human-in-the-loop-copy"
AGENT_ID="elastic-ai-agent"
SKILL_IDS=(deployment-remediation environment-context incident-business-impact)

should_skip_existing() {
  [[ "${OVERWRITE}" == "1" ]] && return 1
  [[ "${SKIP_EXISTING}" == "1" ]]
}

deploy_transform() {
  if artifact_missing "scripts/elasticsearch/orders-otel-demo-transform.json"; then
    log "SKIP transform — JSON definition missing"
    return 0
  fi
  if [[ -z "${ES_URL:-}" ]]; then
    log "SKIP transform — ES_URL not set (need elastic_es_endpoint or elastic_motlp_endpoint)"
    return 0
  fi
  log "Step 1/7 — Elasticsearch transform otel-demo-orders-latest"
  if should_skip_existing; then
    if curl -sS -o /dev/null -w '%{http_code}' \
        -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
        "${ES_URL}/_transform/otel-demo-orders-latest" | grep -q '^200$'; then
      log "  transform exists — skip (set KIBANA_DEPLOY_OVERWRITE=1 to reset)"
      return 0
    fi
  fi
  ES_URL="${ES_URL}" ES_API_KEY="${ELASTIC_API_KEY}" \
    "${KIBANA_REPO_ROOT}/scripts/elasticsearch/create-orders-transform.sh"
}

deploy_otel_workflows() {
  log "Step 2/7 — OTel Demo scenario workflows"
  if [[ -z "${github_http_connector_id:-}" || -z "${github_repo_owner:-}" || -z "${github_repo_name:-}" ]]; then
    log "  SKIP — set github_http_connector_id, github_repo_owner, github_repo_name in vars.yml"
    return 0
  fi
  export GITHUB_HTTP_CONNECTOR_ID="${github_http_connector_id}"
  export GITHUB_REPO_OWNER="${github_repo_owner}"
  export GITHUB_REPO_NAME="${github_repo_name}"
  export GITHUB_REF="${github_ref:-main}"
  "${KIBANA_REPO_ROOT}/scripts/workflows/deploy-workflows.sh"
}

workflow_exists() {
  [[ "$(kibana_http_status "${KIBANA_URL}/api/workflows/workflow/$1")" == "200" ]]
}

ab_resource_exists() {
  [[ "$(kibana_http_status "${KIBANA_URL}/api/agent_builder/$1/$2")" == "200" ]]
}

deploy_rca_workflow() {
  local artifact="kibana/workflows/automatic-ai-based-rca-human-in-the-loop.yaml"
  log "Step 3/7 — RCA workflow ${RCA_ID}"
  if artifact_missing "${artifact}"; then
    log "  SKIP — run ./scripts/kibana/export-from-kibana.sh first"
    return 0
  fi
  if should_skip_existing && workflow_exists "${RCA_ID}"; then
    log "  workflow exists — skip"
    return 0
  fi
  if [[ -z "${RCA_NOTIFICATION_EMAIL:-}" ]]; then
    log "  WARN — rca_notification_email not set; using you@example.com"
    export RCA_NOTIFICATION_EMAIL="you@example.com"
  fi
  local yaml_content
  yaml_content="$(substitute_lab_placeholders "${KIBANA_REPO_ROOT}/${artifact}")"
  if workflow_exists "${RCA_ID}"; then
    log "  updating workflow ${RCA_ID}"
    kibana_curl -X PUT "${KIBANA_URL}/api/workflows/workflow/${RCA_ID}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg yaml "${yaml_content}" '{yaml: $yaml, enabled: true}')" \
      | jq -r '.id // "updated"'
  else
    log "  creating workflow"
    kibana_curl -X POST "${KIBANA_URL}/api/workflows/workflow" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg yaml "${yaml_content}" '{yaml: $yaml}')" \
      | jq -r '.id // .workflowId // "created"'
  fi
}

ab_resource_exists() {
  local kind="$1" id="$2"
  [[ "$(kibana_http_status "${KIBANA_URL}/api/agent_builder/${kind}/${id}")" == "200" ]]
}

deploy_ab_json() {
  local kind="$1" id="$2" artifact="$3"
  local path="${KIBANA_REPO_ROOT}/${artifact}"
  if [[ ! -f "${path}" ]]; then
    log "  SKIP ${kind}/${id} — missing ${artifact}"
    return 0
  fi
  if should_skip_existing && ab_resource_exists "${kind}" "${id}"; then
    log "  ${kind}/${id} exists — skip"
    return 0
  fi
  local body
  body="$(jq 'del(.readonly, .created_at, .updated_at, .created_by, .updated_by) | .' "${path}")"
  if ab_resource_exists "${kind}" "${id}"; then
    log "  updating ${kind}/${id}"
    kibana_curl -X PUT "${KIBANA_URL}/api/agent_builder/${kind}/${id}" \
      -H "Content-Type: application/json" \
      -d "${body}" > /dev/null
  else
    log "  creating ${kind}/${id}"
    kibana_curl -X POST "${KIBANA_URL}/api/agent_builder/${kind}" \
      -H "Content-Type: application/json" \
      -d "${body}" > /dev/null
  fi
}

deploy_agent_builder_tools() {
  log "Step 4/7 — Agent Builder tools"
  deploy_ab_json "tools" "recover_lab_environment" "kibana/agent_builder/tools/recover_lab_environment.json"
  deploy_ab_json "tools" "orders_incident_revenue_impact" "kibana/agent_builder/tools/orders_incident_revenue_impact.json"
}

deploy_agent_builder_skills() {
  log "Step 5/7 — Agent Builder skills"
  for skill_id in "${SKILL_IDS[@]}"; do
    deploy_ab_json "skills" "${skill_id}" "kibana/agent_builder/skills/${skill_id}.json"
  done
}

deploy_agent_skills_assignment() {
  log "Step 6/7 — Assign skills to agent ${AGENT_ID}"
  if ! ab_resource_exists "agents" "${AGENT_ID}"; then
    log "  SKIP — agent ${AGENT_ID} not found in this project"
    return 0
  fi
  local agent_json current_skills merged
  agent_json="$(kibana_curl "${KIBANA_URL}/api/agent_builder/agents/${AGENT_ID}")"
  current_skills="$(jq -r '.skill_ids // [] | @json' <<<"${agent_json}")"
  merged="$(jq -n \
    --argjson cur "${current_skills}" \
    --argjson add "$(printf '%s\n' "${SKILL_IDS[@]}" | jq -R . | jq -s .)" \
    '$cur + $add | unique')"
  if should_skip_existing; then
    local all_present=1 s
    for s in "${SKILL_IDS[@]}"; do
      jq -e --arg s "${s}" '.skill_ids // [] | index($s)' <<<"${agent_json}" >/dev/null || all_present=0
    done
    if [[ "${all_present}" == "1" ]]; then
      log "  all lab skills already assigned — skip"
      return 0
    fi
  fi
  log "  patching skill_ids on ${AGENT_ID}"
  local patch
  patch="$(jq --argjson skills "${merged}" 'del(.readonly) | .skill_ids = $skills' <<<"${agent_json}")"
  kibana_curl -X PUT "${KIBANA_URL}/api/agent_builder/agents/${AGENT_ID}" \
    -H "Content-Type: application/json" \
    -d "${patch}" > /dev/null
}

deploy_saved_objects() {
  local artifact="kibana/saved_objects/lab-objects.ndjson"
  log "Step 7/7 — Saved objects (dashboard + rule)"
  if artifact_missing "${artifact}"; then
    log "  SKIP — run ./scripts/kibana/export-from-kibana.sh first"
    return 0
  fi
  local overwrite_flag="false"
  [[ "${OVERWRITE}" == "1" ]] && overwrite_flag="true"
  local result
  result="$(curl -sS \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true" \
    -X POST "${KIBANA_URL}/api/saved_objects/_import?overwrite=${overwrite_flag}" \
    --form "file=@${KIBANA_REPO_ROOT}/${artifact}")"
  if jq -e '.successResults | length > 0' <<<"${result}" >/dev/null 2>&1; then
    jq -r '.successResults[] | "  imported \(.type)/\(.id)"' <<<"${result}"
  fi
  if jq -e '.errors | length > 0' <<<"${result}" >/dev/null 2>&1; then
    log "  import reported errors (existing objects are skipped when overwrite=false):"
    jq -r '.errors[] | "    \(.type)/\(.id): \(.error.type // .error.message // .)"' <<<"${result}" || true
  fi
}

main() {
  log "Deploying Kibana lab objects (SKIP_EXISTING=${SKIP_EXISTING}, OVERWRITE=${OVERWRITE})"
  deploy_transform
  deploy_otel_workflows
  deploy_rca_workflow
  deploy_agent_builder_tools
  deploy_agent_builder_skills
  deploy_agent_skills_assignment
  deploy_saved_objects
  log "Done."
}

main "$@"
