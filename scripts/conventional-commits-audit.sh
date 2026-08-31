#!/usr/bin/env bash
# Audit Git commit subjects against Conventional Commits policy.
#
# Accepted subject syntax:
#   <type>[optional scope][!]: <description>
#
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
# Scope: lowercase alphanumeric, hyphen, underscore, slash (optional)
# Breaking change: optional '!' before ':' or a footer "BREAKING CHANGE:"
# Description: non-empty, preferably ≤72 characters for the subject line
#
# Exempt by default:
#   - GitHub merge commits: "Merge pull request #N from ..."
#   - GitHub merge branch:  "Merge branch '...' ..."
#   - Git revert subjects that already match: "revert: ..."
#
# Usage:
#   scripts/conventional-commits-audit.sh
#   scripts/conventional-commits-audit.sh --range ORIGIN_REF...HEAD
#   COMMIT_RANGE='origin/main...HEAD' scripts/conventional-commits-audit.sh
#
# Environment:
#   COMMIT_RANGE          Override commit range (default: see below)
#   AUDIT_BASE_REF        Base ref for PR-style ranges (default: origin/main)
#   EXEMPT_MERGE_COMMITS  true|false (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

EXEMPT_MERGE_COMMITS="${EXEMPT_MERGE_COMMITS:-true}"
AUDIT_BASE_REF="${AUDIT_BASE_REF:-origin/main}"
RANGE=""

usage() {
  cat <<'EOF'
Usage: conventional-commits-audit.sh [--range FROM...TO] [-h|--help]

Audit commit subjects for Conventional Commits compliance.

Accepted form:
  <type>[scope][!]: <description>

Allowed types:
  feat fix docs style refactor perf test build ci chore revert

Examples of valid subjects:
  feat: add Apple Silicon hardware detection
  feat(mlx): add environment validation
  docs(models): document 8 GB recommendations
  fix!: reject Intel Macs with a clear error
  chore: add shellcheck workflow

Exempt (when EXEMPT_MERGE_COMMITS=true):
  Merge pull request #123 from user/branch
  Merge branch 'main' into feature

Default range selection:
  1. --range / COMMIT_RANGE if provided
  2. GitHub Actions PR range (GITHUB_BASE_SHA...GITHUB_SHA) when set
  3. AUDIT_BASE_REF...HEAD when the base ref exists
  4. Otherwise: all commits reachable from HEAD (full history)

Exit status:
  0 — all audited commits comply
  1 — one or more violations (or git/range errors)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --range)
      [[ $# -ge 2 ]] || die "--range requires FROM...TO"
      RANGE="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

require_cmd git

if [[ -n "${COMMIT_RANGE:-}" && -z "${RANGE}" ]]; then
  RANGE="${COMMIT_RANGE}"
fi

if [[ -z "${RANGE}" ]]; then
  if [[ -n "${GITHUB_BASE_SHA:-}" && -n "${GITHUB_SHA:-}" ]]; then
    RANGE="${GITHUB_BASE_SHA}...${GITHUB_SHA}"
  elif git rev-parse --verify "${AUDIT_BASE_REF}" >/dev/null 2>&1; then
    RANGE="${AUDIT_BASE_REF}...HEAD"
  else
    RANGE="HEAD"
  fi
fi

# Conventional Commits subject regex (POSIX ERE via grep -E).
# type(scope)!: description  OR  type: description
CC_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9/_.-]+\))?\!?: .+'

is_exempt_merge() {
  local subject="$1"
  if ! is_truthy "${EXEMPT_MERGE_COMMITS}"; then
    return 1
  fi
  case "${subject}" in
    "Merge pull request #"*) return 0 ;;
    "Merge branch "*) return 0 ;;
    "Merge remote-tracking branch "*) return 0 ;;
    *) return 1 ;;
  esac
}

log_header "Conventional Commits audit"
log_info "Range: ${RANGE}"

# Collect commits (macOS-compatible; avoid bash-4 mapfile).
commit_list=""
if [[ "${RANGE}" == "HEAD" ]]; then
  commit_list="$(git rev-list --max-count=1 HEAD)"
else
  if ! git rev-list --count "${RANGE}" >/dev/null 2>&1; then
    die "Invalid or unreachable commit range: ${RANGE}"
  fi
  commit_list="$(git rev-list --reverse "${RANGE}")"
fi

if [[ -z "${commit_list}" ]]; then
  log_ok "No commits in range to audit."
  exit 0
fi

violations=0
audited=0
exempted=0

while IFS= read -r sha; do
  [[ -n "${sha}" ]] || continue
  subject="$(git log -1 --format='%s' "${sha}")"
  if is_exempt_merge "${subject}"; then
    exempted=$((exempted + 1))
    log_info "exempt  ${sha:0:8}  ${subject}"
    continue
  fi
  audited=$((audited + 1))
  if printf '%s\n' "${subject}" | grep -Eq "${CC_REGEX}"; then
    log_ok "pass    ${sha:0:8}  ${subject}"
  else
    violations=$((violations + 1))
    log_error "FAIL    ${sha:0:8}  ${subject}"
    log_error "        Expected: <type>[scope][!]: <description>"
  fi
done <<<"${commit_list}"

echo
log_info "Audited=${audited} exempted=${exempted} violations=${violations}"

if (( violations > 0 )); then
  log_error "Conventional Commits audit failed."
  exit 1
fi

log_ok "Conventional Commits audit passed."
exit 0
