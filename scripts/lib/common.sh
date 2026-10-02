#!/usr/bin/env bash
# Shared helpers for apple-silicon-mlx-native scripts.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
# shellcheck disable=SC2034

set -euo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_LIB_DIR}/../.." && pwd)"

# Default workspace is the repository root (overridable).
MLX_WORKSPACE="${MLX_WORKSPACE:-${REPO_ROOT}}"
MLX_VENV="${MLX_VENV:-${MLX_WORKSPACE}/.venv}"
MLX_PYTHON_VERSION="${MLX_PYTHON_VERSION:-3.12}"
MLX_CONFIG_DIR="${MLX_CONFIG_DIR:-${MLX_WORKSPACE}/config}"
MLX_MODELS_ENV="${MLX_MODELS_ENV:-${MLX_CONFIG_DIR}/models.env}"
MLX_MODELS_EXAMPLE="${REPO_ROOT}/config/models.example.env"

# Deliberately selected Python packages (Pure MLX core + selected media).
# Image/video packages are NOT installed by default — see docs/media.md.
# Core and mlx-audio are pinned so two installs on different days match.
# Override a spec to track upstream, for example:
#   MLX_PACKAGE=mlx MLX_LM_PACKAGE=mlx-lm MLX_AUDIO_PACKAGE=mlx-audio make rebuild
# Do not add PyTorch/MPS as a generation backend.
MLX_PACKAGE="${MLX_PACKAGE:-mlx==0.32.2}"
MLX_LM_PACKAGE="${MLX_LM_PACKAGE:-mlx-lm==0.31.3}"
MLX_AUDIO_PACKAGE="${MLX_AUDIO_PACKAGE:-mlx-audio==0.5.5}"
MLX_CORE_PACKAGES=("${MLX_PACKAGE}" "${MLX_LM_PACKAGE}")
MLX_MEDIA_PACKAGES=("${MLX_AUDIO_PACKAGE}")
MLX_IMAGE_PACKAGE="${MLX_IMAGE_PACKAGE:-mflux==0.19.1}"
# Pin mlx-video to a git SHA (not published on PyPI). Override with MLX_VIDEO_PACKAGE.
MLX_VIDEO_PACKAGE="${MLX_VIDEO_PACKAGE:-git+https://github.com/Blaizzy/mlx-video.git@87db56a51758fefb748a359b90a5283bb8ba4837}"
# Packaging tools are pinned so bootstrap, rebuild, and media installs match
# across days. Bump these in this file for a security fix, a Python
# requirement change, or an install failure, and record the bump in
# CHANGELOG.md. Override a spec to try newer tooling once, for example
# MLX_PIP_PACKAGE=pip.
MLX_PIP_PACKAGE="${MLX_PIP_PACKAGE:-pip==26.2.1}"
MLX_SETUPTOOLS_PACKAGE="${MLX_SETUPTOOLS_PACKAGE:-setuptools==84.0.0}"
MLX_WHEEL_PACKAGE="${MLX_WHEEL_PACKAGE:-wheel==0.48.0}"
# wheel 0.48.0 depends on packaging>=24.0. Pin the library itself so a fresh
# venv does not float to whatever packaging release is newest that day.
# Named MLX_PACKAGING_LIB_PACKAGE so it is not confused with MLX_PACKAGING_PACKAGES.
MLX_PACKAGING_LIB_PACKAGE="${MLX_PACKAGING_LIB_PACKAGE:-packaging==26.3}"
MLX_PACKAGING_PACKAGES=("${MLX_PIP_PACKAGE}" "${MLX_SETUPTOOLS_PACKAGE}" "${MLX_WHEEL_PACKAGE}" "${MLX_PACKAGING_LIB_PACKAGE}")
# pip 26+ applies this to PEP 517 isolated build envs (venv setuptools/wheel are ignored).
MLX_PIP_BUILD_CONSTRAINT_FILE="${MLX_PIP_BUILD_CONSTRAINT_FILE:-${MLX_WORKSPACE}/.mlx-pip-build-constraint.txt}"
MLX_VIDEO_WAN_SOURCE_REPO="${MLX_VIDEO_WAN_SOURCE_REPO:-Wan-AI/Wan2.1-T2V-1.3B}"
MLX_VIDEO_WAN_MODEL_NAME="${MLX_VIDEO_WAN_MODEL_NAME:-wan21-t2v-1.3b-q4}"
MLX_VIDEO_LTX_REPO="${MLX_VIDEO_LTX_REPO:-prince-canuma/LTX-2-distilled}"
MLX_HOMEBREW_PACKAGES=(python@"${MLX_PYTHON_VERSION}" git ffmpeg)

readonly COLOR_RED=$'\033[0;31m'
readonly COLOR_GREEN=$'\033[0;32m'
readonly COLOR_YELLOW=$'\033[0;33m'
readonly COLOR_BLUE=$'\033[0;34m'
readonly COLOR_BOLD=$'\033[1m'
readonly COLOR_RESET=$'\033[0m'

log_info()  { printf '%s%s%s\n' "${COLOR_BLUE}" "INFO: $*" "${COLOR_RESET}"; }
log_ok()    { printf '%s%s%s\n' "${COLOR_GREEN}" "OK: $*" "${COLOR_RESET}"; }
log_warn()  { printf '%s%s%s\n' "${COLOR_YELLOW}" "WARN: $*" "${COLOR_RESET}"; }
log_error() { printf '%s%s%s\n' "${COLOR_RED}" "ERROR: $*" "${COLOR_RESET}" >&2; }
log_header() {
  printf '\n%s%s%s\n' "${COLOR_BOLD}" "=== $* ===" "${COLOR_RESET}"
}

die() {
  log_error "$*"
  exit 1
}

require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    if [[ -n "${hint}" ]]; then
      die "Required command not found: ${cmd}. ${hint}"
    fi
    die "Required command not found: ${cmd}"
  fi
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Positive decimal integer with no sign and no leading zero: 1, 2, 2048.
require_positive_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    die "${name} must be a positive integer (got '${value}')"
  fi
}

# Finite non-negative decimal: 0, 0.7, 10, .5, 5., 1.
# Signs, exponents, nan, inf, and strings longer than 16 characters are
# rejected so Python cannot turn the value into infinity.
require_nonnegative_number() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^([0-9]+(\.[0-9]*)?|\.[0-9]+)$ ]] || (( ${#value} > 16 )); then
    die "${name} must be a finite non-negative number (got '${value}')"
  fi
}

# Integer TCP port in 1..65535. Leading zeros are rejected.
require_tcp_port() {
  local name="$1"
  local value="$2"
  local port
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]] || (( ${#value} > 5 )); then
    die "${name} must be an integer TCP port from 1 to 65535 (got '${value}')"
  fi
  port=$((10#${value}))
  if (( port < 1 || port > 65535 )); then
    die "${name} must be an integer TCP port from 1 to 65535 (got '${value}')"
  fi
}

bytes_to_gib() {
  # Convert bytes to whole GiB (floor).
  local bytes="$1"
  echo $((bytes / 1024 / 1024 / 1024))
}

classify_memory_tier() {
  # Emit: tier_id|tier_label|default_model_hint
  # high starts at 24 GB so 18 GB SKUs stay on the 16 GB conservative
  # image/video profile (OOM fence). Apple has no 19–23 GB SKUs; the
  # bound is < 24 so the documented 24–32 GB high label stays true.
  local mem_gib="$1"
  if (( mem_gib <= 8 )); then
    echo "constrained|8 GB — constrained|3B–4B 4-bit models, short context"
  elif (( mem_gib < 24 )); then
    echo "standard|16–18 GB — standard|3B–8B 4-bit models"
  elif (( mem_gib <= 32 )); then
    echo "high|24–32 GB — high|7B–14B 4-bit / selected 8-bit"
  elif (( mem_gib <= 64 )); then
    echo "workstation|36–64 GB — workstation|14B–32B 4-bit / larger 8-bit"
  else
    echo "large|>64 GB — large-memory workstation|30B+ quantized / multi-model server"
  fi
}

detect_architecture() {
  local arch
  arch="$(uname -m)"
  echo "${arch}"
}

detect_kernel() {
  uname -s
}

host_is_apple_silicon() {
  [[ "$(detect_kernel)" == "Darwin" && "$(detect_architecture)" == "arm64" ]]
}

assert_apple_silicon() {
  local kernel arch
  kernel="$(detect_kernel)"
  arch="$(detect_architecture)"
  if [[ "${kernel}" != "Darwin" ]]; then
    die "Apple Silicon macOS (Darwin arm64) required. Detected OS: ${kernel} architecture: ${arch}."
  fi
  if [[ "${arch}" != "arm64" ]]; then
    die "Apple Silicon (arm64) required. Detected architecture: ${arch}. Intel/x86_64 Macs are not supported."
  fi
}

detect_chip() {
  # Prefer sysctl brand string; fall back to system_profiler.
  local chip=""
  if chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"; then
    :
  elif chip="$(sysctl -n machdep.cpu.brand 2>/dev/null)"; then
    :
  else
    chip="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip|Processor Name/{print $2; exit}')"
  fi
  if [[ -z "${chip}" ]]; then
    chip="Apple Silicon (unknown)"
  fi
  echo "${chip}"
}

trim_whitespace() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

# Parse machdep.cpu.brand_string. Longest SKU match: Ultra, then Max, then Pro, then base.
# "Apple M1 Pro" → family 1, sku pro (not base). "Apple M10" → family 10 (not 1).
# Emit: family|sku   (empty fields on failure)
parse_apple_chip_brand() {
  local brand
  brand="$(trim_whitespace "${1:-}")"
  if [[ "${brand}" =~ ^Apple\ M([0-9]+)(\ Ultra|\ Max|\ Pro)?$ ]]; then
    printf '%s|' "${BASH_REMATCH[1]}"
    case "${BASH_REMATCH[2]:-}" in
      " Ultra") printf 'ultra\n' ;;
      " Max") printf 'max\n' ;;
      " Pro") printf 'pro\n' ;;
      *) printf 'base\n' ;;
    esac
    return 0
  fi
  printf '|\n'
  return 1
}

# Unified-memory bandwidth (GB/s) from family+SKU. Max variants use gpu_cores when bins differ.
# Empty output = unknown chip (RAM-only policy). Small table, not a per-retail-SKU encyclopedia.
lookup_memory_bandwidth_gbs() {
  local family="${1:-}"
  local sku="${2:-}"
  local gpu_cores="${3:-0}"
  [[ "${gpu_cores}" =~ ^[0-9]+$ ]] || gpu_cores=0
  [[ "${family}" =~ ^[0-9]+$ ]] || { printf '\n'; return 0; }

  case "${family}:${sku}" in
    1:base) echo 68 ;;
    1:pro) echo 200 ;;
    1:max) echo 400 ;;
    1:ultra) echo 800 ;;
    2:base) echo 100 ;;
    2:pro) echo 200 ;;
    2:max) echo 400 ;;
    2:ultra) echo 800 ;;
    3:base) echo 100 ;;
    3:pro) echo 150 ;;
    3:max)
      if (( gpu_cores >= 40 )); then echo 400; else echo 300; fi
      ;;
    3:ultra) echo 800 ;;
    4:base) echo 120 ;;
    4:pro) echo 273 ;;
    4:max)
      if (( gpu_cores >= 40 )); then echo 546; else echo 410; fi
      ;;
    # No 4:ultra row: no published M4 Ultra bandwidth. Empty → unknown → RAM-only.
    5:base) echo 153 ;;
    5:pro) echo 307 ;;
    5:max)
      if (( gpu_cores >= 40 )); then echo 614; else echo 460; fi
      ;;
    5:ultra) echo 1200 ;;
    *) printf '\n' ;;
  esac
}

# Bandwidth buckets — not generation number (M3 Pro ~150 is slower than M2 Pro ~200).
classify_throughput_class() {
  local bw="${1:-}"
  [[ "${bw}" =~ ^[0-9]+$ ]] || { echo "unknown"; return 0; }
  if (( bw < 100 )); then
    echo "slow"
  elif (( bw < 150 )); then
    echo "moderate"
  elif (( bw < 300 )); then
    echo "fast"
  elif (( bw <= 600 )); then
    echo "very_fast"
  else
    echo "extreme"
  fi
}

throughput_rank() {
  case "${1:-unknown}" in
    slow) echo 1 ;;
    moderate) echo 2 ;;
    fast) echo 3 ;;
    very_fast) echo 4 ;;
    extreme) echo 5 ;;
    *) echo 0 ;;
  esac
}

throughput_at_least() {
  local have want
  have="$(throughput_rank "${1:-}")"
  want="$(throughput_rank "${2:-}")"
  (( have >= want ))
}

# M5+ GPU Neural Accelerators help prefill/diffusion, not decode. Metal GPU only (no ANE).
chip_has_gpu_nax() {
  local family="${1:-0}"
  [[ "${family}" =~ ^[0-9]+$ ]] || return 1
  (( family >= 5 ))
}

detect_gpu_core_count() {
  local n=""
  n="$(ioreg -c AGXAccelerator -r -d 1 2>/dev/null | awk -F'= ' '/"gpu-core-count"/{gsub(/[ \t]/,"",$2); print $2; exit}')"
  if [[ "${n}" =~ ^[0-9]+$ ]]; then
    echo "${n}"
  else
    echo ""
  fi
}

detect_p_cores() {
  sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo ""
}

detect_e_cores() {
  sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo ""
}

detect_hw_model() {
  sysctl -n hw.model 2>/dev/null || echo ""
}

classify_thermal_class() {
  local model="${1:-}"
  case "${model}" in
    MacBookAir*) echo "fanless" ;;
    "") echo "" ;;
    *) echo "cooled" ;;
  esac
}

bytes_to_gib_display() {
  local bytes="${1:-}"
  [[ "${bytes}" =~ ^[0-9]+$ ]] || { echo ""; return 0; }
  awk -v b="${bytes}" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 }'
}

# Probe mx.device_info() when mlx is importable. Emit: working_set_bytes|gpu_arch
# Omit (empty fields) when mlx/Metal is unavailable. Do not use mx.metal.device_info.
probe_mlx_device_info() {
  local py="${1:-}"
  if [[ -z "${py}" ]]; then
    if [[ -x "${MLX_VENV}/bin/python" ]]; then
      py="${MLX_VENV}/bin/python"
    elif command -v python3 >/dev/null 2>&1; then
      py="python3"
    else
      echo "|"
      return 0
    fi
  fi
  "${py}" - <<'PY' 2>/dev/null || echo "|"
import sys
try:
    import mlx.core as mx
    info = mx.device_info()
    if not isinstance(info, dict):
        raise TypeError("device_info is not a dict")
    ws = info.get("max_recommended_working_set_size", "")
    arch = info.get("architecture", "")
    ws_s = "" if ws in (None, "") else str(int(ws))
    arch_s = "" if arch in (None, "") else str(arch)
    print("%s|%s" % (ws_s, arch_s))
except Exception:
    print("|")
    sys.exit(0)
PY
}

# 256 MiB cache cap for the constrained (≤8 GB) tier.
# Measured on this 8 GB M1 (applegpu_g13g, working set 5726633984):
# the default MLX cache limit is 8160437862 (95% of 8 GB) and retains a freed
# 512 MiB buffer (536870916 bytes). A working-set/4 cap retains it too.
# 256 MiB releases it (cache falls to 4 bytes) without slowing a 2048² GPU
# matmul or changing greedy Llama 3.2 3B tokens. Cache limit 0 is slower.
# Image/video wrappers do not use this cap; they may need swap past the working set.
MLX_CONSTRAINED_CACHE_LIMIT_BYTES=$((256 * 1024 * 1024))

# stdout: apply|cache_bytes. apply=1 only for physical constrained RAM.
# Callers pass MLX_PHYSICAL_TIER_ID. OVERRIDE_MEMORY_TIER is recommendations only.
inference_limit_plan() {
  local tier="${1:-}"
  if [[ "${tier}" == "constrained" ]]; then
    printf '1|%s\n' "${MLX_CONSTRAINED_CACHE_LIMIT_BYTES}"
  else
    printf '0|\n'
  fi
}

# Export the env mlx_launch.py reads. Defaults to physical RAM, not policy.
# Other physical tiers leave MLX defaults in place.
export_inference_limit_env() {
  local tier="${1:-${MLX_PHYSICAL_TIER_ID:-}}"
  local plan apply cache
  plan="$(inference_limit_plan "${tier}")"
  IFS='|' read -r apply cache <<<"${plan}"
  if [[ "${apply}" == "1" ]]; then
    MLX_APPLY_WORKING_SET_LIMITS=1
    MLX_CACHE_LIMIT_BYTES="${cache}"
    export MLX_APPLY_WORKING_SET_LIMITS MLX_CACHE_LIMIT_BYTES
  else
    unset MLX_APPLY_WORKING_SET_LIMITS MLX_CACHE_LIMIT_BYTES
  fi
}

# True when argv contains FLAG or FLAG=value.
argv_has_flag() {
  local flag="$1"
  shift
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "${flag}" || "${arg}" == "${flag}="* ]]; then
      return 0
    fi
  done
  return 1
}

# Print each value bound to FLAG in argv (--flag VALUE and --flag=VALUE).
argv_flag_values() {
  local flag="$1"
  shift
  local argc=$#
  local i=1
  local arg
  while (( i <= argc )); do
    arg="${!i}"
    if [[ "${arg}" == "${flag}" ]]; then
      (( i++ ))
      if (( i <= argc )); then
        printf '%s\n' "${!i}"
      fi
      (( i++ ))
      continue
    fi
    if [[ "${arg}" == "${flag}="* ]]; then
      printf '%s\n' "${arg#"${flag}="}"
    fi
    (( i++ ))
  done
}

# Probe mx.set_wired_limit / set_memory_limit / set_cache_limit from the Metal working set.
# Limits are process-local: this subprocess cannot enforce them on later CLI processes.
# Used by validate-mlx.sh as an API/working-set check. Constrained never exceeds
# max_recommended_working_set_size and uses MLX_CONSTRAINED_CACHE_LIMIT_BYTES.
# Prints KEY=value lines. No-op when mlx/Metal is missing.
apply_mlx_runtime_limits() {
  local py="${1:-$(venv_python)}"
  local tier="${2:-${MLX_TIER_ID:-}}"
  [[ -x "${py}" ]] || return 0
  MLX_LIMIT_TIER="${tier}" \
    MLX_CONSTRAINED_CACHE_LIMIT_BYTES="${MLX_CONSTRAINED_CACHE_LIMIT_BYTES}" \
    "${py}" - <<'PY' 2>/dev/null || true
import os, sys
try:
    import mlx.core as mx
    info = mx.device_info()
except Exception as exc:
    sys.stderr.write("mlx_runtime=unavailable (%s)\n" % (exc,))
    sys.exit(0)

ws = int(info.get("max_recommended_working_set_size") or 0)
arch = str(info.get("architecture") or "")
memsize = int(info.get("memory_size") or 0)
tier = os.environ.get("MLX_LIMIT_TIER", "")
cache_cap_s = os.environ.get("MLX_CONSTRAINED_CACHE_LIMIT_BYTES", "")
cache_cap = int(cache_cap_s) if cache_cap_s.isdigit() else 0
print("working_set_bytes=%s" % (ws if ws else "",))
print("gpu_arch=%s" % (arch,))
print("memory_size_bytes=%s" % (memsize if memsize else "",))
if ws <= 0:
    sys.exit(0)

wired = ws
if tier == "constrained":
    memory = ws
    cache = cache_cap if cache_cap > 0 else max(ws // 4, 1)
else:
    memory = int(ws * 1.5)
    if memsize > 0:
        cap = int(memsize * 0.95)
        if memory > cap:
            memory = cap
    cache = max(ws // 2, 1)

def _set(name, fn, value):
    try:
        fn(value)
        print("%s=%s" % (name, value))
    except Exception as exc:
        sys.stderr.write("%s_error=%s\n" % (name, exc))
        print("%s=" % (name,))

if hasattr(mx, "set_wired_limit"):
    _set("wired_limit_bytes", mx.set_wired_limit, wired)
else:
    print("wired_limit_bytes=")
if hasattr(mx, "set_memory_limit"):
    _set("memory_limit_bytes", mx.set_memory_limit, memory)
else:
    print("memory_limit_bytes=")
if hasattr(mx, "set_cache_limit"):
    _set("cache_limit_bytes", mx.set_cache_limit, cache)
else:
    print("cache_limit_bytes=")
PY
}

mlx_lm_help_has_flag() {
  local module="$1"
  local flag="$2"
  local py
  py="$(venv_python)"
  [[ -x "${py}" ]] || return 1
  "${py}" -m "${module}" --help 2>&1 | grep -q -- "${flag}"
}

dummy_mem_gib_for_tier() {
  case "${1:-}" in
    constrained) echo 8 ;;
    standard) echo 16 ;;
    high) echo 32 ;;
    workstation) echo 64 ;;
    large) echo 65 ;;
    *) echo 8 ;;
  esac
}

detect_memory_bytes() {
  sysctl -n hw.memsize
}

detect_cpu_cores() {
  sysctl -n hw.ncpu
}

detect_macos_version() {
  sw_vers -productVersion
}

detect_disk_available_gib() {
  # Available space (whole GiB) on the volume containing the path.
  local target="${1:-/}"
  df -g "${target}" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Remember a caller-supplied MLX_DISK_AVAIL_GIB before detection overwrites it.
# Idempotent: a later measurement must not become the override.
note_disk_avail_override() {
  if [[ -n "${MLX_DISK_OVERRIDE_NOTED:-}" ]]; then
    return 0
  fi
  MLX_DISK_OVERRIDE_NOTED=1
  if [[ -n "${MLX_DISK_AVAIL_GIB:-}" ]]; then
    MLX_DISK_AVAIL_GIB_OVERRIDE="${MLX_DISK_AVAIL_GIB}"
  else
    MLX_DISK_AVAIL_GIB_OVERRIDE=""
  fi
}

# df needs an existing directory. Walk up so a not-yet-created cache still
# names the volume that will hold it.
existing_dir_for_df() {
  local path="${1:-/}"
  path="${path%/}"
  [[ -n "${path}" ]] || path="/"
  while [[ ! -d "${path}" ]]; do
    if [[ "${path}" == "/" ]]; then
      break
    fi
    path="$(dirname "${path}")"
  done
  printf '%s\n' "${path}"
}

huggingface_hub_cache_dir() {
  local hf_home="${HF_HOME:-${HOME}/.cache/huggingface}"
  printf '%s\n' "${HF_HUB_CACHE:-${hf_home}/hub}"
}

# Restore a `shopt -p nullglob` snapshot. Empty means nullglob was unset.
_restore_nullglob() {
  local state="${1:-}"
  if [[ -n "${state}" ]]; then
    eval "${state}"
  else
    shopt -u nullglob
  fi
}

# Print shard filenames from a safetensors index. No network.
# Uses a line loop so macOS /bin/bash 3.2 (no mapfile) can read the index.
_index_shard_names() {
  local index="${1:-}"
  [[ -f "${index}" ]] || return 1
  python3 - "${index}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    weight_map = json.load(fh).get("weight_map") or {}
seen = sorted({name for name in weight_map.values() if isinstance(name, str) and name})
for name in seen:
    print(name)
PY
}

# config.json plus every shard named by model.safetensors.index.json in this directory.
_indexed_component_ready() {
  local dir="${1%/}"
  local index="${dir}/model.safetensors.index.json"
  local shard="" saw=0
  [[ -f "${dir}/config.json" && -f "${index}" ]] || return 1
  while IFS= read -r shard; do
    [[ -n "${shard}" ]] || continue
    case "${shard}" in
      /*|*..*) return 1 ;;
    esac
    [[ -f "${dir}/${shard}" ]] || return 1
    saw=1
  done < <(_index_shard_names "${index}")
  (( saw == 1 ))
}

# Return 0 when snap holds config.json and loadable weight files (regular
# files only). Sharded repos must have every shard from weight_map. This
# does not contact the network.
hub_snapshot_weights_complete() {
  local snap="${1%/}/"
  local index="${snap}model.safetensors.index.json"
  local nullglob_state w
  local -a weights
  [[ -f "${snap}config.json" ]] || return 1
  if [[ -f "${index}" ]]; then
    _indexed_component_ready "${snap%/}"
    return
  fi
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  weights=( "${snap}model"*.safetensors )
  _restore_nullglob "${nullglob_state}"
  ((${#weights[@]} == 0)) && return 1
  for w in "${weights[@]}"; do
    [[ -f "${w}" ]] || return 1
  done
  return 0
}

# yes when the hub cache holds a complete MLX snapshot for this repo id.
model_weights_cached() {
  local repo_id="${1:-}"
  local cache folder snap nullglob_state
  [[ -n "${repo_id}" ]] || return 1
  cache="$(huggingface_hub_cache_dir)"
  folder="${cache}/models--${repo_id//\//--}"
  [[ -d "${folder}/snapshots" ]] || return 1
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  for snap in "${folder}/snapshots"/*/; do
    if hub_snapshot_weights_complete "${snap}"; then
      _restore_nullglob "${nullglob_state}"
      return 0
    fi
  done
  _restore_nullglob "${nullglob_state}"
  return 1
}

# True when this hub repo still has an incomplete blob (download in progress).
hub_repo_download_incomplete() {
  local repo_id="${1:-}"
  local cache folder nullglob_state
  local -a incomplete
  [[ -n "${repo_id}" && "${repo_id}" == */* ]] || return 1
  cache="$(huggingface_hub_cache_dir)"
  folder="${cache}/models--${repo_id//\//--}"
  [[ -d "${folder}/blobs" ]] || return 1
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  incomplete=( "${folder}/blobs/"*.incomplete )
  _restore_nullglob "${nullglob_state}"
  ((${#incomplete[@]} > 0))
}

# True when dir holds at least one real safetensors file.
_dir_has_safetensors() {
  local dir="${1%/}"
  local path=""
  [[ -d "${dir}" ]] || return 1
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    [[ -f "${path}" ]] && return 0
  done < <(find "${dir}" -name '*.safetensors' \( -type f -o -type l \) -print 2>/dev/null)
  return 1
}

# prince-canuma/LTX-2-distilled layout that the pinned mlx-video distilled
# pipeline opens: transformer, text encoder, and VAE decoder shards, text
# projections, and a root spatial x2 upscaler. One root ltx-2-*.safetensors
# file is not enough. The distilled pipeline does not open the root LoRA file.
ltx_distilled_snapshot_ready() {
  local snap="${1%/}"
  local upscaler="" nullglob_state saw=0
  local -a upscalers
  _indexed_component_ready "${snap}/transformer" || return 1
  _indexed_component_ready "${snap}/text_encoder" || return 1
  _indexed_component_ready "${snap}/vae/decoder" || return 1
  _dir_has_safetensors "${snap}/text_projections" || return 1
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  upscalers=( "${snap}/"*spatial-upscaler-x2*.safetensors )
  _restore_nullglob "${nullglob_state}"
  for upscaler in "${upscalers[@]}"; do
    if [[ -f "${upscaler}" ]]; then
      saw=1
      break
    fi
  done
  (( saw == 1 ))
}

# True when a snapshot has model_index.json or config.json plus at least one
# real safetensors file. Diffusers trees (mflux presets) keep weights in
# subfolders, so this is broader than model_weights_cached. A snapshot that
# has model.safetensors.index.json must include every indexed shard; one
# leftover file is not enough. Incomplete blobs are rejected by
# media_repo_cached before this runs. No network.
hub_repo_has_weights() {
  local repo_id="${1:-}"
  local cache folder snap nullglob_state path
  [[ -n "${repo_id}" && "${repo_id}" == */* ]] || return 1
  cache="$(huggingface_hub_cache_dir)"
  folder="${cache}/models--${repo_id//\//--}"
  [[ -d "${folder}/snapshots" ]] || return 1
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  for snap in "${folder}/snapshots"/*/; do
    if [[ -f "${snap}transformer/model.safetensors.index.json" ]]; then
      if ltx_distilled_snapshot_ready "${snap}"; then
        _restore_nullglob "${nullglob_state}"
        return 0
      fi
      continue
    fi
    if [[ -f "${snap}model.safetensors.index.json" ]]; then
      if hub_snapshot_weights_complete "${snap}"; then
        _restore_nullglob "${nullglob_state}"
        return 0
      fi
      continue
    fi
    if [[ -f "${snap}model_index.json" || -f "${snap}config.json" ]]; then
      while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        if [[ -f "${path}" ]]; then
          _restore_nullglob "${nullglob_state}"
          return 0
        fi
      done < <(find "${snap}" -name '*.safetensors' \( -type f -o -type l \) -print 2>/dev/null)
    fi
  done
  _restore_nullglob "${nullglob_state}"
  return 1
}

# MLX snapshot (config.json + every indexed weight shard) or a diffusers tree
# with weights. An incomplete blob or a partial shard index is not cached.
# Does not contact the network.
media_repo_cached() {
  local repo_id="${1:-}"
  if hub_repo_download_incomplete "${repo_id}"; then
    return 1
  fi
  if model_weights_cached "${repo_id}"; then
    return 0
  fi
  hub_repo_has_weights "${repo_id}"
}

# mflux downloads a preset name or Hugging Face repo into the hub cache.
# A local checkpoint is an absolute path, a ./ ../ or ~ path, or any path
# that already exists. Those generates write a PNG and do not download weights.
image_model_is_local() {
  local model="${1:-}"
  [[ -n "${model}" ]] || return 1
  case "${model}" in
    /*|./*|../*|~*) return 0 ;;
  esac
  [[ -e "${model}" ]]
}

image_generate_disk_profile() {
  if image_model_is_local "${1:-}"; then
    printf '%s\n' image-generate
  else
    printf '%s\n' image-weights
  fi
}

# Where bytes for this profile actually land.
# Pip wheels go into the workspace venv.
# Image weights and LTX video weights go to the Hugging Face hub cache.
# A local image checkpoint writes the PNG on the workspace and skips the hub.
# Wan generate reads a local model directory and writes the MP4 on the workspace.
# Wan prepare writes the snapshot and converted copy under the workspace and
# may also stage blobs in the hub cache, so both paths are checked.
disk_probe_paths() {
  local profile="${1:-}"
  case "${profile}" in
    media-pip|image-pip|video-pip|image-generate)
      printf '%s\n' "${MLX_WORKSPACE}"
      ;;
    image-weights|video-weights)
      huggingface_hub_cache_dir
      ;;
    wan-generate)
      printf '%s\n' "${MLX_WORKSPACE}"
      if [[ -n "${MLX_WAN_GENERATE_DIR:-}" ]]; then
        printf '%s\n' "${MLX_WAN_GENERATE_DIR}"
      fi
      ;;
    wan-prepare)
      printf '%s\n' "${MLX_WORKSPACE}"
      huggingface_hub_cache_dir
      ;;
    *) return 1 ;;
  esac
}

# Smallest successful df reading for the profile, and the path it came from.
# Prints "avail<TAB>path". Fails when every probe is unreadable.
tightest_disk_for_profile() {
  local profile="${1:-}"
  local path="" probe="" avail="" best_avail="" best_path=""
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    probe="$(existing_dir_for_df "${path}")"
    avail="$(detect_disk_available_gib "${probe}")"
    if [[ ! "${avail}" =~ ^[0-9]+$ ]]; then
      continue
    fi
    if [[ -z "${best_avail}" ]] || (( avail < best_avail )); then
      best_avail="${avail}"
      best_path="${probe}"
    fi
  done < <(disk_probe_paths "${profile}")
  if [[ -z "${best_avail}" ]]; then
    return 1
  fi
  printf '%s\t%s\n' "${best_avail}" "${best_path}"
}

# Conservative free-space floors (whole GiB) before large downloads.
# Override one floor with the matching MLX_DISK_MIN_* variable.
# Profiles: media-pip, image-pip, video-pip, image-weights, image-generate,
# video-weights, wan-generate, wan-prepare.
disk_floor_gib() {
  local profile="${1:-}"
  case "${profile}" in
    media-pip) printf '%s\n' "${MLX_DISK_MIN_MEDIA_GIB:-4}" ;;
    image-pip) printf '%s\n' "${MLX_DISK_MIN_IMAGE_GIB:-8}" ;;
    video-pip) printf '%s\n' "${MLX_DISK_MIN_VIDEO_GIB:-8}" ;;
    image-weights) printf '%s\n' "${MLX_DISK_MIN_IMAGE_WEIGHTS_GIB:-12}" ;;
    image-generate) printf '%s\n' "${MLX_DISK_MIN_IMAGE_GENERATE_GIB:-4}" ;;
    video-weights) printf '%s\n' "${MLX_DISK_MIN_VIDEO_WEIGHTS_GIB:-20}" ;;
    wan-generate) printf '%s\n' "${MLX_DISK_MIN_WAN_GENERATE_GIB:-4}" ;;
    wan-prepare) printf '%s\n' "${MLX_DISK_MIN_WAN_GIB:-40}" ;;
    *) return 1 ;;
  esac
}

# ok | low | unknown. Non-integers are unknown so a bad df reading does not abort.
disk_headroom_status() {
  local avail="${1:-}"
  local required="${2:-}"
  if [[ ! "${avail}" =~ ^[0-9]+$ || ! "${required}" =~ ^[0-9]+$ ]]; then
    printf 'unknown\n'
    return 0
  fi
  if (( avail < required )); then
    printf 'low\n'
  else
    printf 'ok\n'
  fi
}

# Warn when free space is under the profile floor. MLX_DISK_ENFORCE=1 aborts.
# MLX_SKIP_DISK_CHECK=1 skips. Does not delete caches or model weights.
# A MLX_DISK_AVAIL_GIB set before detection wins over df. Otherwise df runs
# on the profile's download path (workspace venv, hub cache, or both).
warn_or_die_disk_headroom() {
  local profile="${1:-}"
  local required="" avail="" where="" status="" msg="" tight=""
  if is_truthy "${MLX_SKIP_DISK_CHECK:-}"; then
    log_info "Disk headroom check skipped (MLX_SKIP_DISK_CHECK)."
    return 0
  fi
  required="$(disk_floor_gib "${profile}")" || die "Unknown disk profile: ${profile}"
  if [[ ! "${required}" =~ ^[0-9]+$ ]]; then
    die "Disk floor for ${profile} must be a non-negative integer GiB (got '${required}')."
  fi
  note_disk_avail_override
  if [[ -n "${MLX_DISK_AVAIL_GIB_OVERRIDE:-}" ]]; then
    avail="${MLX_DISK_AVAIL_GIB_OVERRIDE}"
    where="MLX_DISK_AVAIL_GIB override"
  else
    tight="$(tightest_disk_for_profile "${profile}" || true)"
    avail="${tight%%$'\t'*}"
    where="${tight#*$'\t'}"
    if [[ "${where}" == "${avail}" ]]; then
      where=""
    fi
  fi
  status="$(disk_headroom_status "${avail}" "${required}")"
  case "${status}" in
    ok)
      log_ok "Disk headroom: ${avail} GiB free on ${where} (need >= ${required} GiB before ${profile})."
      ;;
    unknown)
      log_warn "Could not read free space before ${profile} (need >= ${required} GiB). Continuing. Set MLX_DISK_AVAIL_GIB to override."
      ;;
    low)
      if [[ -n "${where}" ]]; then
        msg="Only ${avail} GiB free on ${where}; ${profile} wants at least ${required} GiB. Caches are not deleted automatically."
      else
        msg="Only ${avail} GiB free; ${profile} wants at least ${required} GiB. Caches are not deleted automatically."
      fi
      if is_truthy "${MLX_DISK_ENFORCE:-}"; then
        die "${msg} Unset MLX_DISK_ENFORCE or set MLX_SKIP_DISK_CHECK=1 to proceed."
      fi
      log_warn "${msg} Set MLX_DISK_ENFORCE=1 to abort instead of continuing."
      ;;
  esac
}

detect_python_version() {
  if [[ -x "${MLX_VENV}/bin/python" ]]; then
    "${MLX_VENV}/bin/python" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'
  else
    echo "none"
  fi
}

homebrew_prefix() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    echo "/opt/homebrew"
  elif [[ -x /usr/local/bin/brew ]]; then
    echo "/usr/local"
  elif command -v brew >/dev/null 2>&1; then
    brew --prefix
  else
    echo ""
  fi
}

ensure_homebrew_in_path() {
  local prefix
  prefix="$(homebrew_prefix)"
  if [[ -n "${prefix}" && -x "${prefix}/bin/brew" ]]; then
    export PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
  fi
}

check_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

venv_python() {
  echo "${MLX_VENV}/bin/python"
}

venv_pip() {
  echo "${MLX_VENV}/bin/pip"
}

# Print installed pip/setuptools/wheel versions. Warn when an exact pin does
# not match. Does not fail the caller; install_packaging_tools still fails
# if the install itself fails.
report_packaging_tools() {
  local py="${1:-$(venv_python)}"
  local versions name installed spec pin line
  if [[ ! -x "${py}" ]]; then
    log_warn "Packaging tools not reported; Python not found at ${py}"
    return 0
  fi
  if ! versions="$("${py}" -c 'import importlib.metadata as m
for name in ("pip", "setuptools", "wheel", "packaging"):
    try:
        print(name + " " + m.version(name))
    except m.PackageNotFoundError:
        print(name + " missing")
')"; then
    log_warn "Could not read pip, setuptools, wheel, and packaging versions"
    return 0
  fi
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    name="${line%% *}"
    installed="${line#* }"
    case "${name}" in
      pip) spec="${MLX_PIP_PACKAGE}" ;;
      setuptools) spec="${MLX_SETUPTOOLS_PACKAGE}" ;;
      wheel) spec="${MLX_WHEEL_PACKAGE}" ;;
      packaging) spec="${MLX_PACKAGING_LIB_PACKAGE}" ;;
      *) spec="" ;;
    esac
    # Exact pins only. Wildcard specs (setuptools==84.*) and === are not
    # plain string compares, so they are reported as the configured spec.
    if [[ "${spec}" == *==* && "${spec}" != *===* && "${spec}" != *'*'* ]]; then
      pin="${spec#*==}"
      if [[ "${installed}" == "${pin}" ]]; then
        log_ok "Packaging tool ${name} ${installed}"
      else
        log_warn "Packaging tool ${name} ${installed} (pin ${spec})"
      fi
    elif [[ -n "${spec}" ]]; then
      log_info "Packaging tool ${name} ${installed} (spec ${spec})"
    else
      log_info "Packaging tool ${name} ${installed}"
    fi
  done <<< "${versions}"
}

# Write MLX_PACKAGING_PACKAGES to a constraints file and export PIP_BUILD_CONSTRAINT
# so PEP 517 isolated builds (for example git mlx-video) use the same specs.
export_pip_build_constraint() {
  local pkg
  local constraint_file="${MLX_PIP_BUILD_CONSTRAINT_FILE}"
  : >"${constraint_file}"
  for pkg in "${MLX_PACKAGING_PACKAGES[@]}"; do
    printf '%s\n' "${pkg}" >>"${constraint_file}"
  done
  export PIP_BUILD_CONSTRAINT="${constraint_file}"
}

# Install the shared packaging-tool pins into the active venv.
install_packaging_tools() {
  local py
  py="$(venv_python)"
  if [[ ! -x "${py}" ]]; then
    if [[ -d "${MLX_VENV}" ]]; then
      die "Python venv at ${MLX_VENV} is not usable. Run: make rebuild"
    fi
    die "Python venv not found at ${py}. Run: make venv && make install"
  fi
  log_info "Installing pinned packaging tools: ${MLX_PACKAGING_PACKAGES[*]}"
  # Silence "you should upgrade pip" for this process, including later installs.
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  "${py}" -m pip install --disable-pip-version-check --upgrade "${MLX_PACKAGING_PACKAGES[@]}"
  export_pip_build_constraint
  log_info "PEP 517 build isolation constrained via PIP_BUILD_CONSTRAINT=${MLX_PIP_BUILD_CONSTRAINT_FILE}"
  report_packaging_tools "${py}"
}

activate_venv() {
  # shellcheck source=/dev/null
  source "${MLX_VENV}/bin/activate"
}

# Absolute physical path: resolve . / .. and follow existing directory symlinks.
# Missing final components are appended to the longest existing ancestor.
canonical_path() {
  local path="${1:-}"
  local current next suffix resolved part rest
  [[ -n "${path}" ]] || return 1

  if [[ "${path}" != /* ]]; then
    path="${PWD%/}/${path}"
  fi
  while [[ "${path}" != "/" && "${path}" == */ ]]; do
    path="${path%/}"
  done

  if [[ -d "${path}" ]]; then
    (cd "${path}" && pwd -P)
    return 0
  fi

  if [[ -e "${path}" || -L "${path}" ]]; then
    next="$(cd "$(dirname "${path}")" && pwd -P)" || return 1
    printf '%s/%s\n' "${next}" "$(basename "${path}")"
    return 0
  fi

  suffix=""
  current="${path}"
  while [[ "${current}" != "/" && ! -d "${current}" ]]; do
    next="$(basename "${current}")"
    current="$(dirname "${current}")"
    suffix="/${next}${suffix}"
  done

  if [[ -d "${current}" ]]; then
    resolved="$(cd "${current}" && pwd -P)" || return 1
  else
    resolved="/"
  fi

  rest="${suffix#/}"
  while [[ -n "${rest}" ]]; do
    if [[ "${rest}" == */* ]]; then
      part="${rest%%/*}"
      rest="${rest#*/}"
    else
      part="${rest}"
      rest=""
    fi
    if [[ -z "${part}" || "${part}" == "." ]]; then
      continue
    fi
    if [[ "${part}" == ".." ]]; then
      if [[ "${resolved}" != "/" ]]; then
        resolved="$(dirname "${resolved}")"
      fi
      continue
    fi
    resolved="${resolved%/}/${part}"
    if [[ -d "${resolved}" ]]; then
      resolved="$(cd "${resolved}" && pwd -P)" || return 1
    fi
  done
  printf '%s\n' "${resolved}"
}

# True when inner is outer, or a path under outer (after callers canonicalize).
path_is_within() {
  local inner="${1%/}"
  local outer="${2%/}"
  [[ -n "${inner}" && -n "${outer}" ]] || return 1
  [[ "${inner}" == "${outer}" || "${inner}" == "${outer}/"* ]]
}

assert_workspace_safe() {
  local orig="${MLX_WORKSPACE:-}"
  [[ -n "${orig}" ]] || die "MLX_WORKSPACE is empty"
  [[ -d "${orig}" ]] || die "Expected workspace missing: ${orig}"
  MLX_WORKSPACE="$(canonical_path "${orig}")" || die "Cannot resolve workspace: ${orig}"
  [[ "${MLX_WORKSPACE}" != "/" ]] || die "Refusing to operate on workspace /"
}

assert_venv_under_workspace() {
  local orig="${MLX_VENV:-}"
  local ws venv
  [[ -n "${orig}" ]] || die "MLX_VENV is empty"
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  venv="$(canonical_path "${orig}")" || die "Cannot resolve venv path: ${orig}"
  MLX_VENV="${venv}"
  [[ "${venv}" != "${ws}" ]] || die "Refusing to treat the workspace root as a venv: ${orig}"
  [[ "${venv}" == "${ws}/"* ]] || die "Refusing to remove venv outside workspace: ${orig} (resolves to ${venv})"
}

looks_like_venv() {
  local dir="${1:-${MLX_VENV}}"
  [[ -d "${dir}" ]] || return 1
  [[ -f "${dir}/pyvenv.cfg" || -f "${dir}/bin/python" ]]
}

has_venv_interpreter() {
  local dir="${1:-${MLX_VENV}}"
  [[ -f "${dir}/bin/python" || -f "${dir}/bin/python3" ]]
}

venv_project_python() {
  echo "${1:-${MLX_VENV}}/bin/python"
}

# True when bin/python or bin/python3 is a dangling symlink.
venv_interpreter_symlink_broken() {
  local dir="${1:-${MLX_VENV}}"
  local name py
  for name in python python3; do
    py="${dir}/bin/${name}"
    if [[ -L "${py}" && ! -e "${py}" ]]; then
      return 0
    fi
  done
  return 1
}

pyvenv_cfg_value() {
  local dir="$1"
  local key="$2"
  [[ -f "${dir}/pyvenv.cfg" ]] || return 1
  awk -v k="${key}" -F' = ' '$1 == k { sub(/^ +| +$/, "", $2); print $2; exit }' "${dir}/pyvenv.cfg"
}

venv_python_has_pip() {
  local dir="${1:-${MLX_VENV}}"
  local py
  py="$(venv_project_python "${dir}")"
  [[ -x "${py}" ]] || return 1
  "${py}" -m pip --version >/dev/null 2>&1
}

venv_version_matches_expected() {
  local dir="${1:-${MLX_VENV}}"
  local cfg_ver
  cfg_ver="$(pyvenv_cfg_value "${dir}" version)" || return 1
  [[ -n "${cfg_ver}" ]] || return 1
  [[ "${cfg_ver}" == "${MLX_PYTHON_VERSION}"* ]]
}

venv_home_under_homebrew() {
  local dir="${1:-${MLX_VENV}}"
  local prefix cfg_home
  prefix="$(homebrew_prefix)"
  [[ -n "${prefix}" ]] || return 1
  cfg_home="$(pyvenv_cfg_value "${dir}" home)" || return 1
  [[ -n "${cfg_home}" ]] || return 1
  [[ "${cfg_home}" == "${prefix}"* ]]
}

# make venv reuse: Homebrew python@MLX_PYTHON_VERSION with a working pip.
assert_reusable_brew_venv_for_make_venv() {
  local dir="${1:-${MLX_VENV}}"
  local cfg_ver cfg_home prefix
  if venv_interpreter_symlink_broken "${dir}"; then
    die "Refusing to reuse broken venv (interpreter symlink is broken): ${dir}. Run: make rebuild"
  fi
  [[ -x "$(venv_project_python "${dir}")" ]] || die "Refusing to reuse incomplete venv at ${dir}. Run: make rebuild"
  if ! venv_python_has_pip "${dir}"; then
    die "Refusing to reuse incomplete venv (pip is missing or broken) at ${dir}. Run: make rebuild"
  fi
  if ! venv_version_matches_expected "${dir}"; then
    cfg_ver="$(pyvenv_cfg_value "${dir}" version || echo unknown)"
    die "Refusing to reuse venv (Python ${cfg_ver} does not match expected ${MLX_PYTHON_VERSION}): ${dir}. Run: make rebuild"
  fi
  prefix="$(homebrew_prefix)"
  if ! venv_home_under_homebrew "${dir}"; then
    cfg_home="$(pyvenv_cfg_value "${dir}" home || echo unknown)"
    die "Refusing to reuse venv (pyvenv.cfg home ${cfg_home} is not under Homebrew prefix ${prefix}): ${dir}. Run: make rebuild"
  fi
}

# Sibling directories left when an atomic create is killed before rename:
# <dest>.partial.<pid>. Names that are not that pattern are ignored.
list_stale_venv_partials() {
  local dest="$1"
  local stale base name suffix nullglob_state
  base="$(basename "${dest}")"
  [[ -n "${base}" && "${base}" != "/" && "${base}" != "." && "${base}" != ".." ]] || return 0
  nullglob_state="$(shopt -p nullglob || true)"
  shopt -s nullglob
  for stale in "${dest}.partial."*; do
    [[ -d "${stale}" && ! -L "${stale}" ]] || continue
    name="$(basename "${stale}")"
    suffix="${name#"${base}.partial."}"
    [[ "${name}" == "${base}.partial.${suffix}" ]] || continue
    case "${suffix}" in
      ''|*[!0-9]*) continue ;;
    esac
    printf '%s\n' "${stale}"
  done
  _restore_nullglob "${nullglob_state}"
}

# Python's venv records the creation path in bin/pip, bin/activate, and
# pyvenv.cfg. Rewrite that temporary path to the final destination before rename.
rewrite_relocated_venv_paths() {
  local brew_py="$1"
  local partial="$2"
  local dest="$3"
  local old_base new_base
  old_base="$(basename "${partial}")"
  new_base="$(basename "${dest}")"
  [[ "${partial}" == "${dest}.partial."* ]] || die "Refusing to relocate venv with unexpected temporary path: ${partial}"
  [[ -n "${old_base}" && "${old_base}" != "${new_base}" ]] || die "Refusing to relocate venv onto the same path: ${dest}"
  "${brew_py}" - "${partial}" "${dest}" "${old_base}" "${new_base}" "${partial}" <<'PY' || die "Venv creation failed: could not rewrite temporary path in ${partial}"
import os
import sys

old_path, new_path, old_base, new_base, root = sys.argv[1:]
old_path_b = old_path.encode()
new_path_b = new_path.encode()
old_base_b = old_base.encode()
new_base_b = new_base.encode()
if not old_path_b or not new_path_b or not old_base_b or old_base_b == new_base_b:
    sys.stderr.write("refusing empty venv path rewrite\n")
    sys.exit(1)

for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
    dirnames[:] = [entry for entry in dirnames if not os.path.islink(os.path.join(dirpath, entry))]
    for name in filenames:
        path = os.path.join(dirpath, name)
        if os.path.islink(path):
            continue
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError as exc:
            sys.stderr.write(f"cannot read {path}: {exc}\n")
            sys.exit(1)
        if old_path_b not in data and old_base_b not in data:
            continue
        # Compiled files record the creation path as co_filename. Their string
        # lengths are prefixed, so a byte replace would corrupt them. They are
        # removed below and recreated on the next import from the final path.
        if b"\0" in data:
            continue
        updated = data.replace(old_path_b, new_path_b).replace(old_base_b, new_base_b)
        with open(path, "wb") as handle:
            handle.write(updated)

for dirpath, _dirnames, _filenames in os.walk(root, topdown=False, followlinks=False):
    if os.path.basename(dirpath) != "__pycache__" or os.path.islink(dirpath):
        continue
    for name in os.listdir(dirpath):
        cache_path = os.path.join(dirpath, name)
        if os.path.islink(cache_path) or os.path.isfile(cache_path):
            os.remove(cache_path)
    os.rmdir(dirpath)
PY
}

# Exclusive lock for one destination: ${dest}.create-lock/pid.
# mkdir is atomic. A live pid owns the lock; a dead pid is abandoned and replaced.
# Before removing a stale lock, re-read pid so two waiters cannot both delete a
# fresh lock another process just created. Prints the lock directory. Callers
# must remove it on the success path; the EXIT trap removes it when create fails.
acquire_venv_create_lock() {
  local dest="$1"
  local lock pid stale_owner current_owner empty_seen waited logged_wait
  lock="${dest}.create-lock"
  empty_seen=0
  waited=0
  logged_wait=0
  while (( waited < 180 )); do
    if mkdir -- "${lock}" 2>/dev/null; then
      if printf '%s\n' "$$" >"${lock}/pid"; then
        printf '%s\n' "${lock}"
        return 0
      fi
      rm -rf -- "${lock}"
      die "Could not record venv create lock owner in ${lock}"
    fi
    if [[ -L "${lock}" || ! -d "${lock}" ]]; then
      die "Refusing to replace venv create lock that is not a directory: ${lock}"
    fi
    pid=""
    if [[ -f "${lock}/pid" && ! -L "${lock}/pid" ]]; then
      IFS= read -r pid <"${lock}/pid" || pid=""
    fi
    case "${pid}" in
      ''|*[!0-9]*) pid="" ;;
    esac
    if [[ -z "${pid}" ]]; then
      empty_seen=$((empty_seen + 1))
      if (( empty_seen < 5 )); then
        sleep 0.2
        waited=$((waited + 1))
        continue
      fi
    elif kill -0 "${pid}" 2>/dev/null; then
      if (( logged_wait == 0 )); then
        printf 'INFO: Waiting for venv create lock held by pid %s\n' "${pid}" >&2
        logged_wait=1
      fi
      empty_seen=0
      sleep 0.2
      waited=$((waited + 1))
      continue
    fi
    stale_owner="${pid}"
    current_owner=""
    if [[ -f "${lock}/pid" && ! -L "${lock}/pid" ]]; then
      IFS= read -r current_owner <"${lock}/pid" || current_owner=""
    fi
    case "${current_owner}" in
      ''|*[!0-9]*) current_owner="" ;;
    esac
    if [[ -n "${stale_owner}" ]]; then
      if [[ "${current_owner}" != "${stale_owner}" ]]; then
        empty_seen=0
        sleep 0.2
        waited=$((waited + 1))
        continue
      fi
      if kill -0 "${stale_owner}" 2>/dev/null; then
        empty_seen=0
        sleep 0.2
        waited=$((waited + 1))
        continue
      fi
    elif [[ -n "${current_owner}" ]]; then
      empty_seen=0
      sleep 0.2
      waited=$((waited + 1))
      continue
    fi
    rm -rf -- "${lock}"
    empty_seen=0
  done
  die "Timed out waiting for venv create lock: ${lock}"
}

# True when a finished venv still mentions the temporary directory name.
venv_records_temporary_path() {
  local dest="$1"
  local marker="$2"
  local file nullglob_state
  [[ -n "${marker}" ]] || return 1
  if [[ -f "${dest}/pyvenv.cfg" ]] && grep -F -q -- "${marker}" "${dest}/pyvenv.cfg"; then
    return 0
  fi
  nullglob_state="$(shopt -p nullglob || true)"
  shopt -s nullglob
  for file in "${dest}/bin/"*; do
    [[ -f "${file}" && ! -L "${file}" ]] || continue
    if grep -F -q -- "${marker}" "${file}"; then
      _restore_nullglob "${nullglob_state}"
      return 0
    fi
  done
  _restore_nullglob "${nullglob_state}"
  return 1
}

# Create .venv atomically: build in a sibling temp dir, point scripts at the
# final path, verify pip, then rename. One create lock per destination stops a
# second run from deleting the first run's temporary directory. The EXIT trap
# removes that temporary directory until rename; it removes the destination
# only after this run owns the renamed tree.
create_atomic_project_venv() {
  local brew_py="$1"
  local dest="$2"
  local partial py stale stale_pid lock quoted_partial quoted_dest quoted_lock old_base

  [[ -n "${brew_py}" && -x "${brew_py}" ]] || die "Refusing to create venv without a Python interpreter"
  [[ -n "${dest}" ]] || die "Refusing to create venv with an empty destination"
  while [[ "${dest}" != "/" && "${dest}" == */ ]]; do
    dest="${dest%/}"
  done
  [[ ! -e "${dest}" ]] || die "Refusing to overwrite existing path: ${dest}"

  partial="${dest}.partial.$$"
  lock="$(acquire_venv_create_lock "${dest}")"
  quoted_partial="$(printf '%q' "${partial}")"
  quoted_dest="$(printf '%q' "${dest}")"
  quoted_lock="$(printf '%q' "${lock}")"
  # Paths are fixed at registration; the trap must not depend on a nested function.
  # Do not remove the destination yet: this run does not own it.
  # shellcheck disable=SC2064
  trap "rm -rf -- ${quoted_partial} ${quoted_lock}" EXIT
  if [[ -e "${dest}" ]]; then
    die "Refusing to overwrite existing path: ${dest}"
  fi
  while IFS= read -r stale; do
    [[ -n "${stale}" ]] || continue
    stale_pid="${stale##*.}"
    if [[ "${stale_pid}" != "$$" ]] && kill -0 "${stale_pid}" 2>/dev/null; then
      die "Refusing to remove in-use temporary venv ${stale} (pid ${stale_pid} is running). If no other make venv/rebuild is active, remove it or run: make clean"
    fi
    rm -rf -- "${stale}"
  done < <(list_stale_venv_partials "${dest}")
  rm -rf -- "${partial}"
  "${brew_py}" -m venv "${partial}"
  py="${partial}/bin/python"
  [[ -x "${py}" ]] || die "Venv creation failed: ${py} is not executable"
  "${py}" -m pip --version >/dev/null || die "Venv creation failed: pip is not available in ${partial}"
  rewrite_relocated_venv_paths "${brew_py}" "${partial}" "${dest}"
  if [[ -e "${dest}" || -L "${dest}" ]]; then
    die "Refusing to overwrite ${dest}: it appeared while building ${partial}"
  fi
  mv "${partial}" "${dest}"
  # This run now owns the renamed tree. A later failure may remove it.
  # shellcheck disable=SC2064
  trap "rm -rf -- ${quoted_dest} ${quoted_lock}" EXIT
  old_base="$(basename "${partial}")"
  if venv_records_temporary_path "${dest}" "${old_base}"; then
    die "Venv creation failed: temporary path remains in ${dest}"
  fi
  [[ -x "${dest}/bin/pip" ]] || die "Venv creation failed: ${dest}/bin/pip is not executable"
  "${dest}/bin/pip" --version >/dev/null || die "Venv creation failed: ${dest}/bin/pip does not run"
  rm -rf -- "${lock}"
  trap - EXIT
}

# Homebrew python@MLX_PYTHON_VERSION on arm64. No PATH fallback.
resolve_homebrew_python() {
  local py mach prefix
  prefix="$(homebrew_prefix)"
  [[ -n "${prefix}" ]] || die "Homebrew not found. Run: make venv"
  py="${prefix}/opt/python@${MLX_PYTHON_VERSION}/bin/python${MLX_PYTHON_VERSION}"
  if [[ ! -x "${py}" ]]; then
    die "Python ${MLX_PYTHON_VERSION} not found at ${py}. Install via: brew install python@${MLX_PYTHON_VERSION}"
  fi
  mach="$("${py}" -c 'import platform; print(platform.machine())')" || die "Could not read the architecture of ${py}"
  if [[ "${mach}" != "arm64" ]]; then
    die "Homebrew Python at ${py} reports ${mach}, not arm64."
  fi
  printf '%s\n' "${py}"
}

# Detect Homebrew, optionally install it, and reject an Intel prefix.
# rerun_cmd is printed when Homebrew is missing.
ensure_homebrew_ready() {
  local rerun_cmd="$1"
  local brew_arch
  ensure_homebrew_in_path
  if [[ -z "$(homebrew_prefix)" ]]; then
    if is_truthy "${MLX_INSTALL_HOMEBREW:-0}"; then
      log_info "Installing Homebrew (NONINTERACTIVE=1)..."
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      ensure_homebrew_in_path
    else
      cat <<EOF
Homebrew was not found.

Install Homebrew (Apple Silicon default prefix /opt/homebrew), then re-run:

  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "\$(/opt/homebrew/bin/brew shellenv)"

Or allow the venv step to install it:

  ${rerun_cmd}
EOF
      die "Homebrew is required."
    fi
  fi

  require_cmd brew
  brew_arch="$(brew config 2>/dev/null | awk -F': ' '/CPU:/{print $2; exit}')"
  log_ok "Homebrew at $(homebrew_prefix) (CPU: ${brew_arch:-unknown})"
  if [[ "$(homebrew_prefix)" == "/usr/local" ]]; then
    die "Homebrew prefix is /usr/local (Intel/Rosetta). Install Apple Silicon Homebrew at /opt/homebrew, then re-run."
  fi
}

# True when install can use this tree: pyvenv.cfg, executable bin/python, and pip.
venv_install_ready() {
  local dir="${1:-${MLX_VENV}}"
  [[ -f "${dir}/pyvenv.cfg" ]] || return 1
  [[ -x "$(venv_project_python "${dir}")" ]] || return 1
  venv_python_has_pip "${dir}"
}

# Callers mkdir -p the workspace first. Missing .venv is OK (create). An
# existing path must be install-ready under the workspace. bin/python3 alone,
# a non-executable bin/python, or a venv without pip is not enough.
assert_install_venv_paths() {
  local py
  assert_workspace_safe
  assert_venv_under_workspace
  if [[ ! -e "${MLX_VENV}" ]]; then
    return 0
  fi
  if [[ ! -d "${MLX_VENV}" ]]; then
    die "MLX_VENV exists but is not a directory: ${MLX_VENV}"
  fi
  if venv_interpreter_symlink_broken "${MLX_VENV}"; then
    die "Refusing to reuse broken venv (interpreter symlink is broken): ${MLX_VENV}. Run: make rebuild"
  fi
  if venv_install_ready "${MLX_VENV}"; then
    return 0
  fi
  py="$(venv_project_python "${MLX_VENV}")"
  if [[ -f "${MLX_VENV}/pyvenv.cfg" && -e "${py}" && ! -x "${py}" ]]; then
    die "Refusing to reuse incomplete venv (bin/python is not executable): ${MLX_VENV}. Run: make rebuild"
  fi
  if [[ -f "${MLX_VENV}/pyvenv.cfg" && -x "${py}" ]]; then
    die "Refusing to reuse incomplete venv (pip is missing or broken): ${MLX_VENV}. Run: make rebuild"
  fi
  if [[ -f "${MLX_VENV}/pyvenv.cfg" ]]; then
    die "Refusing to reuse incomplete venv (missing bin/python): ${MLX_VENV}. Remove or rename it, then run: make rebuild"
  fi
  if has_venv_interpreter "${MLX_VENV}"; then
    die "Refusing to reuse incomplete venv (missing pyvenv.cfg): ${MLX_VENV}. Remove or rename it, then run: make rebuild"
  fi
  die "Refusing to reuse path that does not look like a venv: ${MLX_VENV}. Remove or rename it."
}

# Install paths must already have a complete venv. Does not create one.
require_install_venv() {
  assert_install_venv_paths
  if [[ ! -d "${MLX_VENV}" ]]; then
    die "Python venv not found at ${MLX_VENV}. Run: make venv"
  fi
}

assert_path_under_workspace() {
  local orig="$1"
  local label="${2:-path}"
  local path ws
  [[ -n "${orig}" ]] || die "Refusing empty ${label}"
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  path="$(canonical_path "${orig}")" || die "Cannot resolve ${label}: ${orig}"
  [[ "${path}" != "/" ]] || die "Refusing to remove /"
  [[ "${path}" != "${ws}" ]] || die "Refusing to remove workspace root as ${label}: ${orig}"
  [[ "${path}" == "${ws}/"* ]] || die "Refusing to remove ${label} outside workspace: ${orig} (resolves to ${path})"
}

human_du() {
  local target="$1"
  if [[ -e "${target}" ]]; then
    du -sh "${target}" 2>/dev/null | awk '{print $1}'
  else
    echo "absent"
  fi
}

warn_unknown_chip_policy() {
  local brand="${1:-}"
  local family="${2:-}"
  local sku="${3:-}"
  local bandwidth="${4:-}"
  if [[ -n "${OVERRIDE_CHIP_FAMILY:-}" ]]; then
    return 0
  fi
  if [[ -z "${family}" ]]; then
    log_warn "Unrecognized Apple Silicon brand '${brand:-unknown}'; falling back to RAM-only defaults."
    return 0
  fi
  if [[ -z "${bandwidth}" ]]; then
    log_warn "Unknown Apple Silicon chip M${family} ${sku:-base}; falling back to RAM-only defaults. Install continues."
  fi
}

# Fail closed on typos: unknown OVERRIDE_* used to look like 8 GB / unknown-chip.
validate_policy_overrides() {
  if [[ -n "${OVERRIDE_MEMORY_TIER:-}" ]]; then
    case "${OVERRIDE_MEMORY_TIER}" in
      constrained|standard|high|workstation|large) ;;
      *)
        die "OVERRIDE_MEMORY_TIER must be constrained|standard|high|workstation|large (got '${OVERRIDE_MEMORY_TIER}')"
        ;;
    esac
  fi
  if [[ -n "${OVERRIDE_CHIP_SKU:-}" ]]; then
    case "${OVERRIDE_CHIP_SKU}" in
      base|pro|max|ultra) ;;
      *)
        die "OVERRIDE_CHIP_SKU must be base|pro|max|ultra (got '${OVERRIDE_CHIP_SKU}')"
        ;;
    esac
  fi
  if [[ -n "${OVERRIDE_THERMAL_CLASS:-}" ]]; then
    case "${OVERRIDE_THERMAL_CLASS}" in
      fanless|cooled) ;;
      *)
        die "OVERRIDE_THERMAL_CLASS must be fanless|cooled (got '${OVERRIDE_THERMAL_CLASS}')"
        ;;
    esac
  fi
  if [[ -n "${OVERRIDE_CHIP_FAMILY:-}" && ! "${OVERRIDE_CHIP_FAMILY}" =~ ^[0-9]+$ ]]; then
    die "OVERRIDE_CHIP_FAMILY must be a generation number (got '${OVERRIDE_CHIP_FAMILY}')"
  fi
}

# Policy only: OVERRIDE_* change recommendations, never reported hardware facts.
compose_chip_policy() {
  local policy_family policy_sku policy_gpu policy_thermal policy_tier policy_bw policy_tp tier_line
  validate_policy_overrides
  if [[ -n "${OVERRIDE_CHIP_FAMILY:-}" ]]; then
    policy_family="${OVERRIDE_CHIP_FAMILY}"
    policy_sku="${OVERRIDE_CHIP_SKU:-base}"
  else
    policy_family="${MLX_CHIP_FAMILY:-}"
    policy_sku="${OVERRIDE_CHIP_SKU:-${MLX_CHIP_SKU:-}}"
  fi
  policy_gpu="${OVERRIDE_GPU_CORES:-${MLX_GPU_CORES:-0}}"
  policy_thermal="${OVERRIDE_THERMAL_CLASS:-${MLX_THERMAL_CLASS:-}}"
  policy_tier="${OVERRIDE_MEMORY_TIER:-${MLX_PHYSICAL_TIER_ID:-constrained}}"
  if [[ -n "${policy_family}" && -z "${policy_sku}" ]]; then
    policy_sku="base"
  fi
  [[ "${policy_gpu}" =~ ^[0-9]+$ ]] || policy_gpu=0

  policy_bw="$(lookup_memory_bandwidth_gbs "${policy_family}" "${policy_sku}" "${policy_gpu}")"
  policy_tp="$(classify_throughput_class "${policy_bw}")"

  if [[ -n "${OVERRIDE_MEMORY_TIER:-}" ]]; then
    log_warn "OVERRIDE_MEMORY_TIER=${OVERRIDE_MEMORY_TIER} (recommendations may differ from physical RAM)"
  fi
  if [[ -n "${OVERRIDE_CHIP_FAMILY:-}" || -n "${OVERRIDE_CHIP_SKU:-}" ]]; then
    log_warn "OVERRIDE_CHIP_FAMILY=${OVERRIDE_CHIP_FAMILY:-} OVERRIDE_CHIP_SKU=${OVERRIDE_CHIP_SKU:-} (policy only; detect facts stay physical)"
  fi
  if [[ -n "${OVERRIDE_GPU_CORES:-}" ]]; then
    log_warn "OVERRIDE_GPU_CORES=${OVERRIDE_GPU_CORES} (policy only)"
  fi
  if [[ -n "${OVERRIDE_THERMAL_CLASS:-}" ]]; then
    log_warn "OVERRIDE_THERMAL_CLASS=${OVERRIDE_THERMAL_CLASS} (policy only)"
  fi

  MLX_TIER_ID="${policy_tier}"
  tier_line="$(classify_memory_tier "$(dummy_mem_gib_for_tier "${policy_tier}")")"
  IFS='|' read -r _ MLX_POLICY_TIER_LABEL MLX_TIER_HINT <<<"${tier_line}"
  if [[ -n "${OVERRIDE_MEMORY_TIER:-}" ]]; then
    MLX_TIER_LABEL="${MLX_POLICY_TIER_LABEL}"
  fi

  MLX_POLICY_CHIP_FAMILY="${policy_family}"
  MLX_POLICY_CHIP_SKU="${policy_sku}"
  MLX_POLICY_GPU_CORES="${policy_gpu}"
  MLX_POLICY_THERMAL_CLASS="${policy_thermal}"
  MLX_POLICY_BANDWIDTH_GBS="${policy_bw}"
  MLX_POLICY_THROUGHPUT_CLASS="${policy_tp}"

  MLX_RECOMMENDED_MODEL="$(recommended_model_for_profile "${policy_tier}" "${policy_tp}" "${policy_thermal}" "${policy_family}")"
  MLX_RECOMMENDED_CONTEXT="$(recommended_context_for_profile "${policy_tier}" "${policy_tp}" "${policy_thermal}")"
  MLX_RECOMMENDED_IMAGE_PROFILE="$(recommended_image_profile_for_profile "${policy_tier}" "${policy_tp}" "${policy_thermal}" "${policy_family}")"
  MLX_RECOMMENDED_VIDEO_PROFILE="$(recommended_video_profile_for_profile "${policy_tier}" "${policy_tp}" "${policy_thermal}" "${policy_family}" "${policy_gpu}")"
  if video_force_required_for_profile "${policy_tier}" "${policy_tp}" "${policy_thermal}"; then
    MLX_VIDEO_FORCE_REQUIRED=1
  else
    MLX_VIDEO_FORCE_REQUIRED=0
  fi
}

collect_hardware_facts() {
  local mem_bytes mem_gib tier_line parsed_family parsed_sku ws_line
  note_disk_avail_override
  mem_bytes="$(detect_memory_bytes)"
  mem_gib="$(bytes_to_gib "${mem_bytes}")"
  tier_line="$(classify_memory_tier "${mem_gib}")"
  IFS='|' read -r MLX_PHYSICAL_TIER_ID MLX_TIER_LABEL MLX_TIER_HINT <<<"${tier_line}"
  MLX_PHYSICAL_TIER_LABEL="${MLX_TIER_LABEL}"

  MLX_ARCH="$(detect_architecture)"
  MLX_CHIP="$(detect_chip)"
  MLX_MEM_BYTES="${mem_bytes}"
  MLX_MEM_GIB="${mem_gib}"
  MLX_CPU_CORES="$(detect_cpu_cores)"
  MLX_MACOS_VERSION="$(detect_macos_version)"
  MLX_DISK_AVAIL_GIB="$(detect_disk_available_gib "${MLX_WORKSPACE}")"
  MLX_HW_MODEL="$(detect_hw_model)"
  MLX_GPU_CORES="$(detect_gpu_core_count)"
  MLX_P_CORES="$(detect_p_cores)"
  MLX_E_CORES="$(detect_e_cores)"
  MLX_THERMAL_CLASS="$(classify_thermal_class "${MLX_HW_MODEL}")"

  parsed_family=""
  parsed_sku=""
  IFS='|' read -r parsed_family parsed_sku <<<"$(parse_apple_chip_brand "${MLX_CHIP}" || true)"
  MLX_CHIP_FAMILY="${parsed_family}"
  MLX_CHIP_SKU="${parsed_sku}"
  MLX_BANDWIDTH_GBS="$(lookup_memory_bandwidth_gbs "${MLX_CHIP_FAMILY}" "${MLX_CHIP_SKU}" "${MLX_GPU_CORES:-0}")"
  MLX_THROUGHPUT_CLASS="$(classify_throughput_class "${MLX_BANDWIDTH_GBS}")"
  warn_unknown_chip_policy "${MLX_CHIP}" "${MLX_CHIP_FAMILY}" "${MLX_CHIP_SKU}" "${MLX_BANDWIDTH_GBS}"

  if [[ "${MLX_SKIP_DEVICE_PROBE:-0}" == "1" ]]; then
    MLX_WORKING_SET_BYTES=""
    MLX_GPU_ARCH=""
  else
    ws_line="$(probe_mlx_device_info "$(venv_python)")"
    IFS='|' read -r MLX_WORKING_SET_BYTES MLX_GPU_ARCH <<<"${ws_line}"
  fi
}

export_chip_profile_vars() {
  export MLX_ARCH MLX_CHIP MLX_MEM_BYTES MLX_MEM_GIB MLX_CPU_CORES
  export MLX_MACOS_VERSION MLX_DISK_AVAIL_GIB
  export MLX_PHYSICAL_TIER_ID MLX_PHYSICAL_TIER_LABEL MLX_TIER_ID MLX_TIER_LABEL MLX_TIER_HINT
  export MLX_CHIP_FAMILY MLX_CHIP_SKU MLX_GPU_CORES MLX_P_CORES MLX_E_CORES
  export MLX_HW_MODEL MLX_THERMAL_CLASS MLX_BANDWIDTH_GBS MLX_THROUGHPUT_CLASS
  export MLX_WORKING_SET_BYTES MLX_GPU_ARCH
  export MLX_POLICY_CHIP_FAMILY MLX_POLICY_CHIP_SKU MLX_POLICY_GPU_CORES
  export MLX_POLICY_THERMAL_CLASS MLX_POLICY_BANDWIDTH_GBS MLX_POLICY_THROUGHPUT_CLASS
  export MLX_RECOMMENDED_MODEL MLX_RECOMMENDED_CONTEXT
  export MLX_RECOMMENDED_IMAGE_PROFILE MLX_RECOMMENDED_VIDEO_PROFILE
  export MLX_VIDEO_FORCE_REQUIRED
}

export_detect_env() {
  # Physical facts + composed policy. OVERRIDE_* never rewrite reported facts.
  collect_hardware_facts
  compose_chip_policy
  export_chip_profile_vars
}

# Portable wrapper: real sysctl on macOS; constrained + OVERRIDE_* on Linux CI.
load_runtime_profile() {
  if detect_memory_bytes >/dev/null 2>&1; then
    export_detect_env
    return
  fi
  load_runtime_profile_without_sysctl
}

# Linux CI / no-sysctl path. Physical RAM is always the constrained floor;
# OVERRIDE_* may rewrite policy labels after this, not physical facts.
load_runtime_profile_without_sysctl() {
  note_disk_avail_override
  MLX_ARCH="$(detect_architecture)"
  MLX_CHIP=""
  MLX_MEM_BYTES=""
  MLX_MEM_GIB=""
  MLX_CPU_CORES=""
  MLX_MACOS_VERSION=""
  MLX_DISK_AVAIL_GIB=""
  MLX_PHYSICAL_TIER_ID="constrained"
  MLX_TIER_LABEL="8 GB — constrained"
  MLX_PHYSICAL_TIER_LABEL="${MLX_TIER_LABEL}"
  MLX_TIER_HINT="3B–4B 4-bit models, short context"
  MLX_CHIP_FAMILY=""
  MLX_CHIP_SKU=""
  MLX_GPU_CORES=""
  MLX_P_CORES=""
  MLX_E_CORES=""
  MLX_HW_MODEL=""
  MLX_THERMAL_CLASS=""
  MLX_BANDWIDTH_GBS=""
  MLX_THROUGHPUT_CLASS="unknown"
  MLX_WORKING_SET_BYTES=""
  MLX_GPU_ARCH=""
  compose_chip_policy
  export_chip_profile_vars
}

print_hardware_summary() {
  if [[ -z "${MLX_MEM_BYTES:-}" || -z "${MLX_CHIP:-}" ]]; then
    export_detect_env
  fi
  local ws_disp=""
  if [[ -n "${MLX_WORKING_SET_BYTES:-}" ]]; then
    ws_disp="$(bytes_to_gib_display "${MLX_WORKING_SET_BYTES}") GiB (${MLX_WORKING_SET_BYTES} bytes)"
  else
    ws_disp="unavailable (mlx not importable)"
  fi

  cat <<EOF
Architecture:     ${MLX_ARCH}
Apple chip:       ${MLX_CHIP}
Chip family/SKU:  ${MLX_CHIP_FAMILY:-unknown} ${MLX_CHIP_SKU:-}
GPU cores:        ${MLX_GPU_CORES:-unknown}
CPU P/E cores:    ${MLX_P_CORES:-?}/${MLX_E_CORES:-?}
Thermal class:    ${MLX_THERMAL_CLASS:-unknown} (${MLX_HW_MODEL:-unknown model})
Bandwidth:        ${MLX_BANDWIDTH_GBS:-unknown} GB/s
Throughput class: ${MLX_THROUGHPUT_CLASS:-unknown}
Memory:           ${MLX_MEM_GIB} GiB (${MLX_MEM_BYTES} bytes)
Memory tier:      ${MLX_PHYSICAL_TIER_LABEL:-${MLX_TIER_LABEL}} (id ${MLX_PHYSICAL_TIER_ID})
Working set:      ${ws_disp}
GPU arch:         ${MLX_GPU_ARCH:-unavailable}
CPU cores:        ${MLX_CPU_CORES}
macOS version:    ${MLX_MACOS_VERSION}
Disk available:   ${MLX_DISK_AVAIL_GIB} GiB (workspace volume)
Python version:   $(detect_python_version)
Workspace:        ${MLX_WORKSPACE}
Recommended:      ${MLX_TIER_HINT}
Default model:    ${MLX_RECOMMENDED_MODEL}
Default context:  ${MLX_RECOMMENDED_CONTEXT}
EOF
}

print_composed_profile() {
  if [[ -z "${MLX_RECOMMENDED_MODEL:-}" ]]; then
    load_runtime_profile
  fi
  cat <<EOF
# Composed MLX defaults (policy). Does not write config/models.env.
# RAM is the OOM fence; chip class is the performance fence.
# After moving a clone to another Mac, compare this output with models.env
# (rebuild preserves that file and will not refresh MLX_DEFAULT_MODEL).

memory_tier=${MLX_TIER_ID}
physical_memory_tier=${MLX_PHYSICAL_TIER_ID:-}
throughput_class=${MLX_POLICY_THROUGHPUT_CLASS:-${MLX_THROUGHPUT_CLASS:-}}
thermal_class=${MLX_POLICY_THERMAL_CLASS:-${MLX_THERMAL_CLASS:-}}
chip_family=${MLX_POLICY_CHIP_FAMILY:-${MLX_CHIP_FAMILY:-}}
chip_sku=${MLX_POLICY_CHIP_SKU:-${MLX_CHIP_SKU:-}}
gpu_cores=${MLX_POLICY_GPU_CORES:-${MLX_GPU_CORES:-}}
bandwidth_gbs=${MLX_POLICY_BANDWIDTH_GBS:-${MLX_BANDWIDTH_GBS:-}}
recommended_model=${MLX_RECOMMENDED_MODEL}
recommended_context=${MLX_RECOMMENDED_CONTEXT}
image_profile=${MLX_RECOMMENDED_IMAGE_PROFILE}
video_profile=${MLX_RECOMMENDED_VIDEO_PROFILE}
video_force_required=${MLX_VIDEO_FORCE_REQUIRED:-0}
working_set_bytes=${MLX_WORKING_SET_BYTES:-}
gpu_arch=${MLX_GPU_ARCH:-}
EOF
}

# KEY=value lines for `eval "$(detect-apple-silicon.sh --env)"`.
# MLX_TIER_ID is the policy tier (honors OVERRIDE_MEMORY_TIER); physical RAM
# is MLX_PHYSICAL_TIER_ID so sourcing --env cannot wipe a policy override.
print_detect_env() {
  local brew_ok="${1:-false}"
  local brew_prefix="${2:-}"
  local xcode_ok="${3:-false}"
  printf 'MLX_ARCH=%q\n' "${MLX_ARCH:-}"
  printf 'MLX_CHIP=%q\n' "${MLX_CHIP:-}"
  printf 'MLX_CHIP_FAMILY=%q\n' "${MLX_CHIP_FAMILY:-}"
  printf 'MLX_CHIP_SKU=%q\n' "${MLX_CHIP_SKU:-}"
  printf 'MLX_GPU_CORES=%q\n' "${MLX_GPU_CORES:-}"
  printf 'MLX_P_CORES=%q\n' "${MLX_P_CORES:-}"
  printf 'MLX_E_CORES=%q\n' "${MLX_E_CORES:-}"
  printf 'MLX_HW_MODEL=%q\n' "${MLX_HW_MODEL:-}"
  printf 'MLX_THERMAL_CLASS=%q\n' "${MLX_THERMAL_CLASS:-}"
  printf 'MLX_BANDWIDTH_GBS=%q\n' "${MLX_BANDWIDTH_GBS:-}"
  printf 'MLX_THROUGHPUT_CLASS=%q\n' "${MLX_THROUGHPUT_CLASS:-}"
  printf 'MLX_MEM_BYTES=%q\n' "${MLX_MEM_BYTES:-}"
  printf 'MLX_MEM_GIB=%q\n' "${MLX_MEM_GIB:-}"
  printf 'MLX_PHYSICAL_TIER_ID=%q\n' "${MLX_PHYSICAL_TIER_ID:-}"
  printf 'MLX_PHYSICAL_TIER_LABEL=%q\n' "${MLX_PHYSICAL_TIER_LABEL:-}"
  printf 'MLX_TIER_ID=%q\n' "${MLX_TIER_ID:-}"
  printf 'MLX_TIER_LABEL=%q\n' "${MLX_TIER_LABEL:-}"
  printf 'MLX_TIER_HINT=%q\n' "${MLX_TIER_HINT:-}"
  printf 'MLX_CPU_CORES=%q\n' "${MLX_CPU_CORES:-}"
  printf 'MLX_MACOS_VERSION=%q\n' "${MLX_MACOS_VERSION:-}"
  printf 'MLX_DISK_AVAIL_GIB=%q\n' "${MLX_DISK_AVAIL_GIB:-0}"
  printf 'MLX_PYTHON_VERSION_DETECTED=%q\n' "$(detect_python_version)"
  printf 'MLX_HOMEBREW=%q\n' "${brew_ok}"
  printf 'MLX_HOMEBREW_PREFIX=%q\n' "${brew_prefix}"
  printf 'MLX_XCODE_CLT=%q\n' "${xcode_ok}"
  printf 'MLX_RECOMMENDED_MODEL=%q\n' "${MLX_RECOMMENDED_MODEL:-}"
  printf 'MLX_RECOMMENDED_CONTEXT=%q\n' "${MLX_RECOMMENDED_CONTEXT:-}"
  printf 'MLX_RECOMMENDED_IMAGE_PROFILE=%q\n' "${MLX_RECOMMENDED_IMAGE_PROFILE:-}"
  printf 'MLX_RECOMMENDED_VIDEO_PROFILE=%q\n' "${MLX_RECOMMENDED_VIDEO_PROFILE:-}"
  printf 'MLX_VIDEO_FORCE_REQUIRED=%q\n' "${MLX_VIDEO_FORCE_REQUIRED:-0}"
  printf 'MLX_WORKING_SET_BYTES=%q\n' "${MLX_WORKING_SET_BYTES:-}"
  printf 'MLX_GPU_ARCH=%q\n' "${MLX_GPU_ARCH:-}"
  printf 'MLX_WORKSPACE=%q\n' "${MLX_WORKSPACE:-}"
}

upsert_env_assignment() {
  local file="$1"
  local key="$2"
  local value="$3"
  local quoted tmp
  is_models_env_key "${key}" || die "Refusing to write non-MLX key to models.env: ${key}"
  quoted="$(quote_env_value "${value}")"
  tmp="$(mktemp)"
  # Pass via ENVIRON so awk -v does not interpret backslashes in POSIX '\'' quoting.
  MLX_UPSERT_KEY="${key}" MLX_UPSERT_VALUE="${quoted}" awk '
    BEGIN { k=ENVIRON["MLX_UPSERT_KEY"]; v=ENVIRON["MLX_UPSERT_VALUE"]; done=0 }
    index($0, k "=") == 1 && !done { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
}

is_models_env_key() {
  [[ "${1:-}" =~ ^MLX_[A-Z0-9_]+$ ]]
}

# Unquoted when the value is a simple token (model ids, numbers, hosts).
# Otherwise POSIX single quotes so the file stays source-able without eval.
quote_env_value() {
  local value="$1"
  local out c
  local -i i
  if [[ "${value}" =~ ^[A-Za-z0-9._:/=@%+-]+$ ]]; then
    printf '%s' "${value}"
    return 0
  fi
  out="'"
  for (( i = 0; i < ${#value}; i++ )); do
    c="${value:i:1}"
    if [[ "${c}" == "'" ]]; then
      out+="'\\''"
    else
      out+="${c}"
    fi
  done
  out+="'"
  printf '%s' "${out}"
}

# Strip surrounding quotes without executing the value. Returns 1 if unsafe.
# Single-quoted values accept POSIX concatenation: 'Bob'\''s-model' → Bob's-model.
unquote_env_value() {
  local raw="$1"
  local inner
  if [[ "${raw:0:1}" == "'" ]]; then
    unquote_posix_single "${raw}"
    return $?
  fi
  if (( ${#raw} >= 2 )) && [[ "${raw:0:1}" == '"' && "${raw: -1}" == '"' ]]; then
    inner="${raw:1:${#raw}-2}"
    case "${inner}" in
      *'$'* | *'`'* | *\\*) return 1 ;;
    esac
    printf '%s' "${inner}"
    return 0
  fi
  if [[ "${raw}" =~ [][\$\`\;\|\&\<\>\(\)\{\}\\\'\"[:space:]] ]]; then
    return 1
  fi
  if [[ -n "${HOME:-}" && "${raw}" == "~" ]]; then
    printf '%s' "${HOME}"
  elif [[ -n "${HOME:-}" && "${raw:0:2}" == $'~/' ]]; then
    printf '%s' "${HOME}/${raw:2}"
  else
    printf '%s' "${raw}"
  fi
}

unquote_posix_single() {
  local raw="$1"
  local out="" c nxt
  local -i i=0 n=${#raw}
  (( n >= 2 )) || return 1
  while (( i < n )); do
    c="${raw:i:1}"
    if [[ "${c}" == "'" ]]; then
      i+=1
      while (( i < n )); do
        c="${raw:i:1}"
        [[ "${c}" == "'" ]] && break
        out+="${c}"
        i+=1
      done
      (( i < n )) || return 1
      i+=1
    elif [[ "${c}" == "\\" ]]; then
      i+=1
      (( i < n )) || return 1
      nxt="${raw:i:1}"
      [[ "${nxt}" == "'" ]] || return 1
      out+="'"
      i+=1
    else
      return 1
    fi
  done
  printf '%s' "${out}"
}

# Parse config/models.env as data. Only documented MLX_* config keys are
# exported. Lines are never executed (no command substitution, PATH=, or
# HF_TOKEN). Runtime identity keys (workspace/venv/paths) are skipped.
# Missing file is OK.
load_models_env() {
  local file="${1:-${MLX_MODELS_ENV}}"
  local line key value decoded
  [[ -f "${file}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    if [[ "${line}" == export[[:space:]]* ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      if ! is_models_env_key "${key}"; then
        log_warn "Skipping non-MLX key ${key} in ${file}"
        continue
      fi
      value="$(strip_unquoted_assignment_comment "${value}")"
      if ! decoded="$(unquote_env_value "${value}")"; then
        log_warn "Skipping unsafe ${key} assignment in ${file}"
        continue
      fi
      if is_models_env_runtime_key "${key}"; then
        log_warn "Skipping runtime key ${key} in ${file}"
        continue
      fi
      printf -v "${key}" '%s' "${decoded}"
      export "${key?}"
    fi
  done <"${file}"
}

is_models_env_runtime_key() {
  case "${1:-}" in
    MLX_WORKSPACE|MLX_VENV|MLX_CONFIG_DIR|MLX_MODELS_ENV|MLX_MODELS_EXAMPLE|MLX_PYTHON_VERSION|MLX_SKIP_DEVICE_PROBE)
      return 0
      ;;
    *) return 1 ;;
  esac
}

# Drop an unquoted " # comment" suffix. Quoted values are left intact.
strip_unquoted_assignment_comment() {
  local value="$1"
  local comment_re='^(.*)[[:space:]]+#'
  if [[ "${value:0:1}" == "'" || "${value:0:1}" == '"' ]]; then
    printf '%s' "${value}"
    return 0
  fi
  if [[ "${value}" =~ ${comment_re} ]]; then
    value="${BASH_REMATCH[1]}"
    value="${value%"${value##*[![:space:]]}"}"
  fi
  printf '%s' "${value}"
}

# Create config/models.env once from the composed profile. Never overwrite an existing file.
seed_models_env_if_missing() {
  local model context
  mkdir -p "${MLX_CONFIG_DIR}"
  if [[ -f "${MLX_MODELS_ENV}" ]]; then
    log_ok "Preserving existing ${MLX_MODELS_ENV}"
    return 0
  fi
  model="${MLX_RECOMMENDED_MODEL:-$(recommended_model_for_tier "${MLX_TIER_ID:-constrained}")}"
  context="${MLX_RECOMMENDED_CONTEXT:-2048}"
  if [[ -f "${MLX_MODELS_EXAMPLE}" ]]; then
    cp "${MLX_MODELS_EXAMPLE}" "${MLX_MODELS_ENV}"
    upsert_env_assignment "${MLX_MODELS_ENV}" MLX_DEFAULT_MODEL "${model}"
    upsert_env_assignment "${MLX_MODELS_ENV}" MLX_RECOMMENDED_CONTEXT "${context}"
    log_ok "Created ${MLX_MODELS_ENV} from composed profile (model=${model} context=${context})"
    log_info "Rebuild preserves this file. After moving this clone to another Mac, run: make recommend"
  else
    cat >"${MLX_MODELS_ENV}" <<EOF
# Local model preferences (not committed)
MLX_DEFAULT_MODEL=$(quote_env_value "${model}")
MLX_RECOMMENDED_CONTEXT=$(quote_env_value "${context}")
MLX_SERVER_HOST=127.0.0.1
MLX_SERVER_PORT=8080
EOF
    log_ok "Created ${MLX_MODELS_ENV}"
  fi
}

recommended_model_for_tier() {
  local tier_id="${1:-}"
  case "${tier_id}" in
    constrained)
      echo "mlx-community/Llama-3.2-3B-Instruct-4bit"
      ;;
    standard)
      echo "mlx-community/Llama-3.2-3B-Instruct-4bit"
      ;;
    high)
      echo "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
      ;;
    workstation)
      echo "mlx-community/Qwen2.5-14B-Instruct-4bit"
      ;;
    large)
      echo "mlx-community/Qwen2.5-32B-Instruct-4bit"
      ;;
    *)
      echo "mlx-community/Llama-3.2-3B-Instruct-4bit"
      ;;
  esac
}

# RAM is the OOM fence; throughput/thermal never raise a model past unified memory.
# Unknown throughput → RAM-only (existing tier table).
# Fanless Airs stay on that RAM-only model even when throughput would otherwise
# raise it (16 GB fast Air stays 3B, not the cooled M5 7B path).
# family is unused here; it exists for API symmetry with the image/video
# profile helpers (callers always pass the composed tuple).
recommended_model_for_profile() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  local family="${4:-0}"
  if [[ "${thermal}" == "fanless" ]]; then
    recommended_model_for_tier "${tier}"
    return
  fi
  if [[ "${throughput}" == "unknown" || -z "${throughput}" ]]; then
    recommended_model_for_tier "${tier}"
    return
  fi
  case "${tier}" in
    constrained|"")
      echo "mlx-community/Llama-3.2-3B-Instruct-4bit"
      ;;
    standard)
      if throughput_at_least "${throughput}" fast; then
        echo "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
      else
        echo "mlx-community/Llama-3.2-3B-Instruct-4bit"
      fi
      ;;
    high)
      if throughput_at_least "${throughput}" very_fast; then
        echo "mlx-community/Qwen2.5-14B-Instruct-4bit"
      else
        echo "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
      fi
      ;;
    workstation)
      echo "mlx-community/Qwen2.5-14B-Instruct-4bit"
      ;;
    large)
      echo "mlx-community/Qwen2.5-32B-Instruct-4bit"
      ;;
    *)
      recommended_model_for_tier "${tier}"
      ;;
  esac
}

# Catalog rows from docs/models.md. id|approx weights|use
# Fit labels are computed for the composed profile, not stored here.
model_catalog_rows() {
  cat <<'EOF'
mlx-community/Llama-3.2-3B-Instruct-4bit|~2.0-2.5 GB|Default chat on 8 GB and slow or moderate 16 GB
mlx-community/Llama-3.2-1B-Instruct-4bit|~0.8-1.2 GB|Ultra-light prompts and classification
mlx-community/Phi-3.5-mini-instruct-4bit|~2.2-2.8 GB|Compact instruct and coding assist
mlx-community/Qwen2.5-3B-Instruct-4bit|~2.0-2.6 GB|Multilingual and general chat
mlx-community/Mistral-7B-Instruct-v0.3-4bit|~4.0-5.0 GB|Default on fast cooled 16 GB; high swap risk on 8 GB
mlx-community/Meta-Llama-3.1-8B-Instruct-4bit|~4.5-5.5 GB|General 8B work on fast cooled 16 GB and up
mlx-community/Qwen2.5-14B-Instruct-4bit|~8-10 GB|Heavier reasoning on very_fast 24 GB and up
mlx-community/Qwen2.5-32B-Instruct-4bit|~18-20 GB|Large single-model server at 36 GB and up
EOF
}

# 7B and 8B: poor on <=8 GB, tight on a 16 GB Air or slow/moderate chip, fits when cooled and fast.
_model_list_fit_7b_8b() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  case "${tier}" in
    constrained|"") printf '%s\n' poor; return ;;
  esac
  if [[ "${thermal}" == "fanless" ]]; then
    if [[ "${tier}" == "standard" ]]; then
      printf '%s\n' tight
    else
      printf '%s\n' fits
    fi
    return
  fi
  if [[ "${tier}" == "standard" ]] && ! throughput_at_least "${throughput}" fast; then
    printf '%s\n' tight
    return
  fi
  printf '%s\n' fits
}

# default | fits | tight | poor for one catalog id on a composed profile.
# default always matches recommended_model_for_profile.
model_list_fit() {
  local id="${1:-}"
  local tier="${2:-}"
  local throughput="${3:-unknown}"
  local thermal="${4:-}"
  local default
  default="$(recommended_model_for_profile "${tier}" "${throughput}" "${thermal}" 0)"
  if [[ "${id}" == "${default}" ]]; then
    printf '%s\n' default
    return
  fi
  case "${id}" in
    mlx-community/Llama-3.2-3B-Instruct-4bit|\
    mlx-community/Llama-3.2-1B-Instruct-4bit|\
    mlx-community/Phi-3.5-mini-instruct-4bit|\
    mlx-community/Qwen2.5-3B-Instruct-4bit)
      printf '%s\n' fits
      ;;
    mlx-community/Mistral-7B-Instruct-v0.3-4bit|\
    mlx-community/Meta-Llama-3.1-8B-Instruct-4bit)
      _model_list_fit_7b_8b "${tier}" "${throughput}" "${thermal}"
      ;;
    mlx-community/Qwen2.5-14B-Instruct-4bit)
      case "${tier}" in
        workstation|large)
          printf '%s\n' fits
          ;;
        high)
          if [[ "${thermal}" != "fanless" ]] && throughput_at_least "${throughput}" very_fast; then
            printf '%s\n' fits
          else
            printf '%s\n' tight
          fi
          ;;
        *)
          printf '%s\n' poor
          ;;
      esac
      ;;
    mlx-community/Qwen2.5-32B-Instruct-4bit)
      case "${tier}" in
        workstation|large) printf '%s\n' fits ;;
        *) printf '%s\n' poor ;;
      esac
      ;;
    *)
      printf '%s\n' poor
      ;;
  esac
}

# Human list for this Mac. Args override the composed profile so tests can
# pass a fixture without sysctl. Empty args use the loaded MLX_* policy.
print_recommended_model_list() {
  local tier="${1:-${MLX_TIER_ID:-}}"
  local throughput="${2:-${MLX_POLICY_THROUGHPUT_CLASS:-${MLX_THROUGHPUT_CLASS:-unknown}}}"
  local thermal="${3:-${MLX_POLICY_THERMAL_CLASS:-${MLX_THERMAL_CLASS:-}}}"
  local chip="${4:-${MLX_CHIP:-unknown}}"
  local mem_gib="${5:-${MLX_MEM_GIB:-?}}"
  local context family sku physical chip_family_label
  local default row id weights use fit cached
  if [[ -n "${6:-}" ]]; then
    context="${6}"
  else
    context="$(recommended_context_for_profile "${tier}" "${throughput}" "${thermal}")"
  fi
  family="${7:-${MLX_POLICY_CHIP_FAMILY:-${MLX_CHIP_FAMILY:-?}}}"
  sku="${8:-${MLX_POLICY_CHIP_SKU:-${MLX_CHIP_SKU:-?}}}"
  physical="${9:-${MLX_PHYSICAL_TIER_ID:-${tier:-unknown}}}"
  default="$(recommended_model_for_profile "${tier}" "${throughput}" "${thermal}" 0)"
  chip_family_label="$(model_list_chip_family_label)"
  cat <<EOF
Apple chip:       ${chip}
${chip_family_label}  ${family} ${sku}
Memory:           ${mem_gib} GiB
Memory tier:      ${tier:-unknown} (physical ${physical})
Thermal class:    ${thermal:-unknown}
Throughput class: ${throughput:-unknown}
Default model:    ${default}
Default context:  ${context}

Weights are not total unified memory. KV cache, runtime, and macOS sit on top.
fit is default (composed choice), fits, tight (measure first), or poor for this Mac.
cached is yes when that repo has config.json and every weight file on disk
(including all shards listed in model.safetensors.index.json when present).

EOF
  printf 'fit\tcached\tmodel\tweights\tuse\n'
  while IFS= read -r row; do
    [[ -z "${row}" || "${row}" == \#* ]] && continue
    IFS='|' read -r id weights use <<<"${row}"
    fit="$(model_list_fit "${id}" "${tier}" "${throughput}" "${thermal}")"
    cached=no
    if model_weights_cached "${id}"; then
      cached=yes
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${fit}" "${cached}" "${id}" "${weights}" "${use}"
  done < <(model_catalog_rows)
  printf '\nOne model at a time: scripts/serve-mlx.sh --model MODEL\n'
}

# Fanless Airs keep the conservative 2k context even on later chips.
# Unknown throughput on standard matches slow/moderate (2048), not the fast 4096 path.
recommended_context_for_profile() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  if [[ "${thermal}" == "fanless" ]]; then
    echo 2048
    return
  fi
  if [[ "${throughput}" == "unknown" || -z "${throughput}" ]]; then
    case "${tier}" in
      constrained|standard) echo 2048 ;;
      high) echo 4096 ;;
      workstation|large) echo 8192 ;;
      *) echo 2048 ;;
    esac
    return
  fi
  case "${tier}" in
    constrained)
      echo 2048
      ;;
    standard)
      if throughput_at_least "${throughput}" fast; then
        echo 4096
      else
        echo 2048
      fi
      ;;
    high)
      if throughput_at_least "${throughput}" very_fast; then
        echo 8192
      else
        echo 4096
      fi
      ;;
    workstation|large)
      echo 8192
      ;;
    *)
      echo 2048
      ;;
  esac
}

# Emit: family|model|quantize|steps|width|height|low_ram
# family selects the mflux CLI; empty model means "package default".
# RAM-only standard is conservative 4-bit; fast cooled chips upgrade in
# recommended_image_profile_for_profile.
recommended_image_profile_for_tier() {
  local tier_id="${1:-}"
  case "${tier_id}" in
    constrained)
      echo "flux2|flux2-klein-4b|4|4|512|512|1"
      ;;
    standard)
      echo "flux2|flux2-klein-4b|4|4|768|768|1"
      ;;
    high|workstation|large)
      echo "z-image-turbo||8|9|1024|1024|0"
      ;;
    *)
      echo "flux2|flux2-klein-4b|4|4|768|768|1"
      ;;
  esac
}

# Fanless / slow 8 GB stay on the conservative Air profile (this M1 is the floor).
recommended_image_profile_for_profile() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  local family="${4:-0}"
  if [[ "${thermal}" == "fanless" || "${tier}" == "constrained" ]]; then
    echo "flux2|flux2-klein-4b|4|4|512|512|1"
    return
  fi
  if [[ "${throughput}" == "unknown" || -z "${throughput}" ]]; then
    recommended_image_profile_for_tier "${tier}"
    return
  fi
  case "${tier}" in
    standard)
      if throughput_at_least "${throughput}" fast; then
        echo "flux2|flux2-klein-4b|8|4|768|768|1"
      else
        echo "flux2|flux2-klein-4b|4|4|768|768|1"
      fi
      ;;
    high|workstation|large)
      echo "z-image-turbo||8|9|1024|1024|0"
      ;;
    *)
      recommended_image_profile_for_tier "${tier}"
      ;;
  esac
}

# Emit: family|model|width|height|frames|steps|tiling
# family selects the mlx-video CLI; wan21 model is a local converted dir name;
# ltx2 model is a Hugging Face repo. Empty steps means "pipeline default".
recommended_video_profile_for_tier() {
  local tier_id="${1:-}"
  case "${tier_id}" in
    constrained)
      echo "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
      ;;
    standard)
      echo "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
      ;;
    high)
      echo "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|33|10|auto"
      ;;
    workstation)
      echo "ltx2|${MLX_VIDEO_LTX_REPO}|512|512|33||auto"
      ;;
    large)
      echo "ltx2|${MLX_VIDEO_LTX_REPO}|768|512|65||auto"
      ;;
    *)
      echo "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
      ;;
  esac
}

# Never advertise LTX when RAM cannot hold it. Fanless stays on the short Wan clip.
recommended_video_profile_for_profile() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  local family="${4:-0}"
  local gpu_cores="${5:-0}"
  local frames=33
  [[ "${gpu_cores}" =~ ^[0-9]+$ ]] || gpu_cores=0
  if [[ "${thermal}" == "fanless" || "${tier}" == "constrained" ]]; then
    echo "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
    return
  fi
  if [[ "${throughput}" == "unknown" || -z "${throughput}" ]]; then
    recommended_video_profile_for_tier "${tier}"
    return
  fi
  case "${tier}" in
    standard)
      echo "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|17|10|auto"
      ;;
    high)
      frames=33
      if { throughput_at_least "${throughput}" very_fast || chip_has_gpu_nax "${family}"; } && (( gpu_cores >= 24 )); then
        frames=49
      fi
      echo "wan21|${MLX_VIDEO_WAN_MODEL_NAME}|832|480|${frames}|10|auto"
      ;;
    workstation)
      echo "ltx2|${MLX_VIDEO_LTX_REPO}|512|512|33||auto"
      ;;
    large)
      echo "ltx2|${MLX_VIDEO_LTX_REPO}|768|512|65||auto"
      ;;
    *)
      recommended_video_profile_for_tier "${tier}"
      ;;
  esac
}

# ≤8 GB always; 16 GB slow/moderate base chips / any fanless Air still need --force (UMT5 ~11 GB).
video_force_required_for_profile() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  if [[ "${tier}" == "constrained" ]]; then
    return 0
  fi
  if [[ "${thermal}" == "fanless" ]]; then
    return 0
  fi
  if [[ "${tier}" == "standard" ]] && ! throughput_at_least "${throughput}" fast; then
    return 0
  fi
  return 1
}

default_video_model_for_family() {
  case "$1" in
    wan21) echo "${MLX_VIDEO_WAN_MODEL_NAME}" ;;
    ltx2) echo "${MLX_VIDEO_LTX_REPO}" ;;
    *) echo "" ;;
  esac
}

video_cli_module_for_family() {
  case "$1" in
    wan21) echo "mlx_video.models.wan_2.generate" ;;
    ltx2) echo "mlx_video.models.ltx_2.generate" ;;
    *) return 1 ;;
  esac
}

# True when model is a known alias of a different family (do not pass it through).
video_model_conflicts_with_family() {
  local family="$1"
  local model="${2:-}"
  local lower
  [[ -n "${model}" ]] || return 1
  lower="$(printf '%s' "${model}" | tr '[:upper:]' '[:lower:]')"
  case "${family}" in
    ltx2)
      case "${lower}" in
        wan21*|wan2.1*|wan-ai/*) return 0 ;;
      esac
      ;;
    wan21)
      case "${lower}" in
        *ltx*|*lightricks*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# Round frames down to 4n+1 (Wan) or 8n+1 (LTX). Minimum one period + 1.
video_align_frames() {
  local family="$1"
  local frames="$2"
  local period=4
  [[ "${family}" == "ltx2" ]] && period=8
  if (( frames < 1 )); then
    echo $((period + 1))
    return
  fi
  if (( (frames - 1) % period == 0 )); then
    echo "${frames}"
    return
  fi
  local n=$(( (frames - 1) / period ))
  if (( n < 1 )); then
    echo $((period + 1))
    return
  fi
  echo $((n * period + 1))
}

video_align_dim() {
  local value="$1"
  local multiple="$2"
  if (( value < multiple )); then
    echo "${multiple}"
    return
  fi
  echo $(( (value / multiple) * multiple ))
}

default_wan_model_dir() {
  echo "${MLX_WORKSPACE}/models/video/${MLX_VIDEO_WAN_MODEL_NAME}"
}

wan_model_dir_ready() {
  local dir="${1:-}"
  [[ -n "${dir}" && -d "${dir}" ]] || return 1
  [[ -f "${dir}/config.json" && -f "${dir}/model.safetensors" && -f "${dir}/t5_encoder.safetensors" && -f "${dir}/vae.safetensors" ]]
}

# mflux preset id for a generate --family. Empty model in an image profile
# means this checkpoint (z-image-turbo's composed profile leaves model blank).
default_image_model_for_family() {
  case "$1" in
    flux2) echo "flux2-klein-4b" ;;
    z-image-turbo) echo "z-image-turbo" ;;
    schnell) echo "schnell" ;;
    *) echo "" ;;
  esac
}

model_list_chip_family_label() {
  if [[ -n "${OVERRIDE_MEMORY_TIER:-}" || -n "${OVERRIDE_CHIP_FAMILY:-}" || -n "${OVERRIDE_CHIP_SKU:-}" \
    || -n "${OVERRIDE_GPU_CORES:-}" || -n "${OVERRIDE_THERMAL_CLASS:-}" ]]; then
    printf '%s\n' "Chip family/SKU (policy):"
  else
    printf '%s\n' "Chip family/SKU:"
  fi
}

# Catalog rows for make list-image. id|family|upstream repo|weights|use
# Upstream repos are what mflux downloads for that preset. Fit is computed.
image_catalog_rows() {
  cat <<'EOF'
flux2-klein-4b|flux2|black-forest-labs/FLUX.2-klein-4B|4B, 4-bit or 8-bit|Floor image model; default through 18 GB and on every fanless Air
z-image-turbo|z-image-turbo|Tongyi-MAI/Z-Image-Turbo|8-bit, wants 24 GB+|Quality default on cooled 24 GB and up
schnell|schnell|black-forest-labs/FLUX.1-schnell|FLUX.1 schnell|Optional FLUX.1 path; not a composed default
EOF
}

# Checkpoint id from the composed image profile (empty model → family default).
image_list_default_id() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  local chip_family="${4:-0}"
  local profile fam model
  profile="$(recommended_image_profile_for_profile "${tier}" "${throughput}" "${thermal}" "${chip_family}")"
  IFS='|' read -r fam model _ <<<"${profile}"
  if [[ -z "${model}" ]]; then
    model="$(default_image_model_for_family "${fam}")"
  fi
  printf '%s\n' "${model}"
}

# default | fits | tight | poor. default matches image_list_default_id.
# z-image-turbo is the >=24 GB cooled default. Below that it is tight on
# 16-18 GB and on a 24-32 GB Air, and poor on <=8 GB. schnell is never default.
# On a fanless 24-32 GB Air, schnell is tight as well (12B is not a better fit
# than 6B z-image). Cooled high and workstation/large keep schnell as fits.
image_list_fit() {
  local id="${1:-}"
  local tier="${2:-}"
  local throughput="${3:-unknown}"
  local thermal="${4:-}"
  local chip_family="${5:-0}"
  local default
  default="$(image_list_default_id "${tier}" "${throughput}" "${thermal}" "${chip_family}")"
  if [[ "${id}" == "${default}" ]]; then
    printf '%s\n' default
    return
  fi
  case "${id}" in
    flux2-klein-4b)
      printf '%s\n' fits
      ;;
    z-image-turbo)
      case "${tier}" in
        constrained|"") printf '%s\n' poor ;;
        standard|high) printf '%s\n' tight ;;
        workstation|large) printf '%s\n' fits ;;
        *) printf '%s\n' poor ;;
      esac
      ;;
    schnell)
      case "${tier}" in
        constrained|"") printf '%s\n' poor ;;
        standard) printf '%s\n' tight ;;
        high)
          if [[ "${thermal}" == "fanless" ]]; then
            printf '%s\n' tight
          else
            printf '%s\n' fits
          fi
          ;;
        workstation|large) printf '%s\n' fits ;;
        *) printf '%s\n' poor ;;
      esac
      ;;
    *)
      printf '%s\n' poor
      ;;
  esac
}

# Human image list. Args override the composed profile so tests skip sysctl.
print_recommended_image_list() {
  local tier="${1:-${MLX_TIER_ID:-}}"
  local throughput="${2:-${MLX_POLICY_THROUGHPUT_CLASS:-${MLX_THROUGHPUT_CLASS:-unknown}}}"
  local thermal="${3:-${MLX_POLICY_THERMAL_CLASS:-${MLX_THERMAL_CLASS:-}}}"
  local chip="${4:-${MLX_CHIP:-unknown}}"
  local mem_gib="${5:-${MLX_MEM_GIB:-?}}"
  local chip_family="${6:-${MLX_POLICY_CHIP_FAMILY:-${MLX_CHIP_FAMILY:-?}}}"
  local sku="${7:-${MLX_POLICY_CHIP_SKU:-${MLX_CHIP_SKU:-?}}}"
  local physical="${8:-${MLX_PHYSICAL_TIER_ID:-${tier:-unknown}}}"
  local profile fam model quant steps width height low_ram
  local low_label quant_label chip_family_label row id locator weights use fit cached
  profile="$(recommended_image_profile_for_profile "${tier}" "${throughput}" "${thermal}" "${chip_family}")"
  IFS='|' read -r fam model quant steps width height low_ram <<<"${profile}"
  if [[ -z "${model}" ]]; then
    model="$(default_image_model_for_family "${fam}")"
  fi
  case "${low_ram}" in
    1) low_label="yes" ;;
    0) low_label="no" ;;
    *) low_label="${low_ram:-no}" ;;
  esac
  if [[ -n "${quant}" ]]; then
    quant_label="${quant}-bit"
  else
    quant_label="package default"
  fi
  chip_family_label="$(model_list_chip_family_label)"
  cat <<EOF
Apple chip:       ${chip}
${chip_family_label}  ${chip_family} ${sku}
Memory:           ${mem_gib} GiB
Memory tier:      ${tier:-unknown} (physical ${physical})
Thermal class:    ${thermal:-unknown}
Throughput class: ${throughput:-unknown}
Default image:    ${model}
Family:           ${fam}
Quantize:         ${quant_label}
Size:             ${width}x${height}
Steps:            ${steps}
Low RAM:          ${low_label}

fit is default (composed choice), fits, tight (measure first), or poor for this Mac.
cached is yes when the Hugging Face cache holds that preset's upstream repo
(model_index.json or config.json, plus a safetensors file, and no incomplete blob).
Nothing is downloaded.

EOF
  printf 'fit\tcached\tmodel\tweights\tuse\n'
  while IFS= read -r row; do
    [[ -z "${row}" || "${row}" == \#* ]] && continue
    IFS='|' read -r id _ locator weights use <<<"${row}"
    fit="$(image_list_fit "${id}" "${tier}" "${throughput}" "${thermal}" "${chip_family}")"
    cached=no
    if media_repo_cached "${locator}"; then
      cached=yes
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${fit}" "${cached}" "${id}" "${weights}" "${use}"
  done < <(image_catalog_rows)
  printf '\nOne image at a time: make image IMAGE_PROMPT="..."\n'
}

# Catalog rows for make list-video. id|family|locator|weights|use
# locator is "local" (converted Wan dir) or "hub" (Hugging Face repo id).
video_catalog_rows() {
  printf '%s\n' \
    "${MLX_VIDEO_WAN_MODEL_NAME}|wan21|local|UMT5 encoder ~11 GB|Wan2.1 T2V 1.3B 4-bit; convert once with make prepare-video" \
    "${MLX_VIDEO_LTX_REPO}|ltx2|hub|distilled, 36 GB+|Quality path on cooled 36 GB and up"
}

video_list_default_id() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  local chip_family="${4:-0}"
  local gpu_cores="${5:-0}"
  local profile fam model
  profile="$(recommended_video_profile_for_profile "${tier}" "${throughput}" "${thermal}" "${chip_family}" "${gpu_cores}")"
  IFS='|' read -r fam model _ <<<"${profile}"
  if [[ -z "${model}" ]]; then
    model="$(default_video_model_for_family "${fam}")"
  fi
  printf '%s\n' "${model}"
}

# default | fits | tight | poor. default matches video_list_default_id.
# LTX is the cooled workstation/large default. It is poor below 36 GB.
# On a fanless workstation the composed clip stays Wan, so LTX is tight.
# Wan is fits when LTX is the composed default.
video_list_fit() {
  local id="${1:-}"
  local tier="${2:-}"
  local throughput="${3:-unknown}"
  local thermal="${4:-}"
  local chip_family="${5:-0}"
  local gpu_cores="${6:-0}"
  local default
  default="$(video_list_default_id "${tier}" "${throughput}" "${thermal}" "${chip_family}" "${gpu_cores}")"
  if [[ "${id}" == "${default}" ]]; then
    printf '%s\n' default
    return
  fi
  case "${id}" in
    "${MLX_VIDEO_WAN_MODEL_NAME}")
      printf '%s\n' fits
      ;;
    "${MLX_VIDEO_LTX_REPO}")
      case "${tier}" in
        workstation|large)
          if [[ "${thermal}" == "fanless" ]]; then
            printf '%s\n' tight
          else
            printf '%s\n' fits
          fi
          ;;
        *)
          printf '%s\n' poor
          ;;
      esac
      ;;
    *)
      printf '%s\n' poor
      ;;
  esac
}

video_catalog_cached() {
  local id="${1:-}"
  local locator="${2:-}"
  case "${locator}" in
    local)
      wan_model_dir_ready "$(default_wan_model_dir)"
      ;;
    hub)
      media_repo_cached "${id}"
      ;;
    *)
      media_repo_cached "${locator}"
      ;;
  esac
}

# Human video list. Args override the composed profile so tests skip sysctl.
print_recommended_video_list() {
  local tier="${1:-${MLX_TIER_ID:-}}"
  local throughput="${2:-${MLX_POLICY_THROUGHPUT_CLASS:-${MLX_THROUGHPUT_CLASS:-unknown}}}"
  local thermal="${3:-${MLX_POLICY_THERMAL_CLASS:-${MLX_THERMAL_CLASS:-}}}"
  local chip="${4:-${MLX_CHIP:-unknown}}"
  local mem_gib="${5:-${MLX_MEM_GIB:-?}}"
  local chip_family="${6:-${MLX_POLICY_CHIP_FAMILY:-${MLX_CHIP_FAMILY:-?}}}"
  local sku="${7:-${MLX_POLICY_CHIP_SKU:-${MLX_CHIP_SKU:-?}}}"
  local physical="${8:-${MLX_PHYSICAL_TIER_ID:-${tier:-unknown}}}"
  local gpu_cores="${9:-${MLX_POLICY_GPU_CORES:-${MLX_GPU_CORES:-0}}}"
  local profile fam model width height frames steps _tiling
  local steps_label generate_label chip_family_label row id locator weights use fit cached
  [[ "${gpu_cores}" =~ ^[0-9]+$ ]] || gpu_cores=0
  profile="$(recommended_video_profile_for_profile "${tier}" "${throughput}" "${thermal}" "${chip_family}" "${gpu_cores}")"
  IFS='|' read -r fam model width height frames steps _tiling <<<"${profile}"
  if [[ -z "${model}" ]]; then
    model="$(default_video_model_for_family "${fam}")"
  fi
  if [[ -n "${steps}" ]]; then
    steps_label="${steps}"
  else
    steps_label="pipeline default"
  fi
  if video_force_required_for_profile "${tier}" "${throughput}" "${thermal}"; then
    generate_label="refused unless --force (UMT5 ~11 GB)"
  else
    generate_label="allowed"
  fi
  chip_family_label="$(model_list_chip_family_label)"
  cat <<EOF
Apple chip:       ${chip}
${chip_family_label}  ${chip_family} ${sku}
Memory:           ${mem_gib} GiB
Memory tier:      ${tier:-unknown} (physical ${physical})
Thermal class:    ${thermal:-unknown}
Throughput class: ${throughput:-unknown}
Default video:    ${model}
Family:           ${fam}
Size:             ${width}x${height}
Frames:           ${frames}
Steps:            ${steps_label}
Generate:         ${generate_label}

fit is default (composed choice), fits, tight (measure first), or poor for this Mac.
cached is yes for Wan when models/video/${MLX_VIDEO_WAN_MODEL_NAME} has config.json,
model.safetensors, t5_encoder.safetensors, and vae.safetensors. LTX is cached when
the distilled snapshot has every transformer, text-encoder, and VAE-decoder shard,
text projections, and a spatial x2 upscaler. Nothing is downloaded.

EOF
  printf 'fit\tcached\tmodel\tweights\tuse\n'
  while IFS= read -r row; do
    [[ -z "${row}" || "${row}" == \#* ]] && continue
    IFS='|' read -r id _ locator weights use <<<"${row}"
    fit="$(video_list_fit "${id}" "${tier}" "${throughput}" "${thermal}" "${chip_family}" "${gpu_cores}")"
    cached=no
    if video_catalog_cached "${id}" "${locator}"; then
      cached=yes
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${fit}" "${cached}" "${id}" "${weights}" "${use}"
  done < <(video_catalog_rows)
  printf '\nOne clip at a time: make video VIDEO_PROMPT="..."\n'
  printf 'Wan convert (once): make prepare-video\n'
}
