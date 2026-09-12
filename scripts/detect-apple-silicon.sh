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
#   scripts/detect-apple-silicon.sh --quiet   # exit 0 on Apple Silicon, 1 otherwise
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MODE="human"

usage() {
  cat <<'EOF'
Usage: detect-apple-silicon.sh [--human|--json|--env|--recommend|--quiet] [-h|--help]

Detect Apple Silicon hardware characteristics for MLX workstation defaults.

  --human       Human-readable summary (default)
  --json        Machine-consumable JSON (physical facts + composed defaults)
  --env         KEY=value lines suitable for eval/sourcing
  --recommend   Print a fresh composed profile only (does not write models.env)
  --quiet       Exit 0 if arm64 Apple Silicon, else exit 1 (no output)
  -h            Show this help

Environment:
  MLX_WORKSPACE            Workspace path used for disk availability (default: repo root)
  OVERRIDE_MEMORY_TIER     Policy-only RAM tier (facts still report physical RAM)
  OVERRIDE_CHIP_FAMILY     Policy-only chip generation (e.g. 1, 5)
  OVERRIDE_CHIP_SKU        Policy-only sku: base|pro|max|ultra
  OVERRIDE_GPU_CORES       Policy-only GPU core count
  OVERRIDE_THERMAL_CLASS   Policy-only thermal class: fanless|cooled

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
    --quiet) MODE="quiet"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

arch="$(detect_architecture)"
if [[ "${arch}" != "arm64" ]]; then
  if [[ "${MODE}" == "quiet" ]]; then
    exit 1
  fi
  die "Apple Silicon (arm64) required. Detected architecture: ${arch}."
fi

if [[ "${MODE}" == "quiet" ]]; then
  exit 0
fi

export_detect_env
brew_prefix="$(homebrew_prefix)"
brew_ok="false"
[[ -n "${brew_prefix}" ]] && brew_ok="true"
xcode_ok="false"
check_xcode_clt && xcode_ok="true"

case "${MODE}" in
  human)
    print_hardware_summary
    echo "Homebrew:         ${brew_ok} (${brew_prefix:-not found})"
    echo "Xcode CLT:        ${xcode_ok}"
    ;;
  recommend)
    print_composed_profile
    ;;
  json)
    DETECT_ARCH="${MLX_ARCH}" \
    DETECT_CHIP="${MLX_CHIP}" \
    DETECT_CHIP_FAMILY="${MLX_CHIP_FAMILY:-}" \
    DETECT_CHIP_SKU="${MLX_CHIP_SKU:-}" \
    DETECT_GPU_CORES="${MLX_GPU_CORES:-}" \
    DETECT_P_CORES="${MLX_P_CORES:-}" \
    DETECT_E_CORES="${MLX_E_CORES:-}" \
    DETECT_HW_MODEL="${MLX_HW_MODEL:-}" \
    DETECT_THERMAL="${MLX_THERMAL_CLASS:-}" \
    DETECT_BANDWIDTH="${MLX_BANDWIDTH_GBS:-}" \
    DETECT_THROUGHPUT="${MLX_THROUGHPUT_CLASS:-}" \
    DETECT_MEM_BYTES="${MLX_MEM_BYTES}" \
    DETECT_MEM_GIB="${MLX_MEM_GIB}" \
    DETECT_TIER_ID="${MLX_PHYSICAL_TIER_ID}" \
    DETECT_TIER_LABEL="${MLX_PHYSICAL_TIER_LABEL:-${MLX_TIER_LABEL}}" \
    DETECT_TIER_HINT="${MLX_TIER_HINT}" \
    DETECT_CORES="${MLX_CPU_CORES}" \
    DETECT_MACOS="${MLX_MACOS_VERSION}" \
    DETECT_DISK="${MLX_DISK_AVAIL_GIB:-0}" \
    DETECT_PY="$(detect_python_version)" \
    DETECT_BREW_OK="${brew_ok}" \
    DETECT_BREW_PREFIX="${brew_prefix}" \
    DETECT_XCODE="${xcode_ok}" \
    DETECT_MODEL="${MLX_RECOMMENDED_MODEL}" \
    DETECT_CONTEXT="${MLX_RECOMMENDED_CONTEXT}" \
    DETECT_WORKING_SET="${MLX_WORKING_SET_BYTES:-}" \
    DETECT_GPU_ARCH="${MLX_GPU_ARCH:-}" \
    DETECT_IMAGE_PROFILE="${MLX_RECOMMENDED_IMAGE_PROFILE}" \
    DETECT_VIDEO_PROFILE="${MLX_RECOMMENDED_VIDEO_PROFILE}" \
    DETECT_VIDEO_FORCE="${MLX_VIDEO_FORCE_REQUIRED:-0}" \
    DETECT_WORKSPACE="${MLX_WORKSPACE}" \
    python3 - <<'PY'
import json, os

def maybe_int(key):
    v = os.environ.get(key, "")
    if v == "":
        return None
    try:
        return int(v)
    except ValueError:
        return None

def maybe_str(key):
    v = os.environ.get(key, "")
    return v if v != "" else None

payload = {
  "architecture": os.environ["DETECT_ARCH"],
  "apple_chip": os.environ["DETECT_CHIP"],
  "chip_family": maybe_int("DETECT_CHIP_FAMILY"),
  "chip_sku": maybe_str("DETECT_CHIP_SKU"),
  "gpu_cores": maybe_int("DETECT_GPU_CORES"),
  "p_cores": maybe_int("DETECT_P_CORES"),
  "e_cores": maybe_int("DETECT_E_CORES"),
  "hw_model": maybe_str("DETECT_HW_MODEL"),
  "thermal_class": maybe_str("DETECT_THERMAL"),
  "bandwidth_gbs": maybe_int("DETECT_BANDWIDTH"),
  "throughput_class": maybe_str("DETECT_THROUGHPUT"),
  "memory_bytes": int(os.environ["DETECT_MEM_BYTES"]),
  "memory_gib": int(os.environ["DETECT_MEM_GIB"]),
  "memory_tier_id": os.environ["DETECT_TIER_ID"],
  "memory_tier_label": os.environ["DETECT_TIER_LABEL"],
  "memory_tier_hint": os.environ["DETECT_TIER_HINT"],
  "cpu_cores": int(os.environ["DETECT_CORES"]),
  "macos_version": os.environ["DETECT_MACOS"],
  "disk_available_gib": int(float(os.environ["DETECT_DISK"] or 0)),
  "python_version": os.environ["DETECT_PY"],
  "homebrew": os.environ["DETECT_BREW_OK"] == "true",
  "homebrew_prefix": os.environ["DETECT_BREW_PREFIX"],
  "xcode_clt": os.environ["DETECT_XCODE"] == "true",
  "recommended_model": os.environ["DETECT_MODEL"],
  "recommended_context": maybe_int("DETECT_CONTEXT"),
  "recommended_image_profile": os.environ.get("DETECT_IMAGE_PROFILE") or None,
  "recommended_video_profile": os.environ.get("DETECT_VIDEO_PROFILE") or None,
  "video_force_required": os.environ.get("DETECT_VIDEO_FORCE", "0") == "1",
  "workspace": os.environ["DETECT_WORKSPACE"],
}
ws = maybe_int("DETECT_WORKING_SET")
if ws is not None:
    payload["working_set_bytes"] = ws
arch = maybe_str("DETECT_GPU_ARCH")
if arch is not None:
    payload["gpu_arch"] = arch
print(json.dumps(payload, indent=2))
PY
    ;;
  env)
    # Quote values so `eval "$(... --env)"` / sourcing is safe with spaces.
    printf 'MLX_ARCH=%q\n' "${MLX_ARCH}"
    printf 'MLX_CHIP=%q\n' "${MLX_CHIP}"
    printf 'MLX_CHIP_FAMILY=%q\n' "${MLX_CHIP_FAMILY:-}"
    printf 'MLX_CHIP_SKU=%q\n' "${MLX_CHIP_SKU:-}"
    printf 'MLX_GPU_CORES=%q\n' "${MLX_GPU_CORES:-}"
    printf 'MLX_P_CORES=%q\n' "${MLX_P_CORES:-}"
    printf 'MLX_E_CORES=%q\n' "${MLX_E_CORES:-}"
    printf 'MLX_HW_MODEL=%q\n' "${MLX_HW_MODEL:-}"
    printf 'MLX_THERMAL_CLASS=%q\n' "${MLX_THERMAL_CLASS:-}"
    printf 'MLX_BANDWIDTH_GBS=%q\n' "${MLX_BANDWIDTH_GBS:-}"
    printf 'MLX_THROUGHPUT_CLASS=%q\n' "${MLX_THROUGHPUT_CLASS:-}"
    printf 'MLX_MEM_BYTES=%q\n' "${MLX_MEM_BYTES}"
    printf 'MLX_MEM_GIB=%q\n' "${MLX_MEM_GIB}"
    printf 'MLX_TIER_ID=%q\n' "${MLX_PHYSICAL_TIER_ID}"
    printf 'MLX_TIER_LABEL=%q\n' "${MLX_PHYSICAL_TIER_LABEL:-${MLX_TIER_LABEL}}"
    printf 'MLX_TIER_HINT=%q\n' "${MLX_TIER_HINT}"
    printf 'MLX_CPU_CORES=%q\n' "${MLX_CPU_CORES}"
    printf 'MLX_MACOS_VERSION=%q\n' "${MLX_MACOS_VERSION}"
    printf 'MLX_DISK_AVAIL_GIB=%q\n' "${MLX_DISK_AVAIL_GIB:-0}"
    printf 'MLX_PYTHON_VERSION_DETECTED=%q\n' "$(detect_python_version)"
    printf 'MLX_HOMEBREW=%q\n' "${brew_ok}"
    printf 'MLX_HOMEBREW_PREFIX=%q\n' "${brew_prefix}"
    printf 'MLX_XCODE_CLT=%q\n' "${xcode_ok}"
    printf 'MLX_RECOMMENDED_MODEL=%q\n' "${MLX_RECOMMENDED_MODEL}"
    printf 'MLX_RECOMMENDED_CONTEXT=%q\n' "${MLX_RECOMMENDED_CONTEXT}"
    printf 'MLX_WORKING_SET_BYTES=%q\n' "${MLX_WORKING_SET_BYTES:-}"
    printf 'MLX_GPU_ARCH=%q\n' "${MLX_GPU_ARCH:-}"
    printf 'MLX_WORKSPACE=%q\n' "${MLX_WORKSPACE}"
    ;;
esac
