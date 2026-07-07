#!/usr/bin/env bash
# Lower fraud-detection memory limit to trigger OOMKill (infra observability demo).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

TARGET="${OOM_TARGET_DEPLOYMENT:-fraud-detection}"
MEMORY_LIMIT="${OOM_MEMORY_LIMIT:-64Mi}"
# Requests must be <= limits (chart default request is 256Mi).
MEMORY_REQUEST="${OOM_MEMORY_REQUEST:-32Mi}"

ensure_namespace
log "Patching ${TARGET} memory to request=${MEMORY_REQUEST} limit=${MEMORY_LIMIT} and restarting"
kubectl_ns patch deployment "${TARGET}" --type=strategic -p "{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [{
          \"name\": \"${TARGET}\",
          \"resources\": {
            \"requests\": {\"memory\": \"${MEMORY_REQUEST}\"},
            \"limits\": {\"memory\": \"${MEMORY_LIMIT}\"}
          }
        }]
      }
    }
  }
}"
kubectl_ns rollout restart "deployment/${TARGET}"
wait_rollout "${TARGET}" || true
log "${TARGET} restarted with low memory — watch for OOMKilled in kubectl get pods"
