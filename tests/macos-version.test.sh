#!/usr/bin/env bash
# Self-test for supported macOS major version guards (26+).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"
# shellcheck source=tests/lib/fake-darwin.sh
source "${TEST_LIB}/fake-darwin.sh"

run_assert_macos() {
  local stub_root="$1"
  env PATH="${stub_root}:${PATH}" bash -c "source \"${COMMON}\"; assert_minimum_macos_for_mlx"
}

run_assert_macos_capture() {
  local stub_root="$1"
  env PATH="${stub_root}:${PATH}" bash -c "source \"${COMMON}\"; assert_minimum_macos_for_mlx" 2>&1
}

stub_for_major() {
  local dest="$1"
  local major="$2"
  fake_darwin_install "${dest}" 17179869184
  cat >"${dest}/sw_vers" <<EOF
#!/bin/sh
printf '%s\n' ${major}.0.1
EOF
  chmod +x "${dest}/sw_vers"
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

for major in 14 15; do
  stub="${TMP}/darwin-${major}"
  stub_for_major "${stub}" "${major}"
  expect_fail "macOS ${major} is rejected" run_assert_macos "${stub}"
  err="$(run_assert_macos "${stub}" 2>&1)" || true
  expect_contains "macOS ${major} error mentions minimum 26" "26" "${err}"
done

for major in 26 27; do
  stub="${TMP}/darwin-${major}"
  stub_for_major "${stub}" "${major}"
  expect_ok "macOS ${major} is accepted" run_assert_macos "${stub}"
done

for major in 28 30; do
  stub="${TMP}/darwin-${major}"
  stub_for_major "${stub}" "${major}"
  expect_ok "macOS ${major} is accepted" run_assert_macos "${stub}"
  warn_out="$(run_assert_macos_capture "${stub}")" || true
  expect_contains "macOS ${major} warns above CI newest" "WARN:" "${warn_out}"
  expect_contains "macOS ${major} warn mentions CI 27" "27" "${warn_out}"
done

assert_finish "macos-version self-test passed"
