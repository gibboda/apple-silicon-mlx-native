#!/usr/bin/env bash
# Parse fixtures for config/models.env (Linux CI safe: no source/eval).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/common.sh
source "${COMMON}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"
ENV_FILE="${TMP}/models.env"
PWNED="${TMP}/pwned"

reset_mlx_keys() {
  unset MLX_DEFAULT_MODEL MLX_RECOMMENDED_CONTEXT MLX_IMAGE_FAMILY MLX_IMAGE_MODEL \
    MLX_SERVER_HOST MLX_SERVER_PORT MLX_VIDEO_IMAGE HF_TOKEN
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

# --- upsert preserves mode, symlinks, and temp cleanup on failure ---

REAL_ENV="${TMP}/real-models.env"
LINK_ENV="${TMP}/models.env.link"
printf 'MLX_DEFAULT_MODEL=old\n' >"${REAL_ENV}"
chmod 644 "${REAL_ENV}"
ln -sf "${REAL_ENV}" "${LINK_ENV}"
upsert_env_assignment "${LINK_ENV}" MLX_DEFAULT_MODEL "mode-check"
link_mode="$(stat -c '%a' "${REAL_ENV}" 2>/dev/null || stat -f '%Lp' "${REAL_ENV}")"
expect_eq "upsert preserves file mode" "${link_mode}" "644"
if [[ -L "${LINK_ENV}" ]]; then
  pass "upsert preserves symlink"
else
  fail "upsert should not replace symlink with a regular file"
fi
expect_eq "upsert writes through symlink" "$(cat "${REAL_ENV}")" "MLX_DEFAULT_MODEL=mode-check"

MID_ENV="${TMP}/mid-models.env"
OUTER_LINK="${TMP}/outer-models.env.link"
printf 'MLX_DEFAULT_MODEL=chain-old\n' >"${MID_ENV}"
ln -sf "${MID_ENV}" "${OUTER_LINK}"
ln -sf "${OUTER_LINK}" "${LINK_ENV}"
upsert_env_assignment "${LINK_ENV}" MLX_DEFAULT_MODEL "chain-new"
if [[ -L "${LINK_ENV}" && -L "${OUTER_LINK}" ]]; then
  pass "upsert preserves multi-hop symlink chain"
else
  fail "upsert should preserve multi-hop symlink chain"
fi
expect_eq "upsert writes through symlink chain" "$(cat "${MID_ENV}")" "MLX_DEFAULT_MODEL=chain-new"

UNREAD_ENV="${TMP}/unreadable.env"
printf 'MLX_DEFAULT_MODEL=old\n' >"${UNREAD_ENV}"
chmod 000 "${UNREAD_ENV}"
leftover_count=0
if bash -c "set -euo pipefail; source \"${COMMON}\"; upsert_env_assignment \"${UNREAD_ENV}\" MLX_DEFAULT_MODEL x" >/dev/null 2>&1; then
  chmod 644 "${UNREAD_ENV}" 2>/dev/null || true
  fail "upsert failure should exit non-zero under errexit"
else
  pass "upsert failure exits non-zero under errexit"
fi
chmod 644 "${UNREAD_ENV}" 2>/dev/null || true
for f in "${TMP}"/unreadable.env.* "${TMP}"/real-models.env.* "${TMP}"/mid-models.env.*; do
  [[ -e "${f}" ]] || continue
  leftover_count=$((leftover_count + 1))
done
if (( leftover_count == 0 )); then
  pass "upsert failure leaves no temp file"
else
  fail "upsert failure leaves no temp file"
fi
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
if [[ "${load_log}" == *"Skipping non-MLX key PATH"* ]]; then
  pass "load warns on PATH without executing it"
else
  fail "load should warn on non-MLX PATH assignment"
fi
if [[ "${load_log}" == *"Skipping non-MLX key HF_TOKEN"* ]]; then
  pass "load warns on HF_TOKEN without loading it"
else
  fail "load should warn on non-MLX HF_TOKEN assignment"
fi
if [[ "${load_log}" == *"/tmp/evil"* ]]; then
  fail "load log leaked PATH value"
else
  pass "load log does not print PATH value"
fi
if [[ "${load_log}" == *"should-not-load"* ]]; then
  fail "load log leaked HF_TOKEN value"
else
  pass "load log does not print HF_TOKEN value"
fi
if [[ "${load_log}" == *"should-not-run"* ]]; then
  fail "load log mentioned a bare command line"
else
  pass "bare command line stays silent"
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

# --- load: skip runtime identity keys ---

reset_mlx_keys
saved_venv="${MLX_VENV}"
printf 'MLX_VENV=/tmp/evil-venv\nMLX_DEFAULT_MODEL=ok-model\n' >"${ENV_FILE}"
runtime_log_file="${TMP}/runtime.log"
load_models_env "${ENV_FILE}" >"${runtime_log_file}" 2>&1
runtime_log="$(cat "${runtime_log_file}")"
expect_eq "runtime MLX_VENV is ignored" "${MLX_VENV}" "${saved_venv}"
expect_eq "safe key after runtime skip still loads" "${MLX_DEFAULT_MODEL}" "ok-model"
if [[ "${runtime_log}" == *"Skipping runtime key MLX_VENV"* ]]; then
  pass "load warns on runtime MLX_VENV"
else
  fail "load should warn on runtime MLX_VENV"
fi
if [[ "${runtime_log}" == *"/tmp/evil-venv"* ]]; then
  fail "load log leaked MLX_VENV value"
else
  pass "load log does not print MLX_VENV value"
fi

# --- load: leading unquoted ~/ expands; quoted ~/ does not ---

reset_mlx_keys
HOME="${TMP}/homedir"
printf 'MLX_VIDEO_IMAGE=~/Pictures/fox.png\n' >"${ENV_FILE}"
load_models_env "${ENV_FILE}" >/dev/null 2>&1
expect_eq "unquoted tilde expands" "${MLX_VIDEO_IMAGE}" "${HOME}/Pictures/fox.png"

reset_mlx_keys
HOME="${TMP}/homedir"
tilde='~'
quoted_tilde="${tilde}/Pictures/fox.png"
printf "MLX_VIDEO_IMAGE='%s'\n" "${quoted_tilde}" >"${ENV_FILE}"
load_models_env "${ENV_FILE}" >/dev/null 2>&1
expect_eq "quoted tilde stays literal" "${MLX_VIDEO_IMAGE}" "${quoted_tilde}"

# --- load: unquoted trailing comments ---

reset_mlx_keys
printf 'MLX_IMAGE_FAMILY=flux2 # note\n' >"${ENV_FILE}"
load_models_env "${ENV_FILE}" >/dev/null 2>&1
expect_eq "unquoted trailing comment is stripped" "${MLX_IMAGE_FAMILY}" "flux2"

# --- load: duplicate keys in file last-win; process env beats file ---

reset_mlx_keys
cat >"${ENV_FILE}" <<'EOF'
MLX_DEFAULT_MODEL=first-in-file
MLX_DEFAULT_MODEL=last-in-file
MLX_RECOMMENDED_CONTEXT=1024
MLX_RECOMMENDED_CONTEXT=4096
EOF
load_models_env "${ENV_FILE}" >/dev/null 2>&1
expect_eq "duplicate model last-win" "${MLX_DEFAULT_MODEL}" "last-in-file"
expect_eq "duplicate context last-win" "${MLX_RECOMMENDED_CONTEXT}" "4096"

reset_mlx_keys
export MLX_DEFAULT_MODEL=from-shell
cat >"${ENV_FILE}" <<'EOF'
MLX_DEFAULT_MODEL=first-in-file
MLX_DEFAULT_MODEL=last-in-file
EOF
load_models_env "${ENV_FILE}" >/dev/null 2>&1
expect_eq "process env beats duplicate file model" "${MLX_DEFAULT_MODEL}" "from-shell"
unset MLX_DEFAULT_MODEL

assert_finish "models-env self-test passed"
