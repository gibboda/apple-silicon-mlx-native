#!/usr/bin/env bash
# Cut a SemVer release from CHANGELOG.md [Unreleased].
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/release.sh
#   scripts/release.sh --dry-run
#   scripts/release.sh --minor
#   scripts/release.sh --no-push
#
# Environment:
#   RELEASE_DATE      Override YYYY-MM-DD (tests / reproducible cuts)
#
# Does not bump pinned mlx/mflux versions. Does not force-push tags.
# Does not skip git hooks (--no-verify is never passed).
#
# This is a bash script. `python3 scripts/release.sh` re-execs bash.
# Polyglot: Python opens a ''' string (the trailing :' is string body).
# Bash concatenates '' with ':' and runs : (no-op). Do not change to ''' —
# that would start a single-quoted string and swallow the script.
# shellcheck source=scripts/lib/common.sh
''':'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
DO_PUSH=1
PUSH_OPT=""
PUBLISH_MERGED=0
VERSION=""
BUMP=""

usage() {
  cat <<'EOF'
Usage: release.sh [--dry-run] [--no-push|--push] [--patch|--minor|--major] [VERSION]
       release.sh --publish-merged

Cut a SemVer release from CHANGELOG.md [Unreleased] and open a pull request.
This is a bash script. `python3 scripts/release.sh` re-execs bash.

  VERSION            Optional override (pre-releases / unusual jumps). Default:
                     patch-bump the latest ## [x.y.z] heading in CHANGELOG.md
  --patch            Next x.y.(z+1) (default when VERSION is omitted)
  --minor            Next x.(y+1).0
  --major            Next (x+1).0.0
  --dry-run          Validate and print the planned changelog; write nothing
  --push             Push chore/release-VERSION and open a pull request (default)
  --no-push          Commit and tag locally; do not push or open a PR
  --publish-merged   CI: tag and gh release create after the cut PR merges to main
  -h, --help         Show this help

Requires a clean work tree on the default branch, a non-empty [Unreleased]
section, and gh (unless --dry-run or --no-push). Never pushes the default
branch (Protect main). Never passes --no-verify or force-pushes tags.

Environment:
  RELEASE_DATE  Override the changelog date (YYYY-MM-DD). Default: today.
EOF
}

set_push_opt() {
  local kind="$1"
  if [[ -n "${PUSH_OPT}" && "${PUSH_OPT}" != "${kind}" ]]; then
    die "Cannot combine --push and --no-push"
  fi
  PUSH_OPT="${kind}"
  if [[ "${kind}" == "push" ]]; then
    DO_PUSH=1
  else
    DO_PUSH=0
  fi
}

is_numeric_identifier() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]
}

# SemVer 2.0 pre-release identifier: non-empty [0-9A-Za-z-]+; all-numeric
# identifiers must not have leading zeros.
is_prerelease_identifier() {
  local id="$1"
  [[ -n "${id}" ]] || return 1
  [[ "${id}" =~ ^[0-9A-Za-z-]+$ ]] || return 1
  if [[ "${id}" =~ ^[0-9]+$ ]]; then
    is_numeric_identifier "${id}" || return 1
  fi
  return 0
}

is_prerelease() {
  local pre="$1"
  local id rest
  [[ -n "${pre}" ]] || return 1
  [[ "${pre}" != .* && "${pre}" != *. && "${pre}" != *..* ]] || return 1
  rest="${pre}"
  while [[ "${rest}" == *.* ]]; do
    id="${rest%%.*}"
    rest="${rest#*.}"
    is_prerelease_identifier "${id}" || return 1
  done
  is_prerelease_identifier "${rest}"
}

is_semver() {
  local v="$1"
  local major minor patch pre
  if [[ ! "${v}" =~ ^([0-9]+)[.]([0-9]+)[.]([0-9]+)(-([0-9A-Za-z.-]+))?$ ]]; then
    return 1
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  pre="${BASH_REMATCH[5]:-}"
  is_numeric_identifier "${major}" || return 1
  is_numeric_identifier "${minor}" || return 1
  is_numeric_identifier "${patch}" || return 1
  if [[ -n "${pre}" ]]; then
    is_prerelease "${pre}" || return 1
  fi
  return 0
}

github_https_from_remote() {
  local raw="$1"
  local owner repo
  raw="${raw%.git}"
  raw="${raw%/}"
  if [[ "${raw}" =~ github[.]com[:/]+([^/]+)/([^/]+) ]]; then
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
    /^## [[]Unreleased][[:space:]]*$/ { grab=1; next }
    grab && /^## [[]/ { exit }
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
    /^## [[][0-9]/ {
      if (match($0, /[[][^]]+/)) {
        print substr($0, RSTART+1, RLENGTH-1)
        exit
      }
    }
  ' "${file}"
}

extract_version_body() {
  local file="$1"
  local version="$2"
  awk -v ver="${version}" '
    $0 ~ "^## [[]" ver "]( |$)" { grab=1; next }
    grab && /^## [[]/ { exit }
    grab { print }
  ' "${file}" | trim_blank_lines
}

version_from_release_subject() {
  local subject="$1"
  local rest version
  [[ "${subject}" == "chore(release): cut "* ]] || return 1
  rest="${subject#chore(release): cut }"
  version="${rest%% *}"
  [[ -n "${version}" ]] || return 1
  printf '%s\n' "${version}"
}

changelog_has_list_item() {
  grep -qE '^[[:space:]]*-[[:space:]]' <<<"$1"
}

set_bump() {
  local kind="$1"
  if [[ -n "${BUMP}" && "${BUMP}" != "${kind}" ]]; then
    die "Cannot combine --${BUMP} and --${kind}"
  fi
  BUMP="${kind}"
}

bump_semver() {
  local v="$1"
  local kind="$2"
  local major minor patch
  if [[ ! "${v}" =~ ^([0-9]+)[.]([0-9]+)[.]([0-9]+)$ ]]; then
    die "Cannot auto-bump '${v}' (pre-release or invalid). Pass an explicit VERSION."
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  case "${kind}" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) die "Unknown bump kind: ${kind}" ;;
  esac
  printf '%s.%s.%s\n' "${major}" "${minor}" "${patch}"
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
    /^[[]Unreleased]:/ { in_footer=1; next }
    /^[[][0-9][^]]+]:/ {
      in_footer=1
      name=$0
      sub(/^[[]/, "", name)
      sub(/].*/, "", name)
      if (name == skip) next
      print
      next
    }
    in_footer && /^[[][^]]+]:/ { print }
  ' "${changelog}"
}

build_new_changelog() {
  local changelog="$1"
  local version="$2"
  local rel_date="$3"
  local body="$4"
  local repo_url="$5"
  local prev="$6"

  awk '/^## [[]Unreleased][[:space:]]*$/ { print; exit } { print }' "${changelog}"
  printf '\n## [%s] - %s\n\n%s\n\n' "${version}" "${rel_date}" "${body}"
  awk '
    BEGIN { skip=1 }
    /^## [[]Unreleased][[:space:]]*$/ { skip=1; next }
    skip && /^## [[]/ { skip=0 }
    skip { next }
    /^[[]Unreleased]:/ { exit }
    /^[[][0-9][^]]+]:/ { exit }
    { print }
  ' "${changelog}"
  build_footer "${repo_url}" "${version}" "${prev}" "${changelog}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --push) set_push_opt push; shift ;;
    --no-push) set_push_opt no-push; shift ;;
    --publish-merged) PUBLISH_MERGED=1; shift ;;
    --patch) set_bump patch; shift ;;
    --minor) set_bump minor; shift ;;
    --major) set_bump major; shift ;;
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

[[ "${DRY_RUN}" -eq 1 && "${PUSH_OPT}" == "push" ]] && die "Cannot combine --dry-run and --push"
if [[ "${PUBLISH_MERGED}" -eq 1 ]]; then
  [[ "${DRY_RUN}" -eq 0 ]] || die "Cannot combine --publish-merged and --dry-run"
  [[ -z "${PUSH_OPT}" ]] || die "Cannot combine --publish-merged and --push/--no-push"
  [[ -z "${VERSION}" && -z "${BUMP}" ]] || die "Cannot combine --publish-merged with VERSION or --patch/--minor/--major"
fi
if [[ -n "${VERSION}" && -n "${BUMP}" ]]; then
  die "Cannot combine explicit VERSION with --patch/--minor/--major"
fi

if [[ -n "${VERSION}" ]]; then
  if [[ "${VERSION}" == v* ]]; then
    die "VERSION must not include a leading v (got '${VERSION}'; pass ${VERSION#v})"
  fi
  is_semver "${VERSION}" || die "VERSION must be MAJOR.MINOR.PATCH with optional pre-release (got '${VERSION}')"
fi

require_cmd git
if [[ -n "${VERSION}" ]]; then
  git check-ref-format "refs/tags/v${VERSION}" \
    || die "VERSION is not a valid git tag name: v${VERSION}"
fi
if [[ "${DRY_RUN}" -eq 0 && ( "${DO_PUSH}" -eq 1 || "${PUBLISH_MERGED}" -eq 1 ) ]]; then
  require_cmd gh "Install GitHub CLI (gh) or pass --dry-run / --no-push."
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git work tree"

GIT_ROOT="$(git rev-parse --show-toplevel)"
CHANGELOG="${GIT_ROOT}/CHANGELOG.md"
[[ -f "${CHANGELOG}" ]] || die "Missing ${CHANGELOG}"

if [[ -n "$(git -C "${GIT_ROOT}" status --porcelain)" ]]; then
  die "Working tree is not clean. Commit or stash changes before cutting a release."
fi

CURRENT_BRANCH="$(git -C "${GIT_ROOT}" rev-parse --abbrev-ref HEAD)"
DEFAULT_BRANCH="$(git -C "${GIT_ROOT}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
[[ -n "${DEFAULT_BRANCH}" ]] || DEFAULT_BRANCH="main"

if [[ "${PUBLISH_MERGED}" -eq 1 ]]; then
  SUBJECT="$(git -C "${GIT_ROOT}" log -1 --format=%s)"
  VERSION="$(version_from_release_subject "${SUBJECT}")" \
    || die "HEAD subject is not 'chore(release): cut VERSION' (got '${SUBJECT}')"
  is_semver "${VERSION}" || die "VERSION must be MAJOR.MINOR.PATCH with optional pre-release (got '${VERSION}')"
  git check-ref-format "refs/tags/v${VERSION}" \
    || die "VERSION is not a valid git tag name: v${VERSION}"
  grep -qF "## [${VERSION}]" "${CHANGELOG}" \
    || die "CHANGELOG.md has no '${VERSION}' section"
  NOTES_BODY="$(extract_version_body "${CHANGELOG}" "${VERSION}")"
  changelog_has_list_item "${NOTES_BODY}" \
    || die "CHANGELOG [${VERSION}] has no notes to publish"
  NOTES_FILE="$(mktemp)"
  trap 'rm -f "${NOTES_FILE}"' EXIT
  {
    printf 'v%s\n\n' "${VERSION}"
    printf '%s\n' "${NOTES_BODY}"
  } >"${NOTES_FILE}"
  if git -C "${GIT_ROOT}" rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
    log_info "Tag v${VERSION} already exists"
  else
    git -C "${GIT_ROOT}" tag -a "v${VERSION}" -F "${NOTES_FILE}"
    log_ok "Created annotated tag v${VERSION}"
  fi
  git -C "${GIT_ROOT}" push origin "refs/tags/v${VERSION}"
  if gh release view "v${VERSION}" >/dev/null 2>&1; then
    log_info "GitHub Release v${VERSION} already exists"
  else
    BODY_FILE="$(mktemp)"
    trap 'rm -f "${NOTES_FILE}" "${BODY_FILE}"' EXIT
    printf '%s\n' "${NOTES_BODY}" >"${BODY_FILE}"
    gh release create "v${VERSION}" --title "v${VERSION}" --notes-file "${BODY_FILE}" --target "$(git -C "${GIT_ROOT}" rev-parse HEAD)"
    log_ok "Created GitHub Release v${VERSION}"
  fi
  exit 0
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
  [[ "${CURRENT_BRANCH}" != "HEAD" ]] || die "Cannot cut a release in detached HEAD"
  if [[ "${CURRENT_BRANCH}" != "${DEFAULT_BRANCH}" ]]; then
    die "Cut releases on ${DEFAULT_BRANCH} (currently on ${CURRENT_BRANCH})"
  fi
fi

grep -qE '^## [[]Unreleased][[:space:]]*$' "${CHANGELOG}" \
  || die "CHANGELOG.md has no '## [Unreleased]' heading"

UNRELEASED_BODY="$(extract_unreleased_body "${CHANGELOG}" | trim_blank_lines)"
changelog_has_list_item "${UNRELEASED_BODY}" \
  || die "CHANGELOG [Unreleased] has no notes to release (need at least one list item)"

PREV_VERSION="$(previous_changelog_version "${CHANGELOG}")"

if [[ -z "${VERSION}" ]]; then
  [[ -n "${BUMP}" ]] || BUMP="patch"
  if [[ -z "${PREV_VERSION}" ]]; then
    VERSION="0.1.0"
    log_info "No previous CHANGELOG version; using ${VERSION}"
  else
    VERSION="$(bump_semver "${PREV_VERSION}" "${BUMP}")"
    log_info "Using ${VERSION} (${BUMP} bump of ${PREV_VERSION} from CHANGELOG.md)"
  fi
fi

git check-ref-format "refs/tags/v${VERSION}" \
  || die "VERSION is not a valid git tag name: v${VERSION}"

if git -C "${GIT_ROOT}" rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
  die "Git tag v${VERSION} already exists"
fi

if grep -qF "## [${VERSION}]" "${CHANGELOG}"; then
  die "CHANGELOG.md already has a '${VERSION}' section"
fi

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
  if [[ "${DO_PUSH}" -eq 1 ]]; then
    log_info "Dry-run: would commit 'chore(release): cut ${VERSION}' on chore/release-${VERSION}, open a pull request to ${DEFAULT_BRANCH}, and tag v${VERSION} after merge"
  else
    log_info "Dry-run: would commit 'chore(release): cut ${VERSION}' and annotated tag v${VERSION} (--no-push)"
  fi
  log_ok "Dry-run complete (no write, no tag, no push)"
  exit 0
fi

RELEASE_BRANCH="chore/release-${VERSION}"
if [[ "${DO_PUSH}" -eq 1 ]]; then
  if git -C "${GIT_ROOT}" show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}"; then
    die "Branch ${RELEASE_BRANCH} already exists"
  fi
  if git -C "${GIT_ROOT}" ls-remote --exit-code --heads origin "${RELEASE_BRANCH}" >/dev/null 2>&1; then
    die "Remote branch ${RELEASE_BRANCH} already exists"
  fi
  git -C "${GIT_ROOT}" checkout -q -b "${RELEASE_BRANCH}"
fi

printf '%s\n' "${NEW_CHANGELOG}" >"${CHANGELOG}"
git -C "${GIT_ROOT}" add -- CHANGELOG.md
git -C "${GIT_ROOT}" commit -m "chore(release): cut ${VERSION}"

if [[ "${DO_PUSH}" -eq 1 ]]; then
  git -C "${GIT_ROOT}" push -u origin HEAD
  PR_URL="$(gh pr create --title "chore(release): cut ${VERSION}" --body "${UNRELEASED_BODY}" --base "${DEFAULT_BRANCH}")"
  log_ok "Opened ${PR_URL} (tag v${VERSION} is created after merge)"
else
  NOTES_FILE="$(mktemp)"
  trap 'rm -f "${NOTES_FILE}"' EXIT
  {
    printf 'v%s\n\n' "${VERSION}"
    printf '%s\n' "${UNRELEASED_BODY}"
  } >"${NOTES_FILE}"
  git -C "${GIT_ROOT}" tag -a "v${VERSION}" -F "${NOTES_FILE}"
  log_ok "Committed CHANGELOG and created annotated tag v${VERSION}"
  log_info "Publish skipped (--no-push)"
fi

# python3 $0 swallows the bash body in a string, then re-execs bash.
: <<'ENDPYTHON'
'''
import os
import sys
os.execvp("bash", ["bash"] + sys.argv)
ENDPYTHON
