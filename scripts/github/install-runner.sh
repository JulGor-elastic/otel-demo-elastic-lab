#!/usr/bin/env bash
# Install a GitHub Actions self-hosted runner on the GCP VM (one-time setup).
#
# GitHub config.sh MUST NOT run as root ("Must not run with sudo").
# This script registers the runner as a normal user (default: julio) and only
# uses root/sudo for packages and the systemd service (svc.sh).
#
# Usage (recommended — run as your SSH user, NOT via sudo su):
#   ./scripts/github/install-runner.sh \
#     --repo JulGor-elastic/otel-demo-elastic-lab \
#     --token ghp_...
#
# Optional:
#   --user julio          Service account (default: current user or SUDO_USER)
#   --dir /path           Install dir (default: /home/<user>/actions-runner)
#   --name otel-demo-vm
#   --labels self-hosted,otel-demo

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-runner.sh --repo OWNER/REPO --token ghp_... [options]

GitHub refuses ./config.sh as root. Run this script as your SSH user (julio).
Do NOT use "sudo su" then run the script — use flags instead.

Options:
  --repo, -r     GitHub repository (required)
  --token, -t    GitHub PAT with repo scope (required)
  --user, -u     Unix user for the runner (default: julio or current user)
  --dir          Install directory (default: /home/<user>/actions-runner)
  --name         Runner name (default: otel-demo-vm)
  --labels       Labels (default: self-hosted,otel-demo)
  -h, --help

Example:
  cd /opt/otel-demo-lab
  ./scripts/github/install-runner.sh \
    -r JulGor-elastic/otel-demo-elastic-lab \
    -t ghp_xxx \
    --dir /opt/actions-runner
EOF
}

GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
RUNNER_NAME="${RUNNER_NAME:-otel-demo-vm}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,otel-demo}"
RUNNER_USER="${RUNNER_USER:-}"
RUNNER_DIR="${RUNNER_DIR:-}"
RUNNER_VERSION="${RUNNER_VERSION:-2.323.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo|-r)   GITHUB_REPO="$2"; shift 2 ;;
    --token|-t)  GITHUB_TOKEN="$2"; shift 2 ;;
    --user|-u)   RUNNER_USER="$2"; shift 2 ;;
    --dir)       RUNNER_DIR="$2"; shift 2 ;;
    --name)      RUNNER_NAME="$2"; shift 2 ;;
    --labels)    RUNNER_LABELS="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${GITHUB_REPO}" || -z "${GITHUB_TOKEN}" ]]; then
  echo "ERROR: --repo and --token are required." >&2
  usage >&2
  exit 1
fi

if [[ -z "${RUNNER_USER}" ]]; then
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    RUNNER_USER="${SUDO_USER}"
  elif [[ "$(id -u)" -ne 0 ]]; then
    RUNNER_USER="$(id -un)"
  else
    RUNNER_USER="julio"
  fi
fi

if [[ -z "${RUNNER_DIR}" ]]; then
  RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"
fi

if [[ "$(id -u)" -eq 0 && "${RUNNER_USER}" == "root" ]]; then
  echo "ERROR: Do not install the runner as root. Use --user julio" >&2
  exit 1
fi

log() { echo "[install-runner] $*"; }

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

log "Runner user: ${RUNNER_USER}"
log "Runner dir:  ${RUNNER_DIR}"

if ! id "${RUNNER_USER}" &>/dev/null; then
  echo "ERROR: user ${RUNNER_USER} does not exist" >&2
  exit 1
fi

as_root apt-get update -qq
as_root apt-get install -y curl jq

as_root mkdir -p "${RUNNER_DIR}"
as_root chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_DIR}"

if [[ -f "${RUNNER_DIR}/svc.sh" ]]; then
  log "Stopping existing runner service (if any)"
  as_root bash -c "cd '${RUNNER_DIR}' && ./svc.sh stop" 2>/dev/null || true
fi

log "Downloading actions-runner v${RUNNER_VERSION}"
sudo -u "${RUNNER_USER}" bash <<EOF
set -euo pipefail
cd '${RUNNER_DIR}'
ARCH="x64"
TARBALL="actions-runner-linux-\${ARCH}-${RUNNER_VERSION}.tar.gz"
curl -fsSL -o "\${TARBALL}" \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/\${TARBALL}"
tar xzf "\${TARBALL}"
rm -f "\${TARBALL}"
EOF

log "Requesting runner registration token for ${GITHUB_REPO}"
api_response="$(curl -fsSL -w '\n%{http_code}' -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token")"

http_code="${api_response##*$'\n'}"
api_body="${api_response%$'\n'*}"

REG_TOKEN="$(echo "${api_body}" | jq -r '.token // empty')"

if [[ -z "${REG_TOKEN}" ]]; then
  log "Failed to obtain runner registration token (HTTP ${http_code})"
  echo "${api_body}" | jq -r '.message // .' 2>/dev/null || echo "${api_body}"
  exit 1
fi

log "Configuring runner (as user ${RUNNER_USER} — not root)"
sudo -u "${RUNNER_USER}" bash <<EOF
set -euo pipefail
cd '${RUNNER_DIR}'
./config.sh --unattended \
  --url "https://github.com/${GITHUB_REPO}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --work "${RUNNER_DIR}/_work" \
  --replace
EOF

log "Installing systemd service"
as_root bash -c "cd '${RUNNER_DIR}' && ./svc.sh install && ./svc.sh start"

log "Runner installed for user ${RUNNER_USER}"
log "Verify: https://github.com/${GITHUB_REPO}/settings/actions/runners"
log "Test: Actions → Demo scenarios → Run workflow → reset-lab"
