#!/usr/bin/env bash
# Model catalogs, hub cache probes, disk headroom, and human list output.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only



mlx_lm_help_has_flag() {
  local module="$1"
  local flag="$2"
  local py help
  py="$(venv_python)"
  [[ -x "${py}" ]] || return 1
  # Capture help first: grep -q under pipefail can SIGPIPE the writer on large --help.
  help="$("${py}" -m "${module}" --help 2>&1)" || return 1
  [[ "${help}" == *"${flag}"* ]]
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

# Print shard filenames from a safetensors index. No network.
# Uses a line loop so macOS /bin/bash 3.2 (no mapfile) can read the index.
_index_shard_names() {
  local index="${1:-}"
  local py
  [[ -f "${index}" ]] || return 1
  py="$(resolve_auxiliary_python)" || return 1
  "${py}" - "${index}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    weight_map = json.load(fh).get("weight_map") or {}
seen = sorted({name for name in weight_map.values() if isinstance(name, str) and name})
for name in seen:
    print(name)
PY
}

# Weight-bearing diffusers component names listed in model_index.json.

# Weight-bearing diffusers component names listed in model_index.json.
_model_index_weight_components() {
  local index="${1:-}"
  [[ -f "${index}" ]] || return 1
  python3 - "${index}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
if not isinstance(data, dict):
    sys.exit(0)
for key in sorted(data.keys()):
    if key.startswith("_"):
        continue
    if key in ("transformer", "unet", "vae") or key.startswith("text_encoder"):
        print(key)
PY
}

# config.json plus every non-empty shard named by model.safetensors.index.json.

# config.json plus every non-empty shard named by model.safetensors.index.json.
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
    [[ -s "${dir}/${shard}" ]] || return 1
    saw=1
  done < <(_index_shard_names "${index}")
  (( saw == 1 ))
}

# Indexed shards or at least one non-empty *.safetensors in this component dir.

# Indexed shards or at least one non-empty *.safetensors in this component dir.
_component_weights_ready() {
  local dir="${1%/}"
  local index="${dir}/model.safetensors.index.json"
  local nullglob_state w saw=0
  local -a weights
  [[ -d "${dir}" ]] || return 1
  if [[ -f "${index}" ]]; then
    _indexed_component_ready "${dir}"
    return
  fi
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  weights=( "${dir}/"*.safetensors )
  _restore_nullglob "${nullglob_state}"
  for w in "${weights[@]}"; do
    [[ -s "${w}" ]] || continue
    saw=1
    break
  done
  (( saw == 1 ))
}

# Standard diffusers subdirs that exist under snap (when model_index lists none).

# Standard diffusers subdirs that exist under snap (when model_index lists none).
_diffusers_component_dirs_present() {
  local snap="${1%/}/"
  local name="" nullglob_state
  local -a encoders
  for name in transformer unet vae text_encoder text_encoder_2 text_encoder_3; do
    [[ -d "${snap}${name}" ]] && printf '%s\n' "${name}"
  done
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  encoders=( "${snap}"text_encoder_*/ )
  _restore_nullglob "${nullglob_state}"
  for name in "${encoders[@]}"; do
    [[ -d "${name}" ]] || continue
    printf '%s\n' "${name##*/}"
  done
}

# Every weight-bearing diffusers component has non-empty weights.

# Every weight-bearing diffusers component has non-empty weights.
diffusers_snapshot_weights_ready() {
  local snap="${1%/}/"
  local index="${snap}model_index.json"
  local comp="" saw=0 has_main=0
  [[ -f "${index}" ]] || return 1
  while IFS= read -r comp; do
    [[ -n "${comp}" ]] || continue
    _component_weights_ready "${snap}${comp}" || return 1
    saw=1
    case "${comp}" in
      transformer|unet) has_main=1 ;;
    esac
  done < <(_model_index_weight_components "${index}")
  if (( saw == 1 )); then
    # model_index is authoritative, but a tree with no transformer/UNet is not
    # a complete image checkpoint (VAE-only indexes must not report cached).
    (( has_main == 1 )) || return 1
    return 0
  fi
  saw=0
  has_main=0
  while IFS= read -r comp; do
    [[ -n "${comp}" ]] || continue
    _component_weights_ready "${snap}${comp}" || return 1
    saw=1
    case "${comp}" in
      transformer|unet) has_main=1 ;;
      vae) ;;
      text_encoder*) ;;
      *) return 1 ;;
    esac
  done < <(_diffusers_component_dirs_present "${snap}")
  if (( saw == 0 )); then
    _snap_root_safetensors_ready "${snap}"
    return
  fi
  (( has_main == 1 )) || return 1
  _component_weights_ready "${snap}vae"
}

# Non-empty safetensors at the snapshot root (single-file hubs).

# Non-empty safetensors at the snapshot root (single-file hubs).
_snap_root_safetensors_ready() {
  local snap="${1%/}/"
  local index="${snap}model.safetensors.index.json"
  local nullglob_state w saw=0
  local -a weights
  if [[ -f "${index}" ]]; then
    _indexed_component_ready "${snap%/}"
    return
  fi
  if [[ -f "${snap}config.json" ]]; then
    hub_snapshot_weights_complete "${snap}"
    return
  fi
  nullglob_state="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  weights=( "${snap}"*.safetensors )
  _restore_nullglob "${nullglob_state}"
  for w in "${weights[@]}"; do
    [[ -s "${w}" ]] || continue
    saw=1
    break
  done
  (( saw == 1 ))
}

# Return 0 when snap holds config.json and loadable weight files (regular
# files only). Sharded repos must have every shard from weight_map. This
# does not contact the network.

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
    [[ -s "${w}" ]] || return 1
  done
  return 0
}

# yes when the hub cache holds a complete MLX snapshot for this repo id.

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

# True when dir holds at least one non-empty safetensors file.

# True when dir holds at least one non-empty safetensors file.
_dir_has_safetensors() {
  local dir="${1%/}"
  local path=""
  [[ -d "${dir}" ]] || return 1
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    [[ -s "${path}" ]] && return 0
  done < <(find "${dir}" -name '*.safetensors' \( -type f -o -type l \) -print 2>/dev/null)
  return 1
}

# prince-canuma/LTX-2-distilled layout that the pinned mlx-video distilled
# pipeline opens: transformer, text encoder, and VAE decoder shards, text
# projections, and a root spatial x2 upscaler. One root ltx-2-*.safetensors
# file is not enough. The distilled pipeline does not open the root LoRA file.

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

# True when a snapshot is a complete MLX tree, a full diffusers tree, or a
# single-file hub layout. Partial diffusers components and empty shards do
# not count. Incomplete blobs are rejected by media_repo_cached first. No
# network.

# True when a snapshot is a complete MLX tree, a full diffusers tree, or a
# single-file hub layout. Partial diffusers components and empty shards do
# not count. Incomplete blobs are rejected by media_repo_cached first. No
# network.
hub_repo_has_weights() {
  local repo_id="${1:-}"
  local cache folder snap nullglob_state
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
    if [[ -f "${snap}model_index.json" ]]; then
      if diffusers_snapshot_weights_ready "${snap}"; then
        _restore_nullglob "${nullglob_state}"
        return 0
      fi
      continue
    fi
    if [[ -f "${snap}config.json" ]]; then
      if hub_snapshot_weights_complete "${snap}"; then
        _restore_nullglob "${nullglob_state}"
        return 0
      fi
    fi
  done
  _restore_nullglob "${nullglob_state}"
  return 1
}

# MLX snapshot (config.json + every indexed weight shard) or a diffusers tree
# with weights. An incomplete blob or a partial shard index is not cached.
# Does not contact the network.

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
    core-pip|media-pip|image-pip|video-pip|image-generate)
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
# Profiles: core-pip, media-pip, image-pip, video-pip, image-weights,
# image-generate, video-weights, wan-generate, wan-prepare.

# Conservative free-space floors (whole GiB) before large downloads.
# Override one floor with the matching MLX_DISK_MIN_* variable.
# Profiles: core-pip, media-pip, image-pip, video-pip, image-weights,
# image-generate, video-weights, wan-generate, wan-prepare.
disk_floor_gib() {
  local profile="${1:-}"
  case "${profile}" in
    core-pip) printf '%s\n' "${MLX_DISK_MIN_CORE_GIB:-12}" ;;
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
cached is yes when that repo has config.json and every non-empty weight file on
disk (including all shards listed in model.safetensors.index.json when present).

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

# Round frames down to 4n+1 (Wan) or 8n+1 (LTX). Minimum one period + 1.
# Reject non-integers before any arithmetic so a models.env or flag value
# cannot be evaluated as a bash expression.
video_align_frames() {
  local family="$1"
  local frames="$2"
  local period=4
  require_media_count "frame count" "${frames}"
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
  require_media_count "dimension" "${value}"
  require_media_count "dimension multiple" "${multiple}"
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


# Catalog rows for make list-image. id|family|upstream repo|weights|use
# Upstream repos are what mflux downloads for that preset. Fit is computed.
image_catalog_rows() {
  cat <<'EOF'
flux2-klein-4b|flux2|black-forest-labs/FLUX.2-klein-4B|4B, 4-bit or 8-bit|Floor image model; default through 18 GB and on every fanless Air
z-image-turbo|z-image-turbo|Tongyi-MAI/Z-Image-Turbo|8-bit, wants 24 GB+|Quality default on cooled 24 GB and up
schnell|schnell|black-forest-labs/FLUX.1-schnell|FLUX.1 schnell|Optional FLUX.1 path; not a composed default
EOF
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
(every diffusers weight component with non-empty shards, or a complete single-file
layout, and no incomplete blob). Nothing is downloaded.

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
