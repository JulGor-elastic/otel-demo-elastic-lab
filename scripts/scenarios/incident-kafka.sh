#!/usr/bin/env bash
# Scale Kafka to 0 — async messaging breaks; checkout and downstream consumers error.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_namespace
log "Scaling deployment/kafka to 0 replicas"
kubectl_ns scale deployment/kafka --replicas=0
kubectl_ns wait --for=delete pod -l opentelemetry.io/name=kafka --timeout=120s 2>/dev/null || true
log "kafka is down — event-driven spans and logs will show producer/consumer failures"
