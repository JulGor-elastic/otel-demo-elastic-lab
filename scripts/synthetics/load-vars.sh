#!/usr/bin/env bash
# Source vars.yml into the current shell (bash/zsh).
# Usage: source scripts/synthetics/load-vars.sh

set -euo pipefail

_SYNTH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_VARS_FILE="${SYNTHETICS_VARS_FILE:-${_SYNTH_ROOT}/vars.yml}"

if [[ ! -f "${_VARS_FILE}" ]]; then
  echo "vars.yml not found at ${_VARS_FILE} (copy vars.yml.example)" >&2
  return 1 2>/dev/null || exit 1
fi

_load_with_python() {
  python3 - "${_VARS_FILE}" <<'PY'
import shlex, sys

try:
    import yaml
except ImportError:
    sys.exit(2)

data = yaml.safe_load(open(sys.argv[1])) or {}
for key, value in data.items():
    if value is None or isinstance(value, (dict, list)):
        continue
    print(f"export {key.upper()}={shlex.quote(str(value))}")
PY
}

_load_with_grep() {
  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    if [[ "${line}" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      val="${val#\"}"; val="${val%\"}"
      val="${val#\'}"; val="${val%\'}"
      key_upper="$(printf '%s' "${key}" | tr '[:lower:]' '[:upper:]')"
      printf 'export %s=%q\n' "${key_upper}" "${val}"
    fi
  done < "${_VARS_FILE}"
}

output=""
if output="$(_load_with_python 2>/dev/null)" && [[ -n "${output}" ]]; then
  :
elif output="$(_load_with_grep)"; then
  :
else
  echo "Could not parse vars.yml" >&2
  return 1 2>/dev/null || exit 1
fi

eval "${output}"

export KIBANA_URL="${KIBANA_URL:-${kibana_url:-}}"
export ELASTIC_API_KEY="${ELASTIC_API_KEY:-${elastic_api_key:-${ELASTIC_TOKEN:-${elastic_token:-}}}}"
export SYNTHETICS_PRIVATE_LOCATION_NAME="${SYNTHETICS_PRIVATE_LOCATION_NAME:-${synthetics_private_location_name:-}}"
