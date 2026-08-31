#!/usr/bin/env bash
# Delete a merged pull-request head branch (same-repository only).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Intended for GitHub Actions on pull_request closed when merged == true.
# Branch names come from the environment so they are not interpolated into
# workflow YAML run scripts.
#
# Usage:
#   HEAD_REPO=owner/repo HEAD_REF=feature/foo BASE_REF=main \
#     DEFAULT_BRANCH=main GITHUB_REPOSITORY=owner/repo \
#     scripts/delete-merged-pr-branch.sh
#
# Environment:
#   GITHUB_REPOSITORY  owner/name of this repository (Actions sets this)
#   HEAD_REPO          owner/name of the PR head repository
#   HEAD_REF           PR head branch name (no refs/heads/ prefix)
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

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
HEAD_REPO="${HEAD_REPO:-}"
HEAD_REF="${HEAD_REF:-}"
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

ref_path="repos/${GITHUB_REPOSITORY}/git/refs/heads/${HEAD_REF}"

if is_truthy "${DRY_RUN}"; then
  log_ok "DRY_RUN: would DELETE ${ref_path}"
  exit 0
fi

log_info "Deleting ${ref_path}"

delete_output=""
delete_status=0
set +e
delete_output="$(gh api --method DELETE "${ref_path}" 2>&1)"
delete_status=$?
set -e

if [[ "${delete_status}" -eq 0 ]]; then
  log_ok "Deleted head branch '${HEAD_REF}'."
  exit 0
fi

# GitHub returns 404/422 when the ref is already gone (native auto-delete, or a
# previous run). Treat that as success so the workflow stays green.
if grep -Eqi 'Reference does not exist|Not Found|"status":[[:space:]]*"404"|HTTP[[:space:]]+404|HTTP[[:space:]]+422' <<<"${delete_output}"; then
  log_ok "Head branch '${HEAD_REF}' already deleted."
  exit 0
fi

log_error "Failed to delete '${HEAD_REF}': ${delete_output}"
exit 1
