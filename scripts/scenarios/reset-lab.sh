#!/usr/bin/env bash
# Restore stable lab state: infra, payment, fraud-detection memory, ordered pod wait.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

INFRA_DEPLOYMENTS=(postgresql kafka valkey-cart)

ensure_namespace

log "Restoring infrastructure deployments to 1 replica"
for dep in "${INFRA_DEPLOYMENTS[@]}"; do
  kubectl_ns scale "deployment/${dep}" --replicas=1
done

log "Restoring payment replicas"
kubectl_ns scale deployment/payment --replicas=1

log "Restoring fraud-detection memory (512Mi limit, 256Mi request — matches otel-values.yaml.j2)"
kubectl_ns patch deployment fraud-detection --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "fraud-detection",
          "resources": {
            "requests": {"memory": "256Mi"},
            "limits": {"memory": "512Mi"}
          }
        }]
      }
    }
  }
}'

kubectl_ns rollout restart deployment/fraud-detection deployment/payment 2>/dev/null || true

WAIT_SCRIPT="${REPO_ROOT}/scripts/wait-otel-demo-ready.sh"
if [[ -x /opt/otel-demo/wait-otel-demo-ready.sh ]]; then
  WAIT_SCRIPT="/opt/otel-demo/wait-otel-demo-ready.sh"
fi
if [[ -x "${WAIT_SCRIPT}" ]]; then
  log "Running ordered readiness wait"
  OTEL_DEMO_NAMESPACE="${NAMESPACE}" bash "${WAIT_SCRIPT}"
else
  log "Wait script not found at ${WAIT_SCRIPT}; waiting for payment rollout only"
  wait_rollout payment
fi

log "Lab reset complete"
