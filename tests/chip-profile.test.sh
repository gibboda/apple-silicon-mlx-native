#!/usr/bin/env bash
# Parser and compose fixtures for chip-aware defaults (Linux CI safe: no sysctl GPU).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_eq() {
  local label="$1"
  local got="$2"
  local want="$3"
  if [[ "${got}" == "${want}" ]]; then
    pass "${label}"
  else
    fail "${label} (got '${got}', want '${want}')"
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

expect_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${label} (expected non-zero exit)"
  else
    pass "${label}"
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

unset OVERRIDE_MEMORY_TIER OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS

# --- Brand parser (longest-match regex, not substring "M1") ---

expect_eq "Apple M1 is family 1 base" "$(parse_apple_chip_brand 'Apple M1')" "1|base"
expect_eq "Apple M1 Pro is pro not base" "$(parse_apple_chip_brand 'Apple M1 Pro')" "1|pro"
expect_eq "Apple M1 Max" "$(parse_apple_chip_brand 'Apple M1 Max')" "1|max"
expect_eq "Apple M1 Ultra" "$(parse_apple_chip_brand 'Apple M1 Ultra')" "1|ultra"
expect_eq "Apple M3 Pro" "$(parse_apple_chip_brand 'Apple M3 Pro')" "3|pro"
expect_eq "Apple M5 is family 5 base" "$(parse_apple_chip_brand 'Apple M5')" "5|base"
expect_eq "Apple M10 is family 10 not 1" "$(parse_apple_chip_brand 'Apple M10')" "10|base"
expect_eq "Apple M10 Pro" "$(parse_apple_chip_brand 'Apple M10 Pro')" "10|pro"
expect_fail "garbage brand does not parse" parse_apple_chip_brand "Intel Core i7"
expect_eq "garbage brand emits empty fields" "$(parse_apple_chip_brand 'not a chip' || true)" "|"
expect_fail "empty brand does not parse" parse_apple_chip_brand ""
expect_fail "Apple Silicon (unknown) does not parse" parse_apple_chip_brand "Apple Silicon (unknown)"

# --- Bandwidth lookup / throughput class (M3 Pro trap vs M2 Pro) ---

expect_eq "M1 base bandwidth ~68" "$(lookup_memory_bandwidth_gbs 1 base)" "68"
expect_eq "M1 base is slow" "$(classify_throughput_class 68)" "slow"
expect_eq "M2 Pro bandwidth ~200" "$(lookup_memory_bandwidth_gbs 2 pro)" "200"
expect_eq "M3 Pro bandwidth ~150 (not generation-ranked above M2 Pro)" "$(lookup_memory_bandwidth_gbs 3 pro)" "150"
expect_eq "M2 Pro faster GB/s than M3 Pro" "$(awk 'BEGIN { print (200 > 150) }')" "1"
expect_eq "M3 Pro is fast bucket" "$(classify_throughput_class 150)" "fast"
expect_eq "M2 Pro is fast bucket" "$(classify_throughput_class 200)" "fast"
expect_eq "M5 base bandwidth ~153" "$(lookup_memory_bandwidth_gbs 5 base)" "153"
expect_eq "M5 base is fast" "$(classify_throughput_class 153)" "fast"
expect_ok "M5 has GPU NAX hint" chip_has_gpu_nax 5
expect_fail "M1 does not have GPU NAX hint" chip_has_gpu_nax 1
expect_eq "M10 unknown bandwidth is empty" "$(lookup_memory_bandwidth_gbs 10 base)" ""
expect_eq "M4 Ultra has no guessed bandwidth row" "$(lookup_memory_bandwidth_gbs 4 ultra)" ""
expect_eq "empty bandwidth is unknown class" "$(classify_throughput_class '')" "unknown"
expect_eq "M3 Max 30-core conservative bin" "$(lookup_memory_bandwidth_gbs 3 max 30)" "300"
expect_eq "M3 Max 40-core bin" "$(lookup_memory_bandwidth_gbs 3 max 40)" "400"
expect_eq "M3 Max unknown gpu uses conservative 300" "$(lookup_memory_bandwidth_gbs 3 max 0)" "300"

# --- Compose: this M1 (constrained + slow + fanless) is the floor ---

m1_model="$(recommended_model_for_profile constrained slow fanless 1)"
m1_ctx="$(recommended_context_for_profile constrained slow fanless)"
m1_img="$(recommended_image_profile_for_profile constrained slow fanless 1)"
m1_vid="$(recommended_video_profile_for_profile constrained slow fanless 1 8)"
expect_eq "M1 8 GB default model is 3B 4-bit" "${m1_model}" "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "M1 8 GB context is 2048" "${m1_ctx}" "2048"
expect_eq "M1 8 GB image is 512 4-bit low-ram" "${m1_img}" "flux2|flux2-klein-4b|4|4|512|512|1"
expect_eq "M1 8 GB video stays wan 17 frames" "${m1_vid}" "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
expect_ok "M1 8 GB video requires --force" video_force_required_for_profile constrained slow fanless

# Same 16 GB RAM: M1 stays 3B; M5 may be 7B–8B 4-bit
expect_eq "M1 16 GB default stays 3B" \
  "$(recommended_model_for_profile standard slow cooled 1)" \
  "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "M5 16 GB default may be 7B 4-bit" \
  "$(recommended_model_for_profile standard fast cooled 5)" \
  "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
expect_eq "M1 16 GB image stays conservative 4-bit" \
  "$(recommended_image_profile_for_profile standard slow cooled 1)" \
  "flux2|flux2-klein-4b|4|4|768|768|1"
expect_eq "M5 16 GB image may use 768 8-bit" \
  "$(recommended_image_profile_for_profile standard fast cooled 5)" \
  "flux2|flux2-klein-4b|8|4|768|768|1"
expect_ok "M1 16 GB video still requires --force" video_force_required_for_profile standard slow cooled
expect_fail "M5 16 GB cooled video does not require --force" video_force_required_for_profile standard fast cooled

# 18 GB SKUs (e.g. M3 Pro) must stay standard; high starts at 24 GB
expect_eq "8 GB is constrained" "$(classify_memory_tier 8 | awk -F'|' '{print $1}')" "constrained"
expect_eq "16 GB is standard" "$(classify_memory_tier 16 | awk -F'|' '{print $1}')" "standard"
expect_eq "18 GB is standard not high" "$(classify_memory_tier 18 | awk -F'|' '{print $1}')" "standard"
expect_eq "23 GB stays standard" "$(classify_memory_tier 23 | awk -F'|' '{print $1}')" "standard"
expect_eq "24 GB is high" "$(classify_memory_tier 24 | awk -F'|' '{print $1}')" "high"
expect_eq "32 GB is high" "$(classify_memory_tier 32 | awk -F'|' '{print $1}')" "high"
expect_eq "18 GB label is 16-18 GB standard" "$(classify_memory_tier 18 | awk -F'|' '{print $2}')" "16–18 GB — standard"

# 18 GB M3 Pro: 7B LLM is fine; image/video stay on the 16 GB conservative profile
expect_eq "18 GB M3 Pro LLM is 7B" \
  "$(recommended_model_for_profile standard fast cooled 3)" \
  "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
expect_eq "18 GB M3 Pro context is 4096" \
  "$(recommended_context_for_profile standard fast cooled)" "4096"
expect_eq "18 GB M3 Pro image stays 768 8-bit not 1024 turbo" \
  "$(recommended_image_profile_for_profile standard fast cooled 3)" \
  "flux2|flux2-klein-4b|8|4|768|768|1"
expect_eq "18 GB M3 Pro video stays 17 frames" \
  "$(recommended_video_profile_for_profile standard fast cooled 3 18)" \
  "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
expect_fail "18 GB M3 Pro video does not require --force" video_force_required_for_profile standard fast cooled

expect_eq "24 GB M3 Pro image is z-image-turbo 1024" \
  "$(recommended_image_profile_for_profile high fast cooled 3)" \
  "z-image-turbo||8|9|1024|1024|0"
expect_eq "24 GB M3 Pro video is 33 frames" \
  "$(recommended_video_profile_for_profile high fast cooled 3 18)" \
  "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|33|10|auto"
expect_fail "24 GB M3 Pro video does not require --force" video_force_required_for_profile high fast cooled

unset OVERRIDE_MEMORY_TIER OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  compose_chip_policy
expect_eq "OVERRIDE 18 GB M3 Pro model is 7B" "${MLX_RECOMMENDED_MODEL}" "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
expect_eq "OVERRIDE 18 GB M3 Pro image is 768 8-bit" "${MLX_RECOMMENDED_IMAGE_PROFILE}" "flux2|flux2-klein-4b|8|4|768|768|1"
expect_eq "OVERRIDE 18 GB M3 Pro video is 17 frames" "${MLX_RECOMMENDED_VIDEO_PROFILE}" "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
expect_eq "OVERRIDE 18 GB M3 Pro no video force" "${MLX_VIDEO_FORCE_REQUIRED}" "0"

OVERRIDE_MEMORY_TIER=high OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  compose_chip_policy
expect_eq "OVERRIDE 24 GB M3 Pro model is 7B" "${MLX_RECOMMENDED_MODEL}" "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
expect_eq "OVERRIDE 24 GB M3 Pro image is z-image-turbo 1024" "${MLX_RECOMMENDED_IMAGE_PROFILE}" "z-image-turbo||8|9|1024|1024|0"
expect_eq "OVERRIDE 24 GB M3 Pro video is 33 frames" "${MLX_RECOMMENDED_VIDEO_PROFILE}" "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|33|10|auto"
expect_eq "OVERRIDE 24 GB M3 Pro no video force" "${MLX_VIDEO_FORCE_REQUIRED}" "0"
unset OVERRIDE_MEMORY_TIER OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS

# 16 GB M2/M3/M4 base (moderate) matches slow/M1 for LLM/image/video force
expect_eq "M3 base bandwidth is moderate bucket" "$(classify_throughput_class "$(lookup_memory_bandwidth_gbs 3 base)")" "moderate"
expect_eq "M3 16 GB default stays 3B" \
  "$(recommended_model_for_profile standard moderate cooled 3)" \
  "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "M3 16 GB context stays 2048" \
  "$(recommended_context_for_profile standard moderate cooled)" "2048"
expect_eq "M3 16 GB image stays conservative 4-bit" \
  "$(recommended_image_profile_for_profile standard moderate cooled 3)" \
  "flux2|flux2-klein-4b|4|4|768|768|1"
expect_ok "M3 16 GB video still requires --force" video_force_required_for_profile standard moderate cooled
expect_eq "M4 base is moderate" "$(classify_throughput_class "$(lookup_memory_bandwidth_gbs 4 base)")" "moderate"

OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
  compose_chip_policy
expect_eq "OVERRIDE M3 16 GB model is 3B" "${MLX_RECOMMENDED_MODEL}" "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "OVERRIDE M3 16 GB context is 2048" "${MLX_RECOMMENDED_CONTEXT}" "2048"
expect_eq "OVERRIDE M3 16 GB image is 4-bit" "${MLX_RECOMMENDED_IMAGE_PROFILE}" "flux2|flux2-klein-4b|4|4|768|768|1"
expect_eq "OVERRIDE M3 16 GB force video" "${MLX_VIDEO_FORCE_REQUIRED}" "1"

# Fanless derate: later Airs cannot raise model/image/video/context via throughput_class
expect_eq "fanless 16 GB fast stays 3B" \
  "$(recommended_model_for_profile standard fast fanless 5)" \
  "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "fanless 16 GB fast still 2048 context" \
  "$(recommended_context_for_profile standard fast fanless)" "2048"
expect_eq "fanless 24 GB still conservative image" \
  "$(recommended_image_profile_for_profile high fast fanless 4)" \
  "flux2|flux2-klein-4b|4|4|512|512|1"
expect_ok "fanless video requires --force" video_force_required_for_profile high fast fanless
expect_eq "fanless does not advertise LTX" \
  "$(recommended_video_profile_for_profile workstation very_fast fanless 4 20)" \
  "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"

# RAM fence: 8 GB never gets 7B even on a fast chip
expect_eq "fast constrained still 3B (RAM wins)" \
  "$(recommended_model_for_profile constrained fast cooled 5)" \
  "mlx-community/Llama-3.2-3B-Instruct-4bit"

# Max 32 GB / Ultra large
expect_eq "fast high (not Max) stays 7B" \
  "$(recommended_model_for_profile high fast cooled 3)" \
  "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
expect_eq "fast high context stays 4096" \
  "$(recommended_context_for_profile high fast cooled)" "4096"
expect_eq "very_fast high is 14B" \
  "$(recommended_model_for_profile high very_fast cooled 4)" \
  "mlx-community/Qwen2.5-14B-Instruct-4bit"
expect_eq "extreme large keeps 32B" \
  "$(recommended_model_for_profile large extreme cooled 1)" \
  "mlx-community/Qwen2.5-32B-Instruct-4bit"

# Unknown chip: RAM-only, no crash
expect_eq "unknown chip uses RAM-only high default" \
  "$(recommended_model_for_profile high unknown cooled 7)" \
  "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
expect_eq "unknown chip uses RAM-only standard image" \
  "$(recommended_image_profile_for_profile standard unknown cooled 7)" \
  "flux2|flux2-klein-4b|4|4|768|768|1"
expect_eq "unknown chip uses RAM-only standard context" \
  "$(recommended_context_for_profile standard unknown cooled)" "2048"
expect_eq "unknown chip uses RAM-only workstation LTX" \
  "$(recommended_video_profile_for_profile workstation unknown cooled 7 0)" \
  "ltx2|${MLX_VIDEO_LTX_REPO}|512|512|33||auto"

# Policy compose via OVERRIDE_* (no sysctl)
unset MLX_CHIP_FAMILY MLX_CHIP_SKU MLX_GPU_CORES MLX_THERMAL_CLASS MLX_THROUGHPUT_CLASS MLX_BANDWIDTH_GBS
unset MLX_RECOMMENDED_MODEL MLX_PHYSICAL_TIER_ID
MLX_PHYSICAL_TIER_ID="constrained"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=1 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=8 \
  compose_chip_policy
expect_eq "OVERRIDE M1 16 GB model is 3B" "${MLX_RECOMMENDED_MODEL}" "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "OVERRIDE M1 16 GB context is 2048" "${MLX_RECOMMENDED_CONTEXT}" "2048"
expect_eq "OVERRIDE M1 16 GB force video" "${MLX_VIDEO_FORCE_REQUIRED}" "1"
env_out="$(print_detect_env false "" false)"
expect_eq "print_detect_env policy MLX_TIER_ID is standard" \
  "$(printf '%s\n' "${env_out}" | awk -F= '/^MLX_TIER_ID=/{print $2; exit}')" "standard"
expect_eq "print_detect_env physical MLX_PHYSICAL_TIER_ID stays constrained" \
  "$(printf '%s\n' "${env_out}" | awk -F= '/^MLX_PHYSICAL_TIER_ID=/{print $2; exit}')" "constrained"
expect_contains "print_detect_env includes image profile key" "MLX_RECOMMENDED_IMAGE_PROFILE=" "${env_out}"
expect_contains "print_detect_env includes video profile key" "MLX_RECOMMENDED_VIDEO_PROFILE=" "${env_out}"
expect_contains "print_detect_env includes video force key" "MLX_VIDEO_FORCE_REQUIRED=" "${env_out}"
expect_contains "print_detect_env raw image profile value" "flux2-klein-4b" "${env_out}"
expect_contains "print_detect_env raw video profile value" "${MLX_VIDEO_WAN_MODEL_NAME}" "${env_out}"
expect_contains "print_detect_env raw video force token" "MLX_VIDEO_FORCE_REQUIRED=1" "${env_out}"
eval "$(print_detect_env false "" false)"
expect_eq "print_detect_env exports image profile" \
  "${MLX_RECOMMENDED_IMAGE_PROFILE}" "flux2|flux2-klein-4b|4|4|768|768|1"
expect_eq "print_detect_env exports video profile" \
  "${MLX_RECOMMENDED_VIDEO_PROFILE}" "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
expect_eq "print_detect_env exports video force" "${MLX_VIDEO_FORCE_REQUIRED}" "1"

# Linux / no-sysctl fallback must keep physical label stable when OVERRIDE rewrites policy.
unset OVERRIDE_MEMORY_TIER OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS
unset MLX_CHIP_FAMILY MLX_CHIP_SKU MLX_GPU_CORES MLX_THERMAL_CLASS MLX_THROUGHPUT_CLASS MLX_BANDWIDTH_GBS
OVERRIDE_MEMORY_TIER=high
load_runtime_profile_without_sysctl
expect_eq "Linux fallback physical id stays constrained under OVERRIDE" "${MLX_PHYSICAL_TIER_ID}" "constrained"
expect_eq "Linux fallback physical label stays 8 GB" "${MLX_PHYSICAL_TIER_LABEL}" "8 GB — constrained"
expect_eq "Linux fallback policy tier honors OVERRIDE high" "${MLX_TIER_ID}" "high"
expect_eq "Linux fallback policy label is 24-32 GB high" "${MLX_TIER_LABEL}" "24–32 GB — high"
eval "$(print_detect_env false "" false)"
expect_eq "sourced fallback env physical id stays constrained" "${MLX_PHYSICAL_TIER_ID}" "constrained"
expect_eq "sourced fallback env physical label stays 8 GB" "${MLX_PHYSICAL_TIER_LABEL}" "8 GB — constrained"
expect_eq "sourced fallback env policy id is high" "${MLX_TIER_ID}" "high"
expect_eq "sourced fallback env policy label is 24-32 GB high" "${MLX_TIER_LABEL}" "24–32 GB — high"
unset OVERRIDE_MEMORY_TIER

# Unknown OVERRIDE_* must die instead of mapping to 8 GB / unknown-chip.
unknown_tier_out=""
if unknown_tier_out="$(OVERRIDE_MEMORY_TIER=hgih compose_chip_policy 2>&1)"; then
  fail "unknown OVERRIDE_MEMORY_TIER dies"
else
  pass "unknown OVERRIDE_MEMORY_TIER dies"
fi
expect_contains "unknown OVERRIDE_MEMORY_TIER names the id" "hgih" "${unknown_tier_out}"
expect_contains "unknown OVERRIDE_MEMORY_TIER lists valid ids" "constrained|standard|high|workstation|large" "${unknown_tier_out}"

unknown_sku_out=""
if unknown_sku_out="$(OVERRIDE_CHIP_SKU=proo compose_chip_policy 2>&1)"; then
  fail "unknown OVERRIDE_CHIP_SKU dies"
else
  pass "unknown OVERRIDE_CHIP_SKU dies"
fi
expect_contains "unknown OVERRIDE_CHIP_SKU names the id" "proo" "${unknown_sku_out}"

unknown_thermal_out=""
if unknown_thermal_out="$(OVERRIDE_THERMAL_CLASS=hot compose_chip_policy 2>&1)"; then
  fail "unknown OVERRIDE_THERMAL_CLASS dies"
else
  pass "unknown OVERRIDE_THERMAL_CLASS dies"
fi
expect_contains "unknown OVERRIDE_THERMAL_CLASS names the id" "hot" "${unknown_thermal_out}"

unknown_family_out=""
if unknown_family_out="$(OVERRIDE_CHIP_FAMILY=M3 compose_chip_policy 2>&1)"; then
  fail "non-numeric OVERRIDE_CHIP_FAMILY dies"
else
  pass "non-numeric OVERRIDE_CHIP_FAMILY dies"
fi
expect_contains "non-numeric OVERRIDE_CHIP_FAMILY names the id" "M3" "${unknown_family_out}"

OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
  compose_chip_policy
expect_eq "OVERRIDE M5 16 GB model is 7B" "${MLX_RECOMMENDED_MODEL}" "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
expect_eq "OVERRIDE M5 16 GB context is 4096" "${MLX_RECOMMENDED_CONTEXT}" "4096"
expect_eq "OVERRIDE M5 16 GB no video force" "${MLX_VIDEO_FORCE_REQUIRED}" "0"

unset OVERRIDE_MEMORY_TIER OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS
MLX_CHIP_FAMILY=""
MLX_CHIP_SKU=""
MLX_GPU_CORES=""
MLX_THERMAL_CLASS=""
MLX_PHYSICAL_TIER_ID="standard"
compose_chip_policy
expect_eq "unknown chip policy stays RAM-only 3B on standard" "${MLX_RECOMMENDED_MODEL}" "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "unknown chip policy stays RAM-only 2048 context on standard" "${MLX_RECOMMENDED_CONTEXT}" "2048"
expect_eq "unknown chip policy stays RAM-only 4-bit image on standard" "${MLX_RECOMMENDED_IMAGE_PROFILE}" "flux2|flux2-klein-4b|4|4|768|768|1"

# --- seed_models_env_if_missing: create once, preserve on rebuild path ---

SEED_TMP="$(mktemp -d)"
trap 'rm -rf "${SEED_TMP}"' EXIT
SEED_WS="${SEED_TMP}/ws"
SEED_CFG="${SEED_WS}/config"
SEED_ENV="${SEED_CFG}/models.env"
export MLX_WORKSPACE="${SEED_WS}"
export MLX_CONFIG_DIR="${SEED_CFG}"
export MLX_MODELS_ENV="${SEED_ENV}"
export MLX_MODELS_EXAMPLE="${ROOT}/config/models.example.env"
mkdir -p "${SEED_CFG}"
unset OVERRIDE_MEMORY_TIER OVERRIDE_CHIP_FAMILY OVERRIDE_CHIP_SKU OVERRIDE_GPU_CORES OVERRIDE_THERMAL_CLASS
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
  compose_chip_policy

seed_log="$(seed_models_env_if_missing 2>&1)"
expect_ok "seed creates models.env on first call" test -f "${SEED_ENV}"
expect_contains "seed first call logs created" "Created ${SEED_ENV}" "${seed_log}"
expect_contains "seed first call uses composed model" "MLX_DEFAULT_MODEL=${MLX_RECOMMENDED_MODEL}" "$(cat "${SEED_ENV}")"
expect_contains "seed first call uses composed context" "MLX_RECOMMENDED_CONTEXT=${MLX_RECOMMENDED_CONTEXT}" "$(cat "${SEED_ENV}")"

SAVED_MODEL="${MLX_RECOMMENDED_MODEL}"
SAVED_CONTEXT="${MLX_RECOMMENDED_CONTEXT}"
unset MLX_DEFAULT_MODEL MLX_RECOMMENDED_CONTEXT
load_models_env "${SEED_ENV}"
expect_eq "seed load round-trips model" "${MLX_DEFAULT_MODEL}" "${SAVED_MODEL}"
expect_eq "seed load round-trips context" "${MLX_RECOMMENDED_CONTEXT}" "${SAVED_CONTEXT}"

SEED_FIRST="$(cat "${SEED_ENV}")"
MLX_RECOMMENDED_MODEL="mlx-community/SHOULD-NOT-OVERWRITE"
MLX_RECOMMENDED_CONTEXT=99999
preserve_log="$(seed_models_env_if_missing 2>&1)"
expect_eq "seed second call preserves file content" "$(cat "${SEED_ENV}")" "${SEED_FIRST}"
expect_contains "seed second call logs preserve" "Preserving existing ${SEED_ENV}" "${preserve_log}"

rebuild_log="$(seed_models_env_if_missing 2>&1)"
expect_eq "seed rebuild path still preserves file" "$(cat "${SEED_ENV}")" "${SEED_FIRST}"
expect_contains "seed rebuild path logs preserve" "Preserving existing ${SEED_ENV}" "${rebuild_log}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: chip-profile self-test passed\n'
