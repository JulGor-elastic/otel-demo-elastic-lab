#!/usr/bin/env bash
# Wait for Fleet agent, optionally create Private Location, push monitors.
#
# Usage:
#   ./scripts/synthetics/configure.sh
#   SYNTHETICS_SKIP_PRIVATE_LOCATION=1 ./scripts/synthetics/configure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/wait-fleet-agent.sh"
"${SCRIPT_DIR}/reassign-fleet-agent.sh"

if [[ "${SYNTHETICS_SKIP_PRIVATE_LOCATION:-}" == "1" ]]; then
  echo "[synthetics-configure] Skipping Private Location create (SYNTHETICS_SKIP_PRIVATE_LOCATION=1)"
else
  "${SCRIPT_DIR}/create-private-location.sh" || {
    echo ""
    echo "If creation failed with HTTP 500, see docs/phase2-synthetics.md (Known cluster bug)."
    echo "Reuse an existing location: SYNTHETICS_SKIP_PRIVATE_LOCATION=1 make synthetics-configure"
    exit 1
  }
fi

"${SCRIPT_DIR}/push-monitors.sh"
