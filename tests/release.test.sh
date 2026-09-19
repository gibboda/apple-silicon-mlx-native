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
  git -C "${repo}" init -q --template= -b main
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

path_without() {
  local hide="$1"
  local prefix="$2"
  local dir src out="" oldifs
  mkdir -p "${prefix}"
  oldifs="${IFS}"
  IFS=':'
  # shellcheck disable=SC2086
  for dir in ${PATH}; do
    IFS="${oldifs}"
    if [[ -n "${dir}" && -e "${dir}/${hide}" ]]; then
      for src in git awk grep sed date mktemp cat; do
        if [[ -x "${dir}/${src}" && ! -e "${prefix}/${src}" ]]; then
          ln -s "${dir}/${src}" "${prefix}/${src}"
        fi
      done
      continue
    fi
    out="${out:+${out}:}${dir}"
  done
  IFS="${oldifs}"
  printf '%s' "${prefix}:${out}"
}

expect_ok "help" "${RELEASE}" --help
if command -v python3 >/dev/null 2>&1; then
  py_help=""
  if py_help="$(python3 "${RELEASE}" --help 2>&1)"; then
    pass "python3 invocation re-execs bash --help"
  else
    fail "python3 invocation re-execs bash --help"
    printf '%s\n' "${py_help}" >&2
  fi
  expect_contains "python3 --help is bash usage" "Usage: release.sh" "${py_help}"
  expect_missing "python3 invocation is not a SyntaxError" "SyntaxError" "${py_help}"
  expect_missing "python3 invocation is not a SyntaxWarning" "SyntaxWarning" "${py_help}"
else
  pass "python3 not installed; skip interpreter-mismatch fixture"
fi
expect_fail "invalid semver 1.2" "${RELEASE}" 1.2
expect_fail "leading v is rejected" "${RELEASE}" v0.2.0
expect_fail "empty prerelease identifier is rejected" "${RELEASE}" 1.0.0-rc..1
expect_fail "trailing prerelease dot is rejected" "${RELEASE}" 1.0.0-rc.
expect_fail "leading prerelease dot is rejected" "${RELEASE}" 1.0.0-.rc
expect_fail "numeric leading zero is rejected" "${RELEASE}" 01.0.0
expect_fail "git-ref-illegal prerelease is rejected" "${RELEASE}" 1.0.0-rc.lock
expect_fail "dry-run plus push rejected" "${RELEASE}" --dry-run --push 0.2.0
expect_fail "explicit VERSION cannot combine with --minor" "${RELEASE}" --minor 0.2.0
expect_fail "push and no-push rejected" "${RELEASE}" --push --no-push
expect_fail "publish-merged plus dry-run rejected" "${RELEASE}" --publish-merged --dry-run

REPO="${TMP}/cut"
init_repo "${REPO}"
SEED="$(git -C "${REPO}" rev-parse HEAD)"

auto_patch=""
if auto_patch="$(run_release "${REPO}" --dry-run 2>&1)"; then
  pass "dry-run without VERSION patch-bumps CHANGELOG"
else
  fail "dry-run without VERSION patch-bumps CHANGELOG"
  printf '%s\n' "${auto_patch}" >&2
fi
expect_contains "auto patch heading is 0.1.1" "## [0.1.1] - 2026-01-02" "${auto_patch}"
expect_contains "auto patch logs CHANGELOG source" "patch bump of 0.1.0 from CHANGELOG.md" "${auto_patch}"

auto_minor=""
if auto_minor="$(run_release "${REPO}" --dry-run --minor 2>&1)"; then
  pass "dry-run --minor bumps from CHANGELOG"
else
  fail "dry-run --minor bumps from CHANGELOG"
  printf '%s\n' "${auto_minor}" >&2
fi
expect_contains "auto minor heading is 0.2.0" "## [0.2.0] - 2026-01-02" "${auto_minor}"

auto_major=""
if auto_major="$(run_release "${REPO}" --dry-run --major 2>&1)"; then
  pass "dry-run --major bumps from CHANGELOG"
else
  fail "dry-run --major bumps from CHANGELOG"
  printf '%s\n' "${auto_major}" >&2
fi
expect_contains "auto major heading is 1.0.0" "## [1.0.0] - 2026-01-02" "${auto_major}"

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
expect_contains "default dry-run plan opens a PR" \
  "open a pull request to main" "${dry_out}"
expect_contains "default dry-run plan tags after merge" \
  "tag v0.2.0 after merge" "${dry_out}"

no_push_dry=""
if no_push_dry="$(run_release "${REPO}" --dry-run --no-push 2>&1)"; then
  pass "dry-run --no-push exits 0"
else
  fail "dry-run --no-push exits 0"
  printf '%s\n' "${no_push_dry}" >&2
fi
expect_contains "dry-run --no-push plan mentions --no-push" "(--no-push)" "${no_push_dry}"
expect_missing "dry-run --no-push plan omits git push" "git push" "${no_push_dry}"
expect_missing "dry-run --no-push plan omits gh release create" "gh release create" "${no_push_dry}"

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
expect_fail "empty Unreleased is rejected" run_release "${empty}" --no-push 0.2.0

dup="${TMP}/dup-section"
init_repo "${dup}"
expect_fail "duplicate changelog version is rejected" run_release "${dup}" --no-push 0.1.0

tagged="${TMP}/existing-tag"
init_repo "${tagged}"
git -C "${tagged}" tag -a v0.2.0 -m "already"
expect_fail "existing tag is rejected" run_release "${tagged}" --no-push 0.2.0

dirty="${TMP}/dirty"
init_repo "${dirty}"
printf 'dirty\n' >"${dirty}/extra.txt"
expect_fail "dirty work tree is rejected" run_release "${dirty}" --no-push 0.2.0

nogh="${TMP}/push-no-gh"
init_repo "${nogh}"
nogh_seed="$(git -C "${nogh}" rev-parse HEAD)"
nogh_path="$(path_without gh "${TMP}/no-gh-bin")"
push_without_gh() {
  (
    cd "${nogh}"
    env PATH="${nogh_path}" RELEASE_DATE=2026-01-02 "${RELEASE}"
  )
}
expect_fail "publish without gh is rejected before commit" push_without_gh
if [[ "$(git -C "${nogh}" rev-parse HEAD)" == "${nogh_seed}" ]]; then
  pass "publish without gh does not create a commit"
else
  fail "publish without gh created a commit"
fi
if git -C "${nogh}" rev-parse -q --verify refs/tags/v0.2.0 >/dev/null; then
  fail "publish without gh created tag v0.2.0"
else
  pass "publish without gh does not create a tag"
fi
expect_missing "publish without gh does not rewrite CHANGELOG" "## [0.1.1]" "$(cat "${nogh}/CHANGELOG.md")"

hookrepo="${TMP}/hooks"
init_repo "${hookrepo}"
mkdir -p "${hookrepo}/.git/hooks"
printf '#!/bin/sh\nexit 1\n' >"${hookrepo}/.git/hooks/commit-msg"
chmod +x "${hookrepo}/.git/hooks/commit-msg"
expect_fail "does not skip commit-msg hook" run_release "${hookrepo}" --no-push 0.2.0
if git -C "${hookrepo}" rev-parse -q --verify refs/tags/v0.2.0 >/dev/null; then
  fail "failed hook still created tag v0.2.0"
else
  pass "failed hook does not create a tag"
fi

cut="${TMP}/real-cut"
init_repo "${cut}"
cut_out=""
if cut_out="$(run_release "${cut}" --no-push 0.2.0 2>&1)"; then
  pass "real cut succeeds"
else
  fail "real cut succeeds"
  printf '%s\n' "${cut_out}" >&2
fi
expect_contains "no-push logs publish skipped" "Publish skipped (--no-push)" "${cut_out}"
expect_missing "no-push does not print git push commands" "git push origin v0.2.0" "${cut_out}"
expect_missing "no-push does not print gh release create" "gh release create" "${cut_out}"
cut_log="$(cat "${cut}/CHANGELOG.md")"
expect_contains "cut writes version heading" "## [0.2.0] - 2026-01-02" "${cut_log}"
expect_contains "cut keeps Unreleased stub" "## [Unreleased]" "${cut_log}"
expect_contains "cut moves the note under the version" "- a notable fix" "${cut_log}"
title_count="$(printf '%s\n' "${cut_log}" | grep -c '^# Changelog' || true)"
if [[ "${title_count}" == "1" ]]; then
  pass "cut changelog has a single title"
else
  fail "cut changelog title count is ${title_count}, want 1"
fi
if printf '%s\n' "${cut_log}" | grep -n '^# Changelog' | grep -qv '^1:'; then
  fail "cut changelog reprinted the file preamble"
else
  pass "cut changelog does not reprint the preamble"
fi
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

auto_cut="${TMP}/auto-cut"
init_repo "${auto_cut}"
auto_cut_out=""
if auto_cut_out="$(run_release "${auto_cut}" --no-push 2>&1)"; then
  pass "cut without VERSION or bump flag"
else
  fail "cut without VERSION or bump flag"
  printf '%s\n' "${auto_cut_out}" >&2
fi
expect_contains "auto cut logs CHANGELOG source" "patch bump of 0.1.0 from CHANGELOG.md" "${auto_cut_out}"
expect_contains "auto cut writes patch heading" "## [0.1.1] - 2026-01-02" "$(cat "${auto_cut}/CHANGELOG.md")"
if git -C "${auto_cut}" rev-parse -q --verify refs/tags/v0.1.1 >/dev/null; then
  pass "auto cut creates tag v0.1.1"
else
  fail "auto cut did not create tag v0.1.1"
fi

offmain="${TMP}/off-main"
init_repo "${offmain}"
git -C "${offmain}" checkout -q -b feature
if run_release "${offmain}" --dry-run >/dev/null 2>&1; then
  pass "dry-run allowed off main"
else
  fail "dry-run allowed off main"
fi
expect_fail "refuses to cut off main" run_release "${offmain}" --no-push

pub="${TMP}/publish-pr"
init_repo "${pub}"
bare="${TMP}/origin.git"
git init -q --bare --template= -b main "${bare}"
git -C "${pub}" remote set-url --push origin "${bare}"
git -C "${pub}" push -q -u origin main
fake_gh="${TMP}/fake-gh-bin"
mkdir -p "${fake_gh}"
cat >"${fake_gh}/gh" <<'EOF'
#!/bin/sh
if [ "$1" = pr ] && [ "$2" = create ]; then
  echo https://github.com/example/apple-silicon-mlx-native/pull/42
  exit 0
fi
exit 1
EOF
chmod +x "${fake_gh}/gh"
pub_seed="$(git -C "${pub}" rev-parse HEAD)"
pub_out=""
publish_pr() {
  (
    cd "${pub}"
    env PATH="${fake_gh}:${PATH}" RELEASE_DATE=2026-01-02 "${RELEASE}"
  )
}
if pub_out="$(publish_pr 2>&1)"; then
  pass "default publish opens a PR"
else
  fail "default publish opens a PR"
  printf '%s\n' "${pub_out}" >&2
fi
expect_contains "publish output has PR URL" \
  "https://github.com/example/apple-silicon-mlx-native/pull/42" "${pub_out}"
expect_contains "publish notes tag after merge" "tag v0.1.1 is created after merge" "${pub_out}"
if [[ "$(git -C "${pub}" rev-parse --abbrev-ref HEAD)" == "chore/release-0.1.1" ]]; then
  pass "publish checks out chore/release-0.1.1"
else
  fail "publish checks out chore/release-0.1.1 (got $(git -C "${pub}" rev-parse --abbrev-ref HEAD))"
fi
if git -C "${bare}" show-ref --verify --quiet refs/heads/chore/release-0.1.1; then
  pass "publish pushes chore/release-0.1.1"
else
  fail "publish pushes chore/release-0.1.1"
fi
if [[ "$(git -C "${bare}" rev-parse refs/heads/main)" == "${pub_seed}" ]]; then
  pass "publish does not push main"
else
  fail "publish pushed main"
fi
if git -C "${pub}" rev-parse -q --verify refs/tags/v0.1.1 >/dev/null; then
  fail "publish created local tag v0.1.1"
else
  pass "publish does not tag before merge"
fi

first="${TMP}/first-release"
mkdir -p "${first}"
git -C "${first}" init -q --template= -b main
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
first_auto=""
if first_auto="$(run_release "${first}" --dry-run 2>&1)"; then
  pass "first release without VERSION uses 0.1.0"
else
  fail "first release without VERSION uses 0.1.0"
  printf '%s\n' "${first_auto}" >&2
fi
expect_contains "first auto heading is 0.1.0" "## [0.1.0] - 2026-01-02" "${first_auto}"
expect_ok "first release succeeds" run_release "${first}" --no-push
first_log="$(cat "${first}/CHANGELOG.md")"
expect_contains "first release uses tag URL not compare" \
  "[0.1.0]: https://github.com/example/apple-silicon-mlx-native/releases/tag/v0.1.0" "${first_log}"
expect_contains "ssh origin becomes https footer" \
  "[Unreleased]: https://github.com/example/apple-silicon-mlx-native/compare/v0.1.0...HEAD" "${first_log}"

prerelease="${TMP}/rc"
init_repo "${prerelease}"
expect_ok "pre-release version succeeds" run_release "${prerelease}" --no-push 1.0.0-rc.1
pre_log="$(cat "${prerelease}/CHANGELOG.md")"
expect_contains "pre-release heading" "## [1.0.0-rc.1] - 2026-01-02" "${pre_log}"
expect_contains "pre-release compare URL" \
  "[1.0.0-rc.1]: https://github.com/example/apple-silicon-mlx-native/compare/v0.1.0...v1.0.0-rc.1" "${pre_log}"

rcprev="${TMP}/rc-prev"
init_repo "${rcprev}"
cat >"${rcprev}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Fixed

- a notable fix

## [1.0.0-rc.1] - 2026-01-01

### Added

- preview

[Unreleased]: https://github.com/example/apple-silicon-mlx-native/compare/v1.0.0-rc.1...HEAD
[1.0.0-rc.1]: https://github.com/example/apple-silicon-mlx-native/releases/tag/v1.0.0-rc.1
EOF
git -C "${rcprev}" add CHANGELOG.md
git -C "${rcprev}" commit -q -m "chore: seed rc changelog"
expect_fail "auto-bump refuses pre-release previous version" run_release "${rcprev}" --dry-run

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: release self-test passed\n'
