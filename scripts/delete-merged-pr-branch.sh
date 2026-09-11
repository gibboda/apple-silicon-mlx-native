#!/usr/bin/env bash
# Delete a merged pull-request head branch (same-repository only).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Intended for GitHub Actions on pull_request closed when merged == true.
# Branch names and the merged head SHA come from the environment so they
# are not interpolated into workflow YAML run scripts.
#
# Usage:
#   HEAD_REPO=owner/repo HEAD_REF=feature/foo HEAD_SHA=<40-hex> BASE_REF=main \
#     DEFAULT_BRANCH=main GITHUB_REPOSITORY=owner/repo \
#     scripts/delete-merged-pr-branch.sh
#
# Environment:
#   GITHUB_REPOSITORY  owner/name of this repository (Actions sets this)
#   HEAD_REPO          owner/name of the PR head repository
#   HEAD_REF           PR head branch name (no refs/heads/ prefix)
#   HEAD_SHA           merged PR head commit SHA (40 hex); required unless DRY_RUN
#   BASE_REF           PR base branch name
#   DEFAULT_BRANCH     repository default branch (typically main)
#   GH_TOKEN           token with contents:write (Actions GITHUB_TOKEN)
#   DRY_RUN            true|false — skip the DELETE (default: false)

set -euo pipefail

log_info()  { printf 'INFO: %s\n' "$*"; }
log_ok()    { printf 'OK: %s\n' "$*"; }
log_error() { printf 'ERROR: %s\n' "$*" >&2; }

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Percent-encode a git ref so `gh api` does not treat # ? as URL delimiters.
# RFC 3986 unreserved characters stay literal; every other character becomes %HH
# (including /, which GitHub documents as requiring encoding in ref names).
percent_encode() {
  local LC_ALL=C
  local s=$1
  local i c hex out=''
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9._~-]) out+=$c ;;
      *)
        printf -v hex '%02X' "'$c"
        out+="%$hex"
        ;;
    esac
  done
  printf '%s' "$out"
}

# Delete-a-reference returns 422 with this message when the ref is gone.
# Do not treat generic 404/422 bodies as success.
is_delete_missing_ref() {
  grep -Fq 'Reference does not exist' <<<"$1"
}

# Get-a-reference returns 404 Not Found for a missing ref (not the delete
# message above). Require the get-a-reference documentation marker so a
# generic repository 404 is not mistaken for "already deleted".
is_get_missing_ref() {
  grep -Fq 'get-a-reference' <<<"$1" && grep -Eq '"status":[[:space:]]*"404"' <<<"$1"
}

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
HEAD_REPO="${HEAD_REPO:-}"
HEAD_REF="${HEAD_REF:-}"
HEAD_SHA="${HEAD_SHA:-}"
BASE_REF="${BASE_REF:-}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
DRY_RUN="${DRY_RUN:-false}"

if [[ -z "${GITHUB_REPOSITORY}" ]]; then
  log_error "GITHUB_REPOSITORY is required."
  exit 1
fi

if [[ -z "${HEAD_REF}" ]]; then
  log_ok "HEAD_REF is empty; nothing to delete."
  exit 0
fi

# GitHub head.ref is the branch name; tolerate an accidental refs/heads/ prefix.
HEAD_REF="${HEAD_REF#refs/heads/}"

# Reject empty-after-strip, path traversal, and whitespace (defense in depth).
case "${HEAD_REF}" in
  ''|*..*|*[[:space:]]*|/*)
    log_ok "HEAD_REF is empty or unsafe (${HEAD_REF:-<empty>}); skipping delete."
    exit 0
    ;;
esac

if [[ -z "${HEAD_REPO}" ]]; then
  log_error "HEAD_REPO is required."
  exit 1
fi

if [[ "${HEAD_REPO}" != "${GITHUB_REPOSITORY}" ]]; then
  log_ok "Skipping fork head ${HEAD_REPO} (this repo is ${GITHUB_REPOSITORY})."
  exit 0
fi

if [[ "${HEAD_REF}" == "${DEFAULT_BRANCH}" || "${HEAD_REF}" == "main" || "${HEAD_REF}" == "${BASE_REF}" ]]; then
  log_ok "Refusing to delete default/base branch '${HEAD_REF}'."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  log_error "Required command not found: gh"
  exit 1
fi

stacked_count="$(
  gh pr list \
    --repo "${GITHUB_REPOSITORY}" \
    --base "${HEAD_REF}" \
    --state open \
    --json number \
    --jq 'length'
)"

if [[ "${stacked_count}" != "0" ]]; then
  log_ok "Skipping delete of '${HEAD_REF}': ${stacked_count} open PR(s) still use it as base."
  exit 0
fi

encoded_ref="$(percent_encode "${HEAD_REF}")"
get_path="repos/${GITHUB_REPOSITORY}/git/ref/heads/${encoded_ref}"
delete_path="repos/${GITHUB_REPOSITORY}/git/refs/heads/${encoded_ref}"

if is_truthy "${DRY_RUN}" && [[ -z "${HEAD_SHA}" ]]; then
  log_ok "DRY_RUN: would DELETE ${delete_path}"
  exit 0
fi

if [[ -z "${HEAD_SHA}" ]]; then
  log_error "HEAD_SHA is required to verify the ref still points at the merged head."
  exit 1
fi

if [[ ! "${HEAD_SHA}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  log_error "HEAD_SHA must be a 40-character commit SHA."
  exit 1
fi

log_info "Fetching ${get_path}"

get_output=""
get_status=0
set +e
get_output="$(gh api --method GET "${get_path}" --jq .object.sha 2>&1)"
get_status=$?
set -e

if [[ "${get_status}" -ne 0 ]]; then
  if is_get_missing_ref "${get_output}" || is_delete_missing_ref "${get_output}"; then
    log_ok "Head branch '${HEAD_REF}' already deleted."
    exit 0
  fi
  log_error "Failed to read ref '${HEAD_REF}': ${get_output}"
  exit 1
fi

current_sha="$(printf '%s' "${get_output}" | tr -d '[:space:]')"
if [[ ! "${current_sha}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  log_error "Unexpected GET ref response for '${HEAD_REF}': ${get_output}"
  exit 1
fi

expected_sha="$(printf '%s' "${HEAD_SHA}" | tr '[:upper:]' '[:lower:]')"
actual_sha="$(printf '%s' "${current_sha}" | tr '[:upper:]' '[:lower:]')"
if [[ "${actual_sha}" != "${expected_sha}" ]]; then
  log_ok "Skipping delete of '${HEAD_REF}': ref points at ${current_sha}, merged head was ${HEAD_SHA}."
  exit 0
fi

if is_truthy "${DRY_RUN}"; then
  log_ok "DRY_RUN: would DELETE ${delete_path} (sha ${current_sha})"
  exit 0
fi

log_info "Deleting ${delete_path}"

delete_output=""
delete_status=0
set +e
delete_output="$(gh api --method DELETE "${delete_path}" 2>&1)"
delete_status=$?
set -e

if [[ "${delete_status}" -eq 0 ]]; then
  log_ok "Deleted head branch '${HEAD_REF}'."
  exit 0
fi

if is_delete_missing_ref "${delete_output}"; then
  log_ok "Head branch '${HEAD_REF}' already deleted."
  exit 0
fi

log_error "Failed to delete '${HEAD_REF}': ${delete_output}"
exit 1
