#!/usr/bin/env bash
# Restore payment service to 1 replica.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ensure_namespace
log "Scaling deployment/payment to 1 replica"
kubectl_ns scale deployment/payment --replicas=1
wait_rollout payment
log "payment recovered"
