#!/usr/bin/env bash
# Self-test for scripts/cleanup-mlx-native.sh (Linux and macOS).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP="${ROOT}/scripts/cleanup-mlx-native.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

make_venv() {
  local dest="$1"
  mkdir -p "${dest}/bin"
  printf 'home = /usr/bin/python3\ninclude-system-site-packages = false\n' >"${dest}/pyvenv.cfg"
}

assert_exists() { [[ -e "$1" ]] || fail "expected to exist: $1"; }
assert_missing() { [[ ! -e "$1" ]] || fail "expected missing: $1"; }

expect_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${label} (expected non-zero exit)"
  else
    pass "${label}"
  fi
}

expect_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "${label}"
  else
    fail "${label} (expected success)"
  fi
}

WS="${TMP}/ws"
export MLX_WORKSPACE="${WS}"
export MLX_VENV="${WS}/.venv"
export HOME="${TMP}/home"
mkdir -p "${HOME}" "${WS}/config" "${WS}/models"
make_venv "${MLX_VENV}"
printf 'MLX_DEFAULT_MODEL=test\n' >"${WS}/config/models.env"
printf 'fake-weight\n' >"${WS}/models/weights.txt"
printf '%s\n' "# apple-silicon-mlx-native workspace" >"${WS}/.mlx-workspace"
# Committed-looking example must never be deleted even if pointed at.
printf 'example\n' >"${WS}/config/models.example.env"
export MLX_MODELS_ENV="${WS}/config/models.env"

# 1. dry-run does not delete
expect_ok "dry-run succeeds" "${CLEANUP}" --dry-run --force
assert_exists "${MLX_VENV}/pyvenv.cfg"
assert_exists "${WS}/config/models.env"
assert_exists "${WS}/models/weights.txt"
if [[ -d "${MLX_VENV}" ]]; then
  pass "dry-run left .venv in place"
else
  fail "dry-run removed .venv"
fi

# 2. default cleanup removes venv only
expect_ok "default cleanup removes venv" "${CLEANUP}" --force
assert_missing "${MLX_VENV}"
assert_exists "${WS}/config/models.env"
assert_exists "${WS}/models/weights.txt"

# 3. idempotent when venv already gone
expect_ok "idempotent cleanup with no venv" "${CLEANUP}" --force

# 4. refuse venv outside workspace
mkdir -p "${TMP}/outside"
make_venv "${TMP}/outside/venv"
if MLX_VENV="${TMP}/outside/venv" "${CLEANUP}" --force >/dev/null 2>&1; then
  fail "refused to reject venv outside workspace"
else
  pass "rejects venv outside workspace"
fi
assert_exists "${TMP}/outside/venv/pyvenv.cfg"

# 5. refuse path that is not a venv
mkdir -p "${WS}/.venv"
printf 'not a venv\n' >"${WS}/.venv/readme.txt"
expect_fail "rejects non-venv directory" "${CLEANUP}" --force
assert_exists "${WS}/.venv/readme.txt"
rm -rf "${WS}/.venv"

# 6. refuse non-interactive without --force
make_venv "${MLX_VENV}"
expect_fail "non-interactive without --force is rejected" "${CLEANUP}" < /dev/null
assert_exists "${MLX_VENV}/pyvenv.cfg"

# 7. --purge removes config and workspace caches, not the example file
expect_ok "purge removes config and caches" "${CLEANUP}" --purge --force
assert_missing "${MLX_VENV}"
assert_missing "${WS}/config/models.env"
assert_missing "${WS}/models"
assert_exists "${WS}/config/models.example.env"

# 8. refuse deleting the committed example via MLX_MODELS_ENV
export MLX_MODELS_ENV="${WS}/config/models.example.env"
expect_fail "refuses to delete models.example.env" "${CLEANUP}" --config --force
assert_exists "${WS}/config/models.example.env"
export MLX_MODELS_ENV="${WS}/config/models.env"

# 9. Hugging Face hub cache: dry-run then remove only under a fake HOME
export HF_HOME="${HOME}/.cache/huggingface"
export HF_HUB_CACHE="${HF_HOME}/hub"
mkdir -p "${HF_HUB_CACHE}/models--mlx-community--tiny"
printf 'blob\n' >"${HF_HUB_CACHE}/models--mlx-community--tiny/model.bin"
printf 'token\n' >"${HF_HOME}/token"
expect_ok "hf cache dry-run" "${CLEANUP}" --huggingface-cache --keep-venv --dry-run --force
assert_exists "${HF_HUB_CACHE}/models--mlx-community--tiny/model.bin"
make_venv "${MLX_VENV}"
expect_ok "hf cache remove keeps venv" "${CLEANUP}" --huggingface-cache --keep-venv --force
assert_missing "${HF_HUB_CACHE}"
assert_exists "${HF_HOME}/token"
assert_exists "${MLX_VENV}/pyvenv.cfg"

# 10. refuse shallow HF cache paths
expect_fail "rejects shallow HF hub cache" \
  env HF_HUB_CACHE=/tmp HF_HOME=/tmp "${CLEANUP}" --huggingface-cache --keep-venv --force

# 11. refuse venv paths that lexically look in-workspace but resolve outside via ..
make_venv "${MLX_VENV}"
mkdir -p "${TMP}/outside"
make_venv "${TMP}/outside/venv"
if MLX_VENV="${WS}/../outside/venv" "${CLEANUP}" --force >/dev/null 2>&1; then
  fail "refused to reject venv path with .. escaping the workspace"
else
  pass "rejects venv path with .. escaping the workspace"
fi
assert_exists "${TMP}/outside/venv/pyvenv.cfg"
assert_exists "${MLX_VENV}/pyvenv.cfg"

# 12. allow venv paths whose .. still resolves inside the workspace
mkdir -p "${WS}/nested"
expect_ok "accepts venv path with .. that stays in workspace" \
  env MLX_VENV="${WS}/nested/../.venv" "${CLEANUP}" --force
assert_missing "${WS}/.venv"

# 13. refuse HF_HUB_CACHE equal to HF_HOME (would delete tokens)
export HF_HOME="${HOME}/.cache/huggingface"
export HF_HUB_CACHE="${HF_HOME}"
mkdir -p "${HF_HOME}/hub"
printf 'token\n' >"${HF_HOME}/token"
printf 'blob\n' >"${HF_HOME}/hub/model.bin"
expect_fail "rejects HF_HUB_CACHE equal to HF_HOME" \
  "${CLEANUP}" --huggingface-cache --keep-venv --force
assert_exists "${HF_HOME}/token"
assert_exists "${HF_HOME}/hub/model.bin"

# 14. refuse HF_HUB_CACHE that uses .. to escape to another directory
mkdir -p "${TMP}/huggingface/nested" "${TMP}/victim"
printf 'secret\n' >"${TMP}/victim/secret"
expect_fail "rejects HF_HUB_CACHE with .. escaping to victim" \
  env HF_HOME="${HF_HOME}" HF_HUB_CACHE="${TMP}/huggingface/nested/../../victim" \
  "${CLEANUP}" --huggingface-cache --keep-venv --force
assert_exists "${TMP}/victim/secret"

# 15. refuse HF_HUB_CACHE pointing at a parent of HF_HOME
expect_fail "rejects HF_HUB_CACHE parent of HF_HOME" \
  env HF_HOME="${HF_HOME}" HF_HUB_CACHE="${HOME}/.cache" \
  "${CLEANUP}" --huggingface-cache --keep-venv --force
assert_exists "${HF_HOME}/token"

# 16. --config path with .. that escapes the workspace
printf 'MLX_DEFAULT_MODEL=test\n' >"${WS}/config/models.env"
export MLX_MODELS_ENV="${WS}/config/models.env"
mkdir -p "${TMP}/outside"
printf 'keep-me\n' >"${TMP}/outside/secret.env"
expect_fail "rejects config path with .. escaping the workspace" \
  env MLX_MODELS_ENV="${WS}/config/../../outside/secret.env" \
  "${CLEANUP}" --config --keep-venv --force
assert_exists "${TMP}/outside/secret.env"

# 17. default cleanup removes a killed atomic-create directory, not a similar name
dead_partial_pid=2147483646
while kill -0 "${dead_partial_pid}" 2>/dev/null; do
  dead_partial_pid=$((dead_partial_pid - 1))
done
make_venv "${MLX_VENV}"
make_venv "${WS}/.venv.partial.${dead_partial_pid}"
mkdir -p "${WS}/.venv.partial.notes"
printf 'keep\n' >"${WS}/.venv.partial.notes/marker"
expect_ok "cleanup removes stale partial venv" "${CLEANUP}" --force
assert_missing "${MLX_VENV}"
assert_missing "${WS}/.venv.partial.${dead_partial_pid}"
assert_exists "${WS}/.venv.partial.notes/marker"

# 18. cleanup skips a partial directory whose pid suffix is still running
sleep 30 &
live_partial_pid=$!
mkdir -p "${WS}/.venv.partial.${live_partial_pid}"
printf 'live\n' >"${WS}/.venv.partial.${live_partial_pid}/marker"
expect_ok "cleanup skips in-use partial venv" "${CLEANUP}" --force
if [[ -f "${WS}/.venv.partial.${live_partial_pid}/marker" ]]; then
  pass "cleanup left in-use partial venv in place"
else
  fail "cleanup removed an in-use partial venv"
fi
kill "${live_partial_pid}" 2>/dev/null || true
wait "${live_partial_pid}" 2>/dev/null || true
rm -rf "${WS}/.venv.partial.${live_partial_pid}"

# 19. --purge refuses $HOME, a parent of $HOME, a system root, and a directory
# without a marker. Files must still be there afterwards.
other_home="${TMP}/other-home"
mkdir -p "${other_home}"

home_ws="${TMP}/as-home"
mkdir -p "${home_ws}/models" "${home_ws}/.venv/bin"
printf 'home-secret\n' >"${home_ws}/models/secret.txt"
printf 'home = /usr\n' >"${home_ws}/.venv/pyvenv.cfg"
printf '%s\n' marker >"${home_ws}/.mlx-workspace"
home_purge_status=0
home_purge_out="$(
  HOME="${home_ws}" MLX_WORKSPACE="${home_ws}" MLX_VENV="${home_ws}/.venv" \
    "${CLEANUP}" --purge --force 2>&1
)" || home_purge_status=$?
if [[ "${home_purge_status}" -ne 0 ]]; then
  pass "purge refuses workspace equal to HOME"
else
  fail "purge refuses workspace equal to HOME"
fi
if [[ "${home_purge_out}" == *"Refusing to purge workspace that is \$HOME"* ]]; then
  pass "HOME purge names the refusal"
else
  fail "HOME purge names the refusal"
fi
assert_exists "${home_ws}/models/secret.txt"
assert_exists "${home_ws}/.venv/pyvenv.cfg"

parent_ws="${TMP}/parent-ws"
parent_home="${parent_ws}/user"
mkdir -p "${parent_home}" "${parent_ws}/models" "${parent_ws}/outputs"
printf 'keep\n' >"${parent_home}/secret"
printf 'weight\n' >"${parent_ws}/models/w"
printf 'out\n' >"${parent_ws}/outputs/o"
printf '%s\n' marker >"${parent_ws}/.mlx-workspace"
expect_fail "purge refuses a parent of HOME" \
  env HOME="${parent_home}" MLX_WORKSPACE="${parent_ws}" MLX_VENV="${parent_ws}/.venv" \
  "${CLEANUP}" --workspace-caches --keep-venv --force
assert_exists "${parent_home}/secret"
assert_exists "${parent_ws}/models/w"
assert_exists "${parent_ws}/outputs/o"

plain_ws="${TMP}/plain-ws"
mkdir -p "${plain_ws}/models"
printf 'weight\n' >"${plain_ws}/models/w"
expect_fail "purge refuses a workspace without a marker" \
  env HOME="${other_home}" MLX_WORKSPACE="${plain_ws}" MLX_VENV="${plain_ws}/.venv" \
  "${CLEANUP}" --purge --force
assert_exists "${plain_ws}/models/w"

if [[ -d /usr ]]; then
  expect_fail "purge refuses system root /usr" \
    env HOME="${other_home}" MLX_WORKSPACE=/usr MLX_VENV=/usr/.venv \
    "${CLEANUP}" --purge --force
fi

lookalike_ws="${TMP}/lookalike-ws"
mkdir -p "${lookalike_ws}/scripts/lib" "${lookalike_ws}/models" "${lookalike_ws}/outputs" "${lookalike_ws}/tmp"
printf 'all:\n' >"${lookalike_ws}/Makefile"
printf '# unrelated\n' >"${lookalike_ws}/scripts/lib/common.sh"
printf 'weight\n' >"${lookalike_ws}/models/w"
printf 'out\n' >"${lookalike_ws}/outputs/o"
printf 'temp\n' >"${lookalike_ws}/tmp/t"
lookalike_status=0
lookalike_out="$(
  HOME="${other_home}" MLX_WORKSPACE="${lookalike_ws}" MLX_VENV="${lookalike_ws}/.venv" \
    "${CLEANUP}" --workspace-caches --keep-venv --force 2>&1
)" || lookalike_status=$?
if [[ "${lookalike_status}" -ne 0 ]]; then
  pass "look-alike repository without a marker is refused"
else
  fail "look-alike repository without a marker is refused"
fi
if [[ "${lookalike_out}" == *"without a toolkit marker"* ]]; then
  pass "look-alike refusal names the missing marker"
else
  fail "look-alike refusal names the missing marker"
fi
assert_exists "${lookalike_ws}/models/w"
assert_exists "${lookalike_ws}/outputs/o"
assert_exists "${lookalike_ws}/tmp/t"
assert_exists "${lookalike_ws}/Makefile"

marked_ws="${TMP}/marked-ws"
mkdir -p "${marked_ws}/models" "${marked_ws}/outputs"
printf 'weight\n' >"${marked_ws}/models/w"
printf 'out\n' >"${marked_ws}/outputs/o"
printf '%s\n' "# apple-silicon-mlx-native workspace" >"${marked_ws}/.mlx-workspace"
marked_out="$(
  HOME="${other_home}" MLX_WORKSPACE="${marked_ws}" MLX_VENV="${marked_ws}/.venv" \
    "${CLEANUP}" --workspace-caches --keep-venv --force 2>&1
)" || true
if [[ ! -e "${marked_ws}/models" && ! -e "${marked_ws}/outputs" && -f "${marked_ws}/.mlx-workspace" ]]; then
  pass "sentinel allows purge of its own caches"
else
  fail "sentinel allows purge of its own caches"
fi
if [[ "${marked_out}" == *"The following paths will be removed:"* && "${marked_out}" == *"${marked_ws}/models"* ]]; then
  pass "force still prints the removal list"
else
  fail "force still prints the removal list"
fi

checkout_busy=0
for checkout_name in models .cache huggingface .huggingface transformers mlx_models outputs generated tmp temp .tmp; do
  if [[ -e "${ROOT}/${checkout_name}" || -L "${ROOT}/${checkout_name}" ]]; then
    checkout_busy=1
  fi
done
if (( checkout_busy )); then
  pass "skipped checkout purge because cache directories already exist"
else
  mkdir -p "${ROOT}/models" "${ROOT}/outputs"
  printf 'weight\n' >"${ROOT}/models/w"
  printf 'out\n' >"${ROOT}/outputs/o"
  checkout_status=0
  HOME="${other_home}" MLX_WORKSPACE="${ROOT}" MLX_VENV="${ROOT}/.venv" \
    "${CLEANUP}" --workspace-caches --keep-venv --force >/dev/null 2>&1 || checkout_status=$?
  if [[ "${checkout_status}" -eq 0 && ! -e "${ROOT}/models" && ! -e "${ROOT}/outputs" ]]; then
    pass "this repository checkout purges its own caches without a marker"
  else
    fail "this repository checkout purges its own caches without a marker"
  fi
  rm -rf "${ROOT}/models" "${ROOT}/outputs"
fi

hf_ws="${TMP}/hf-ws"
mkdir -p "${hf_ws}/.cache/huggingface/hub" "${hf_ws}/models" "${hf_ws}/outputs"
printf 'token\n' >"${hf_ws}/.cache/huggingface/token"
printf 'blob\n' >"${hf_ws}/.cache/huggingface/hub/model.bin"
printf 'weight\n' >"${hf_ws}/models/w"
printf 'out\n' >"${hf_ws}/outputs/o"
printf '%s\n' marker >"${hf_ws}/.mlx-workspace"
mkdir -p "${hf_ws}/config"
printf 'MLX_DEFAULT_MODEL=test\n' >"${hf_ws}/config/models.env"
expect_ok "purge skips .cache that holds HF_HOME" \
  env HOME="${other_home}" \
    HF_HOME="${hf_ws}/.cache/huggingface" \
    HF_HUB_CACHE="${hf_ws}/.cache/huggingface/hub" \
    MLX_WORKSPACE="${hf_ws}" MLX_VENV="${hf_ws}/.venv" \
    MLX_MODELS_ENV="${hf_ws}/config/models.env" \
  "${CLEANUP}" --purge --force
assert_missing "${hf_ws}/config/models.env"
assert_exists "${hf_ws}/.cache/huggingface/token"
assert_exists "${hf_ws}/.cache/huggingface/hub/model.bin"
assert_missing "${hf_ws}/models"
assert_missing "${hf_ws}/outputs"

marker_ws="${TMP}/marker-write"
mkdir -p "${marker_ws}"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"
if workspace_is_repo_root "${ROOT}"; then
  pass "workspace identity matches this checkout"
else
  fail "workspace identity matches this checkout"
fi
if workspace_is_repo_root "${lookalike_ws}"; then
  fail "workspace identity rejects a look-alike tree"
else
  pass "workspace identity rejects a look-alike tree"
fi
saved_ws="${MLX_WORKSPACE}"
saved_venv="${MLX_VENV}"
saved_home="${HOME}"
MLX_WORKSPACE="${marker_ws}"
MLX_VENV="${marker_ws}/.venv"
ensure_mlx_workspace_marker
if [[ -f "${marker_ws}/.mlx-workspace" ]]; then
  pass "toolkit writes .mlx-workspace outside the repo"
else
  fail "toolkit writes .mlx-workspace outside the repo"
fi
MLX_WORKSPACE="${other_home}"
MLX_VENV="${other_home}/.venv"
HOME="${other_home}"
ensure_mlx_workspace_marker
MLX_WORKSPACE="${saved_ws}"
MLX_VENV="${saved_venv}"
HOME="${saved_home}"
if [[ ! -e "${other_home}/.mlx-workspace" ]]; then
  pass "toolkit does not mark HOME as a purge workspace"
else
  fail "toolkit does not mark HOME as a purge workspace"
fi

if (( failures > 0 )); then
  printf 'CLEANUP_SELFTEST_RESULT=fail (%s)\n' "${failures}" >&2
  exit 1
fi
printf 'CLEANUP_SELFTEST_RESULT=success\n'
exit 0
