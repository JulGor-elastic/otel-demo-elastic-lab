#!/usr/bin/env bash
# Scale payment to 0 — checkout fails; order-placed logs stop (business-impact demo).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_namespace
log "Scaling deployment/payment to 0 replicas"
kubectl_ns scale deployment/payment --replicas=0
kubectl_ns wait --for=delete pod -l opentelemetry.io/name=payment --timeout=120s 2>/dev/null || true
log "payment is down — trigger checkout in the storefront to observe failures in Elastic"
