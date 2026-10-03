#!/usr/bin/env bash
# The README repository tree must match git-tracked files.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="${ROOT}/README.md"

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

# Print one relative path per file entry in the Repository structure fence.
readme_tree_files() {
  local source="${1:-${README}}"
  local line rest name depth i joined previous
  local -a stack=()
  local -a next=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -n "${line}" ]] || continue
    [[ "${line}" == *├──* || "${line}" == *└──* ]] || continue
    rest="${line}"
    depth=0
    while true; do
      previous="${rest}"
      if [[ "${rest}" == │[[:space:]][[:space:]][[:space:]]* ]]; then
        rest="${rest#│   }"
        depth=$((depth + 1))
      elif [[ "${rest}" == "    "* ]]; then
        rest="${rest#    }"
        depth=$((depth + 1))
      else
        break
      fi
      if [[ "${rest}" == "${previous}" ]]; then
        printf 'unparsed tree line: %s\n' "${line}" >&2
        return 1
      fi
    done
    if [[ "${rest}" == ├─* ]]; then
      name="${rest#├── }"
    elif [[ "${rest}" == └─* ]]; then
      name="${rest#└── }"
    else
      printf 'unparsed tree line: %s\n' "${line}" >&2
      return 1
    fi
    next=()
    for (( i = 0; i < depth && i < ${#stack[@]}; i++ )); do
      next[i]="${stack[i]}"
    done
    if (( ${#next[@]} > 0 )); then
      stack=("${next[@]}")
    else
      stack=()
    fi
    if [[ "${name}" == */ ]]; then
      stack[depth]="${name%/}"
      continue
    fi
    if (( ${#stack[@]} > 0 )); then
      joined=""
      for (( i = 0; i < ${#stack[@]}; i++ )); do
        if [[ -n "${joined}" ]]; then
          joined="${joined}/${stack[i]}"
        else
          joined="${stack[i]}"
        fi
      done
      printf '%s/%s\n' "${joined}" "${name}"
    else
      printf '%s\n' "${name}"
    fi
  done < <(
    awk '
      { sub(/\r$/, "") }
      /^## Repository structure/ { in_heading = 1; next }
      in_heading && /^```text$/ { in_tree = 1; next }
      in_heading && in_tree && /^```$/ { exit }
      in_tree { print }
    ' "${source}"
  )
}

if ! command -v git >/dev/null 2>&1; then
  printf 'FAIL: git is required to compare the README tree\n' >&2
  exit 1
fi

if ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "not a git repository (README tree test requires git-tracked files)"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
tracked="${TMP}/tracked"
listed="${TMP}/listed"

git -C "${ROOT}" ls-files | LC_ALL=C sort >"${tracked}"
if ! readme_tree_files | LC_ALL=C sort >"${listed}"; then
  fail "README repository tree could not be parsed"
else
  pass "README repository tree parsed"
fi

if [[ ! -s "${listed}" ]]; then
  fail "README '## Repository structure' text fence not found or empty"
else
  missing="$(comm -23 "${tracked}" "${listed}" || true)"
  extra="$(comm -13 "${tracked}" "${listed}" || true)"
  if [[ -z "${missing}" && -z "${extra}" ]]; then
    pass "README repository tree matches tracked files"
  else
    if [[ -n "${missing}" ]]; then
      fail "README tree is missing tracked paths"
      printf '%s\n' "${missing}" >&2
    fi
    if [[ -n "${extra}" ]]; then
      fail "README tree lists paths that are not tracked"
      printf '%s\n' "${extra}" >&2
    fi
    printf 'Hint: Update the tree under %s in README.md.\n' "'## Repository structure'" >&2
  fi
fi

crlf_src="${TMP}/readme-crlf.md"
printf '%s\r\n' \
  '## Repository structure' \
  '```text' \
  'apple-silicon-mlx-native/' \
  '├── README.md' \
  '```' \
  >"${crlf_src}"
crlf_parsed="$(readme_tree_files "${crlf_src}")"
if [[ "${crlf_parsed}" == "README.md" ]]; then
  pass "README tree parser accepts CRLF fences"
else
  fail "README tree parser accepts CRLF fences (${crlf_parsed})"
fi

if (( failures > 0 )); then
  printf 'FAIL: %s README tree check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: readme-tree self-test passed\n'
exit 0
