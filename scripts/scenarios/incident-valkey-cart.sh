#!/usr/bin/env bash
# Scale Valkey (cart cache) to 0 — cart operations fail before checkout.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_namespace
log "Scaling deployment/valkey-cart to 0 replicas"
kubectl_ns scale deployment/valkey-cart --replicas=0
kubectl_ns wait --for=delete pod -l opentelemetry.io/name=valkey-cart --timeout=120s 2>/dev/null || true
log "valkey-cart is down — add-to-cart and checkout path will fail in Elastic"
