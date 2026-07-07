#!/usr/bin/env bash
# Lower fraud-detection memory limit to trigger OOMKill (infra observability demo).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

TARGET="${OOM_TARGET_DEPLOYMENT:-fraud-detection}"
MEMORY_LIMIT="${OOM_MEMORY_LIMIT:-64Mi}"

ensure_namespace
log "Patching ${TARGET} memory limit to ${MEMORY_LIMIT} and restarting"
kubectl_ns patch deployment "${TARGET}" --type=json -p="[
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/limits/memory\",\"value\":\"${MEMORY_LIMIT}\"}
]" 2>/dev/null || \
kubectl_ns set resources "deployment/${TARGET}" --limits=memory="${MEMORY_LIMIT}"
kubectl_ns rollout restart "deployment/${TARGET}"
wait_rollout "${TARGET}" || true
log "${TARGET} restarted with low memory — watch for OOMKilled in kubectl get pods"
