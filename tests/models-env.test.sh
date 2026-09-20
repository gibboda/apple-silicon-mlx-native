#!/usr/bin/env bash
# Parse fixtures for config/models.env (Linux CI safe: no source/eval).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_eq() {
  local label="$1"
  local got="$2"
  local want="$3"
  if [[ "${got}" == "${want}" ]]; then
    pass "${label}"
  else
    fail "${label} (got '${got}', want '${want}')"
  fi
}

expect_fail() {
  local label="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    fail "${label} (expected non-zero exit)"
  else
    pass "${label}"
  fi
}

ENV_FILE="${TMP}/models.env"
PWNED="${TMP}/pwned"

reset_mlx_keys() {
  unset MLX_DEFAULT_MODEL MLX_RECOMMENDED_CONTEXT MLX_IMAGE_FAMILY MLX_IMAGE_MODEL \
    MLX_SERVER_HOST MLX_SERVER_PORT HF_TOKEN
}

# --- quoting ---

expect_eq "simple token stays unquoted" "$(quote_env_value 'mlx-community/Llama-3.2-3B-Instruct-4bit')" \
  "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "spaces become single-quoted" "$(quote_env_value 'hello world')" "'hello world'"
expect_eq "apostrophe uses POSIX concatenation" "$(quote_env_value "it's")" "'it'\\''s'"

# --- upsert quotes and refuses non-MLX keys ---

printf 'MLX_DEFAULT_MODEL=old\n' >"${ENV_FILE}"
upsert_env_assignment "${ENV_FILE}" MLX_DEFAULT_MODEL "hello world"
expect_eq "upsert quotes spaces" "$(cat "${ENV_FILE}")" "MLX_DEFAULT_MODEL='hello world'"
expect_fail "upsert refuses PATH" upsert_env_assignment "${ENV_FILE}" PATH /tmp/evil
expect_fail "upsert refuses HF_TOKEN" upsert_env_assignment "${ENV_FILE}" HF_TOKEN secret

reset_mlx_keys
printf 'MLX_DEFAULT_MODEL=old\n' >"${ENV_FILE}"
upsert_env_assignment "${ENV_FILE}" MLX_DEFAULT_MODEL "Bob's-model"
expect_eq "upsert apostrophe keeps POSIX concatenation" "$(cat "${ENV_FILE}")" \
  "MLX_DEFAULT_MODEL='Bob'\\''s-model'"
load_models_env "${ENV_FILE}" >/dev/null 2>&1
expect_eq "load apostrophe round-trips" "${MLX_DEFAULT_MODEL}" "Bob's-model"
sourced_apostrophe="$(MLX_DEFAULT_MODEL="" bash -c 'set -euo pipefail; source "$1"; printf %s "${MLX_DEFAULT_MODEL}"' bash "${ENV_FILE}")"
expect_eq "source apostrophe round-trips" "${sourced_apostrophe}" "Bob's-model"

# --- load: comments, blanks, MLX_* only ---

reset_mlx_keys
cat >"${ENV_FILE}" <<'EOF'
# comment
MLX_DEFAULT_MODEL=mlx-community/Llama-3.2-3B-Instruct-4bit

export MLX_RECOMMENDED_CONTEXT=2048
PATH=/tmp/evil
HF_TOKEN=should-not-load
touch should-not-run
MLX_IMAGE_FAMILY='flux2'
EOF
saved_path="${PATH}"
load_log_file="${TMP}/load.log"
load_models_env "${ENV_FILE}" >"${load_log_file}" 2>&1
load_log="$(cat "${load_log_file}")"
expect_eq "load model" "${MLX_DEFAULT_MODEL}" "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "load export-prefixed context" "${MLX_RECOMMENDED_CONTEXT}" "2048"
expect_eq "load quoted image family" "${MLX_IMAGE_FAMILY}" "flux2"
expect_eq "PATH is unchanged" "${PATH}" "${saved_path}"
expect_eq "HF_TOKEN is not set" "${HF_TOKEN:-}" ""
if [[ "${load_log}" == *"should-not-load"* || "${load_log}" == *"HF_TOKEN"* ]]; then
  fail "load log leaked HF_TOKEN"
else
  pass "load log does not mention HF_TOKEN"
fi

# --- load: command lines and substitutions are not executed ---

reset_mlx_keys
rm -f "${PWNED}"
{
  printf 'touch %q\n' "${PWNED}"
  printf "MLX_DEFAULT_MODEL=\$(touch %q)\n" "${PWNED}"
  printf 'MLX_IMAGE_MODEL=ok-model\n'
} >"${ENV_FILE}"
load_models_env "${ENV_FILE}" >/dev/null 2>&1
if [[ -e "${PWNED}" ]]; then
  fail "command line in models.env was executed"
else
  pass "command line in models.env is not executed"
fi
expect_eq "unsafe unquoted substitution is skipped" "${MLX_DEFAULT_MODEL:-}" ""
expect_eq "safe assignment after junk still loads" "${MLX_IMAGE_MODEL}" "ok-model"

# --- load: single-quoted $(...) is literal, not executed ---

reset_mlx_keys
rm -f "${PWNED}"
printf "MLX_DEFAULT_MODEL='\$(touch %s)'\n" "${PWNED}" >"${ENV_FILE}"
load_models_env "${ENV_FILE}" >/dev/null 2>&1
if [[ -e "${PWNED}" ]]; then
  fail "quoted command substitution was executed"
else
  pass "quoted command substitution is not executed"
fi
expect_eq "quoted substitution is literal" "${MLX_DEFAULT_MODEL}" "\$(touch ${PWNED})"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: models-env self-test passed\n'
exit 0
