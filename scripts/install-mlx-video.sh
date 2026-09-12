#!/usr/bin/env bash
# Install Pure MLX text-to-video tooling (mlx-video) into the existing project venv.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Does not recreate .venv. Does not install Diffusers+MPS as a generation backend.
# Denoising remains MLX. Wan .pth conversion (optional prepare script) needs torch.
#
# Usage:
#   scripts/install-mlx-video.sh
#   make install-video
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: install-mlx-video.sh [-h|--help]

Install mlx-video into the existing MLX virtualenv for text-to-video generation.

Requires a prior `make install` (or equivalent). Does not uninstall or
recreate .venv. Does not download or convert Wan weights (see
scripts/prepare-mlx-video-wan.sh). LTX-2 distilled weights download on
first generate when that family is selected.

Pinned by default to a git SHA via MLX_VIDEO_PACKAGE (not on PyPI).
On 8–16 GB this is opt-in and swap-heavy; Wan 1.3B still loads an ~11 GB
UMT5 encoder. Prefer ≥24 GB and stop mlx_lm.server first. Fanless and
16 GB base M1 still refuse generate unless --force.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

log_header "Install MLX text-to-video (mlx-video)"

PY="$(venv_python)"
PIP="$(venv_pip)"
if [[ ! -x "${PY}" ]]; then
  die "Python venv not found at ${MLX_VENV}. Run: make install"
fi

assert_apple_silicon
export_detect_env

if (( MLX_MEM_GIB <= 8 )); then
  log_warn "8 GB unified memory: text-to-video is not practical (UMT5 encoder ~11 GB). Expect failure or extreme swap."
elif (( MLX_MEM_GIB < 24 )); then
  log_warn "Under 24 GB unified memory: Wan 1.3B 4-bit may swap. Unload mlx_lm.server and other GPU apps."
fi
if [[ "${MLX_THERMAL_CLASS}" == "fanless" || "${MLX_THROUGHPUT_CLASS}" == "slow" ]]; then
  log_warn "Fanless and/or slow-bandwidth machines: generate refuses text-to-video without --force (UMT5 ~11 GB). Do not advertise LTX here."
fi

require_cmd git

log_info "Installing ${MLX_VIDEO_PACKAGE} into ${MLX_VENV}"
"${PY}" -m pip install --upgrade pip setuptools wheel
"${PIP}" install --upgrade "${MLX_VIDEO_PACKAGE}"

if "${PY}" -c "import mlx_video" >/dev/null 2>&1; then
  ver="$("${PY}" -c 'import mlx_video, importlib.metadata as m
try:
    print(m.version("mlx-video"))
except m.PackageNotFoundError:
    print(getattr(mlx_video, "__version__", "unknown"))')"
  log_ok "mlx_video importable (version ${ver})"
else
  die "mlx-video installed but is not importable"
fi

if "${PY}" -c "import torch" >/dev/null 2>&1; then
  torch_ver="$("${PY}" -c 'import importlib.metadata as m; print(m.version("torch"))')"
  log_warn "torch ${torch_ver} is present in this venv. mlx-video generation is MLX; torch is only needed to convert original Wan .pth checkpoints (scripts/prepare-mlx-video-wan.sh)."
fi

cat <<EOF

${COLOR_BOLD}Generate a video${COLOR_RESET}

  make video VIDEO_PROMPT="a red fox running through snow"
  # equivalent: scripts/generate-mlx-video.sh --prompt "a red fox running through snow"

Wan2.1 1.3B (default on ≤32 GB) needs a converted MLX directory first:

  scripts/prepare-mlx-video-wan.sh

LTX-2 distilled (default on ≥36 GB) downloads Hugging Face weights on first generate.
Outputs go to outputs/videos/. See docs/media.md for models, memory, and extra flags.
EOF

log_ok "MLX text-to-video tooling installed."
