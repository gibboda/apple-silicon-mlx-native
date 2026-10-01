#!/usr/bin/env bash
# Create the project Python virtual environment only.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Assumptions: macOS + Apple Silicon. Does not assume Homebrew or a venv exist.
# Installs Homebrew Python when needed, then creates .venv. Does not pip-install
# MLX packages, seed models.env, or install git/ffmpeg.
#
# Usage:
#   scripts/create-mlx-venv.sh
#   MLX_INSTALL_HOMEBREW=1 scripts/create-mlx-venv.sh
#
# Environment:
#   MLX_WORKSPACE           Workspace root (default: repository root)
#   MLX_PYTHON_VERSION      Homebrew Python formula version (default: 3.12)
#   MLX_INSTALL_HOMEBREW    If 1, install Homebrew non-interactively when missing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MLX_INSTALL_HOMEBREW="${MLX_INSTALL_HOMEBREW:-0}"

usage() {
  cat <<'EOF'
Usage: create-mlx-venv.sh [-h|--help]

Create the project .venv with Homebrew Python. Does not install MLX packages.

Steps:
  1. Verify Darwin arm64
  2. Validate workspace / venv paths (missing .venv is OK; incomplete is not)
  3. Verify/install Xcode CLT guidance
  4. Detect (or optionally install) Homebrew
  5. Install Homebrew python only
  6. Create .venv, or reuse a complete one

Package install is a later step: make install
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

log_header "Apple Silicon MLX native — create venv"

assert_apple_silicon
export_detect_env

log_info "Detected chip: ${MLX_CHIP} (family=${MLX_CHIP_FAMILY:-unknown} sku=${MLX_CHIP_SKU:-unknown})"
log_info "Memory: ${MLX_MEM_GIB} GiB — physical tier: ${MLX_PHYSICAL_TIER_ID} policy tier: ${MLX_TIER_ID}"

log_header "Workspace"
mkdir -p "${MLX_WORKSPACE}"
assert_install_venv_paths
log_ok "Workspace validated: ${MLX_WORKSPACE}"

log_header "Prerequisites"

if check_xcode_clt; then
  log_ok "Xcode Command Line Tools present: $(xcode-select -p)"
else
  log_error "Xcode Command Line Tools are required."
  log_info "Install with: xcode-select --install"
  die "Aborting until Xcode CLT are installed."
fi

ensure_homebrew_in_path
if [[ -z "$(homebrew_prefix)" ]]; then
  if is_truthy "${MLX_INSTALL_HOMEBREW}"; then
    log_info "Installing Homebrew (NONINTERACTIVE=1)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ensure_homebrew_in_path
  else
    cat <<'EOF'
Homebrew was not found.

Install Homebrew (Apple Silicon default prefix /opt/homebrew), then re-run:

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"

Or allow this script to install it:

  MLX_INSTALL_HOMEBREW=1 scripts/create-mlx-venv.sh
EOF
    die "Homebrew is required."
  fi
fi

require_cmd brew
brew_arch="$(brew config 2>/dev/null | awk -F': ' '/CPU:/{print $2; exit}')"
log_ok "Homebrew at $(homebrew_prefix) (CPU: ${brew_arch:-unknown})"

if [[ "$(homebrew_prefix)" == "/usr/local" ]]; then
  die "Homebrew prefix is /usr/local (Intel/Rosetta). Install Apple Silicon Homebrew at /opt/homebrew, then re-run."
fi

python_formula="python@${MLX_PYTHON_VERSION}"
log_header "Homebrew Python"
if brew list --versions "${python_formula}" >/dev/null 2>&1; then
  log_ok "Already installed: ${python_formula}"
else
  log_info "Installing ${python_formula}..."
  brew install "${python_formula}"
fi

BREW_PY="$(homebrew_prefix)/opt/python@${MLX_PYTHON_VERSION}/bin/python${MLX_PYTHON_VERSION}"
if [[ ! -x "${BREW_PY}" ]]; then
  BREW_PY="$(command -v "python${MLX_PYTHON_VERSION}" || true)"
fi
if [[ -z "${BREW_PY}" || ! -x "${BREW_PY}" ]]; then
  die "Python ${MLX_PYTHON_VERSION} not found after Homebrew install."
fi
log_ok "Using Python: ${BREW_PY} ($("${BREW_PY}" --version))"

log_header "Python virtual environment"
if [[ -d "${MLX_VENV}" ]]; then
  log_warn "Existing venv found at ${MLX_VENV}; reusing. Use make rebuild to recreate."
else
  "${BREW_PY}" -m venv "${MLX_VENV}"
  log_ok "Created venv at ${MLX_VENV}"
fi

log_ok "Venv ready at ${MLX_VENV}. Next: make install"
