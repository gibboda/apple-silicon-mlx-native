#!/usr/bin/env bash
# Generate a video with Pure MLX mlx-video using memory-tier defaults.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/generate-mlx-video.sh --prompt "a red fox running through snow"
#   make video VIDEO_PROMPT="a red fox running through snow"
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROMPT="${VIDEO_PROMPT:-}"
FAMILY=""
MODEL=""
WIDTH=""
HEIGHT=""
FRAMES=""
STEPS=""
SEED=""
OUTPUT=""
TILING=""
IMAGE=""
CUSTOM_OUTPUT=0
DUMP_PLAN=0
FORCE=0
PASSTHRU=()
CLI_FAMILY=""
CLI_MODEL=""
CLI_MODEL_DIR=""
CLI_MODEL_REPO=""
CLI_WIDTH=""
CLI_HEIGHT=""
CLI_FRAMES=""
CLI_STEPS=""
CLI_TILING=""
CLI_PIPELINE=""
PIPELINE=""

usage() {
  cat <<'EOF'
Usage: generate-mlx-video.sh --prompt TEXT [options]

Generate an MP4 with mlx-video (Pure MLX). Requires `make install-video`.
Wan2.1 1.3B also requires `scripts/prepare-mlx-video-wan.sh` once.

Options:
  --prompt TEXT       Text prompt (required; or VIDEO_PROMPT)
  --family NAME       wan21 | ltx2 (CLI/checkpoint; default: memory-tier profile)
  --model NAME        Wan converted dir name / path, or LTX Hugging Face repo
  --model-dir PATH    Wan converted MLX directory (overrides --model for wan21)
  --model-repo REPO   LTX Hugging Face repo (overrides --model for ltx2)
  --width N           Video width
  --height N          Video height
  --frames N          Frame count (Wan: 4n+1; LTX: 8n+1)
  --steps N           Diffusion steps (Wan; LTX distilled ignores this)
  --seed N            RNG seed
  --output PATH       Output MP4 (default: outputs/videos/mlx-<timestamp>.mp4)
  --image PATH        Optional first-frame image (I2V; must exist under MLX_WORKSPACE)
  --pipeline NAME     LTX pipeline (default: distilled; or MLX_VIDEO_LTX_PIPELINE)
  --tiling MODE       VAE tiling: auto|none|default|aggressive|conservative|spatial|temporal
  --force             Allow generate when the composed profile refuses (8 GB, 16 GB slow/moderate base chips (M1–M4), fanless Airs)
  --dump-plan         Print resolved plan and exit
  --                  Extra args passed through to mlx-video
  -h, --help          Show this help

Defaults come from the composed profile (memory tier + throughput class +
thermal class, or OVERRIDE_MEMORY_TIER / OVERRIDE_CHIP_* / OVERRIDE_THERMAL_CLASS),
then config/models.env (MLX_VIDEO_*). --family changes the mlx-video module and
default checkpoint only; width/height/frames/steps/tiling still follow the composed
profile unless you set those flags or MLX_VIDEO_*. Dimensions and frames are aligned
to the selected family (Wan 4n+1 / LTX 8n+1 and 64px).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --prompt)
      [[ $# -ge 2 ]] || die "--prompt requires TEXT"
      PROMPT="$2"
      shift 2
      ;;
    --family)
      [[ $# -ge 2 ]] || die "--family requires NAME"
      CLI_FAMILY="$2"
      FAMILY="$2"
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || die "--model requires NAME"
      CLI_MODEL="$2"
      MODEL="$2"
      shift 2
      ;;
    --model-dir)
      [[ $# -ge 2 ]] || die "--model-dir requires PATH"
      CLI_MODEL_DIR="$2"
      shift 2
      ;;
    --model-repo)
      [[ $# -ge 2 ]] || die "--model-repo requires REPO"
      CLI_MODEL_REPO="$2"
      shift 2
      ;;
    --width)
      [[ $# -ge 2 ]] || die "--width requires N"
      CLI_WIDTH="$2"
      WIDTH="$2"
      shift 2
      ;;
    --height)
      [[ $# -ge 2 ]] || die "--height requires N"
      CLI_HEIGHT="$2"
      HEIGHT="$2"
      shift 2
      ;;
    --frames)
      [[ $# -ge 2 ]] || die "--frames requires N"
      CLI_FRAMES="$2"
      FRAMES="$2"
      shift 2
      ;;
    --steps)
      [[ $# -ge 2 ]] || die "--steps requires N"
      CLI_STEPS="$2"
      STEPS="$2"
      shift 2
      ;;
    --seed)
      [[ $# -ge 2 ]] || die "--seed requires N"
      SEED="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die "--output requires PATH"
      OUTPUT="$2"
      CUSTOM_OUTPUT=1
      shift 2
      ;;
    --image)
      [[ $# -ge 2 ]] || die "--image requires PATH"
      IMAGE="$2"
      shift 2
      ;;
    --tiling)
      [[ $# -ge 2 ]] || die "--tiling requires MODE"
      CLI_TILING="$2"
      TILING="$2"
      shift 2
      ;;
    --pipeline)
      [[ $# -ge 2 ]] || die "--pipeline requires NAME"
      CLI_PIPELINE="$2"
      shift 2
      ;;
    --force) FORCE=1; shift ;;
    --dump-plan) DUMP_PLAN=1; shift ;;
    --)
      shift
      PASSTHRU+=("$@")
      break
      ;;
    *) die "Unknown argument: $1 (use -- to pass flags through to mlx-video)" ;;
  esac
done

if [[ -z "${PROMPT}" ]]; then
  usage >&2
  die "Missing --prompt (or VIDEO_PROMPT). Example: scripts/generate-mlx-video.sh --prompt \"a red fox running through snow\""
fi

load_models_env

SEED="${SEED:-${MLX_VIDEO_SEED:-}}"
IMAGE="${IMAGE:-${MLX_VIDEO_IMAGE:-}}"

if (( DUMP_PLAN == 0 )); then
  PY="$(venv_python)"
  if [[ ! -x "${PY}" ]]; then
    die "Python venv not found at ${MLX_VENV}. Run: make install && make install-video"
  fi
  assert_apple_silicon
fi
if (( DUMP_PLAN == 1 )); then
  MLX_SKIP_DEVICE_PROBE=1
fi
load_runtime_profile

if (( DUMP_PLAN == 0 )) && (( FORCE == 0 )) && ! is_truthy "${MLX_VIDEO_FORCE:-}"; then
  if [[ "${MLX_VIDEO_FORCE_REQUIRED}" == "1" ]] || { [[ -n "${MLX_MEM_GIB:-}" ]] && (( MLX_MEM_GIB <= 8 )); }; then
    die "Text-to-video needs more unified memory than this profile allows (UMT5 text encoder ~11 GB). 8 GB, 16 GB slow/moderate base chips (M1–M4), and fanless Airs refuse unless you pass --force or set MLX_VIDEO_FORCE=1 (expect failure or extreme swap)."
  fi
fi

profile="${MLX_RECOMMENDED_VIDEO_PROFILE:-$(recommended_video_profile_for_tier "${MLX_TIER_ID}")}"
IFS='|' read -r def_family def_model def_width def_height def_frames def_steps def_tiling <<<"${profile}"

FAMILY="${CLI_FAMILY:-${MLX_VIDEO_FAMILY:-${def_family}}}"
WIDTH="${CLI_WIDTH:-${MLX_VIDEO_WIDTH:-${def_width}}}"
HEIGHT="${CLI_HEIGHT:-${MLX_VIDEO_HEIGHT:-${def_height}}}"
FRAMES="${CLI_FRAMES:-${MLX_VIDEO_FRAMES:-${def_frames}}}"
if [[ -n "${CLI_STEPS}" ]]; then
  STEPS="${CLI_STEPS}"
elif [[ -n "${MLX_VIDEO_STEPS:-}" ]]; then
  STEPS="${MLX_VIDEO_STEPS}"
else
  STEPS="${def_steps}"
fi
TILING="${CLI_TILING:-${MLX_VIDEO_TILING:-${def_tiling}}}"
PIPELINE="${CLI_PIPELINE:-${MLX_VIDEO_LTX_PIPELINE:-distilled}}"

if [[ -n "${CLI_MODEL}" ]]; then
  MODEL="${CLI_MODEL}"
elif [[ -n "${MLX_VIDEO_MODEL:-}" ]] && ! video_model_conflicts_with_family "${FAMILY}" "${MLX_VIDEO_MODEL}"; then
  MODEL="${MLX_VIDEO_MODEL}"
elif [[ "${FAMILY}" == "${def_family}" ]]; then
  MODEL="${def_model}"
else
  MODEL="$(default_video_model_for_family "${FAMILY}")"
fi
if [[ -z "${MODEL}" ]]; then
  MODEL="$(default_video_model_for_family "${FAMILY}")"
fi
if video_model_conflicts_with_family "${FAMILY}" "${MODEL}"; then
  die "Model '${MODEL}' cannot be used with family '${FAMILY}'. Omit --model or pass a ${FAMILY} checkpoint."
fi

cli_mod="$(video_cli_module_for_family "${FAMILY}")" \
  || die "Unknown --family ${FAMILY}. Use wan21 or ltx2."

if [[ -n "${CLI_FRAMES}" ]]; then
  aligned="$(video_align_frames "${FAMILY}" "${CLI_FRAMES}")"
  if [[ "${aligned}" != "${CLI_FRAMES}" ]]; then
    die "Frame count ${CLI_FRAMES} is invalid for family ${FAMILY} (Wan: 4n+1, LTX: 8n+1). Closest valid value: ${aligned}"
  fi
else
  FRAMES="$(video_align_frames "${FAMILY}" "${FRAMES}")"
fi

if [[ "${FAMILY}" == "ltx2" ]]; then
  if [[ -n "${CLI_WIDTH}" ]] && (( CLI_WIDTH % 64 != 0 )); then
    die "LTX width must be divisible by 64 (got ${CLI_WIDTH})"
  fi
  if [[ -n "${CLI_HEIGHT}" ]] && (( CLI_HEIGHT % 64 != 0 )); then
    die "LTX height must be divisible by 64 (got ${CLI_HEIGHT})"
  fi
  WIDTH="$(video_align_dim "${WIDTH}" 64)"
  HEIGHT="$(video_align_dim "${HEIGHT}" 64)"
fi

MODEL_DIR=""
MODEL_REPO=""
if [[ "${FAMILY}" == "wan21" ]]; then
  if [[ -n "${CLI_MODEL_DIR}" ]]; then
    MODEL_DIR="${CLI_MODEL_DIR}"
  elif [[ -n "${MLX_VIDEO_MODEL_DIR:-}" ]]; then
    MODEL_DIR="${MLX_VIDEO_MODEL_DIR}"
  elif [[ "${MODEL}" == /* || "${MODEL}" == ./* || "${MODEL}" == ../* ]]; then
    MODEL_DIR="${MODEL}"
  else
    MODEL_DIR="${MLX_WORKSPACE}/models/video/${MODEL}"
  fi
else
  if [[ -n "${CLI_MODEL_REPO}" ]]; then
    MODEL_REPO="${CLI_MODEL_REPO}"
  elif [[ -n "${MLX_VIDEO_MODEL_REPO:-}" ]]; then
    MODEL_REPO="${MLX_VIDEO_MODEL_REPO}"
  else
    MODEL_REPO="${MODEL}"
  fi
fi

if (( CUSTOM_OUTPUT )); then
  assert_workspace_safe
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  resolved_output="$(canonical_path "${OUTPUT}")" || die "Cannot resolve output path: ${OUTPUT}"
  path_is_within "${resolved_output}" "${ws}" \
    || die "Output path must be under MLX_WORKSPACE (${ws}): ${OUTPUT}"
  OUTPUT="${resolved_output}"
fi

if [[ -n "${IMAGE}" ]]; then
  assert_workspace_safe
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  [[ -f "${IMAGE}" ]] || die "Image file not found: ${IMAGE}"
  resolved_image="$(canonical_path "${IMAGE}")" || die "Cannot resolve image path: ${IMAGE}"
  path_is_within "${resolved_image}" "${ws}" \
    || die "Image path must be under MLX_WORKSPACE (${ws}): ${IMAGE}"
  IMAGE="${resolved_image}"
fi

STEPS_PLAN="${STEPS:-default}"
if (( DUMP_PLAN == 1 )); then
  printf 'family=%s\nmodel=%s\ncli=%s\ntier=%s\nthroughput_class=%s\nthermal_class=%s\nchip_family=%s\nchip_sku=%s\ngpu_cores=%s\nwidth=%s\nheight=%s\nframes=%s\nsteps=%s\ntiling=%s\npipeline=%s\nmodel_dir=%s\nmodel_repo=%s\nforce_required=%s\n' \
    "${FAMILY}" "${MODEL}" "${cli_mod}" "${MLX_TIER_ID}" \
    "${MLX_POLICY_THROUGHPUT_CLASS:-${MLX_THROUGHPUT_CLASS:-}}" \
    "${MLX_POLICY_THERMAL_CLASS:-${MLX_THERMAL_CLASS:-}}" \
    "${MLX_POLICY_CHIP_FAMILY:-${MLX_CHIP_FAMILY:-}}" \
    "${MLX_POLICY_CHIP_SKU:-${MLX_CHIP_SKU:-}}" \
    "${MLX_POLICY_GPU_CORES:-${MLX_GPU_CORES:-}}" \
    "${WIDTH}" "${HEIGHT}" "${FRAMES}" "${STEPS_PLAN}" "${TILING}" "${PIPELINE}" "${MODEL_DIR}" "${MODEL_REPO}" \
    "${MLX_VIDEO_FORCE_REQUIRED:-0}"
  exit 0
fi

require_cmd ffmpeg "Install with: brew install ffmpeg"

if ! "${PY}" -c "import mlx_video" >/dev/null 2>&1; then
  die "mlx-video is not importable. Run: make install-video"
fi

if [[ "${FAMILY}" == "wan21" ]]; then
  if ! wan_model_dir_ready "${MODEL_DIR}"; then
    die "Wan MLX model directory is not ready (${MODEL_DIR}). Run: scripts/prepare-mlx-video-wan.sh"
  fi
fi

if [[ -z "${OUTPUT}" ]]; then
  mkdir -p "${MLX_WORKSPACE}/outputs/videos"
  OUTPUT="${MLX_WORKSPACE}/outputs/videos/mlx-$(date +%Y%m%d-%H%M%S).mp4"
else
  mkdir -p "$(dirname "${OUTPUT}")"
fi

if [[ -n "${MLX_MEM_GIB:-}" ]] && (( MLX_MEM_GIB <= 8 )); then
  log_warn "8 GB: text-to-video is not practical (UMT5 ~11 GB). Stop mlx_lm.server; expect failure or extreme swap."
elif [[ "${MLX_VIDEO_FORCE_REQUIRED}" == "1" ]]; then
  log_warn "This chip/thermal profile still treats video as --force-only (UMT5 ~11 GB). Expect swap."
elif [[ -n "${MLX_MEM_GIB:-}" ]] && (( MLX_MEM_GIB < 24 )); then
  log_warn "Under 24 GB: expecting swap. Stop mlx_lm.server and other GPU/memory-heavy apps first."
fi

cmd=("${PY}" -m "${cli_mod}" --prompt "${PROMPT}" --width "${WIDTH}" --height "${HEIGHT}")

if [[ "${FAMILY}" == "wan21" ]]; then
  cmd+=(--model-dir "${MODEL_DIR}" --num-frames "${FRAMES}" --output-path "${OUTPUT}" --tiling "${TILING}")
  if [[ -n "${STEPS}" ]]; then
    cmd+=(--steps "${STEPS}")
  fi
else
  cmd+=(--model-repo "${MODEL_REPO}" --num-frames "${FRAMES}" --output-path "${OUTPUT}" --tiling "${TILING}")
  if [[ -n "${PIPELINE}" ]]; then
    cmd+=(--pipeline "${PIPELINE}")
  fi
  if [[ -n "${STEPS}" ]]; then
    cmd+=(--steps "${STEPS}")
  fi
fi

if [[ -n "${SEED}" ]]; then
  cmd+=(--seed "${SEED}")
fi
if [[ -n "${IMAGE}" ]]; then
  cmd+=(--image "${IMAGE}")
fi
if ((${#PASSTHRU[@]} > 0)); then
  cmd+=("${PASSTHRU[@]}")
fi

log_header "MLX text-to-video"
log_info "family=${FAMILY} model=${MODEL} ${WIDTH}x${HEIGHT} frames=${FRAMES} steps=${STEPS_PLAN} tiling=${TILING}"
log_info "output=${OUTPUT}"
"${cmd[@]}"
log_ok "Wrote ${OUTPUT}"
