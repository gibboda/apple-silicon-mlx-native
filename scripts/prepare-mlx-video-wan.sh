#!/usr/bin/env bash
# Download Wan2.1 T2V 1.3B and convert it to MLX 4-bit for mlx-video.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Conversion loads original .pth T5/VAE with torch (weight loading only).
# Generation itself remains MLX. Does not install torch automatically.
#
# Usage:
#   scripts/prepare-mlx-video-wan.sh
#   scripts/prepare-mlx-video-wan.sh --force
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

FORCE=0

usage() {
  cat <<'EOF'
Usage: prepare-mlx-video-wan.sh [--force] [-h|--help]

Download Wan-AI/Wan2.1-T2V-1.3B and convert it to an MLX 4-bit directory
for scripts/generate-mlx-video.sh (family wan21).

Requires `make install-video`. Conversion of the original T5/VAE .pth
files needs torch in the venv (not installed automatically). Reuse
torch from `make install-image` when present, or install manually.
mlx-video does not use torch as the generation backend.

  --force   Re-download/convert even if the converted directory exists
  -h        Show this help

Writes:
  models/video/src/Wan2.1-T2V-1.3B     (upstream snapshot)
  models/video/wan21-t2v-1.3b-q4       (converted MLX weights)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

log_header "Prepare Wan2.1 T2V 1.3B (MLX 4-bit)"

PY="$(venv_python)"
if [[ ! -x "${PY}" ]]; then
  die "Python venv not found at ${MLX_VENV}. Run: make install && make install-video"
fi

assert_apple_silicon
assert_workspace_safe
export_detect_env

if ! "${PY}" -c "import mlx_video" >/dev/null 2>&1; then
  die "mlx-video is not importable. Run: make install-video"
fi

if ! "${PY}" -c "import torch" >/dev/null 2>&1; then
  die "torch is required to load Wan .pth T5/VAE weights (conversion only, not a generation backend). Reuse torch from make install-image if already present, otherwise install into the venv: ${MLX_VENV}/bin/pip install 'torch==2.14.0'"
fi

src_dir="${MLX_WORKSPACE}/models/video/src/Wan2.1-T2V-1.3B"
out_dir="$(default_wan_model_dir)"

if wan_model_dir_ready "${out_dir}" && (( FORCE == 0 )); then
  log_ok "Converted Wan model already present: ${out_dir}"
  log_info "Re-run with --force to convert again."
  exit 0
fi

mkdir -p "$(dirname "${src_dir}")" "$(dirname "${out_dir}")"

log_info "Downloading ${MLX_VIDEO_WAN_SOURCE_REPO} → ${src_dir}"
export MLX_VIDEO_WAN_SOURCE_REPO
export MLX_VIDEO_WAN_PREPARE_SRC_DIR="${src_dir}"
"${PY}" - <<'PY'
import os

from huggingface_hub import snapshot_download

snapshot_download(
    repo_id=os.environ["MLX_VIDEO_WAN_SOURCE_REPO"],
    local_dir=os.environ["MLX_VIDEO_WAN_PREPARE_SRC_DIR"],
)
print("download_ok")
PY

log_info "Converting to MLX 4-bit → ${out_dir}"
"${PY}" -m mlx_video.models.wan_2.convert \
  --checkpoint-dir "${src_dir}" \
  --output-dir "${out_dir}" \
  --dtype bfloat16 \
  --quantize \
  --bits 4 \
  --group-size 64

if ! wan_model_dir_ready "${out_dir}"; then
  die "Conversion finished but ${out_dir} is missing required files (config.json, model.safetensors, t5_encoder.safetensors, vae.safetensors)"
fi

log_ok "Wan MLX model ready: ${out_dir}"
log_info "Generate with: make video VIDEO_PROMPT=\"a red fox running through snow\""
