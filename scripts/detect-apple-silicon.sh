#!/usr/bin/env bash
# Detect Apple Silicon hardware and emit human or machine-readable output.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/detect-apple-silicon.sh
#   scripts/detect-apple-silicon.sh --json
#   scripts/detect-apple-silicon.sh --env
#   scripts/detect-apple-silicon.sh --recommend
#   scripts/detect-apple-silicon.sh --list
#   scripts/detect-apple-silicon.sh --list-image
#   scripts/detect-apple-silicon.sh --list-video
#   scripts/detect-apple-silicon.sh --quiet   # exit 0 on Darwin arm64, 1 otherwise
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MODE="human"

usage() {
  cat <<'EOF'
Usage: detect-apple-silicon.sh [--human|--json|--env|--recommend|--list|--list-image|--list-video|--quiet] [-h|--help]

Detect Apple Silicon hardware characteristics for MLX workstation defaults.

  --human       Human-readable summary (default)
  --json        Machine-consumable JSON (physical facts + composed defaults)
  --env         KEY=value lines suitable for eval/sourcing
                (MLX_TIER_ID is policy; MLX_PHYSICAL_TIER_ID is detected RAM)
  --recommend   Print a fresh composed profile only (does not write models.env)
  --list        List catalog text models with fit for this Mac (does not download)
  --list-image  List catalog image models with fit for this Mac (does not download)
  --list-video  List catalog video models with fit for this Mac (does not download)
  --quiet       Exit 0 if Darwin arm64, else exit 1 (no output)
  -h            Show this help

Environment:
  MLX_WORKSPACE            Workspace path used for disk availability (default: repo root)
  OVERRIDE_MEMORY_TIER     Policy-only RAM tier: constrained|standard|high|workstation|large
  OVERRIDE_CHIP_FAMILY     Policy-only chip generation (e.g. 1, 5)
  OVERRIDE_CHIP_SKU        Policy-only sku: base|pro|max|ultra
  OVERRIDE_GPU_CORES       Policy-only GPU core count
  OVERRIDE_THERMAL_CLASS   Policy-only thermal class: fanless|cooled

Unknown override ids fail (they do not silently map to 8 GB / unknown-chip).

Physical detect output stays truthful when overrides are set. After moving a
cloned config/models.env to another Mac, run --recommend and update that file
if the composed default model/context changed (rebuild will not overwrite it).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --human) MODE="human"; shift ;;
    --json)  MODE="json"; shift ;;
    --env)   MODE="env"; shift ;;
    --recommend) MODE="recommend"; shift ;;
    --list-image) MODE="list-image"; shift ;;
    --list-video) MODE="list-video"; shift ;;
    --list) MODE="list"; shift ;;
    --quiet) MODE="quiet"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

if [[ "${MODE}" == "quiet" ]]; then
  if host_is_apple_silicon; then
    exit 0
  fi
  exit 1
fi

assert_apple_silicon

export_detect_env
brew_prefix="$(homebrew_prefix)"
brew_ok="false"
[[ -n "${brew_prefix}" ]] && brew_ok="true"
xcode_ok="false"
check_xcode_clt && xcode_ok="true"

# JSON comes from scripts/lib/detect_json.py. log_warn writes to stderr so a
# chip-policy warning cannot land on stdout ahead of the JSON object.
print_detect_json() {
  local brew_ok="$1" brew_prefix="$2" xcode_ok="$3" detect_py
  export DETECT_ARCH="${MLX_ARCH}"
  export DETECT_CHIP="${MLX_CHIP}"
  export DETECT_CHIP_FAMILY="${MLX_CHIP_FAMILY:-}"
  export DETECT_CHIP_SKU="${MLX_CHIP_SKU:-}"
  export DETECT_GPU_CORES="${MLX_GPU_CORES:-}"
  export DETECT_P_CORES="${MLX_P_CORES:-}"
  export DETECT_E_CORES="${MLX_E_CORES:-}"
  export DETECT_HW_MODEL="${MLX_HW_MODEL:-}"
  export DETECT_THERMAL="${MLX_THERMAL_CLASS:-}"
  export DETECT_BANDWIDTH="${MLX_BANDWIDTH_GBS:-}"
  export DETECT_THROUGHPUT="${MLX_THROUGHPUT_CLASS:-}"
  export DETECT_MEM_BYTES="${MLX_MEM_BYTES}"
  export DETECT_MEM_GIB="${MLX_MEM_GIB}"
  export DETECT_TIER_ID="${MLX_TIER_ID}"
  export DETECT_TIER_LABEL="${MLX_TIER_LABEL}"
  export DETECT_PHYSICAL_TIER_ID="${MLX_PHYSICAL_TIER_ID}"
  export DETECT_PHYSICAL_TIER_LABEL="${MLX_PHYSICAL_TIER_LABEL:-}"
  export DETECT_TIER_HINT="${MLX_TIER_HINT}"
  export DETECT_CORES="${MLX_CPU_CORES}"
  export DETECT_MACOS="${MLX_MACOS_VERSION}"
  export DETECT_DISK="${MLX_DISK_AVAIL_GIB:-0}"
  detect_py="$(detect_python_version)"
  export DETECT_PY="${detect_py}"
  export DETECT_BREW_OK="${brew_ok}"
  export DETECT_BREW_PREFIX="${brew_prefix}"
  export DETECT_XCODE="${xcode_ok}"
  export DETECT_MODEL="${MLX_RECOMMENDED_MODEL}"
  export DETECT_CONTEXT="${MLX_RECOMMENDED_CONTEXT}"
  export DETECT_WORKING_SET="${MLX_WORKING_SET_BYTES:-}"
  export DETECT_GPU_ARCH="${MLX_GPU_ARCH:-}"
  export DETECT_IMAGE_PROFILE="${MLX_RECOMMENDED_IMAGE_PROFILE:-}"
  export DETECT_VIDEO_PROFILE="${MLX_RECOMMENDED_VIDEO_PROFILE:-}"
  export DETECT_VIDEO_FORCE="${MLX_VIDEO_FORCE_REQUIRED:-0}"
  export DETECT_WORKSPACE="${MLX_WORKSPACE}"
  python3 "${SCRIPT_DIR}/lib/detect_json.py" || die "detect JSON emission failed"
}

# Emit JSON before the other modes. The failure mode on CI was a warning on
# stdout (unrecognized virtual brand), not a skipped case arm or here-doc.
if [[ "${MODE}" == "json" ]]; then
  print_detect_json "${brew_ok}" "${brew_prefix}" "${xcode_ok}"
  exit 0
fi

case "${MODE}" in
  human)
    print_hardware_summary
    echo "Homebrew:         ${brew_ok} (${brew_prefix:-not found})"
    echo "Xcode CLT:        ${xcode_ok}"
    ;;
  recommend)
    print_composed_profile
    ;;
  list)
    # Flag parser consumes all args; no positional passthrough to the list renderer.
    # shellcheck disable=SC2119
    print_recommended_model_list
    ;;
  list-image)
    # shellcheck disable=SC2119
    print_recommended_image_list
    ;;
  list-video)
    # shellcheck disable=SC2119
    print_recommended_video_list
    ;;
  env)
    # Quote values so `eval "$(... --env)"` / sourcing is safe with spaces.
    print_detect_env "${brew_ok}" "${brew_prefix}" "${xcode_ok}"
    ;;
  *)
    die "Unhandled detect mode: ${MODE}"
    ;;
esac
