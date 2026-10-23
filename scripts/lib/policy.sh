#!/usr/bin/env bash
# Composed defaults, inference limits, fit labels, and family conflict checks.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
# shellcheck disable=SC2034

# shellcheck source=policy_fit_rules.sh
# shellcheck disable=SC1091
source "${SCRIPT_LIB_DIR}/policy_fit_rules.sh"

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
  local _family="${4:-0}"
  text_default_model_for_profile "${tier}" "${throughput}" "${thermal}"
}

# Catalog rows from docs/models.md. id|approx weights|use
# Fit labels are computed for the composed profile, not stored here.

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
  text_model_fit_from_rule "${id}" "${tier}" "${throughput}" "${thermal}"
}

# Human list for this Mac. Args override the composed profile so tests can
# pass a fixture without sysctl. Empty args use the loaded MLX_* policy.

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

# True when model is a known alias of a different family (do not pass it through).

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
# Reject non-integers before any arithmetic so a models.env or flag value
# cannot be evaluated as a bash expression.

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
  image_model_fit_from_rule "${id}" "${tier}" "${throughput}" "${thermal}" "${chip_family}"
}

# Human image list. Args override the composed profile so tests skip sysctl.

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
  video_model_fit_from_rule "${id}" "${tier}" "${throughput}" "${thermal}" "${chip_family}" "${gpu_cores}"
}

