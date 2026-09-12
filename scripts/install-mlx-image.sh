#!/usr/bin/env bash
# Install Pure MLX text-to-image tooling (mflux) into the existing project venv.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Does not recreate .venv. Does not install Diffusers+MPS as a generation backend;
# torch may be installed transitively (mflux uses safetensors.torch for weight loading).
# Denoising remains MLX.
#
# Usage:
#   scripts/install-mlx-image.sh
#   make install-image
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: install-mlx-image.sh [-h|--help]

Install mflux into the existing MLX virtualenv for text-to-image generation.

Requires a prior `make install` (or equivalent). Does not uninstall or
recreate .venv. Image model weights download on first generate.

On 8 GB machines this is opt-in and swap-heavy; the generate wrapper
defaults to FLUX.2 Klein 4B, 4-bit, 512², and --low-ram. Fanless + slow
chips keep that conservative Air profile even at higher RAM.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

log_header "Install MLX text-to-image (mflux)"

PY="$(venv_python)"
PIP="$(venv_pip)"
if [[ ! -x "${PY}" ]]; then
  die "Python venv not found at ${MLX_VENV}. Run: make install"
fi

assert_apple_silicon
export_detect_env

if (( MLX_MEM_GIB <= 8 )); then
  log_warn "8 GB unified memory: text-to-image will likely swap. Close other apps, unload mlx_lm.server, and use the constrained defaults (FLUX.2 Klein 4B, 4-bit, 512px, --low-ram)."
elif (( MLX_MEM_GIB < 16 )); then
  log_warn "Under 16 GB unified memory: prefer quantized 4B models and modest resolution."
fi
if [[ "${MLX_THERMAL_CLASS}" == "fanless" && "${MLX_THROUGHPUT_CLASS}" == "slow" ]]; then
  log_warn "Fanless + slow bandwidth (this is the conservative Air profile): keep 512² 4-bit --low-ram. Later Airs still do not raise image defaults via chip class."
elif [[ "${MLX_THERMAL_CLASS}" == "fanless" ]]; then
  log_warn "Fanless chassis: image/video/context stay on the conservative Air profile even if RAM is larger."
fi

log_info "Installing ${MLX_IMAGE_PACKAGE} into ${MLX_VENV}"
"${PY}" -m pip install --upgrade pip setuptools wheel
"${PIP}" install --upgrade "${MLX_IMAGE_PACKAGE}"

if "${PY}" -c "import mflux" >/dev/null 2>&1; then
  ver="$("${PY}" -c 'import importlib.metadata as m; print(m.version("mflux"))')"
  log_ok "mflux importable (version ${ver})"
else
  die "mflux installed but is not importable"
fi

if "${PY}" -c "import torch" >/dev/null 2>&1; then
  torch_ver="$("${PY}" -c 'import importlib.metadata as m; print(m.version("torch"))')"
  log_warn "mflux currently requires torch ${torch_ver} for safetensors weight loading. Denoising still runs on MLX; torch is not the image-generation backend."
fi

cat <<EOF

${COLOR_BOLD}Generate an image${COLOR_RESET}

  make image IMAGE_PROMPT="a red fox in snow"
  # equivalent: scripts/generate-mlx-image.sh --prompt "a red fox in snow"

First run downloads model weights (several GB). Outputs go to outputs/images/.
See docs/media.md for models, memory, and extra mflux flags.
EOF

log_ok "MLX text-to-image tooling installed."
