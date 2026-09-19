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
MLX_CORE_PACKAGES=(mlx mlx-lm)
MLX_MEDIA_PACKAGES=(mlx-audio)
MLX_IMAGE_PACKAGE="${MLX_IMAGE_PACKAGE:-mflux==0.19.1}"
# Pin mlx-video to a git SHA (not published on PyPI). Override with MLX_VIDEO_PACKAGE.
MLX_VIDEO_PACKAGE="${MLX_VIDEO_PACKAGE:-git+https://github.com/Blaizzy/mlx-video.git@87db56a51758fefb748a359b90a5283bb8ba4837}"
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

assert_apple_silicon() {
  local arch
  arch="$(detect_architecture)"
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

# Probe mx.set_wired_limit / set_memory_limit / set_cache_limit from the Metal working set.
# Limits are process-local: this subprocess cannot enforce them on later CLI processes.
# Used by validate-mlx.sh as an API/working-set check. Constrained never exceeds
# max_recommended_working_set_size. Prints KEY=value lines. No-op when mlx/Metal is missing.
apply_mlx_runtime_limits() {
  local py="${1:-$(venv_python)}"
  local tier="${2:-${MLX_TIER_ID:-}}"
  [[ -x "${py}" ]] || return 0
  MLX_LIMIT_TIER="${tier}" "${py}" - <<'PY' 2>/dev/null || true
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
print("working_set_bytes=%s" % (ws if ws else "",))
print("gpu_arch=%s" % (arch,))
print("memory_size_bytes=%s" % (memsize if memsize else "",))
if ws <= 0:
    sys.exit(0)

wired = ws
if tier == "constrained":
    memory = ws
    cache = max(ws // 4, 1)
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
  # Available space on the volume containing MLX_WORKSPACE (or /).
  local target="${1:-/}"
  df -g "${target}" 2>/dev/null | awk 'NR==2 {print $4}'
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
  printf 'MLX_WORKING_SET_BYTES=%q\n' "${MLX_WORKING_SET_BYTES:-}"
  printf 'MLX_GPU_ARCH=%q\n' "${MLX_GPU_ARCH:-}"
  printf 'MLX_WORKSPACE=%q\n' "${MLX_WORKSPACE:-}"
}

upsert_env_assignment() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v k="${key}" -v v="${value}" '
    BEGIN { done=0 }
    index($0, k "=") == 1 && !done { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
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
MLX_DEFAULT_MODEL=${model}
MLX_RECOMMENDED_CONTEXT=${context}
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
