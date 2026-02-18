#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../gcp-common
source "${ROOT_DIR}/gcp-common"

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

require_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "expected output to not contain: $needle"
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
touch "${BASE_DIR}/alpha/application_default_credentials.json"
cat > "${BASE_DIR}/bravo/configurations/config_default" <<'EOF'
[core]
account = user-c2@company2.com
project = c2-bravo-project
EOF

LS_OUT="$(GCP_CFG_BASE="$BASE_DIR" "${ROOT_DIR}/gcp-ls")"
require_contains "$LS_OUT" "1) alpha, user-c1@company1.com, c1-alpha-project"
require_contains "$LS_OUT" "2) bravo, user-c2@company2.com, c2-bravo-project"

ACTIVE_LS_OUT="$(GCP_CFG_BASE="$BASE_DIR" CLOUDSDK_CONFIG="${BASE_DIR}/alpha" "${ROOT_DIR}/gcp-ls")"
require_contains "$ACTIVE_LS_OUT" "*1) alpha, user-c1@company1.com, c1-alpha-project"

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

ERREXIT_STATE="$(bash -lc "set +e; GCP_CFG_BASE='${BASE_DIR}' source '${ROOT_DIR}/gcp-auth' -l >/dev/null; set -o | awk '/errexit/ {print \$2}'")"
require_contains "$ERREXIT_STATE" "off"

AUTH_NOARG="$(bash -lc "GCP_CFG_BASE='${BASE_DIR}' source '${ROOT_DIR}/gcp-auth'")"
require_contains "$AUTH_NOARG" "1) alpha,"
require_contains "$AUTH_NOARG" "Run: source gcp-auth <profile_number_or_name>"

FAKE_BIN="${TMP_ROOT}/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_GCLOUD_LOG:-}" ]]; then
  printf "%s\n" "$*" >> "${FAKE_GCLOUD_LOG}"
fi

if [[ "${1:-}" == "--quiet" ]]; then
  shift
fi

if [[ "${1:-}" == "config" && "${2:-}" == "get-value" ]]; then
  key="${3:-}"
  cfg="${CLOUDSDK_CONFIG:-}/configurations/config_default"
  if [[ -f "$cfg" ]]; then
    value="$(sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "$cfg" | head -n1)"
    if [[ -n "$value" ]]; then
      printf "%s\n" "$value"
      exit 0
    fi
  fi
  echo "(unset)"
  exit 0
fi

if [[ "${1:-}" == "config" && "${2:-}" == "set" ]]; then
  key="${3:-}"
  value="${4:-}"
  cfg="${CLOUDSDK_CONFIG:-}/configurations/config_default"
  mkdir -p "$(dirname "$cfg")"
  if [[ ! -f "$cfg" ]]; then
    printf "[core]\n" > "$cfg"
  fi
  tmp_cfg="${cfg}.tmp"
  awk -v key="$key" -v value="$value" '
    BEGIN { replaced=0 }
    $0 ~ "^" key "[[:space:]]*=" {
      print key " = " value
      replaced=1
      next
    }
    { print }
    END {
      if (!replaced) {
        print key " = " value
      }
    }
  ' "$cfg" > "$tmp_cfg"
  mv "$tmp_cfg" "$cfg"
  exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == "--update-adc" ]]; then
      touch "${CLOUDSDK_CONFIG:-}/application_default_credentials.json"
      break
    fi
  done
  exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "application-default" && "${3:-}" == "login" ]]; then
  touch "${CLOUDSDK_CONFIG:-}/application_default_credentials.json"
  exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "application-default" && "${3:-}" == "set-quota-project" ]]; then
  exit 0
fi

echo "fake gcloud unexpected args: $*" >&2
exit 1
EOF
chmod +x "${FAKE_BIN}/gcloud"

: > "${TMP_ROOT}/gcloud.log"
set +e
AUTH_EMAIL_ONLY_NEW="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' tn-tndata-api admin-ag039ag@tn.gov" 2>&1
)"
AUTH_EMAIL_ONLY_NEW_CODE=$?
set -e
[[ "$AUTH_EMAIL_ONLY_NEW_CODE" -eq 2 ]] || fail "expected missing-project failure when second arg is an email"
require_contains "$AUTH_EMAIL_ONLY_NEW" "has no saved project"
require_contains "$AUTH_EMAIL_ONLY_NEW" "argument order is"
[[ ! -s "${TMP_ROOT}/gcloud.log" ]] || fail "expected no gcloud calls when project is missing"

: > "${TMP_ROOT}/gcloud.log"
AUTH_PROJECT_ONLY_EXISTING_ADC="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' -y alpha c1-alpha-next" 2>&1
)"
require_contains "$AUTH_PROJECT_ONLY_EXISTING_ADC" "==> Project: c1-alpha-next"
require_contains "$AUTH_PROJECT_ONLY_EXISTING_ADC" "set-quota-project"
PROJECT_ONLY_LOG="$(cat "${TMP_ROOT}/gcloud.log")"
require_contains "$PROJECT_ONLY_LOG" "config set project c1-alpha-next"
require_contains "$PROJECT_ONLY_LOG" "auth application-default set-quota-project c1-alpha-next"
require_not_contains "$PROJECT_ONLY_LOG" "auth login"
require_not_contains "$PROJECT_ONLY_LOG" "auth application-default login"

: > "${TMP_ROOT}/gcloud.log"
rm -f "${BASE_DIR}/alpha/application_default_credentials.json"
AUTH_PROJECT_ONLY_MISSING_ADC="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' -y alpha c1-alpha-next2" 2>&1
)"
require_contains "$AUTH_PROJECT_ONLY_MISSING_ADC" "==> Project: c1-alpha-next2"
require_contains "$AUTH_PROJECT_ONLY_MISSING_ADC" "application-default login"
PROJECT_ONLY_NO_ADC_LOG="$(cat "${TMP_ROOT}/gcloud.log")"
require_contains "$PROJECT_ONLY_NO_ADC_LOG" "config set project c1-alpha-next2"
require_contains "$PROJECT_ONLY_NO_ADC_LOG" "auth application-default login"
require_not_contains "$PROJECT_ONLY_NO_ADC_LOG" "auth login"
require_not_contains "$PROJECT_ONLY_NO_ADC_LOG" "set-quota-project"

touch "${BASE_DIR}/alpha/application_default_credentials.json"
: > "${TMP_ROOT}/gcloud.log"
AUTH_SWAPPED_ARGS="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' -y alpha new-user@company1.com c1-alpha-project" 2>&1
)"
require_contains "$AUTH_SWAPPED_ARGS" "Warning: argument order looked swapped"
require_contains "$AUTH_SWAPPED_ARGS" "==> Project: c1-alpha-project"
require_contains "$AUTH_SWAPPED_ARGS" "==> Preferred account: new-user@company1.com"

: > "${TMP_ROOT}/gcloud.log"
AUTH_SINGLE_STEP_UPDATE_ADC="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' -y alpha c1-alpha-project combined-flow@company1.com" 2>&1
)"
require_contains "$AUTH_SINGLE_STEP_UPDATE_ADC" "auth login --update-adc"
SINGLE_STEP_LOG="$(cat "${TMP_ROOT}/gcloud.log")"
require_contains "$SINGLE_STEP_LOG" "auth login --account=combined-flow@company1.com"
require_contains "$SINGLE_STEP_LOG" "--update-adc"
require_not_contains "$SINGLE_STEP_LOG" "auth application-default login"

: > "${TMP_ROOT}/gcloud.log"
AUTH_NO_BROWSER="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' -y --no-browser alpha c1-alpha-project nobrowser-flow@company1.com" 2>&1
)"
require_contains "$AUTH_NO_BROWSER" "Browser launch disabled"
NO_BROWSER_LOG="$(cat "${TMP_ROOT}/gcloud.log")"
require_contains "$NO_BROWSER_LOG" "auth login --account=nobrowser-flow@company1.com --no-launch-browser --update-adc"
require_not_contains "$NO_BROWSER_LOG" "auth application-default login"

: > "${TMP_ROOT}/gcloud.log"
AUTH_NO_BROSER_ALIAS="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' -y --no-broser alpha c1-alpha-project typoalias-flow@company1.com" 2>&1
)"
NO_BROSER_ALIAS_LOG="$(cat "${TMP_ROOT}/gcloud.log")"
require_contains "$NO_BROSER_ALIAS_LOG" "auth login --account=typoalias-flow@company1.com --no-launch-browser --update-adc"
require_not_contains "$NO_BROSER_ALIAS_LOG" "auth application-default login"

: > "${TMP_ROOT}/gcloud.log"
AUTH_WSL_AUTO_NO_BROWSER="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" WSL_INTEROP='/tmp/wsl.sock' GCP_CFG_BASE='${BASE_DIR}' FAKE_GCLOUD_LOG='${TMP_ROOT}/gcloud.log' source '${ROOT_DIR}/gcp-auth' -y alpha c1-alpha-project wsl-auto@company1.com" 2>&1
)"
WSL_AUTO_LOG="$(cat "${TMP_ROOT}/gcloud.log")"
require_contains "$WSL_AUTO_LOG" "auth login --account=wsl-auto@company1.com --no-launch-browser --update-adc"

AUTH_SWITCH_BY_INDEX="$(
  bash -lc "PATH='${FAKE_BIN}':\"\$PATH\" GCP_CFG_BASE='${BASE_DIR}' source '${ROOT_DIR}/gcp-auth' 3; printf 'CLOUDSDK_CONFIG=%s\n' \"\$CLOUDSDK_CONFIG\""
)"
require_contains "$AUTH_SWITCH_BY_INDEX" "==> Using profile: bravo-renamed"
require_contains "$AUTH_SWITCH_BY_INDEX" "Re-auth skipped"
require_contains "$AUTH_SWITCH_BY_INDEX" "CLOUDSDK_CONFIG=${BASE_DIR}/bravo-renamed"

set +e
AUTH_BAD_INDEX="$(bash -lc "GCP_CFG_BASE='${BASE_DIR}' source '${ROOT_DIR}/gcp-auth' 99" 2>&1)"
AUTH_BAD_INDEX_CODE=$?
set -e
[[ "$AUTH_BAD_INDEX_CODE" -eq 2 ]] || fail "expected gcp-auth invalid numeric selector failure"
require_contains "$AUTH_BAD_INDEX" "profile number '99' not found"

LOCK_BASE="${TMP_ROOT}/lock-base"
LOCK_DIR="${LOCK_BASE}/.gcpdash.lock"
mkdir -p "$LOCK_DIR"
printf "999999\n" > "${LOCK_DIR}/pid"
LOCK_STALE_MARKER="${TMP_ROOT}/lock-stale.marker"
gcp_run_with_lock "$LOCK_BASE" bash -c "printf 'ok\n' > '${LOCK_STALE_MARKER}'"
[[ -f "$LOCK_STALE_MARKER" ]] || fail "expected stale lock to be reclaimed and command to run"
[[ ! -d "$LOCK_DIR" ]] || fail "expected stale lock dir to be removed"

set +e
gcp_run_with_lock "$LOCK_BASE" bash -c 'kill -INT $$'
LOCK_INT_CODE=$?
set -e
[[ "$LOCK_INT_CODE" -eq 130 ]] || fail "expected INT path to return 130 from gcp_run_with_lock"
[[ ! -d "$LOCK_DIR" ]] || fail "expected lock dir cleanup after INT"

INDEX_OUT="$("${ROOT_DIR}/gcp-")"
require_contains "$INDEX_OUT" "gcp-cp-profile"
require_contains "$INDEX_OUT" "gcp-rm-profile"

echo "All tests passed."
