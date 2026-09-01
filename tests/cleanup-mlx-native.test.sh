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
expect_fail "non-interactive without --force is rejected" "${CLEANUP}"
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

if (( failures > 0 )); then
  printf 'CLEANUP_SELFTEST_RESULT=fail (%s)\n' "${failures}" >&2
  exit 1
fi
printf 'CLEANUP_SELFTEST_RESULT=success\n'
exit 0
