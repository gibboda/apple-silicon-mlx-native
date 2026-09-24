#!/usr/bin/env bash
# Make image/video extra args must not be evaluated as shell.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

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

help_out="$(make -C "${ROOT}" help)"
expect_contains "help still lists image" "make image" "${help_out}"
expect_contains "help still lists video" "make video" "${help_out}"

plan="$(make -C "${ROOT}" image IMAGE_PROMPT='a red fox' GENERATE_IMAGE_ARGS='--family schnell --dump-plan')"
expect_contains "image args reach the generator" "family=schnell" "${plan}"

sentinel="${TMP}/pwned"
rm -f "${sentinel}"
set +e
make -C "${ROOT}" image IMAGE_PROMPT='a fox' GENERATE_IMAGE_ARGS="; touch ${sentinel}" >/dev/null 2>&1
set -e
if [[ -e "${sentinel}" ]]; then
  fail "semicolon in GENERATE_IMAGE_ARGS was executed"
else
  pass "semicolon in GENERATE_IMAGE_ARGS was not executed"
fi

rm -f "${sentinel}"
set +e
make -C "${ROOT}" image IMAGE_PROMPT='a fox' GENERATE_IMAGE_ARGS='`touch '"${sentinel}"'`' >/dev/null 2>&1
set -e
if [[ -e "${sentinel}" ]]; then
  fail "backticks in GENERATE_IMAGE_ARGS were executed"
else
  pass "backticks in GENERATE_IMAGE_ARGS were not executed"
fi

rm -f "${sentinel}"
set +e
# Two dollar signs so Make receives a literal $(touch ...) and the recipe shell does not run it.
touch_expr="$(printf '%b%b(touch %s)' '\044' '\044' "${sentinel}")"
make -C "${ROOT}" video VIDEO_PROMPT='a fox' GENERATE_VIDEO_ARGS="${touch_expr}" >/dev/null 2>&1
set -e
if [[ -e "${sentinel}" ]]; then
  fail "command substitution in GENERATE_VIDEO_ARGS was executed"
else
  pass "command substitution in GENERATE_VIDEO_ARGS was not executed"
fi

plan_video="$(make -C "${ROOT}" video VIDEO_PROMPT='a fox' GENERATE_VIDEO_ARGS='--dump-plan')"
expect_contains "video args reach the generator" "family=" "${plan_video}"

if (( failures > 0 )); then
  printf 'FAIL: %s generate-args check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: generate args are not a shell\n'
