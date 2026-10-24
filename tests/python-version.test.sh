#!/usr/bin/env bash
# Self-test for MLX_PYTHON_VERSION range and exact major.minor venv matching.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"

run_assert_python_supported() {
  env MLX_PYTHON_VERSION="$1" bash -c "source \"${COMMON}\"; assert_mlx_python_version_supported"
}

run_venv_version_match() {
  env MLX_WORKSPACE="$1" MLX_VENV="$2" MLX_PYTHON_VERSION="${3:-3.12}" bash -c \
    "source \"${COMMON}\"; venv_version_matches_expected"
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

for ver in 3.12 3.13 3.14; do
  expect_ok "MLX_PYTHON_VERSION ${ver} is supported" run_assert_python_supported "${ver}"
done

expect_fail "MLX_PYTHON_VERSION 3.11 is below range" run_assert_python_supported 3.11
below_err="$(run_assert_python_supported 3.11 2>&1)" || true
expect_contains "below range mentions 3.12" "3.12" "${below_err}"

expect_fail "MLX_PYTHON_VERSION 3.15 is above range" run_assert_python_supported 3.15
above_err="$(run_assert_python_supported 3.15 2>&1)" || true
expect_contains "above range mentions 3.14" "3.14" "${above_err}"

expect_fail "MLX_PYTHON_VERSION patch form is rejected" run_assert_python_supported 3.12.1

# --- exact major.minor venv match (3.1 must not match 3.12) ---

MATCH_WS="${TMP}/match"
mkdir -p "${MATCH_WS}/.venv"
printf 'version = 3.12.9\n' >"${MATCH_WS}/.venv/pyvenv.cfg"
expect_ok "venv 3.12.9 matches MLX_PYTHON_VERSION 3.12" \
  run_venv_version_match "${MATCH_WS}" "${MATCH_WS}/.venv" 3.12

printf 'version = 3.1.9\n' >"${MATCH_WS}/.venv/pyvenv.cfg"
expect_fail "venv 3.1.9 does not match MLX_PYTHON_VERSION 3.12" \
  run_venv_version_match "${MATCH_WS}" "${MATCH_WS}/.venv" 3.12

assert_finish "python-version self-test passed"
