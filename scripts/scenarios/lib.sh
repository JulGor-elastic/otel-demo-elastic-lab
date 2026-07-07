#!/usr/bin/env bash
# Shared helpers for OTel Demo scenario scripts (Phase 4).
set -euo pipefail

NAMESPACE="${OTEL_DEMO_NAMESPACE:-otel-demo}"
KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
export KUBECONFIG

log() { echo "[scenario] $*"; }

kubectl_ns() {
  kubectl "$@" -n "${NAMESPACE}"
}

wait_rollout() {
  local deployment="$1"
  log "Waiting for rollout: ${deployment}"
  kubectl_ns rollout status "deployment/${deployment}" --timeout=120s
}

ensure_namespace() {
  if ! kubectl_ns get namespace "${NAMESPACE}" &>/dev/null; then
    log "ERROR: namespace ${NAMESPACE} not found"
    exit 1
  fi
}
