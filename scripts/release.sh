#!/usr/bin/env bash
# Cut a SemVer release from CHANGELOG.md [Unreleased].
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/release.sh 0.2.2
#   scripts/release.sh --dry-run 0.2.2
#   scripts/release.sh --push 0.2.2
#
# Environment:
#   RELEASE_DATE      Override YYYY-MM-DD (tests / reproducible cuts)
#
# Does not bump pinned mlx/mflux versions. Does not force-push tags.
# Does not skip git hooks (--no-verify is never passed).
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
DO_PUSH=0
VERSION=""

usage() {
  cat <<'EOF'
Usage: release.sh [--dry-run] [--push] VERSION

Cut a SemVer release from CHANGELOG.md [Unreleased].

  VERSION       MAJOR.MINOR.PATCH with optional pre-release (e.g. 0.2.2, 1.0.0-rc.1)
  --dry-run     Validate and print the planned changelog; write nothing, do not tag
  --push        After commit+tag, git push and gh release create (off by default)
  -h, --help    Show this help

Requires a clean work tree and a non-empty [Unreleased] section. Creates commit
  chore(release): cut VERSION
and annotated tag vVERSION. Never passes --no-verify or force-pushes tags.

Environment:
  RELEASE_DATE  Override the changelog date (YYYY-MM-DD). Default: today.
EOF
}

is_semver() {
  local v="$1"
  [[ "${v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]
}

github_https_from_remote() {
  local raw="$1"
  local owner repo
  raw="${raw%.git}"
  raw="${raw%/}"
  if [[ "${raw}" =~ github\.com[:/]+([^/]+)/([^/]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    repo="${repo%.git}"
    printf 'https://github.com/%s/%s\n' "${owner}" "${repo}"
    return 0
  fi
  return 1
}

extract_unreleased_body() {
  local file="$1"
  awk '
    /^## \[Unreleased\][[:space:]]*$/ { grab=1; next }
    grab && /^## \[/ { exit }
    grab { print }
  ' "${file}"
}

trim_blank_lines() {
  awk '
    { lines[NR]=$0 }
    END {
      start=1
      end=NR
      while (start<=end && lines[start] ~ /^[[:space:]]*$/) start++
      while (end>=start && lines[end] ~ /^[[:space:]]*$/) end--
      for (i=start; i<=end; i++) print lines[i]
    }
  '
}

previous_changelog_version() {
  local file="$1"
  awk '
    /^## \[[0-9]/ {
      if (match($0, /\[[^]]+\]/)) {
        print substr($0, RSTART+1, RLENGTH-2)
        exit
      }
    }
  ' "${file}"
}

changelog_has_list_item() {
  grep -qE '^[[:space:]]*-[[:space:]]' <<<"$1"
}

build_footer() {
  local repo_url="$1"
  local version="$2"
  local prev="$3"
  local changelog="$4"

  printf '[Unreleased]: %s/compare/v%s...HEAD\n' "${repo_url}" "${version}"
  if [[ -n "${prev}" ]]; then
    printf '[%s]: %s/compare/v%s...v%s\n' "${version}" "${repo_url}" "${prev}" "${version}"
  else
    printf '[%s]: %s/releases/tag/v%s\n' "${version}" "${repo_url}" "${version}"
  fi
  awk -v skip="${version}" '
    /^\[Unreleased\]:/ { in_footer=1; next }
    /^\[[0-9][^]]+\]:/ {
      in_footer=1
      name=$0
      sub(/^\[/, "", name)
      sub(/].*/, "", name)
      if (name == skip) next
      print
      next
    }
    in_footer && /^\[[^]]+\]:/ { print }
  ' "${changelog}"
}

build_new_changelog() {
  local changelog="$1"
  local version="$2"
  local rel_date="$3"
  local body="$4"
  local repo_url="$5"
  local prev="$6"

  awk '/^## \[Unreleased\][[:space:]]*$/ { print; exit } { print }' "${changelog}"
  printf '\n## [%s] - %s\n\n%s\n\n' "${version}" "${rel_date}" "${body}"
  awk '
    /^## \[Unreleased\][[:space:]]*$/ { skip=1; next }
    skip && /^## \[/ { skip=0 }
    skip { next }
    /^\[Unreleased\]:/ { exit }
    /^\[[0-9][^]]+\]:/ { exit }
    { print }
  ' "${changelog}"
  build_footer "${repo_url}" "${version}" "${prev}" "${changelog}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --push) DO_PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "Unknown argument: $1" ;;
    *)
      if [[ -n "${VERSION}" ]]; then
        die "Unexpected extra argument: $1"
      fi
      VERSION="$1"
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  if [[ -n "${VERSION}" ]]; then
    die "Unexpected extra argument: $1"
  fi
  VERSION="$1"
  shift
  [[ $# -eq 0 ]] || die "Unexpected extra argument: $1"
fi

[[ -n "${VERSION}" ]] || die "VERSION is required (e.g. 0.2.2). See --help."
[[ "${DRY_RUN}" -eq 1 && "${DO_PUSH}" -eq 1 ]] && die "Cannot combine --dry-run and --push"

if [[ "${VERSION}" == v* ]]; then
  die "VERSION must not include a leading v (got '${VERSION}'; pass ${VERSION#v})"
fi
is_semver "${VERSION}" || die "VERSION must be MAJOR.MINOR.PATCH with optional pre-release (got '${VERSION}')"

require_cmd git
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git work tree"

GIT_ROOT="$(git rev-parse --show-toplevel)"
CHANGELOG="${GIT_ROOT}/CHANGELOG.md"
[[ -f "${CHANGELOG}" ]] || die "Missing ${CHANGELOG}"

if [[ -n "$(git -C "${GIT_ROOT}" status --porcelain)" ]]; then
  die "Working tree is not clean. Commit or stash changes before cutting a release."
fi

if git -C "${GIT_ROOT}" rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
  die "Git tag v${VERSION} already exists"
fi

if grep -qF "## [${VERSION}]" "${CHANGELOG}"; then
  die "CHANGELOG.md already has a '${VERSION}' section"
fi

grep -qE '^## \[Unreleased\][[:space:]]*$' "${CHANGELOG}" \
  || die "CHANGELOG.md has no '## [Unreleased]' heading"

UNRELEASED_BODY="$(extract_unreleased_body "${CHANGELOG}" | trim_blank_lines)"
changelog_has_list_item "${UNRELEASED_BODY}" \
  || die "CHANGELOG [Unreleased] has no notes to release (need at least one list item)"

PREV_VERSION="$(previous_changelog_version "${CHANGELOG}")"
REL_DATE="${RELEASE_DATE:-$(date +%Y-%m-%d)}"
if [[ ! "${REL_DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  die "RELEASE_DATE must be YYYY-MM-DD (got '${REL_DATE}')"
fi

ORIGIN_URL="$(git -C "${GIT_ROOT}" remote get-url origin 2>/dev/null || true)"
[[ -n "${ORIGIN_URL}" ]] || die "git remote 'origin' is required to write changelog compare URLs"
REPO_URL="$(github_https_from_remote "${ORIGIN_URL}")" \
  || die "origin remote is not a GitHub URL: ${ORIGIN_URL}"

NEW_CHANGELOG="$(build_new_changelog "${CHANGELOG}" "${VERSION}" "${REL_DATE}" "${UNRELEASED_BODY}" "${REPO_URL}" "${PREV_VERSION}")"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log_info "Dry-run: CHANGELOG.md would become:"
  printf '%s\n' "${NEW_CHANGELOG}"
  log_info "Dry-run: would commit 'chore(release): cut ${VERSION}' and annotated tag v${VERSION}"
  log_ok "Dry-run complete (no write, no tag, no push)"
  exit 0
fi

printf '%s\n' "${NEW_CHANGELOG}" >"${CHANGELOG}"
git -C "${GIT_ROOT}" add -- CHANGELOG.md
git -C "${GIT_ROOT}" commit -m "chore(release): cut ${VERSION}"

NOTES_FILE="$(mktemp)"
trap 'rm -f "${NOTES_FILE}"' EXIT
{
  printf 'v%s\n\n' "${VERSION}"
  printf '%s\n' "${UNRELEASED_BODY}"
} >"${NOTES_FILE}"
git -C "${GIT_ROOT}" tag -a "v${VERSION}" -F "${NOTES_FILE}"

log_ok "Committed CHANGELOG and created annotated tag v${VERSION}"
log_info "Push skipped (default). To publish: scripts/release.sh --push ${VERSION}"
log_info "or: git push && git push origin v${VERSION} && gh release create v${VERSION}"

if [[ "${DO_PUSH}" -eq 1 ]]; then
  require_cmd gh "Install GitHub CLI (gh) or omit --push."
  if git -C "${GIT_ROOT}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git -C "${GIT_ROOT}" push
  else
    git -C "${GIT_ROOT}" push -u origin HEAD
  fi
  git -C "${GIT_ROOT}" push origin "refs/tags/v${VERSION}"
  BODY_FILE="$(mktemp)"
  trap 'rm -f "${NOTES_FILE}" "${BODY_FILE}"' EXIT
  printf '%s\n' "${UNRELEASED_BODY}" >"${BODY_FILE}"
  gh release create "v${VERSION}" --title "v${VERSION}" --notes-file "${BODY_FILE}"
  log_ok "Pushed v${VERSION} and created GitHub Release"
fi
