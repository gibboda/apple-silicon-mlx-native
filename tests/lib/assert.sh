#!/usr/bin/env bash
# Shared assertion helpers for portable shell self-tests (bash 3.2+).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Source after set -euo pipefail. Initializes failures/skips when unset.

: "${failures:=0}"
: "${skips:=0}"

pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; skips=$((skips + 1)); }

expect_fail() {
  local label="$1"
  shift
  # Subshell contains die()/exit from the command under test (set -e safe).
  if ( "$@" ) >/dev/null 2>&1; then
    fail "${label} (expected non-zero exit)"
  else
    pass "${label}"
  fi
}

expect_ok() {
  local label="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    pass "${label}"
  else
    fail "${label} (expected success)"
  fi
}

expect_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    pass "${label}"
  else
    fail "${label} (missing ${needle})"
  fi
}

expect_eq() {
  local label="$1"
  local left="$2"
  local right="$3"
  if [[ "${left}" == "${right}" ]]; then
    pass "${label}"
  else
    fail "${label} (${left} != ${right})"
  fi
}

# Assert haystack contains a line exactly equal to line (grep -qxF).
expect_line() {
  local label="$1"
  local line="$2"
  local haystack="$3"
  # Here-string avoids printf|grep SIGPIPE flakes on macOS bash 3.2 (set -o pipefail).
  if grep -qxF -- "${line}" <<< "${haystack}"; then
    pass "${label}"
  else
    fail "${label} (missing exact line ${line})"
  fi
}

expect_missing() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "${label} (found ${needle})"
  else
    pass "${label}"
  fi
}

# Back-compat names used by a few self-tests.
expect_exact_line() { expect_line "$@"; }
expect_not_contains() { expect_missing "$@"; }

assert_finish() {
  local suite_name="$1"
  if (( failures > 0 )); then
    printf 'FAIL: %s failure(s)\n' "${failures}" >&2
    exit 1
  fi
  if (( skips > 0 )); then
    printf 'OK: %s passed (%s skipped)\n' "${suite_name}" "${skips}"
  else
    printf 'OK: %s\n' "${suite_name}"
  fi
}
