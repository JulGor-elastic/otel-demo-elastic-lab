#!/usr/bin/env bash
# Dispatcher for demo scenarios. Used by GitHub Actions and manual runs.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run.sh <scenario>

Scenarios:
  incident-payment   Scale payment to 0 (checkout failure)
  recover-payment    Scale payment back to 1
  oom-pressure       Lower fraud-detection memory → OOMKill
  reset-lab          Restore stable state + wait script

Environment:
  OTEL_DEMO_NAMESPACE   Kubernetes namespace (default: otel-demo)
  KUBECONFIG            Path to kubeconfig (default: /root/.kube/config)
EOF
}

SCENARIO="${1:-}"
if [[ -z "${SCENARIO}" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${SCENARIO}" in
  incident-payment)  exec bash "${SCRIPT_DIR}/incident-payment.sh" ;;
  recover-payment)   exec bash "${SCRIPT_DIR}/recover-payment.sh" ;;
  oom-pressure)      exec bash "${SCRIPT_DIR}/oom-pressure.sh" ;;
  reset-lab)         exec bash "${SCRIPT_DIR}/reset-lab.sh" ;;
  -h|--help)         usage; exit 0 ;;
  *)
    echo "Unknown scenario: ${SCENARIO}" >&2
    usage
    exit 1
    ;;
esac
