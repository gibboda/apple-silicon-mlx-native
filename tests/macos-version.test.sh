#!/usr/bin/env bash
# Self-test for supported macOS major version guards (26+).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
DETECT="${ROOT}/scripts/detect-apple-silicon.sh"
DOCTOR="${ROOT}/scripts/doctor-mlx-native.sh"
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

run_entrypoint_capture() {
  local stub_root="$1"
  shift
  env PATH="${stub_root}:${PATH}" "$@" 2>&1
}

stub_for_major() {
  local dest="$1"
  local major="$2"
  local patch="${3:-.0.1}"
  fake_darwin_install "${dest}" 17179869184
  cat >"${dest}/sw_vers" <<EOF
#!/bin/sh
printf '%s\n' ${major}${patch}
EOF
  chmod +x "${dest}/sw_vers"
}

install_sw_vers_script() {
  local dest="$1"
  local body="$2"
  fake_darwin_install "${dest}" 17179869184
  cat >"${dest}/sw_vers" <<EOF
#!/bin/sh
${body}
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
  expect_contains "macOS ${major} error mentions minimum supported major version (26)" \
    "minimum supported major version (26)" "${err}"
done

for major in 26 27; do
  stub="${TMP}/darwin-${major}"
  stub_for_major "${stub}" "${major}"
  expect_ok "macOS ${major} is accepted" run_assert_macos "${stub}"
  ok_out="$(run_assert_macos_capture "${stub}")" || true
  expect_not_contains "macOS ${major} has no WARN" "WARN:" "${ok_out}"
done

for major in 28 30; do
  stub="${TMP}/darwin-${major}"
  stub_for_major "${stub}" "${major}"
  expect_ok "macOS ${major} is accepted" run_assert_macos "${stub}"
  warn_out="$(run_assert_macos_capture "${stub}")" || true
  expect_contains "macOS ${major} warns above CI newest" "WARN:" "${warn_out}"
  expect_contains "macOS ${major} warn mentions newer than macOS 27" \
    "newer than macOS 27" "${warn_out}"
done

# --- parse edge cases ---

stub="${TMP}/darwin-bare-26"
install_sw_vers_script "${stub}" 'printf "%s\n" 26'
expect_ok "bare major 26 without dot is accepted" run_assert_macos "${stub}"

stub="${TMP}/darwin-empty-swvers"
install_sw_vers_script "${stub}" 'printf "%s\n" ""'
expect_fail "empty sw_vers output is rejected" run_assert_macos "${stub}"
empty_err="$(run_assert_macos_capture "${stub}")" || true
expect_contains "empty sw_vers mentions Could not parse" "Could not parse macOS version" "${empty_err}"

stub="${TMP}/darwin-abc-swvers"
install_sw_vers_script "${stub}" 'printf "%s\n" abc'
expect_fail "non-numeric sw_vers is rejected" run_assert_macos "${stub}"
abc_err="$(run_assert_macos_capture "${stub}")" || true
expect_contains "abc sw_vers mentions Could not parse" "Could not parse macOS version" "${abc_err}"

stub="${TMP}/darwin-fail-swvers"
install_sw_vers_script "${stub}" 'exit 1'
expect_fail "failing sw_vers is rejected" run_assert_macos "${stub}"
fail_err="$(run_assert_macos_capture "${stub}")" || true
expect_contains "failing sw_vers mentions Could not parse" "Could not parse macOS version" "${fail_err}"

stub="${TMP}/darwin-8-1"
install_sw_vers_script "${stub}" 'printf "%s\n" 8.1'
expect_fail "macOS 8.1 is below minimum" run_assert_macos "${stub}"
old_err="$(run_assert_macos_capture "${stub}")" || true
expect_contains "macOS 8.1 error mentions minimum supported major version (26)" \
  "minimum supported major version (26)" "${old_err}"

# --- entrypoints enforce the guard (Darwin 15 stub) ---

stub="${TMP}/darwin-15-entry"
stub_for_major "${stub}" 15

expect_fail "detect --quiet rejects macOS 15 stub" \
  env PATH="${stub}:${PATH}" "${DETECT}" --quiet
quiet_err="$(run_entrypoint_capture "${stub}" "${DETECT}" --quiet)" || true
expect_contains "detect --quiet macOS 15 mentions minimum supported major version (26)" \
  "minimum supported major version (26)" "${quiet_err}"

expect_fail "doctor rejects macOS 15 stub" env PATH="${stub}:${PATH}" "${DOCTOR}"
doctor_err="$(run_entrypoint_capture "${stub}" "${DOCTOR}")" || true
expect_contains "doctor macOS 15 mentions minimum supported major version (26)" \
  "minimum supported major version (26)" "${doctor_err}"

assert_finish "macos-version self-test passed"
