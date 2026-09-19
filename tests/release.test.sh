#!/usr/bin/env bash
# Self-test for scripts/release.sh (Linux and macOS). Never tags the toolkit repo.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="${ROOT}/scripts/release.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Isolate git from the developer/CI global config and hooks.
unset GIT_DIR GIT_WORK_TREE
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="${TMP}/empty.gitconfig"
: >"${GIT_CONFIG_GLOBAL}"

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

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

expect_missing() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "${label} (unexpected ${needle})"
  else
    pass "${label}"
  fi
}

write_changelog() {
  local dest="$1"
  cat >"${dest}" <<'EOF'
# Changelog

## [Unreleased]

### Fixed

- a notable fix

## [0.1.0] - 2026-01-01

### Added

- first release

[Unreleased]: https://github.com/example/apple-silicon-mlx-native/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/example/apple-silicon-mlx-native/releases/tag/v0.1.0
EOF
}

init_repo() {
  local repo="$1"
  mkdir -p "${repo}"
  git -C "${repo}" init -q --template=
  git -C "${repo}" config user.email "release-test@example.com"
  git -C "${repo}" config user.name "Release Test"
  git -C "${repo}" remote add origin "https://github.com/example/apple-silicon-mlx-native.git"
  write_changelog "${repo}/CHANGELOG.md"
  git -C "${repo}" add CHANGELOG.md
  git -C "${repo}" commit -q -m "chore: seed changelog"
}

run_release() {
  local repo="$1"
  shift
  (
    cd "${repo}"
    RELEASE_DATE=2026-01-02 "${RELEASE}" "$@"
  )
}

expect_ok "help" "${RELEASE}" --help
expect_fail "missing version" "${RELEASE}"
expect_fail "invalid semver 1.2" "${RELEASE}" 1.2
expect_fail "leading v is rejected" "${RELEASE}" v0.2.0
expect_fail "dry-run plus push rejected" "${RELEASE}" --dry-run --push 0.2.0

REPO="${TMP}/cut"
init_repo "${REPO}"
SEED="$(git -C "${REPO}" rev-parse HEAD)"

dry_out=""
if dry_out="$(run_release "${REPO}" --dry-run 0.2.0 2>&1)"; then
  pass "dry-run exits 0"
else
  fail "dry-run exits 0"
  printf '%s\n' "${dry_out}" >&2
fi
expect_contains "dry-run preview has version heading" "## [0.2.0] - 2026-01-02" "${dry_out}"
expect_contains "dry-run preview keeps unreleased stub" "## [Unreleased]" "${dry_out}"
expect_contains "dry-run preview moves the note" "- a notable fix" "${dry_out}"
expect_contains "dry-run Unreleased compare uses new tag" \
  "[Unreleased]: https://github.com/example/apple-silicon-mlx-native/compare/v0.2.0...HEAD" "${dry_out}"
expect_contains "dry-run new version compare uses previous tag" \
  "[0.2.0]: https://github.com/example/apple-silicon-mlx-native/compare/v0.1.0...v0.2.0" "${dry_out}"
expect_contains "dry-run keeps original tag URL" \
  "[0.1.0]: https://github.com/example/apple-silicon-mlx-native/releases/tag/v0.1.0" "${dry_out}"

on_disk="$(cat "${REPO}/CHANGELOG.md")"
expect_missing "dry-run does not write version heading" "## [0.2.0]" "${on_disk}"
expect_contains "dry-run leaves previous Unreleased compare" \
  "compare/v0.1.0...HEAD" "${on_disk}"
expect_eq_head="$(git -C "${REPO}" rev-parse HEAD)"
if [[ "${expect_eq_head}" == "${SEED}" ]]; then
  pass "dry-run does not create a commit"
else
  fail "dry-run created a commit"
fi
if git -C "${REPO}" rev-parse -q --verify refs/tags/v0.2.0 >/dev/null; then
  fail "dry-run created tag v0.2.0"
else
  pass "dry-run does not create a tag"
fi

empty="${TMP}/empty-unreleased"
init_repo "${empty}"
cat >"${empty}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.1.0] - 2026-01-01

### Added

- first release
EOF
git -C "${empty}" add CHANGELOG.md
git -C "${empty}" commit -q -m "chore: empty unreleased"
expect_fail "empty Unreleased is rejected" run_release "${empty}" 0.2.0

dup="${TMP}/dup-section"
init_repo "${dup}"
expect_fail "duplicate changelog version is rejected" run_release "${dup}" 0.1.0

tagged="${TMP}/existing-tag"
init_repo "${tagged}"
git -C "${tagged}" tag -a v0.2.0 -m "already"
expect_fail "existing tag is rejected" run_release "${tagged}" 0.2.0

dirty="${TMP}/dirty"
init_repo "${dirty}"
printf 'dirty\n' >"${dirty}/extra.txt"
expect_fail "dirty work tree is rejected" run_release "${dirty}" 0.2.0

hookrepo="${TMP}/hooks"
init_repo "${hookrepo}"
mkdir -p "${hookrepo}/.git/hooks"
printf '#!/bin/sh\nexit 1\n' >"${hookrepo}/.git/hooks/commit-msg"
chmod +x "${hookrepo}/.git/hooks/commit-msg"
expect_fail "does not skip commit-msg hook" run_release "${hookrepo}" 0.2.0
if git -C "${hookrepo}" rev-parse -q --verify refs/tags/v0.2.0 >/dev/null; then
  fail "failed hook still created tag v0.2.0"
else
  pass "failed hook does not create a tag"
fi

cut="${TMP}/real-cut"
init_repo "${cut}"
expect_ok "real cut succeeds" run_release "${cut}" 0.2.0
cut_log="$(cat "${cut}/CHANGELOG.md")"
expect_contains "cut writes version heading" "## [0.2.0] - 2026-01-02" "${cut_log}"
expect_contains "cut keeps Unreleased stub" "## [Unreleased]" "${cut_log}"
expect_contains "cut moves the note under the version" "- a notable fix" "${cut_log}"
expect_contains "cut Unreleased compare uses new tag" \
  "[Unreleased]: https://github.com/example/apple-silicon-mlx-native/compare/v0.2.0...HEAD" "${cut_log}"
expect_contains "cut new version compare uses previous tag" \
  "[0.2.0]: https://github.com/example/apple-silicon-mlx-native/compare/v0.1.0...v0.2.0" "${cut_log}"
unreleased_block="$(awk '/^## \[Unreleased\]/{p=1; next} /^## \[/{exit} p{print}' "${cut}/CHANGELOG.md")"
if printf '%s\n' "${unreleased_block}" | grep -qE '^[[:space:]]*-[[:space:]]'; then
  fail "cut left notes under Unreleased"
else
  pass "cut leaves Unreleased without notes"
fi
subject="$(git -C "${cut}" log -1 --format=%s)"
if [[ "${subject}" == "chore(release): cut 0.2.0" ]]; then
  pass "cut commit subject follows chore(release)"
else
  fail "cut commit subject (got '${subject}')"
fi
if git -C "${cut}" rev-parse -q --verify refs/tags/v0.2.0 >/dev/null; then
  pass "cut creates tag v0.2.0"
else
  fail "cut did not create tag v0.2.0"
fi
tag_type="$(git -C "${cut}" cat-file -t v0.2.0)"
if [[ "${tag_type}" == "tag" ]]; then
  pass "cut tag is annotated"
else
  fail "cut tag is ${tag_type}, want annotated tag"
fi
tag_body="$(git -C "${cut}" for-each-ref --format='%(contents)' refs/tags/v0.2.0)"
expect_contains "annotated tag includes release notes" "- a notable fix" "${tag_body}"

first="${TMP}/first-release"
mkdir -p "${first}"
git -C "${first}" init -q --template=
git -C "${first}" config user.email "release-test@example.com"
git -C "${first}" config user.name "Release Test"
git -C "${first}" remote add origin "git@github.com:example/apple-silicon-mlx-native.git"
cat >"${first}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

- ship it
EOF
git -C "${first}" add CHANGELOG.md
git -C "${first}" commit -q -m "chore: seed first changelog"
expect_ok "first release succeeds" run_release "${first}" 0.1.0
first_log="$(cat "${first}/CHANGELOG.md")"
expect_contains "first release uses tag URL not compare" \
  "[0.1.0]: https://github.com/example/apple-silicon-mlx-native/releases/tag/v0.1.0" "${first_log}"
expect_contains "ssh origin becomes https footer" \
  "[Unreleased]: https://github.com/example/apple-silicon-mlx-native/compare/v0.1.0...HEAD" "${first_log}"

prerelease="${TMP}/rc"
init_repo "${prerelease}"
expect_ok "pre-release version succeeds" run_release "${prerelease}" 1.0.0-rc.1
pre_log="$(cat "${prerelease}/CHANGELOG.md")"
expect_contains "pre-release heading" "## [1.0.0-rc.1] - 2026-01-02" "${pre_log}"
expect_contains "pre-release compare URL" \
  "[1.0.0-rc.1]: https://github.com/example/apple-silicon-mlx-native/compare/v0.1.0...v1.0.0-rc.1" "${pre_log}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: release self-test passed\n'
