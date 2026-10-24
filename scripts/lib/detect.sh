#!/usr/bin/env bash
# Hardware detection, chip parsing, memory tier, and detect --env output.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
# shellcheck disable=SC2034



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


# Parse machdep.cpu.brand_string. Longest SKU match: Ultra, then Max, then Pro, then base.
# "Apple M1 Pro" → family 1, sku pro (not base). "Apple M10" → family 10 (not 1).
# Emit: family|sku   (empty fields on failure)
parse_apple_chip_brand() {
  local brand family rest
  brand="$(trim_whitespace "${1:-}")"
  # Suffix SKUs via rest (not ERE \\ Pro) so /bin/bash 3.2 on macOS matches GNU bash 5.
  if [[ "${brand}" =~ ^Apple[[:space:]]M([0-9]+) ]]; then
    family="${BASH_REMATCH[1]}"
    rest="${brand#Apple M"${family}"}"
    printf '%s|' "${family}"
    case "${rest}" in
      " Ultra") printf 'ultra\n' ;;
      " Max") printf 'max\n' ;;
      " Pro") printf 'pro\n' ;;
      "") printf 'base\n' ;;
      *)
        printf '|\n'
        return 1
        ;;
    esac
    return 0
  fi
  printf '|\n'
  return 1
}

# Unified-memory bandwidth (GB/s) from family+SKU. Max variants use gpu_cores when bins differ.
# Empty output = unknown chip (RAM-only policy). Small table, not a per-retail-SKU encyclopedia.

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

# Fanless when hw.model is a MacBook Air.
# M1 keeps the MacBookAir* prefix. Later Airs use MacNN,N identifiers.
# M2–M4 IDs are from Apple Support "Identify your MacBook Air model"
# (https://support.apple.com/en-us/102869). Mac17,3 and Mac17,4 are M5 Air
# IDs from third-party listings and are not on that page yet.

# Fanless when hw.model is a MacBook Air.
# M1 keeps the MacBookAir* prefix. Later Airs use MacNN,N identifiers.
# M2–M4 IDs are from Apple Support "Identify your MacBook Air model"
# (https://support.apple.com/en-us/102869). Mac17,3 and Mac17,4 are M5 Air
# IDs from third-party listings and are not on that page yet.
classify_thermal_class() {
  local model="${1:-}"
  case "${model}" in
    MacBookAir*|Mac14,2|Mac14,15|Mac15,12|Mac15,13|Mac16,12|Mac16,13|Mac17,3|Mac17,4)
      echo "fanless"
      ;;
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


assert_minimum_macos_for_mlx() {
  local ver major
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  ver="$(detect_macos_version 2>/dev/null)" || ver=""
  major="${ver%%.*}"
  [[ -n "${major}" && "${major}" =~ ^[0-9]+$ ]] \
    || die "Could not parse macOS version from sw_vers (got: ${ver}). See docs/troubleshooting.md#macos-version"
  if [[ "${major}" -lt "${MLX_MACOS_VERSION_MIN_MAJOR}" ]]; then
    die "macOS ${ver} is below the minimum supported major version (${MLX_MACOS_VERSION_MIN_MAJOR}). Supported: macOS ${MLX_MACOS_VERSION_MIN_MAJOR} or newer on Apple Silicon only. See docs/troubleshooting.md#macos-version"
  fi
  if [[ "${major}" -gt "${MLX_MACOS_VERSION_CI_NEWEST_MAJOR}" ]]; then
    log_warn "macOS ${ver} is newer than macOS ${MLX_MACOS_VERSION_CI_NEWEST_MAJOR}, the newest major version CI smoke-tests today. Report issues if make install or make validate fails."
  fi
}


detect_disk_available_gib() {
  # Available space (whole GiB) on the volume containing the path.
  # Returns empty when df fails (do not treat as 0 GiB free).
  local target="${1:-/}"
  local avail=""
  avail="$(df -g "${target}" 2>/dev/null | awk 'NR==2 {print $4}')" || true
  if [[ "${avail}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${avail}"
  fi
}

# Remember a caller-supplied MLX_DISK_AVAIL_GIB before detection overwrites it.
# Idempotent: a later measurement must not become the override.

# Remember a caller-supplied MLX_DISK_AVAIL_GIB before detection overwrites it.
# Idempotent: a later measurement must not become the override.
note_disk_avail_override() {
  if [[ -n "${MLX_DISK_OVERRIDE_NOTED:-}" ]]; then
    return 0
  fi
  MLX_DISK_OVERRIDE_NOTED=1
  if [[ -n "${MLX_DISK_AVAIL_GIB:-}" && "${MLX_DISK_AVAIL_GIB}" =~ ^[0-9]+$ ]]; then
    MLX_DISK_AVAIL_GIB_OVERRIDE="${MLX_DISK_AVAIL_GIB}"
  else
    MLX_DISK_AVAIL_GIB_OVERRIDE=""
  fi
}

# df needs an existing directory. Walk up so a not-yet-created cache still
# names the volume that will hold it.

detect_python_version() {
  local py
  if [[ -x "${MLX_VENV}/bin/python" ]]; then
    "${MLX_VENV}/bin/python" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'
  elif py="$(resolve_auxiliary_python 2>/dev/null)" && [[ -n "${py}" ]]; then
    "${py}" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'
  else
    echo "none"
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
Disk available:   ${MLX_DISK_AVAIL_GIB:-unknown} GiB (workspace volume)
Python version:   $(detect_python_version)
Workspace:        ${MLX_WORKSPACE}
Recommended:      ${MLX_TIER_HINT}
Default model:    ${MLX_RECOMMENDED_MODEL}
Default context:  ${MLX_RECOMMENDED_CONTEXT}
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
  if [[ -n "${MLX_DISK_AVAIL_GIB:-}" && "${MLX_DISK_AVAIL_GIB}" =~ ^[0-9]+$ ]]; then
    printf 'MLX_DISK_AVAIL_GIB=%q\n' "${MLX_DISK_AVAIL_GIB}"
  else
    # Empty when df failed: do not emit "unknown" (sourcing would disable later df checks).
    printf 'MLX_DISK_AVAIL_GIB=%q\n' ""
  fi
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

