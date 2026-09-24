#!/usr/bin/env bash
# Portable fixtures for scripts/conventional-commits-audit.sh.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="${ROOT}/scripts/conventional-commits-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "${label}"
  else
    fail "${label} (expected success)"
  fi
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${label} (expected non-zero exit)"
  else
    pass "${label}"
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

REPO="${TMP}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q --template= -b main
git -C "${REPO}" config user.email "audit-test@example.com"
git -C "${REPO}" config user.name "Audit Test"

commit_msg() {
  git -C "${REPO}" commit -q --allow-empty -m "$1"
}

audit_in() {
  (
    cd "${REPO}"
    env \
      EXEMPT_MERGE_COMMITS="${EXEMPT_MERGE_COMMITS:-true}" \
      AUDIT_BASE_REF="${AUDIT_BASE_REF:-origin/main}" \
      AUDIT_BASE_SHA="${AUDIT_BASE_SHA:-}" \
      AUDIT_HEAD_SHA="${AUDIT_HEAD_SHA:-}" \
      COMMIT_RANGE="${COMMIT_RANGE:-}" \
      "${AUDIT}" "$@"
  )
}

expect_ok "help" audit_in --help
expect_fail "unknown argument" audit_in --nope
expect_fail "range flag needs a value" audit_in --range

commit_msg "feat: seed the repo"
expect_ok "valid feat subject" audit_in --range HEAD

commit_msg "not conventional"
expect_fail "rejects a bare subject" audit_in --range HEAD

commit_msg "feat:no space"
expect_fail "requires a space after the colon" audit_in --range HEAD

commit_msg "Feat: upper type"
expect_fail "type must be lowercase" audit_in --range HEAD

commit_msg "feat(Bad): upper scope"
expect_fail "scope must be lowercase" audit_in --range HEAD

commit_msg "fix(mlx)!: reject bad pins"
expect_ok "breaking scope subject" audit_in --range HEAD

commit_msg "docs(models): document 8 GB recommendations"
expect_ok "docs scope subject" audit_in --range HEAD

commit_msg "ci(workflows): pin checkout"
expect_ok "slash in scope" audit_in --range HEAD

commit_msg "revert: undo the pin"
expect_ok "revert subject" audit_in --range HEAD

commit_msg "Merge pull request #12 from owner/branch"
expect_ok "github merge pull request is exempt" audit_in --range HEAD
EXEMPT_MERGE_COMMITS=false
expect_fail "merge exemption can be disabled" audit_in --range HEAD
EXEMPT_MERGE_COMMITS=true

commit_msg "Merge branch 'main' into feature"
expect_ok "merge branch is exempt" audit_in --range HEAD

commit_msg "Merge remote-tracking branch 'origin/main' into feature"
expect_ok "merge remote-tracking branch is exempt" audit_in --range HEAD

hex_a="$(printf 'a%.0s' {1..40})"
hex_b="$(printf 'b%.0s' {1..40})"
commit_msg "Merge ${hex_a} into ${hex_b}"
expect_ok "actions test-merge subject is exempt" audit_in --range HEAD

# Two-dot: a bad commit that exists only on main must not fail feature.
git -C "${REPO}" checkout -q -b feature
commit_msg "feat: add the widget"
git -C "${REPO}" checkout -q main
commit_msg "wip forgot the type"

two_dot="$(audit_in --range main..feature)"
expect_contains "two-dot audits the feature commit" "feat: add the widget" "${two_dot}"
expect_ok "two-dot ignores a main-only bad subject" audit_in --range main..feature
expect_fail "three-dot includes the main-only bad subject" audit_in --range main...feature

empty="$(audit_in --range main..main || true)"
expect_contains "empty two-dot range" "No commits in range" "${empty}"
expect_ok "empty range exits 0" audit_in --range main..main
expect_fail "missing ref is an error" audit_in --range does-not-exist..HEAD

feature_sha="$(git -C "${REPO}" rev-parse feature)"
base_sha="$(git -C "${REPO}" merge-base main feature)"
AUDIT_BASE_SHA="${base_sha}"
AUDIT_HEAD_SHA="${feature_sha}"
sha_out="$(audit_in)"
expect_contains "AUDIT_* SHAs select a two-dot range" "feat: add the widget" "${sha_out}"
expect_ok "AUDIT_BASE_SHA..AUDIT_HEAD_SHA passes" audit_in
unset AUDIT_BASE_SHA AUDIT_HEAD_SHA

git -C "${REPO}" checkout -q feature
AUDIT_BASE_REF=main
default_out="$(audit_in)"
expect_contains "default ref range is two-dot" "main..HEAD" "${default_out}"
expect_ok "default two-dot from feature ignores main-only commits" audit_in
unset AUDIT_BASE_REF

if (( failures > 0 )); then
  printf 'FAIL: %s conventional-commits check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: conventional-commits audit\n'
