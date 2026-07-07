#!/usr/bin/env bash
# Scale PostgreSQL to 0 — shared DB dependency; widespread service errors and no new orders.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_namespace
log "Scaling deployment/postgresql to 0 replicas"
kubectl_ns scale deployment/postgresql --replicas=0
kubectl_ns wait --for=delete pod -l opentelemetry.io/name=postgresql --timeout=120s 2>/dev/null || true
log "postgresql is down — cart, checkout, product-catalog and others will fail in Elastic"
