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

unset MLX_IMAGE_FAMILY MLX_IMAGE_MODEL MLX_IMAGE_QUANTIZE MLX_IMAGE_STEPS MLX_IMAGE_WIDTH MLX_IMAGE_HEIGHT MLX_IMAGE_LOW_RAM MLX_IMAGE_SEED
unset OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS
export OVERRIDE_MEMORY_TIER=constrained
export OVERRIDE_THERMAL_CLASS=cooled
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
expect_contains "constrained default tier" "tier=constrained" "${plan_default}"
expect_contains "constrained default width" "width=512" "${plan_default}"
expect_contains "constrained default height" "height=512" "${plan_default}"
expect_contains "constrained default steps" "steps=4" "${plan_default}"
expect_contains "constrained default quantize" "quantize=4" "${plan_default}"
expect_contains "constrained default low_ram" "low_ram=1" "${plan_default}"
expect_contains "constrained default vae_tiling" "vae_tiling=1" "${plan_default}"

plan_z="$("${GENERATE}" --dump-plan --prompt "plan" --family z-image-turbo)"
expect_contains "z-image family selected" "family=z-image-turbo" "${plan_z}"
expect_contains "z-image does not inherit flux2-klein-4b" "model=z-image-turbo" "${plan_z}"
expect_contains "z-image cli is turbo generator" "cli=mflux-generate-z-image-turbo" "${plan_z}"
expect_contains "z-image on constrained keeps ram-tier width" "width=512" "${plan_z}"
expect_contains "z-image on constrained keeps ram-tier steps" "steps=4" "${plan_z}"
expect_contains "z-image on constrained still vae-tiles" "vae_tiling=1" "${plan_z}"
if [[ "${plan_z}" == *"flux2-klein-4b"* ]]; then
  fail "z-image plan leaked flux2-klein-4b"
else
  pass "z-image plan has no flux2-klein-4b"
fi

plan_high="$(OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "high tier default family is z-image-turbo" "family=z-image-turbo" "${plan_high}"
expect_contains "high tier default model is z-image-turbo" "model=z-image-turbo" "${plan_high}"
expect_contains "high tier cli is turbo generator" "cli=mflux-generate-z-image-turbo" "${plan_high}"
expect_contains "high tier width is 1024" "width=1024" "${plan_high}"
expect_contains "high tier steps is 9" "steps=9" "${plan_high}"
expect_contains "high tier does not auto vae-tile" "vae_tiling=0" "${plan_high}"
if [[ "${plan_high}" == *"flux2-klein-4b"* ]]; then
  fail "high tier plan leaked flux2-klein-4b"
else
  pass "high tier plan has no flux2-klein-4b"
fi

expect_fail "mismatched --model/--family rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --family z-image-turbo --model flux2-klein-4b

expect_fail "custom output outside workspace rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --output /tmp/mlx-image-outside.png
out_escape="$("${GENERATE}" --dump-plan --prompt "plan" --output /tmp/mlx-image-outside.png 2>&1 || true)"
expect_contains "outside output mentions MLX_WORKSPACE" "MLX_WORKSPACE" "${out_escape}"

expect_fail "output via .. outside workspace rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --output "${MLX_WORKSPACE}/../escape.png"

expect_ok "custom output under workspace accepted" \
  "${GENERATE}" --dump-plan --prompt "plan" --output "${MLX_WORKSPACE}/outputs/images/ok.png"

plan_m1="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=1 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=8 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "M1 16 GB dump-plan chip family" "chip_family=1" "${plan_m1}"
expect_contains "M1 16 GB dump-plan sku base" "chip_sku=base" "${plan_m1}"
expect_contains "M1 16 GB dump-plan slow" "throughput_class=slow" "${plan_m1}"
expect_contains "M1 16 GB stays 4-bit" "quantize=4" "${plan_m1}"
expect_contains "M1 16 GB stays low_ram" "low_ram=1" "${plan_m1}"

plan_m5="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "M5 16 GB dump-plan chip family" "chip_family=5" "${plan_m5}"
expect_contains "M5 16 GB dump-plan fast" "throughput_class=fast" "${plan_m5}"
expect_contains "M5 16 GB may use 8-bit" "quantize=8" "${plan_m5}"
expect_contains "M5 16 GB width 768" "width=768" "${plan_m5}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: mlx-image self-test passed\n'
