#!/usr/bin/env bash
# Detect Apple Silicon hardware and emit human or machine-readable output.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/detect-apple-silicon.sh
#   scripts/detect-apple-silicon.sh --json
#   scripts/detect-apple-silicon.sh --env
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
Usage: detect-apple-silicon.sh [--human|--json|--env|--quiet] [-h|--help]

Detect Apple Silicon hardware characteristics for MLX workstation defaults.

  --human   Human-readable summary (default)
  --json    Machine-consumable JSON
  --env     KEY=value lines suitable for eval/sourcing
  --quiet   Exit 0 if arm64 Apple Silicon, else exit 1 (no output)
  -h        Show this help

Environment:
  MLX_WORKSPACE   Workspace path used for disk availability (default: repo root)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --human) MODE="human"; shift ;;
    --json)  MODE="json"; shift ;;
    --env)   MODE="env"; shift ;;
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

chip="$(detect_chip)"
mem_bytes="$(detect_memory_bytes)"
mem_gib="$(bytes_to_gib "${mem_bytes}")"
cores="$(detect_cpu_cores)"
macos="$(detect_macos_version)"
disk="$(detect_disk_available_gib "${MLX_WORKSPACE}")"
py="$(detect_python_version)"
brew_prefix="$(homebrew_prefix)"
brew_ok="false"
[[ -n "${brew_prefix}" ]] && brew_ok="true"
xcode_ok="false"
check_xcode_clt && xcode_ok="true"
tier_line="$(classify_memory_tier "${mem_gib}")"
IFS='|' read -r tier_id tier_label tier_hint <<<"${tier_line}"
model="$(recommended_model_for_tier "${tier_id}")"

case "${MODE}" in
  human)
    print_hardware_summary
    echo "Homebrew:         ${brew_ok} (${brew_prefix:-not found})"
    echo "Xcode CLT:        ${xcode_ok}"
    echo "Default model:    ${model}"
    ;;
  json)
    DETECT_ARCH="${arch}" \
    DETECT_CHIP="${chip}" \
    DETECT_MEM_BYTES="${mem_bytes}" \
    DETECT_MEM_GIB="${mem_gib}" \
    DETECT_TIER_ID="${tier_id}" \
    DETECT_TIER_LABEL="${tier_label}" \
    DETECT_TIER_HINT="${tier_hint}" \
    DETECT_CORES="${cores}" \
    DETECT_MACOS="${macos}" \
    DETECT_DISK="${disk:-0}" \
    DETECT_PY="${py}" \
    DETECT_BREW_OK="${brew_ok}" \
    DETECT_BREW_PREFIX="${brew_prefix}" \
    DETECT_XCODE="${xcode_ok}" \
    DETECT_MODEL="${model}" \
    DETECT_WORKSPACE="${MLX_WORKSPACE}" \
    python3 - <<'PY'
import json, os
print(json.dumps({
  "architecture": os.environ["DETECT_ARCH"],
  "apple_chip": os.environ["DETECT_CHIP"],
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
  "workspace": os.environ["DETECT_WORKSPACE"],
}, indent=2))
PY
    ;;
  env)
    # Quote values so `eval "$(... --env)"` / sourcing is safe with spaces.
    printf 'MLX_ARCH=%q\n' "${arch}"
    printf 'MLX_CHIP=%q\n' "${chip}"
    printf 'MLX_MEM_BYTES=%q\n' "${mem_bytes}"
    printf 'MLX_MEM_GIB=%q\n' "${mem_gib}"
    printf 'MLX_TIER_ID=%q\n' "${tier_id}"
    printf 'MLX_TIER_LABEL=%q\n' "${tier_label}"
    printf 'MLX_TIER_HINT=%q\n' "${tier_hint}"
    printf 'MLX_CPU_CORES=%q\n' "${cores}"
    printf 'MLX_MACOS_VERSION=%q\n' "${macos}"
    printf 'MLX_DISK_AVAIL_GIB=%q\n' "${disk:-0}"
    printf 'MLX_PYTHON_VERSION_DETECTED=%q\n' "${py}"
    printf 'MLX_HOMEBREW=%q\n' "${brew_ok}"
    printf 'MLX_HOMEBREW_PREFIX=%q\n' "${brew_prefix}"
    printf 'MLX_XCODE_CLT=%q\n' "${xcode_ok}"
    printf 'MLX_RECOMMENDED_MODEL=%q\n' "${model}"
    printf 'MLX_WORKSPACE=%q\n' "${MLX_WORKSPACE}"
    ;;
esac
