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
  command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
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
  local mem_gib="$1"
  if (( mem_gib <= 8 )); then
    echo "constrained|8 GB — constrained|3B–4B 4-bit models, short context"
  elif (( mem_gib <= 16 )); then
    echo "standard|16 GB — standard|3B–8B 4-bit models"
  elif (( mem_gib <= 32 )); then
    echo "high|24–32 GB — high|7B–14B 4-bit / selected 8-bit"
  elif (( mem_gib <= 64 )); then
    echo "workstation|36–64 GB — workstation|14B–32B 4-bit / larger 8-bit"
  else
    echo "large| >64 GB — large-memory workstation|30B+ quantized / multi-model server"
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

print_hardware_summary() {
  local arch chip mem_bytes mem_gib cores macos disk py tier_line tier_id tier_label tier_hint
  arch="$(detect_architecture)"
  chip="$(detect_chip)"
  mem_bytes="$(detect_memory_bytes)"
  mem_gib="$(bytes_to_gib "${mem_bytes}")"
  cores="$(detect_cpu_cores)"
  macos="$(detect_macos_version)"
  disk="$(detect_disk_available_gib "${MLX_WORKSPACE}")"
  py="$(detect_python_version)"
  tier_line="$(classify_memory_tier "${mem_gib}")"
  IFS='|' read -r tier_id tier_label tier_hint <<<"${tier_line}"

  cat <<EOF
Architecture:     ${arch}
Apple chip:       ${chip}
Memory:           ${mem_gib} GiB (${mem_bytes} bytes)
Memory tier:      ${tier_label}
CPU cores:        ${cores}
macOS version:    ${macos}
Disk available:   ${disk} GiB (workspace volume)
Python version:   ${py}
Workspace:        ${MLX_WORKSPACE}
Recommended:      ${tier_hint}
EOF
}

export_detect_env() {
  # Export machine-consumable variables for other scripts.
  local mem_bytes mem_gib tier_line
  mem_bytes="$(detect_memory_bytes)"
  mem_gib="$(bytes_to_gib "${mem_bytes}")"
  tier_line="$(classify_memory_tier "${mem_gib}")"
  IFS='|' read -r MLX_TIER_ID MLX_TIER_LABEL MLX_TIER_HINT <<<"${tier_line}"

  export MLX_ARCH
  export MLX_CHIP
  export MLX_MEM_BYTES
  export MLX_MEM_GIB
  export MLX_CPU_CORES
  export MLX_MACOS_VERSION
  export MLX_DISK_AVAIL_GIB
  export MLX_TIER_ID
  export MLX_TIER_LABEL
  export MLX_TIER_HINT

  MLX_ARCH="$(detect_architecture)"
  MLX_CHIP="$(detect_chip)"
  MLX_MEM_BYTES="${mem_bytes}"
  MLX_MEM_GIB="${mem_gib}"
  MLX_CPU_CORES="$(detect_cpu_cores)"
  MLX_MACOS_VERSION="$(detect_macos_version)"
  MLX_DISK_AVAIL_GIB="$(detect_disk_available_gib "${MLX_WORKSPACE}")"
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
