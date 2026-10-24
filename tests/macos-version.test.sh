#!/usr/bin/env bash
# Self-test for supported macOS major version guards (26–27).
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

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

for major in 14 15; do
  stub="${TMP}/darwin-${major}"
  fake_darwin_install "${stub}" 17179869184
  cat >"${stub}/sw_vers" <<EOF
#!/bin/sh
printf '%s\n' ${major}.0
EOF
  chmod +x "${stub}/sw_vers"
  expect_fail "macOS ${major} is rejected" run_assert_macos "${stub}"
  err="$(run_assert_macos "${stub}" 2>&1)" || true
  expect_contains "macOS ${major} error mentions minimum 26" "26" "${err}"
done

for major in 26 27; do
  stub="${TMP}/darwin-${major}"
  fake_darwin_install "${stub}" 17179869184
  cat >"${stub}/sw_vers" <<EOF
#!/bin/sh
printf '%s\n' ${major}.0.1
EOF
  chmod +x "${stub}/sw_vers"
  expect_ok "macOS ${major} is accepted" run_assert_macos "${stub}"
done

stub="${TMP}/darwin-28"
fake_darwin_install "${stub}" 17179869184
cat >"${stub}/sw_vers" <<'EOF'
#!/bin/sh
printf '%s\n' 28.0
EOF
chmod +x "${stub}/sw_vers"
expect_fail "macOS 28 is rejected" run_assert_macos "${stub}"
above_err="$(run_assert_macos "${stub}" 2>&1)" || true
expect_contains "macOS 28 error mentions maximum 27" "27" "${above_err}"

assert_finish "macos-version self-test passed"
