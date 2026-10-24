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
# Default 3.12 until project policy changes; venv guards follow MLX_PYTHON_VERSION.
# See docs/troubleshooting.md#python-version-venv before changing the default.
MLX_PYTHON_VERSION="${MLX_PYTHON_VERSION:-3.12}"
# Supported Homebrew python@ minors for make install (macOS arm64 wheel availability).
MLX_PYTHON_VERSION_MIN="${MLX_PYTHON_VERSION_MIN:-3.12}"
MLX_PYTHON_VERSION_MAX="${MLX_PYTHON_VERSION_MAX:-3.14}"
# Supported macOS major versions (Apple Silicon only). See docs/troubleshooting.md.
MLX_MACOS_VERSION_MIN_MAJOR="${MLX_MACOS_VERSION_MIN_MAJOR:-26}"
MLX_MACOS_VERSION_MAX_MAJOR="${MLX_MACOS_VERSION_MAX_MAJOR:-27}"
MLX_CONFIG_DIR="${MLX_CONFIG_DIR:-${MLX_WORKSPACE}/config}"
MLX_MODELS_ENV="${MLX_MODELS_ENV:-${MLX_CONFIG_DIR}/models.env}"
MLX_MODELS_EXAMPLE="${REPO_ROOT}/config/models.example.env"
# Written into a non-repo MLX_WORKSPACE so purge can tell a toolkit directory
# from $HOME or another broad path. The repository itself is its own marker.
MLX_WORKSPACE_SENTINEL_NAME=".mlx-workspace"

# Deliberately selected Python packages (Pure MLX core + selected media).
# Image/video packages are NOT installed by default — see docs/media.md.
# requirements/constraints.txt is the pin manifest. Defaults below read that
# file so a Dependabot edit is the install default. An explicit MLX_* spec
# still wins, and export_pip_constraint rewrites PIP_CONSTRAINT so the old
# pin does not force the override back. An MLX_PACKAGE override also
# retargets mlx-metal to the same mlx==version, or drops that pin when the
# spec is not an exact pin. Not a full lockfile yet.
# Override a spec to track upstream, for example:
#   MLX_PACKAGE=mlx MLX_LM_PACKAGE=mlx-lm MLX_AUDIO_PACKAGE=mlx-audio make rebuild
# Do not add PyTorch/MPS as a generation backend.
MLX_PIP_CONSTRAINT_FILE="${MLX_PIP_CONSTRAINT_FILE:-${REPO_ROOT}/requirements/constraints.txt}"

# Exact name==version line from the manifest, or the fallback when that line is absent.
_pin_default() {
  local name="$1"
  local fallback="$2"
  local line=""
  if [[ -f "${MLX_PIP_CONSTRAINT_FILE}" ]]; then
    line="$(grep -E "^${name}==[^[:space:]]+$" "${MLX_PIP_CONSTRAINT_FILE}" | head -n 1 || true)"
  fi
  if [[ -n "${line}" ]]; then
    printf '%s' "${line}"
  else
    printf '%s' "${fallback}"
  fi
}

MLX_PACKAGE="${MLX_PACKAGE:-$(_pin_default mlx mlx==0.32.4)}"
MLX_LM_PACKAGE="${MLX_LM_PACKAGE:-$(_pin_default mlx-lm mlx-lm==0.32.0)}"
MLX_AUDIO_PACKAGE="${MLX_AUDIO_PACKAGE:-$(_pin_default mlx-audio mlx-audio==0.5.8)}"
MLX_CORE_PACKAGES=("${MLX_PACKAGE}" "${MLX_LM_PACKAGE}")
MLX_MEDIA_PACKAGES=("${MLX_AUDIO_PACKAGE}")
MLX_IMAGE_PACKAGE="${MLX_IMAGE_PACKAGE:-$(_pin_default mflux mflux==0.19.1)}"
# Pin mlx-video to a git SHA (not published on PyPI). Override with MLX_VIDEO_PACKAGE.
MLX_VIDEO_PACKAGE="${MLX_VIDEO_PACKAGE:-git+https://github.com/Blaizzy/mlx-video.git@87db56a51758fefb748a359b90a5283bb8ba4837}"
# Packaging tools are pinned so bootstrap, rebuild, and media installs match
# across days. Bump requirements/constraints.txt for a security fix, a Python
# requirement change, or an install failure, and record the bump in
# CHANGELOG.md. Override a spec to try newer tooling once, for example
# MLX_PIP_PACKAGE=pip. Bump requirements/constraints.txt; these fallbacks apply
# only when that manifest has no matching line.
MLX_PIP_PACKAGE="${MLX_PIP_PACKAGE:-$(_pin_default pip pip==26.2.1)}"
MLX_SETUPTOOLS_PACKAGE="${MLX_SETUPTOOLS_PACKAGE:-$(_pin_default setuptools setuptools==84.1.0)}"
MLX_WHEEL_PACKAGE="${MLX_WHEEL_PACKAGE:-$(_pin_default wheel wheel==0.48.0)}"
# wheel 0.48.0 depends on packaging>=24.0. Pin the library itself so a fresh
# venv does not float to whatever packaging release is newest that day.
# Named MLX_PACKAGING_LIB_PACKAGE so it is not confused with MLX_PACKAGING_PACKAGES.
MLX_PACKAGING_LIB_PACKAGE="${MLX_PACKAGING_LIB_PACKAGE:-$(_pin_default packaging packaging==26.3)}"
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

# Cohesive modules (order matters). Callers still source common.sh only.
# shellcheck source=scripts/lib/ui.sh
source "${SCRIPT_LIB_DIR}/ui.sh"
# shellcheck source=scripts/lib/detect.sh
source "${SCRIPT_LIB_DIR}/detect.sh"
# shellcheck source=scripts/lib/policy.sh
source "${SCRIPT_LIB_DIR}/policy.sh"
# shellcheck source=scripts/lib/catalog.sh
source "${SCRIPT_LIB_DIR}/catalog.sh"
# shellcheck source=scripts/lib/envfile.sh
source "${SCRIPT_LIB_DIR}/envfile.sh"
# shellcheck source=scripts/lib/venv.sh
source "${SCRIPT_LIB_DIR}/venv.sh"
