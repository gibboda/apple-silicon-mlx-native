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

plan_m3="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "M3 16 GB dump-plan chip family" "chip_family=3" "${plan_m3}"
expect_contains "M3 16 GB dump-plan moderate" "throughput_class=moderate" "${plan_m3}"
expect_contains "M3 16 GB stays 4-bit" "quantize=4" "${plan_m3}"
expect_contains "M3 16 GB stays low_ram" "low_ram=1" "${plan_m3}"
expect_contains "M3 16 GB width 768" "width=768" "${plan_m3}"

plan_m3pro18="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro \
  OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "18 GB M3 Pro dump-plan chip family" "chip_family=3" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro dump-plan sku pro" "chip_sku=pro" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro dump-plan gpu cores" "gpu_cores=18" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro dump-plan fast" "throughput_class=fast" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro dump-plan standard tier" "tier=standard" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro stays flux2" "family=flux2" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro is 8-bit" "quantize=8" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro width 768" "width=768" "${plan_m3pro18}"
expect_contains "18 GB M3 Pro height 768" "height=768" "${plan_m3pro18}"
if [[ "${plan_m3pro18}" == *"z-image-turbo"* || "${plan_m3pro18}" == *"width=1024"* ]]; then
  fail "18 GB M3 Pro plan used the 24 GB image profile"
else
  pass "18 GB M3 Pro plan is not z-image-turbo 1024"
fi

plan_m3pro24="$(OVERRIDE_MEMORY_TIER=high OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro \
  OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "24 GB M3 Pro dump-plan high tier" "tier=high" "${plan_m3pro24}"
expect_contains "24 GB M3 Pro dump-plan sku pro" "chip_sku=pro" "${plan_m3pro24}"
expect_contains "24 GB M3 Pro default family is z-image-turbo" "family=z-image-turbo" "${plan_m3pro24}"
expect_contains "24 GB M3 Pro width 1024" "width=1024" "${plan_m3pro24}"
expect_contains "24 GB M3 Pro height 1024" "height=1024" "${plan_m3pro24}"
expect_contains "24 GB M3 Pro steps 9" "steps=9" "${plan_m3pro24}"
expect_contains "24 GB M3 Pro is 8-bit" "quantize=8" "${plan_m3pro24}"
if [[ "${plan_m3pro24}" == *"flux2-klein-4b"* ]]; then
  fail "24 GB M3 Pro plan leaked flux2-klein-4b"
else
  pass "24 GB M3 Pro plan has no flux2-klein-4b"
fi

mkdir -p "${MLX_WORKSPACE}/config"
PWNED_ENV="${TMP}/pwned-from-models-env"
printf 'touch %q\nMLX_IMAGE_WIDTH=640\n' "${PWNED_ENV}" >"${MLX_WORKSPACE}/config/models.env"
plan_env="$("${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "models.env width is parsed" "width=640" "${plan_env}"
if [[ -e "${PWNED_ENV}" ]]; then
  fail "models.env command line was executed"
else
  pass "models.env command line is not executed"
fi

image_marker="${TMP}/image-numeric-marker"
empty_image_env="${TMP}/empty-image.env"
: >"${empty_image_env}"

reject_image_number() {
  local label="$1"
  local needle="$2"
  shift 2
  local out rc
  rm -f "${image_marker}"
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    fail "${label} (expected non-zero exit)"
    return
  fi
  if [[ -e "${image_marker}" ]]; then
    fail "${label} (marker file was created)"
    return
  fi
  if [[ "${out}" == *"Python venv not found"* || "${out}" == *"syntax error"* || "${out}" == *"invalid arithmetic"* ]]; then
    fail "${label} (ran arithmetic or venv work)"
    return
  fi
  expect_contains "${label}" "${needle}" "${out}"
}

# $(touch ...) is the payload text. This shell must not run it.
inject="HOME[\$(touch ${image_marker})]"
reject_image_number "CLI width injection" "--width" \
  "${GENERATE}" --prompt plan --width "${inject}"
reject_image_number "CLI width 17abc" "--width" \
  "${GENERATE}" --dump-plan --prompt plan --width 17abc
reject_image_number "CLI width 0" "--width" \
  "${GENERATE}" --dump-plan --prompt plan --width 0
reject_image_number "CLI width negative" "--width" \
  "${GENERATE}" --dump-plan --prompt plan --width -1
reject_image_number "CLI width empty" "--width" \
  "${GENERATE}" --dump-plan --prompt plan --width ""
reject_image_number "CLI height injection" "--height" \
  "${GENERATE}" --dump-plan --prompt plan --height "${inject}"
reject_image_number "CLI steps injection" "--steps" \
  "${GENERATE}" --dump-plan --prompt plan --steps "${inject}"
reject_image_number "CLI quantize 7" "--quantize" \
  "${GENERATE}" --dump-plan --prompt plan --quantize 7
reject_image_number "CLI quantize empty" "--quantize" \
  "${GENERATE}" --dump-plan --prompt plan --quantize ""
reject_image_number "CLI seed injection" "--seed" \
  "${GENERATE}" --dump-plan --prompt plan --seed "${inject}"
reject_image_number "CLI seed negative" "--seed" \
  "${GENERATE}" --dump-plan --prompt plan --seed -1
reject_image_number "CLI seed empty" "--seed" \
  "${GENERATE}" --dump-plan --prompt plan --seed ""
reject_image_number "CLI width above 999999" "999999" \
  "${GENERATE}" --dump-plan --prompt plan --width 1000000

printf '%s\n' "MLX_IMAGE_WIDTH='${inject}'" >"${TMP}/bad-image-width.env"
reject_image_number "models.env width injection" "MLX_IMAGE_WIDTH" \
  env MLX_MODELS_ENV="${TMP}/bad-image-width.env" "${GENERATE}" --prompt plan
printf '%s\n' "MLX_IMAGE_QUANTIZE=" >"${TMP}/bad-image-quant.env"
reject_image_number "models.env quantize empty" "MLX_IMAGE_QUANTIZE" \
  env MLX_MODELS_ENV="${TMP}/bad-image-quant.env" "${GENERATE}" --dump-plan --prompt plan
printf '%s\n' "MLX_IMAGE_STEPS=0" >"${TMP}/bad-image-steps.env"
reject_image_number "models.env steps 0" "MLX_IMAGE_STEPS" \
  env MLX_MODELS_ENV="${TMP}/bad-image-steps.env" "${GENERATE}" --dump-plan --prompt plan

reject_image_number "env width injection" "MLX_IMAGE_WIDTH" \
  env MLX_IMAGE_WIDTH="${inject}" MLX_MODELS_ENV="${empty_image_env}" \
  "${GENERATE}" --dump-plan --prompt plan

printf '%s\n' "MLX_IMAGE_SEED=-1" >"${TMP}/bad-image-seed-neg.env"
reject_image_number "models.env seed negative" "MLX_IMAGE_SEED" \
  env MLX_MODELS_ENV="${TMP}/bad-image-seed-neg.env" "${GENERATE}" --dump-plan --prompt plan
printf '%s\n' "MLX_IMAGE_SEED=abc" >"${TMP}/bad-image-seed-abc.env"
reject_image_number "models.env seed abc" "MLX_IMAGE_SEED" \
  env MLX_MODELS_ENV="${TMP}/bad-image-seed-abc.env" "${GENERATE}" --dump-plan --prompt plan
printf '%s\n' "MLX_IMAGE_SEED=" >"${TMP}/bad-image-seed-empty.env"
reject_image_number "models.env seed empty" "MLX_IMAGE_SEED" \
  env MLX_MODELS_ENV="${TMP}/bad-image-seed-empty.env" "${GENERATE}" --dump-plan --prompt plan
reject_image_number "env seed negative" "MLX_IMAGE_SEED" \
  env MLX_IMAGE_SEED=-1 MLX_MODELS_ENV="${empty_image_env}" \
  "${GENERATE}" --dump-plan --prompt plan

plan_numbers="$(
  env MLX_MODELS_ENV="${empty_image_env}" \
    "${GENERATE}" --dump-plan --prompt plan --quantize 6 --width 640 --height 768 --steps 2 --seed 0
)"
expect_contains "quantize 6 accepted" "quantize=6" "${plan_numbers}"
expect_contains "width 640 accepted" "width=640" "${plan_numbers}"
expect_contains "height 768 accepted" "height=768" "${plan_numbers}"
expect_contains "steps 2 accepted" "steps=2" "${plan_numbers}"
expect_contains "seed 0 accepted" "seed=0" "${plan_numbers}"
plan_max_width="$(
  env MLX_MODELS_ENV="${empty_image_env}" \
    "${GENERATE}" --dump-plan --prompt plan --width 999999
)"
expect_contains "width 999999 accepted" "width=999999" "${plan_max_width}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: mlx-image self-test passed\n'
