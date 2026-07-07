#!/usr/bin/env bash
# Wait until the OTel Demo is ready, respecting dependency order between
# infrastructure components and microservices.
#
# Known issue: on Minikube, pods are scheduled in parallel and some
# microservices hang if their dependencies (kafka, postgresql, etc.) are not
# ready yet. The Helm chart includes init containers on some services but not
# all; this script complements helm --wait with explicit waits and rollout
# restart remediation.

set -euo pipefail

NAMESPACE="${OTEL_DEMO_NAMESPACE:-otel-demo}"
KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
export KUBECONFIG

# Infrastructure first, then collector, then everything else.
INFRA_COMPONENTS=(postgresql kafka valkey-cart flagd)
# Microservices that talk to flagd but lack a wait-for-flagd init container (race on first start)
FLAGD_DEPENDENT_DEPLOYMENTS=(
  cart
  recommendation
  product-catalog
  payment
  shipping
  load-generator
  ad
  fraud-detection
)
TIMEOUT="${WAIT_TIMEOUT:-600}"
REMEDIATION_ROUNDS="${REMEDIATION_ROUNDS:-2}"

log() { echo "[wait-otel-demo] $*"; }

wait_pods_by_label() {
  local component="$1"
  local timeout="$2"
  log "Waiting for ready pods: ${component} (timeout ${timeout}s)"
  kubectl wait --for=condition=ready pod \
    -l "opentelemetry.io/name=${component}" \
    -n "${NAMESPACE}" \
    --timeout="${timeout}s"
}

wait_collector_ready() {
  local timeout="$1"
  log "Waiting for OTel Collector (Helm subchart, timeout ${timeout}s)"
  kubectl wait deployment \
    -l "app.kubernetes.io/name=opentelemetry-collector" \
    -n "${NAMESPACE}" \
    --for=condition=Available \
    --timeout="${timeout}s"
}

wait_deployment_by_name_label() {
  local name="$1"
  local timeout="$2"
  log "Waiting for deployment: ${name} (timeout ${timeout}s)"
  kubectl wait deployment \
    -l "app.kubernetes.io/name=${name}" \
    -n "${NAMESPACE}" \
    --for=condition=Available \
    --timeout="${timeout}s"
}

wait_all_pods_ready() {
  local timeout="$1"
  log "Waiting for all pods in namespace to be Ready (timeout ${timeout}s)"
  kubectl wait --for=condition=ready pod \
    --all \
    -n "${NAMESPACE}" \
    --timeout="${timeout}s"
}

count_unready_pods() {
  kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null \
    | awk '$2 !~ /^[0-9]+\/[0-9]+$/ || $3 != "Running" { count++ } END { print count+0 }'
}

remediate_unhealthy_workloads() {
  log "Restarting workloads with unavailable replicas"
  local deploy
  while IFS= read -r deploy; do
    [[ -z "${deploy}" ]] && continue
    log "  rollout restart deployment/${deploy}"
    kubectl rollout restart "deployment/${deploy}" -n "${NAMESPACE}"
  done < <(
    kubectl get deploy -n "${NAMESPACE}" -o json \
      | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    status = item.get('status', {})
    desired = status.get('replicas', 0)
    available = status.get('availableReplicas', 0)
    if desired and available < desired:
        print(item['metadata']['name'])
"
  )

  local sts
  while IFS= read -r sts; do
    [[ -z "${sts}" ]] && continue
    log "  rollout restart statefulset/${sts}"
    kubectl rollout restart "statefulset/${sts}" -n "${NAMESPACE}"
  done < <(
    kubectl get statefulset -n "${NAMESPACE}" -o json 2>/dev/null \
      | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    status = item.get('status', {})
    desired = status.get('replicas', 0)
    ready = status.get('readyReplicas', 0)
    if desired and ready < desired:
        print(item['metadata']['name'])
" 2>/dev/null || true
  )
}

restart_flagd_dependent_services() {
  log "Rollout restart: microservices that depend on flagd (startup race mitigation)"
  local deploy
  local names=()
  for deploy in "${FLAGD_DEPENDENT_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "${deploy}" -n "${NAMESPACE}" &>/dev/null; then
      names+=("${deploy}")
    fi
  done
  if ((${#names[@]} == 0)); then
    log "  no flagd-dependent deployments found; skipping"
    return 0
  fi
  kubectl rollout restart deployment "${names[@]}" -n "${NAMESPACE}"
  for deploy in "${names[@]}"; do
    log "  waiting for deployment/${deploy}"
    kubectl rollout status "deployment/${deploy}" -n "${NAMESPACE}" --timeout="${TIMEOUT}s"
  done
}

count_oom_pods() {
  kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null \
    | awk '$4 ~ /OOMKilled/ { count++ } END { print count+0 }'
}

assert_cluster_healthy() {
  local oom unready
  oom="$(count_oom_pods)"
  if (( oom > 0 )); then
    log "ERROR: ${oom} pod(s) in OOMKilled state"
    kubectl get pods -n "${NAMESPACE}" | awk 'NR==1 || /OOMKilled/'
    return 1
  fi
  unready="$(count_unready_pods)"
  if (( unready > 0 )); then
    log "ERROR: ${unready} pod(s) not Running/Ready"
    kubectl get pods -n "${NAMESPACE}"
    return 1
  fi
  return 0
}

# Phase 1: infrastructure in order
for component in "${INFRA_COMPONENTS[@]}"; do
  wait_pods_by_label "${component}" "${TIMEOUT}"
done

# Phase 1b: flagd is up but dependents may have started too early
restart_flagd_dependent_services

# Phase 2: collector (subchart) before most microservices
wait_collector_ready "${TIMEOUT}"

# Phase 2b: Prometheus and Grafana (Phase 1 observability stack)
wait_deployment_by_name_label "prometheus" "${TIMEOUT}"
wait_deployment_by_name_label "grafana" "${TIMEOUT}"

# Phase 3: all pods + remediation if needed
round=0
while (( round <= REMEDIATION_ROUNDS )); do
  if wait_all_pods_ready "${TIMEOUT}" && assert_cluster_healthy; then
    log "All pods are Ready and healthy"
    exit 0
  fi

  unready="$(count_unready_pods)"
  if (( round == REMEDIATION_ROUNDS )); then
    log "ERROR: ${unready} pod(s) still not Ready after ${REMEDIATION_ROUNDS} remediation round(s)"
    kubectl get pods -n "${NAMESPACE}"
    exit 1
  fi

  log "${unready} pod(s) not Ready; remediation round $((round + 1))/${REMEDIATION_ROUNDS}"
  remediate_unhealthy_workloads
  log "Waiting for stabilization after remediation..."
  sleep 30
  round=$((round + 1))
done
