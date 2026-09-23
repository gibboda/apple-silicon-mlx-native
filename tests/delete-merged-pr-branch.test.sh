#!/usr/bin/env bash
# Portable fixtures for scripts/delete-merged-pr-branch.sh.
# Fake `gh` only — never calls the GitHub delete API.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELETE="${ROOT}/scripts/delete-merged-pr-branch.sh"
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

expect_not_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "${label} (unexpected ${needle})"
  else
    pass "${label}"
  fi
}

FAKE_BIN="${TMP}/bin"
GH_LOG="${TMP}/gh.log"
mkdir -p "${FAKE_BIN}"
cat >"${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${GH_LOG}"
if [[ "${1:-}" == "pr" ]]; then
  printf '%s\n' "${FAKE_STACKED:-0}"
  exit 0
fi
if [[ "${1:-}" == "api" ]]; then
  method=""
  path=""
  prev=""
  for arg in "$@"; do
    if [[ "${prev}" == "--method" ]]; then
      method="${arg}"
      prev=""
      continue
    fi
    if [[ "${prev}" == "--jq" ]]; then
      prev=""
      continue
    fi
    case "${arg}" in
      --method|--jq) prev="${arg}" ;;
      api) ;;
      --*) ;;
      *) path="${arg}" ;;
    esac
  done
  printf 'METHOD=%s PATH=%s\n' "${method}" "${path}" >>"${GH_LOG}"
  if [[ "${method}" == "GET" ]]; then
    if [[ "${FAKE_GET_STATUS:-0}" != "0" ]]; then
      printf '%s\n' "${FAKE_GET_BODY:-}"
      exit "${FAKE_GET_STATUS}"
    fi
    printf '%s\n' "${FAKE_SHA:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
    exit 0
  fi
  if [[ "${method}" == "DELETE" ]]; then
    if [[ "${FAKE_DELETE_STATUS:-0}" != "0" ]]; then
      printf '%s\n' "${FAKE_DELETE_BODY:-}"
      exit "${FAKE_DELETE_STATUS}"
    fi
    exit 0
  fi
fi
printf 'unexpected gh invocation\n' >&2
exit 99
EOF
chmod +x "${FAKE_BIN}/gh"

SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
SHA_A_UPPER="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

GITHUB_REPOSITORY="example/repo"
HEAD_REPO="example/repo"
HEAD_REF="feature/foo"
HEAD_SHA=""
BASE_REF="main"
DEFAULT_BRANCH="main"
DRY_RUN="false"
FAKE_STACKED="0"
FAKE_SHA="${SHA_A}"
FAKE_GET_STATUS="0"
FAKE_GET_BODY=""
FAKE_DELETE_STATUS="0"
FAKE_DELETE_BODY=""

invoke() {
  : >"${GH_LOG}"
  PATH="${FAKE_BIN}:/usr/bin:/bin" \
    GH_LOG="${GH_LOG}" \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY}" \
    HEAD_REPO="${HEAD_REPO}" \
    HEAD_REF="${HEAD_REF}" \
    HEAD_SHA="${HEAD_SHA}" \
    BASE_REF="${BASE_REF}" \
    DEFAULT_BRANCH="${DEFAULT_BRANCH}" \
    DRY_RUN="${DRY_RUN}" \
    FAKE_STACKED="${FAKE_STACKED}" \
    FAKE_SHA="${FAKE_SHA}" \
    FAKE_GET_STATUS="${FAKE_GET_STATUS}" \
    FAKE_GET_BODY="${FAKE_GET_BODY}" \
    FAKE_DELETE_STATUS="${FAKE_DELETE_STATUS}" \
    FAKE_DELETE_BODY="${FAKE_DELETE_BODY}" \
    "${DELETE}"
}

reset_case() {
  GITHUB_REPOSITORY="example/repo"
  HEAD_REPO="example/repo"
  HEAD_REF="feature/foo"
  HEAD_SHA=""
  BASE_REF="main"
  DEFAULT_BRANCH="main"
  DRY_RUN="false"
  FAKE_STACKED="0"
  FAKE_SHA="${SHA_A}"
  FAKE_GET_STATUS="0"
  FAKE_GET_BODY=""
  FAKE_DELETE_STATUS="0"
  FAKE_DELETE_BODY=""
}

reset_case
GITHUB_REPOSITORY=""
expect_fail "requires GITHUB_REPOSITORY" invoke

reset_case
HEAD_REF=""
out="$(invoke)"
expect_contains "empty HEAD_REF skips" "nothing to delete" "${out}"
expect_eq_log="$(cat "${GH_LOG}")"
expect_not_contains "empty HEAD_REF does not call gh" "pr list" "${expect_eq_log}"

reset_case
HEAD_REF="feature/../../etc"
out="$(invoke)"
expect_contains "unsafe HEAD_REF skips" "unsafe" "${out}"

reset_case
HEAD_REPO="other/fork"
out="$(invoke)"
expect_contains "fork head skips" "Skipping fork head other/fork" "${out}"
expect_not_contains "fork skip does not call gh" "pr list" "$(cat "${GH_LOG}")"

reset_case
HEAD_REF="main"
out="$(invoke)"
expect_contains "refuses default branch" "Refusing to delete default/base branch 'main'" "${out}"

reset_case
HEAD_REF="develop"
BASE_REF="develop"
DEFAULT_BRANCH="main"
out="$(invoke)"
expect_contains "refuses base branch" "Refusing to delete default/base branch 'develop'" "${out}"

reset_case
HEAD_REF="refs/heads/main"
out="$(invoke)"
expect_contains "strips refs/heads before refusing main" "Refusing to delete default/base branch 'main'" "${out}"

reset_case
FAKE_STACKED="2"
out="$(invoke)"
expect_contains "stacked PRs skip delete" "2 open PR(s) still use it as base" "${out}"
expect_not_contains "stacked skip does not DELETE" "METHOD=DELETE" "$(cat "${GH_LOG}")"

reset_case
DRY_RUN="true"
HEAD_REF="feature/foo#bar"
out="$(invoke)"
expect_contains "dry-run percent-encodes the ref" "git/refs/heads/feature%2Ffoo%23bar" "${out}"
expect_not_contains "dry-run without SHA does not DELETE" "METHOD=DELETE" "$(cat "${GH_LOG}")"

reset_case
expect_fail "HEAD_SHA required unless dry-run" invoke

reset_case
HEAD_SHA="not-a-sha"
expect_fail "HEAD_SHA must be 40 hex" invoke

reset_case
HEAD_SHA="${SHA_A}"
FAKE_SHA="${SHA_B}"
out="$(invoke)"
expect_contains "SHA mismatch skips" "ref points at ${SHA_B}" "${out}"
expect_not_contains "SHA mismatch does not DELETE" "METHOD=DELETE" "$(cat "${GH_LOG}")"

reset_case
HEAD_SHA="${SHA_A}"
FAKE_SHA="${SHA_A_UPPER}"
DRY_RUN="true"
out="$(invoke)"
expect_contains "SHA match is case-insensitive" "would DELETE" "${out}"
expect_contains "dry-run records the live sha" "sha ${SHA_A_UPPER}" "${out}"
expect_not_contains "dry-run with SHA does not DELETE" "METHOD=DELETE" "$(cat "${GH_LOG}")"

reset_case
HEAD_SHA="${SHA_A}"
FAKE_GET_STATUS="1"
FAKE_GET_BODY='{"message":"Not Found","documentation_url":"https://docs.github.com/rest/git/refs#get-a-reference","status":"404"}'
out="$(invoke)"
expect_contains "missing ref on GET is already deleted" "already deleted" "${out}"
expect_not_contains "missing GET does not DELETE" "METHOD=DELETE" "$(cat "${GH_LOG}")"

reset_case
HEAD_SHA="${SHA_A}"
FAKE_GET_STATUS="1"
FAKE_GET_BODY='{"message":"Not Found","status":"404"}'
expect_fail "generic 404 is not already-deleted" invoke

reset_case
HEAD_SHA="${SHA_A}"
FAKE_DELETE_STATUS="1"
FAKE_DELETE_BODY='{"message":"Reference does not exist","status":"422"}'
out="$(invoke)"
expect_contains "delete 422 missing ref is already deleted" "already deleted" "${out}"
expect_contains "matching SHA does call DELETE" "METHOD=DELETE" "$(cat "${GH_LOG}")"

reset_case
HEAD_SHA="${SHA_A}"
out="$(invoke)"
expect_contains "delete success" "Deleted head branch 'feature/foo'" "${out}"
expect_contains "delete path is encoded" "METHOD=DELETE PATH=repos/example/repo/git/refs/heads/feature%2Ffoo" "$(cat "${GH_LOG}")"

reset_case
HEAD_SHA="${SHA_A}"
FAKE_DELETE_STATUS="1"
FAKE_DELETE_BODY='{"message":"Server Error","status":"500"}'
expect_fail "other delete errors fail" invoke

if (( failures > 0 )); then
  printf 'FAIL: %s branch-delete check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: delete-merged-pr-branch\n'
