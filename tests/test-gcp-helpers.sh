#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "expected output to contain: $needle"
  fi
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true' EXIT
BASE_DIR="${TMP_ROOT}/profiles"

mkdir -p "${BASE_DIR}/alpha/configurations" "${BASE_DIR}/bravo/configurations"
cat > "${BASE_DIR}/alpha/configurations/config_default" <<'EOF'
[core]
account = user-c1@company1.com
project = c1-alpha-project
EOF
cat > "${BASE_DIR}/bravo/configurations/config_default" <<'EOF'
[core]
account = user-c2@company2.com
project = c2-bravo-project
EOF

LS_OUT="$(GCP_CFG_BASE="$BASE_DIR" "${ROOT_DIR}/gcp-ls")"
require_contains "$LS_OUT" "1) alpha, user-c1@company1.com, c1-alpha-project"
require_contains "$LS_OUT" "2) bravo, user-c2@company2.com, c2-bravo-project"

JSON_OUT="$(GCP_CFG_BASE="$BASE_DIR" "${ROOT_DIR}/gcp-ls" --json)"
require_contains "$JSON_OUT" '"name":"alpha"'
require_contains "$JSON_OUT" '"project":"c1-alpha-project"'
require_contains "$JSON_OUT" '"name":"bravo"'

GCP_CFG_BASE="$BASE_DIR" "${ROOT_DIR}/gcp-cp-profile" -y alpha alpha-copy >/dev/null
[[ -d "${BASE_DIR}/alpha-copy" ]] || fail "expected copied profile directory alpha-copy"

GCP_CFG_BASE="$BASE_DIR" "${ROOT_DIR}/gcp-nc" -y bravo bravo-renamed >/dev/null
[[ -d "${BASE_DIR}/bravo-renamed" ]] || fail "expected renamed profile directory bravo-renamed"
[[ ! -d "${BASE_DIR}/bravo" ]] || fail "expected original bravo directory to be gone"

set +e
RM_OUT="$(GCP_CFG_BASE="$BASE_DIR" "${ROOT_DIR}/gcp-rm-profile" 1 2>&1)"
RM_CODE=$?
set -e
[[ "$RM_CODE" -eq 1 ]] || fail "expected gcp-rm-profile non-interactive confirmation failure"
require_contains "$RM_OUT" "confirmation requires an interactive terminal"

STATUS_LIST="$(GCP_CFG_BASE="$BASE_DIR" "${ROOT_DIR}/gcp-status" -l)"
require_contains "$STATUS_LIST" "1) alpha,"

AUTH_LIST="$(bash -lc "GCP_CFG_BASE='${BASE_DIR}' source '${ROOT_DIR}/gcp-auth' -l")"
require_contains "$AUTH_LIST" "1) alpha,"

INDEX_OUT="$("${ROOT_DIR}/gcp-")"
require_contains "$INDEX_OUT" "gcp-cp-profile"
require_contains "$INDEX_OUT" "gcp-rm-profile"

echo "All tests passed."
