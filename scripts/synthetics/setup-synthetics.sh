#!/usr/bin/env bash
# End-to-end Synthetics setup for the OTel Demo lab.
#
# Phase A (manual, once): Fleet agent policy + enrollment token in vars.yml — see docs/phase2-synthetics.md
# Phase B (this script): deploy agent → wait Fleet → create Private Location → push monitors
#
# Usage:
#   ./scripts/synthetics/setup-synthetics.sh
#   ./scripts/synthetics/setup-synthetics.sh --skip-deploy   # agent already running

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/hosts.ini}"
SKIP_DEPLOY=0

for arg in "$@"; do
  case "${arg}" in
    --skip-deploy) SKIP_DEPLOY=1 ;;
    -h|--help)
      echo "Usage: $0 [--skip-deploy]"
      exit 0
      ;;
    *) echo "Unknown option: ${arg}" >&2; exit 1 ;;
  esac
done

# shellcheck source=load-vars.sh
source "${SCRIPT_DIR}/load-vars.sh"

log() { echo "[setup-synthetics] $*" >&2; }

if [[ "${SKIP_DEPLOY}" -eq 0 ]]; then
  log "1/4 Deploying Elastic Agent on the lab VM (Ansible)..."
  ansible-playbook -i "${INVENTORY}" "${ROOT}/synthetics-deploy.yml"
else
  log "1/4 Skipping agent deploy (--skip-deploy)"
fi

log "2/4 Waiting for Fleet agent to come online..."
"${SCRIPT_DIR}/wait-fleet-agent.sh"

log "3/4 Creating Private Location (API, idempotent)..."
"${SCRIPT_DIR}/create-private-location.sh"

log "4/4 Pushing Synthetics monitors..."
"${SCRIPT_DIR}/push-monitors.sh"

log "Synthetics setup complete."
