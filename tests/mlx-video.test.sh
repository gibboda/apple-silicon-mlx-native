#!/usr/bin/env bash
# Self-test for opt-in MLX video install/generate wrappers (Linux and macOS).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${ROOT}/scripts/install-mlx-video.sh"
PREPARE="${ROOT}/scripts/prepare-mlx-video-wan.sh"
GENERATE="${ROOT}/scripts/generate-mlx-video.sh"
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

unset MLX_VIDEO_FAMILY MLX_VIDEO_MODEL MLX_VIDEO_MODEL_DIR MLX_VIDEO_MODEL_REPO
unset MLX_VIDEO_WIDTH MLX_VIDEO_HEIGHT MLX_VIDEO_FRAMES MLX_VIDEO_STEPS MLX_VIDEO_TILING MLX_VIDEO_LTX_PIPELINE
unset MLX_VIDEO_SEED MLX_VIDEO_IMAGE MLX_VIDEO_FORCE
unset OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS
export OVERRIDE_MEMORY_TIER=constrained
export OVERRIDE_THERMAL_CLASS=cooled
export MLX_WORKSPACE="${TMP}/ws"
export MLX_VENV="${MLX_WORKSPACE}/.venv"
mkdir -p "${MLX_WORKSPACE}"

expect_ok "install --help" "${INSTALL}" --help
expect_ok "prepare --help" "${PREPARE}" --help
expect_ok "generate --help" "${GENERATE}" --help
expect_fail "install unknown arg" "${INSTALL}" --nope
expect_fail "prepare unknown arg" "${PREPARE}" --nope
expect_fail "generate unknown arg" "${GENERATE}" --nope

help_out="$("${GENERATE}" --help)"
expect_contains "generate help mentions wan21" "wan21" "${help_out}"
expect_contains "generate help mentions ltx2" "ltx2" "${help_out}"
expect_contains "generate help mentions --force" "--force" "${help_out}"
expect_contains "generate help mentions --pipeline" "--pipeline" "${help_out}"
expect_contains "generate help --force names moderate chips" "slow/moderate" "${help_out}"

install_help="$("${INSTALL}" --help)"
expect_contains "install help names moderate chips" "slow/moderate" "${install_help}"

expect_fail "generate without prompt" "${GENERATE}"
expect_fail "install without venv" "${INSTALL}"
expect_fail "prepare without venv" "${PREPARE}"
expect_fail "generate with prompt but no venv" "${GENERATE}" --prompt "a test prompt"

out="$("${GENERATE}" 2>&1 || true)"
expect_contains "missing prompt mentions --prompt" "--prompt" "${out}"

plan_default="$("${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "constrained default family is wan21" "family=wan21" "${plan_default}"
expect_contains "constrained default model is wan21-t2v-1.3b-q4" "model=wan21-t2v-1.3b-q4" "${plan_default}"
expect_contains "constrained default cli is wan generate" "cli=mlx_video.models.wan_2.generate" "${plan_default}"
expect_contains "constrained default tier" "tier=constrained" "${plan_default}"
expect_contains "constrained default width" "width=832" "${plan_default}"
expect_contains "constrained default height" "height=480" "${plan_default}"
expect_contains "constrained default frames" "frames=17" "${plan_default}"
expect_contains "constrained default steps" "steps=10" "${plan_default}"
expect_contains "constrained default tiling" "tiling=auto" "${plan_default}"
expect_contains "constrained wan model_dir uses workspace" "models/video/wan21-t2v-1.3b-q4" "${plan_default}"

plan_ltx="$("${GENERATE}" --dump-plan --prompt "plan" --family ltx2)"
expect_contains "ltx2 family selected" "family=ltx2" "${plan_ltx}"
expect_contains "ltx2 default model is distilled repo" "model=prince-canuma/LTX-2-distilled" "${plan_ltx}"
expect_contains "ltx2 cli is ltx generate" "cli=mlx_video.models.ltx_2.generate" "${plan_ltx}"
expect_contains "ltx2 on constrained keeps 832 width (already 64-aligned)" "width=832" "${plan_ltx}"
expect_contains "ltx2 on constrained aligns height to 64" "height=448" "${plan_ltx}"
expect_contains "ltx2 on constrained keeps 17 frames (already 8n+1)" "frames=17" "${plan_ltx}"
expect_contains "ltx2 model_repo set" "model_repo=prince-canuma/LTX-2-distilled" "${plan_ltx}"
expect_contains "ltx2 default pipeline is distilled" "pipeline=distilled" "${plan_ltx}"
if [[ "${plan_ltx}" == *"wan21-t2v-1.3b-q4"* ]]; then
  fail "ltx2 plan leaked wan21-t2v-1.3b-q4"
else
  pass "ltx2 plan has no wan21-t2v-1.3b-q4"
fi

plan_high="$(OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "high tier default family is wan21" "family=wan21" "${plan_high}"
expect_contains "high tier frames is 33" "frames=33" "${plan_high}"
expect_contains "high tier width is 832" "width=832" "${plan_high}"

plan_ws="$(OVERRIDE_MEMORY_TIER=workstation OVERRIDE_THERMAL_CLASS=cooled "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "workstation default family is ltx2" "family=ltx2" "${plan_ws}"
expect_contains "workstation default model is distilled" "model=prince-canuma/LTX-2-distilled" "${plan_ws}"
expect_contains "workstation width is 512" "width=512" "${plan_ws}"
expect_contains "workstation frames is 33" "frames=33" "${plan_ws}"
expect_contains "workstation steps is default" "steps=default" "${plan_ws}"
expect_contains "workstation default pipeline is distilled" "pipeline=distilled" "${plan_ws}"

plan_pipeline="$("${GENERATE}" --dump-plan --prompt "plan" --family ltx2 --pipeline full)"
expect_contains "custom ltx pipeline honored" "pipeline=full" "${plan_pipeline}"

expect_ok "dump-plan with --force accepted" \
  "${GENERATE}" --dump-plan --prompt "plan" --force

expect_fail "mismatched --model/--family rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --family ltx2 --model wan21-t2v-1.3b-q4

expect_fail "invalid wan frames rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --family wan21 --frames 16

expect_fail "invalid ltx frames rejected when passed explicitly" \
  "${GENERATE}" --dump-plan --prompt "plan" --family ltx2 --frames 18

expect_fail "custom output outside workspace rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --output /tmp/mlx-video-outside.mp4
out_escape="$("${GENERATE}" --dump-plan --prompt "plan" --output /tmp/mlx-video-outside.mp4 2>&1 || true)"
expect_contains "outside output mentions MLX_WORKSPACE" "MLX_WORKSPACE" "${out_escape}"

expect_fail "output via .. outside workspace rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --output "${MLX_WORKSPACE}/../escape.mp4"

expect_ok "custom output under workspace accepted" \
  "${GENERATE}" --dump-plan --prompt "plan" --output "${MLX_WORKSPACE}/outputs/videos/ok.mp4"

OUTSIDE_IMG="${TMP}/outside-frame.png"
touch "${OUTSIDE_IMG}"
expect_fail "image outside workspace rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --image "${OUTSIDE_IMG}"
out_img_escape="$("${GENERATE}" --dump-plan --prompt "plan" --image "${OUTSIDE_IMG}" 2>&1 || true)"
expect_contains "outside image mentions MLX_WORKSPACE" "MLX_WORKSPACE" "${out_img_escape}"

touch "${MLX_WORKSPACE}/frame.png"
expect_ok "image under workspace accepted" \
  "${GENERATE}" --dump-plan --prompt "plan" --image "${MLX_WORKSPACE}/frame.png"

expect_fail "missing image file rejected" \
  "${GENERATE}" --dump-plan --prompt "plan" --image "${MLX_WORKSPACE}/missing.png"

plan_m1="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=1 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=8 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "M1 16 GB dump-plan chip family" "chip_family=1" "${plan_m1}"
expect_contains "M1 16 GB dump-plan slow" "throughput_class=slow" "${plan_m1}"
expect_contains "M1 16 GB stays wan21" "family=wan21" "${plan_m1}"
expect_contains "M1 16 GB force_required" "force_required=1" "${plan_m1}"
if [[ "${plan_m1}" == *"ltx2"* || "${plan_m1}" == *"LTX"* ]]; then
  fail "M1 16 GB plan advertised LTX"
else
  pass "M1 16 GB plan does not advertise LTX"
fi

plan_m5="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "M5 16 GB dump-plan fast" "throughput_class=fast" "${plan_m5}"
expect_contains "M5 16 GB stays wan21 (RAM too small for LTX)" "family=wan21" "${plan_m5}"
expect_contains "M5 16 GB does not require force" "force_required=0" "${plan_m5}"

plan_m3="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "M3 16 GB dump-plan chip family" "chip_family=3" "${plan_m3}"
expect_contains "M3 16 GB dump-plan moderate" "throughput_class=moderate" "${plan_m3}"
expect_contains "M3 16 GB stays wan21" "family=wan21" "${plan_m3}"
expect_contains "M3 16 GB force_required" "force_required=1" "${plan_m3}"

plan_air="$(OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=fanless OVERRIDE_GPU_CORES=10 \
  "${GENERATE}" --dump-plan --prompt "plan")"
expect_contains "fanless M5 still force_required" "force_required=1" "${plan_air}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: mlx-video self-test passed\n'
