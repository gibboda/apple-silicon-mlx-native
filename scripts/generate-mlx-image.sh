#!/usr/bin/env bash
# Generate an image with Pure MLX mflux using memory-tier defaults.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/generate-mlx-image.sh --prompt "a red fox in snow"
#   make image IMAGE_PROMPT="a red fox in snow"
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROMPT="${IMAGE_PROMPT:-}"
FAMILY=""
MODEL=""
QUANTIZE=""
STEPS=""
WIDTH=""
HEIGHT=""
SEED=""
OUTPUT=""
LOW_RAM=""
CUSTOM_OUTPUT=0
DUMP_PLAN=0
PASSTHRU=()
CLI_FAMILY=""
CLI_MODEL=""

usage() {
  cat <<'EOF'
Usage: generate-mlx-image.sh --prompt TEXT [options]

Generate a PNG with mflux (Pure MLX). Requires `make install-image`.

Options:
  --prompt TEXT     Text prompt (required; or IMAGE_PROMPT)
  --family NAME     flux2 | z-image-turbo | schnell (CLI/checkpoint; default: memory-tier profile)
  --model NAME      mflux --model value (FLUX.2 Klein id, HF repo, or local path)
  --quantize N      Weight quantize bits (3–8). Alias: -q
  --steps N         Denoising steps
  --width N         Image width
  --height N        Image height
  --seed N          RNG seed
  --output PATH     Output PNG (default: outputs/images/mlx-<timestamp>.png)
  --low-ram         Force mflux --low-ram
  --no-low-ram      Disable --low-ram even on constrained machines
  --dump-plan       Print resolved plan (family/model/CLI/tier/chip/size/steps) and exit
  --                Extra args passed through to the mflux CLI
  -h, --help        Show this help

Defaults come from the composed profile (memory tier + throughput class +
thermal class, or OVERRIDE_MEMORY_TIER / OVERRIDE_CHIP_* / OVERRIDE_THERMAL_CLASS),
then config/models.env (MLX_IMAGE_*). --family changes the mflux CLI and default
checkpoint only; width/height/steps/quantize/--low-ram still follow the composed
profile unless you set those flags or MLX_IMAGE_*.
EOF
}

image_cli_for_family() {
  case "$1" in
    flux2) echo "mflux-generate-flux2" ;;
    z-image-turbo) echo "mflux-generate-z-image-turbo" ;;
    schnell) echo "mflux-generate" ;;
    *) return 1 ;;
  esac
}

default_image_model_for_family() {
  case "$1" in
    flux2) echo "flux2-klein-4b" ;;
    z-image-turbo) echo "z-image-turbo" ;;
    schnell) echo "schnell" ;;
    *) echo "" ;;
  esac
}

# True when model is a known alias of a different family (do not pass it through).
image_model_conflicts_with_family() {
  local family="$1"
  local model="${2:-}"
  local lower
  [[ -n "${model}" ]] || return 1
  lower="$(printf '%s' "${model}" | tr '[:upper:]' '[:lower:]')"
  case "${family}" in
    z-image-turbo)
      case "${lower}" in
        flux2-*|schnell|dev|krea-dev) return 0 ;;
      esac
      ;;
    flux2)
      case "${lower}" in
        z-image-turbo|zimage-turbo|z-image|schnell) return 0 ;;
      esac
      ;;
    schnell)
      case "${lower}" in
        flux2-*|z-image*|zimage-*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --prompt)
      [[ $# -ge 2 ]] || die "--prompt requires TEXT"
      PROMPT="$2"
      shift 2
      ;;
    --family)
      [[ $# -ge 2 ]] || die "--family requires NAME"
      CLI_FAMILY="$2"
      FAMILY="$2"
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || die "--model requires NAME"
      CLI_MODEL="$2"
      MODEL="$2"
      shift 2
      ;;
    --quantize|-q)
      [[ $# -ge 2 ]] || die "--quantize requires N"
      QUANTIZE="$2"
      shift 2
      ;;
    --steps)
      [[ $# -ge 2 ]] || die "--steps requires N"
      STEPS="$2"
      shift 2
      ;;
    --width)
      [[ $# -ge 2 ]] || die "--width requires N"
      WIDTH="$2"
      shift 2
      ;;
    --height)
      [[ $# -ge 2 ]] || die "--height requires N"
      HEIGHT="$2"
      shift 2
      ;;
    --seed)
      [[ $# -ge 2 ]] || die "--seed requires N"
      SEED="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires PATH"
      OUTPUT="$2"
      CUSTOM_OUTPUT=1
      shift 2
      ;;
    --low-ram) LOW_RAM=1; shift ;;
    --no-low-ram) LOW_RAM=0; shift ;;
    --dump-plan) DUMP_PLAN=1; shift ;;
    --)
      shift
      PASSTHRU+=("$@")
      break
      ;;
    *) die "Unknown argument: $1 (use -- to pass flags through to mflux)" ;;
  esac
done

if [[ -z "${PROMPT}" ]]; then
  usage >&2
  die "Missing --prompt (or IMAGE_PROMPT). Example: scripts/generate-mlx-image.sh --prompt \"a red fox in snow\""
fi

if [[ -f "${MLX_MODELS_ENV}" ]]; then
  # shellcheck source=/dev/null
  source "${MLX_MODELS_ENV}"
fi

SEED="${SEED:-${MLX_IMAGE_SEED:-}}"

if (( DUMP_PLAN == 0 )); then
  if [[ ! -x "$(venv_python)" ]]; then
    die "Python venv not found at ${MLX_VENV}. Run: make install && make install-image"
  fi
  assert_apple_silicon
fi
if (( DUMP_PLAN == 1 )); then
  MLX_SKIP_DEVICE_PROBE=1
fi
load_runtime_profile

profile="${MLX_RECOMMENDED_IMAGE_PROFILE:-$(recommended_image_profile_for_tier "${MLX_TIER_ID}")}"
IFS='|' read -r def_family def_model def_quant def_steps def_width def_height def_low_ram <<<"${profile}"

FAMILY="${CLI_FAMILY:-${MLX_IMAGE_FAMILY:-${def_family}}}"
QUANTIZE="${QUANTIZE:-${MLX_IMAGE_QUANTIZE:-${def_quant}}}"
STEPS="${STEPS:-${MLX_IMAGE_STEPS:-${def_steps}}}"
WIDTH="${WIDTH:-${MLX_IMAGE_WIDTH:-${def_width}}}"
HEIGHT="${HEIGHT:-${MLX_IMAGE_HEIGHT:-${def_height}}}"
if [[ -z "${LOW_RAM}" ]]; then
  LOW_RAM="${MLX_IMAGE_LOW_RAM:-${def_low_ram}}"
fi

if [[ -n "${CLI_MODEL}" ]]; then
  MODEL="${CLI_MODEL}"
elif [[ -n "${MLX_IMAGE_MODEL:-}" ]] && ! image_model_conflicts_with_family "${FAMILY}" "${MLX_IMAGE_MODEL}"; then
  MODEL="${MLX_IMAGE_MODEL}"
elif [[ "${FAMILY}" == "${def_family}" ]]; then
  MODEL="${def_model}"
else
  MODEL="$(default_image_model_for_family "${FAMILY}")"
fi
if [[ -z "${MODEL}" ]]; then
  MODEL="$(default_image_model_for_family "${FAMILY}")"
fi
if image_model_conflicts_with_family "${FAMILY}" "${MODEL}"; then
  die "Model '${MODEL}' cannot be used with family '${FAMILY}'. Omit --model or pass a ${FAMILY} checkpoint."
fi

cli_name="$(image_cli_for_family "${FAMILY}")" \
  || die "Unknown --family ${FAMILY}. Use flux2, z-image-turbo, or schnell."

passthru_has_flag() {
  local flag="$1"
  local arg
  ((${#PASSTHRU[@]} > 0)) || return 1
  for arg in "${PASSTHRU[@]}"; do
    [[ "${arg}" == "${flag}" ]] && return 0
  done
  return 1
}

VAE_TILING=0
if passthru_has_flag "--vae-tiling"; then
  VAE_TILING=1
elif [[ "${MLX_TIER_ID}" == "constrained" || "${MLX_TIER_ID}" == "standard" || "${MLX_POLICY_THERMAL_CLASS:-}" == "fanless" ]]; then
  VAE_TILING=1
fi

if (( CUSTOM_OUTPUT )); then
  assert_workspace_safe
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  resolved_output="$(canonical_path "${OUTPUT}")" || die "Cannot resolve output path: ${OUTPUT}"
  path_is_within "${resolved_output}" "${ws}" \
    || die "Output path must be under MLX_WORKSPACE (${ws}): ${OUTPUT}"
  OUTPUT="${resolved_output}"
fi

if (( DUMP_PLAN == 1 )); then
  printf 'family=%s\nmodel=%s\ncli=%s\ntier=%s\nthroughput_class=%s\nthermal_class=%s\nchip_family=%s\nchip_sku=%s\ngpu_cores=%s\nquantize=%s\nsteps=%s\nwidth=%s\nheight=%s\nlow_ram=%s\nvae_tiling=%s\n' \
    "${FAMILY}" "${MODEL}" "${cli_name}" "${MLX_TIER_ID}" \
    "${MLX_POLICY_THROUGHPUT_CLASS:-${MLX_THROUGHPUT_CLASS:-}}" \
    "${MLX_POLICY_THERMAL_CLASS:-${MLX_THERMAL_CLASS:-}}" \
    "${MLX_POLICY_CHIP_FAMILY:-${MLX_CHIP_FAMILY:-}}" \
    "${MLX_POLICY_CHIP_SKU:-${MLX_CHIP_SKU:-}}" \
    "${MLX_POLICY_GPU_CORES:-${MLX_GPU_CORES:-}}" \
    "${QUANTIZE}" "${STEPS}" "${WIDTH}" "${HEIGHT}" "${LOW_RAM}" "${VAE_TILING}"
  exit 0
fi

cli_bin="${MLX_VENV}/bin/${cli_name}"
if [[ ! -x "${cli_bin}" ]]; then
  die "mflux CLI not found (${cli_bin}). Run: make install-image"
fi

if [[ -z "${OUTPUT}" ]]; then
  mkdir -p "${MLX_WORKSPACE}/outputs/images"
  OUTPUT="${MLX_WORKSPACE}/outputs/images/mlx-$(date +%Y%m%d-%H%M%S).png"
else
  mkdir -p "$(dirname "${OUTPUT}")"
fi

if (( MLX_MEM_GIB <= 8 )); then
  log_warn "8 GB: expecting swap. Stop mlx_lm.server and other GPU/memory-heavy apps first."
fi

cmd=("${cli_bin}" --prompt "${PROMPT}" --width "${WIDTH}" --height "${HEIGHT}" --steps "${STEPS}" --quantize "${QUANTIZE}" --output "${OUTPUT}")
if [[ -n "${MODEL}" ]]; then
  cmd+=(--model "${MODEL}")
fi
if [[ -n "${SEED}" ]]; then
  cmd+=(--seed "${SEED}")
fi
if is_truthy "${LOW_RAM}"; then
  cmd+=(--low-ram)
fi
if (( VAE_TILING == 1 )) && ! passthru_has_flag "--vae-tiling"; then
  cmd+=(--vae-tiling)
fi
if ((${#PASSTHRU[@]} > 0)); then
  cmd+=("${PASSTHRU[@]}")
fi

log_header "MLX text-to-image"
log_info "family=${FAMILY} model=${MODEL:-default} ${WIDTH}x${HEIGHT} steps=${STEPS} quantize=${QUANTIZE} low_ram=${LOW_RAM}"
log_info "output=${OUTPUT}"
"${cmd[@]}"
log_ok "Wrote ${OUTPUT}"
