#!/usr/bin/env bash
# Self-test for opt-in MLX image install/generate wrappers (Linux and macOS).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${ROOT}/scripts/install-mlx-image.sh"
GENERATE="${ROOT}/scripts/generate-mlx-image.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

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

unset MLX_IMAGE_FAMILY MLX_IMAGE_MODEL MLX_IMAGE_QUANTIZE MLX_IMAGE_STEPS MLX_IMAGE_WIDTH MLX_IMAGE_HEIGHT MLX_IMAGE_LOW_RAM OVERRIDE_MEMORY_TIER
export MLX_WORKSPACE="${TMP}/ws"
export MLX_VENV="${MLX_WORKSPACE}/.venv"
mkdir -p "${MLX_WORKSPACE}"

expect_ok "install --help" "${INSTALL}" --help
expect_ok "generate --help" "${GENERATE}" --help
expect_fail "install unknown arg" "${INSTALL}" --nope
expect_fail "generate unknown arg" "${GENERATE}" --nope

help_out="$("${GENERATE}" --help)"
expect_contains "generate help mentions flux2" "flux2" "${help_out}"

expect_fail "generate without prompt" "${GENERATE}"
expect_fail "install without venv" "${INSTALL}"
expect_fail "generate with prompt but no venv" "${GENERATE}" --prompt "a test prompt"

out="$("${GENERATE}" 2>&1 || true)"
expect_contains "missing prompt mentions --prompt" "--prompt" "${out}"

plan_default="$("${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "constrained default family is flux2" "family=flux2" "${plan_default}"
expect_contains "constrained default model is flux2-klein-4b" "model=flux2-klein-4b" "${plan_default}"
expect_contains "constrained default cli is flux2" "cli=mflux-generate-flux2" "${plan_default}"

plan_z="$("${GENERATE}" --dump-plan --prompt "plan" --family z-image-turbo)"
expect_contains "z-image family selected" "family=z-image-turbo" "${plan_z}"
expect_contains "z-image does not inherit flux2-klein-4b" "model=z-image-turbo" "${plan_z}"
expect_contains "z-image cli is turbo generator" "cli=mflux-generate-z-image-turbo" "${plan_z}"
if [[ "${plan_z}" == *"flux2-klein-4b"* ]]; then
  fail "z-image plan leaked flux2-klein-4b"
else
  pass "z-image plan has no flux2-klein-4b"
fi

plan_high="$(OVERRIDE_MEMORY_TIER=high "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "high tier default family is z-image-turbo" "family=z-image-turbo" "${plan_high}"
expect_contains "high tier default model is z-image-turbo" "model=z-image-turbo" "${plan_high}"
expect_contains "high tier cli is turbo generator" "cli=mflux-generate-z-image-turbo" "${plan_high}"
if [[ "${plan_high}" == *"flux2-klein-4b"* ]]; then
  fail "high tier plan leaked flux2-klein-4b"
else
  pass "high tier plan has no flux2-klein-4b"
fi

expect_fail "mismatched --model/--family rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --family z-image-turbo --model flux2-klein-4b

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: mlx-image self-test passed\n'
