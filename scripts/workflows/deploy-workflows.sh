#!/usr/bin/env bash
# Deploy OTel Demo Elastic Workflows to Kibana (Phase 4 — F4).
#
# Required environment variables (or set in vars.yml and export before running):
#   KIBANA_URL                  — Serverless Kibana URL (*.kb.*.aws.elastic.cloud)
#   ELASTIC_API_KEY             — API key with workflowsManagement:create
#   GITHUB_HTTP_CONNECTOR_ID    — HTTP connector ID for GitHub API (see create-github-connector.sh)
#   GITHUB_REPO_OWNER           — GitHub org or user
#   GITHUB_REPO_NAME            — Repository name
#   GITHUB_REF                  — Branch for workflow_dispatch (default: main)
#
# Usage:
#   source vars.yml  # or export vars manually
#   export KIBANA_URL="https://..."
#   export ELASTIC_API_KEY="..."
#   ./scripts/workflows/deploy-workflows.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KIBANA_URL="${KIBANA_URL:?Set KIBANA_URL}"
ELASTIC_API_KEY="${ELASTIC_API_KEY:-${elastic_api_key:-${elastic_token:-}}}"
GITHUB_HTTP_CONNECTOR_ID="${GITHUB_HTTP_CONNECTOR_ID:-${github_http_connector_id:-}}"
GITHUB_REPO_OWNER="${GITHUB_REPO_OWNER:-${github_repo_owner:-}}"
GITHUB_REPO_NAME="${GITHUB_REPO_NAME:-${github_repo_name:-}}"
GITHUB_REF="${GITHUB_REF:-${github_ref:-main}}"

if [[ -z "${ELASTIC_API_KEY}" ]]; then
  echo "Set ELASTIC_API_KEY or elastic_api_key in vars.yml" >&2
  exit 1
fi
if [[ -z "${GITHUB_HTTP_CONNECTOR_ID}" || -z "${GITHUB_REPO_OWNER}" || -z "${GITHUB_REPO_NAME}" ]]; then
  echo "Set GITHUB_HTTP_CONNECTOR_ID, GITHUB_REPO_OWNER, GITHUB_REPO_NAME" >&2
  exit 1
fi

substitute_placeholders() {
  local file="$1"
  sed \
    -e "s|__GITHUB_HTTP_CONNECTOR_ID__|${GITHUB_HTTP_CONNECTOR_ID}|g" \
    -e "s|__GITHUB_REPO_OWNER__|${GITHUB_REPO_OWNER}|g" \
    -e "s|__GITHUB_REPO_NAME__|${GITHUB_REPO_NAME}|g" \
    -e "s|__GITHUB_REF__|${GITHUB_REF}|g" \
    "${file}"
}

deploy_workflow() {
  local file="$1"
  local yaml_content
  yaml_content="$(substitute_placeholders "${file}")"
  local name
  name="$(basename "${file}" .yaml)"

  echo "Deploying workflow: ${name}"
  curl -fsSL -X POST "${KIBANA_URL}/api/workflows/workflow" \
    -H "Authorization: ApiKey ${ELASTIC_API_KEY}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg yaml "${yaml_content}" '{yaml: $yaml}')" | jq -r '.id // .workflowId // "ok"'
}

shopt -s nullglob
for wf in "${SCRIPT_DIR}"/otel-demo-*.yaml; do
  deploy_workflow "${wf}"
done

echo "Done. Open Kibana → Workflows to run scenarios."
