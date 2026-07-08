#!/usr/bin/env bash
# Export Kibana lab objects from your reference Serverless project into kibana/.
#
# Prerequisites (vars.yml):
#   kibana_url, elastic_api_key
#   API key needs: saved_objects export, workflowsManagement:read,
#   agentBuilder:read, plus existing ingest privileges for transform verify.
#
# Usage:
#   ./scripts/kibana/export-from-kibana.sh
#
# After export, review git diff — emails in RCA workflow are redacted to
# __RCA_NOTIFICATION_EMAIL__. Commit artifacts to the repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

kibana_load_vars

RCA_ID="automatic-ai-based-rca-human-in-the-loop-copy"
DASHBOARD_ID="5c9b8fc2-a1be-4ad9-beb8-efb28310ddbf"
RULE_ID="ff3d48a2-ad11-40df-8ab6-6ef2797914b7"
TOOL_IDS=(recover_lab_environment orders_incident_revenue_impact)
SKILL_IDS=(deployment-remediation environment-context incident-business-impact)
AGENT_ID="elastic-ai-agent"

ensure_dir "${KIBANA_REPO_ROOT}/kibana/workflows"
ensure_dir "${KIBANA_REPO_ROOT}/kibana/saved_objects"
ensure_dir "${KIBANA_REPO_ROOT}/kibana/agent_builder/tools"
ensure_dir "${KIBANA_REPO_ROOT}/kibana/agent_builder/skills"
ensure_dir "${KIBANA_REPO_ROOT}/kibana/agent_builder/agents"

log "Exporting RCA workflow ${RCA_ID}"
rca_json="$(kibana_curl -X POST "${KIBANA_URL}/api/workflows/export" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg id "${RCA_ID}" '{ids: [$id]}')")"
rca_yaml="$(jq -r '.entries[0].yaml // empty' <<<"${rca_json}")"
if [[ -z "${rca_yaml}" ]]; then
  echo "Failed to export workflow ${RCA_ID}" >&2
  jq . <<<"${rca_json}" >&2 || true
  exit 1
fi
printf '%s\n' "${rca_yaml}" | redact_emails \
  > "${KIBANA_REPO_ROOT}/kibana/workflows/automatic-ai-based-rca-human-in-the-loop.yaml"
log "  → kibana/workflows/automatic-ai-based-rca-human-in-the-loop.yaml"

log "Exporting saved objects (dashboard + rule)"
kibana_curl -X POST "${KIBANA_URL}/api/saved_objects/_export" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg dash "${DASHBOARD_ID}" \
    --arg rule "${RULE_ID}" \
    '{
      objects: [
        {type: "dashboard", id: $dash},
        {type: "alert", id: $rule}
      ],
      includeReferencesDeep: true,
      excludeExportDetails: false
    }')" \
  > "${KIBANA_REPO_ROOT}/kibana/saved_objects/lab-objects.ndjson"
log "  → kibana/saved_objects/lab-objects.ndjson"

for tool_id in "${TOOL_IDS[@]}"; do
  log "Exporting tool ${tool_id}"
  kibana_curl "${KIBANA_URL}/api/agent_builder/tools/${tool_id}" \
    | jq '.' \
    > "${KIBANA_REPO_ROOT}/kibana/agent_builder/tools/${tool_id}.json"
  log "  → kibana/agent_builder/tools/${tool_id}.json"
done

for skill_id in "${SKILL_IDS[@]}"; do
  log "Exporting skill ${skill_id}"
  kibana_curl "${KIBANA_URL}/api/agent_builder/skills/${skill_id}" \
    | jq '.' \
    > "${KIBANA_REPO_ROOT}/kibana/agent_builder/skills/${skill_id}.json"
  log "  → kibana/agent_builder/skills/${skill_id}.json"
done

log "Exporting agent ${AGENT_ID} (reference for skill assignment)"
kibana_curl "${KIBANA_URL}/api/agent_builder/agents/${AGENT_ID}" \
  | jq '.' \
  > "${KIBANA_REPO_ROOT}/kibana/agent_builder/agents/${AGENT_ID}.json"
log "  → kibana/agent_builder/agents/${AGENT_ID}.json"

cat <<EOF

Export complete.

Next steps:
  1. Review diffs (especially RCA workflow — emails should be __RCA_NOTIFICATION_EMAIL__ only)
  2. git add kibana/
  3. On a new lab: set rca_notification_email in vars.yml → make kibana-deploy

Transform otel-demo-orders-latest is already in scripts/elasticsearch/ (not exported here).
EOF
