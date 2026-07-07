#!/usr/bin/env bash
# Install a GitHub Actions self-hosted runner on the GCP VM (one-time setup).
#
# Required environment variables:
#   GITHUB_REPO   — owner/repo (e.g. elastic/otel-demo-ansible)
#   GITHUB_TOKEN  — PAT with repo + admin:org (for org runners) or repo scope
#
# Optional:
#   RUNNER_NAME   — default: otel-demo-vm
#   RUNNER_LABELS — default: self-hosted,otel-demo
#   RUNNER_DIR    — default: /opt/actions-runner
#
# Usage (on the VM as root):
#   export GITHUB_REPO="your-org/otel-demo-ansible"
#   export GITHUB_TOKEN="ghp_..."
#   sudo -E ./scripts/github/install-runner.sh

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:?Set GITHUB_REPO (owner/repo)}"
GITHUB_TOKEN="${GITHUB_TOKEN:?Set GITHUB_TOKEN (PAT with repo scope)}"
RUNNER_NAME="${RUNNER_NAME:-otel-demo-vm}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,otel-demo}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
RUNNER_VERSION="${RUNNER_VERSION:-2.323.0}"

log() { echo "[install-runner] $*"; }

if [[ "$(id -u)" -ne 0 ]]; then
  log "Run as root (sudo) so kubectl uses /root/.kube/config"
  exit 1
fi

apt-get update -qq
apt-get install -y curl jq

mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

if [[ -f ./run.sh ]]; then
  log "Runner already installed in ${RUNNER_DIR}; stopping service to reconfigure"
  ./svc.sh stop 2>/dev/null || true
fi

ARCH="x64"
TARBALL="actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"
curl -fsSL -o "${TARBALL}" \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"
tar xzf "${TARBALL}"
rm -f "${TARBALL}"

REG_TOKEN="$(curl -fsSL -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
  | jq -r '.token')"

if [[ -z "${REG_TOKEN}" || "${REG_TOKEN}" = "null" ]]; then
  log "Failed to obtain runner registration token"
  exit 1
fi

./config.sh --unattended \
  --url "https://github.com/${GITHUB_REPO}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --work "${RUNNER_DIR}/_work" \
  --replace

./svc.sh install
./svc.sh start

log "Runner installed. Verify in GitHub → Settings → Actions → Runners"
log "Test: trigger workflow 'Demo scenarios' with scenario=reset-lab"
