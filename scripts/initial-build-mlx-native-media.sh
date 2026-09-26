#!/usr/bin/env bash
# Bootstrap a pure Apple Silicon MLX-native workstation environment.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Assumptions: macOS + Apple Silicon. Does not assume Homebrew or a venv exist.
# Never installs Rosetta-only/x86 packages. Never uses sudo pip.
#
# Usage:
#   scripts/initial-build-mlx-native-media.sh
#   MLX_INSTALL_HOMEBREW=1 scripts/initial-build-mlx-native-media.sh
#   MLX_SKIP_MEDIA=1 scripts/initial-build-mlx-native-media.sh
#
# Environment:
#   MLX_WORKSPACE           Workspace root (default: repository root)
#   MLX_PYTHON_VERSION      Homebrew Python formula version (default: 3.12)
#   MLX_INSTALL_HOMEBREW    If 1, install Homebrew non-interactively when missing
#   MLX_SKIP_MEDIA          If 1, skip selected media packages (mlx-audio)
#   MLX_INSTALL_IMAGE       If 1, optionally install mflux (Pure MLX image; high memory)
#   MLX_INSTALL_VIDEO       If 1, optionally install mlx-video (Pure MLX video; high memory)
#   MLX_PACKAGE             pip spec for mlx (default: pinned == version)
#   MLX_LM_PACKAGE          pip spec for mlx-lm (default: pinned == version)
#   MLX_AUDIO_PACKAGE       pip spec for mlx-audio (default: pinned == version)
#   MLX_DISK_ENFORCE        If 1, abort when free space is under the download floor
#   MLX_SKIP_DISK_CHECK     If 1, skip the free-space warning
#   OVERRIDE_MEMORY_TIER    Force policy tier id: constrained|standard|high|workstation|large
#   OVERRIDE_CHIP_FAMILY    Force policy chip generation (e.g. 1, 5)
#   OVERRIDE_CHIP_SKU       Force policy sku: base|pro|max|ultra
#   OVERRIDE_GPU_CORES      Force policy GPU core count
#   OVERRIDE_THERMAL_CLASS  Force policy thermal class: fanless|cooled

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MLX_INSTALL_HOMEBREW="${MLX_INSTALL_HOMEBREW:-0}"
MLX_SKIP_MEDIA="${MLX_SKIP_MEDIA:-0}"
MLX_INSTALL_IMAGE="${MLX_INSTALL_IMAGE:-0}"
MLX_INSTALL_VIDEO="${MLX_INSTALL_VIDEO:-0}"

usage() {
  cat <<'EOF'
Usage: initial-build-mlx-native-media.sh [-h|--help]

Bootstrap MLX-native tooling on a new Apple Silicon Mac.

Steps:
  1. Verify Darwin arm64 / detect hardware, chip class, and memory tier
  2. Validate workspace / venv paths (fail closed before Homebrew)
  3. Verify/install Xcode CLT guidance
  4. Detect (or optionally install) Homebrew
  5. Install Homebrew packages (python, git, ffmpeg)
  6. Seed config and create or reuse Python venv
  7. Upgrade packaging tools; install pinned mlx, mlx-lm, selected media
  8. Validate MLX; print versions, hardware, next commands

Image/video packages are NOT installed by default. See docs/media.md.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

log_header "Apple Silicon MLX native — initial build"

assert_apple_silicon
export_detect_env

log_info "Detected chip: ${MLX_CHIP} (family=${MLX_CHIP_FAMILY:-unknown} sku=${MLX_CHIP_SKU:-unknown})"
log_info "Throughput: ${MLX_THROUGHPUT_CLASS:-unknown} @ ${MLX_BANDWIDTH_GBS:-?} GB/s thermal=${MLX_THERMAL_CLASS:-unknown}"
log_info "Memory: ${MLX_MEM_GIB} GiB — physical tier: ${MLX_PHYSICAL_TIER_ID} policy tier: ${MLX_TIER_ID}"
log_info "Composed default: ${MLX_RECOMMENDED_MODEL} context=${MLX_RECOMMENDED_CONTEXT}"

if (( MLX_MEM_GIB <= 8 )); then
  log_warn "8 GB systems: prefer ~3B–4B 4-bit models and conservative context lengths."
fi
if [[ "${MLX_THERMAL_CLASS}" == "fanless" ]]; then
  log_warn "Fanless chassis (MacBook Air): image/video/context stay on the conservative Air profile."
fi

log_header "Workspace"
mkdir -p "${MLX_WORKSPACE}"
mkdir -p "${MLX_CONFIG_DIR}"
assert_install_venv_paths
log_ok "Workspace validated: ${MLX_WORKSPACE}"
seed_models_env_if_missing

# --- Prerequisites ---
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

  MLX_INSTALL_HOMEBREW=1 scripts/initial-build-mlx-native-media.sh
EOF
    die "Homebrew is required."
  fi
fi

require_cmd brew
brew_arch="$(brew config 2>/dev/null | awk -F': ' '/CPU:/{print $2; exit}')"
log_ok "Homebrew at $(homebrew_prefix) (CPU: ${brew_arch:-unknown})"

# Reject Intel/Rosetta Homebrew on Apple Silicon hosts before installing.
if [[ "$(homebrew_prefix)" == "/usr/local" ]]; then
  die "Homebrew prefix is /usr/local (Intel/Rosetta). Install Apple Silicon Homebrew at /opt/homebrew, then re-run."
fi

log_header "Homebrew packages"
for pkg in "${MLX_HOMEBREW_PACKAGES[@]}"; do
  if brew list --versions "${pkg}" >/dev/null 2>&1; then
    log_ok "Already installed: ${pkg}"
  else
    log_info "Installing ${pkg}..."
    brew install "${pkg}"
  fi
done

# Prefer Homebrew Python for the venv when available.
BREW_PY="$(homebrew_prefix)/opt/python@${MLX_PYTHON_VERSION}/bin/python${MLX_PYTHON_VERSION}"
if [[ ! -x "${BREW_PY}" ]]; then
  BREW_PY="$(command -v "python${MLX_PYTHON_VERSION}" || true)"
fi
if [[ -z "${BREW_PY}" || ! -x "${BREW_PY}" ]]; then
  die "Python ${MLX_PYTHON_VERSION} not found after Homebrew install."
fi
log_ok "Using Python: ${BREW_PY} ($("${BREW_PY}" --version))"

# --- Virtual environment ---
log_header "Python virtual environment"
if [[ -d "${MLX_VENV}" ]]; then
  log_warn "Existing venv found at ${MLX_VENV}; reusing. Use make rebuild to recreate."
else
  "${BREW_PY}" -m venv "${MLX_VENV}"
  log_ok "Created venv at ${MLX_VENV}"
fi

PY="$(venv_python)"
PIP="$(venv_pip)"
"${PY}" -m pip install --upgrade pip setuptools wheel

log_header "MLX core packages"
log_info "Installing pinned core: ${MLX_CORE_PACKAGES[*]}"
"${PIP}" install --upgrade "${MLX_CORE_PACKAGES[@]}"

if ! is_truthy "${MLX_SKIP_MEDIA}"; then
  log_header "Selected MLX-native media packages"
  log_info "Installing Pure MLX speech/audio: ${MLX_MEDIA_PACKAGES[*]}"
  warn_or_die_disk_headroom media-pip
  "${PIP}" install --upgrade "${MLX_MEDIA_PACKAGES[@]}"
else
  log_warn "Skipping media packages (MLX_SKIP_MEDIA=1)"
fi

if is_truthy "${MLX_INSTALL_IMAGE}"; then
  if (( MLX_MEM_GIB < 16 )); then
    log_warn "Image generation (mflux) typically needs ≥16 GB unified memory; proceeding due to MLX_INSTALL_IMAGE=1"
  fi
  log_info "Installing Pure MLX image tooling: ${MLX_IMAGE_PACKAGE} (opt-in)"
  warn_or_die_disk_headroom image-pip
  "${PIP}" install --upgrade "${MLX_IMAGE_PACKAGE}"
else
  log_info "Image tooling (${MLX_IMAGE_PACKAGE}) not installed by default. Run: make install-image"
fi

if is_truthy "${MLX_INSTALL_VIDEO}"; then
  if (( MLX_MEM_GIB < 24 )); then
    log_warn "Video generation (mlx-video) typically needs ≥24 GB unified memory; proceeding due to MLX_INSTALL_VIDEO=1"
  fi
  log_info "Installing Pure MLX video tooling: ${MLX_VIDEO_PACKAGE} (opt-in)"
  warn_or_die_disk_headroom video-pip
  "${PIP}" install --upgrade "${MLX_VIDEO_PACKAGE}"
else
  log_info "Video tooling (mlx-video) is not installed by default. Run: make install-video"
fi

# --- Validate ---
log_header "Validation"
"${SCRIPT_DIR}/validate-mlx.sh" --venv "${MLX_VENV}"

log_header "Installed versions"
"${PIP}" show mlx mlx-lm mlx-audio 2>/dev/null | awk '/^Name:|^Version:/{print}' || true

log_header "Hardware"
print_hardware_summary

recommended="${MLX_RECOMMENDED_MODEL}"
context="${MLX_RECOMMENDED_CONTEXT}"
server_kv=""
if mlx_lm_help_has_flag mlx_lm.server --max-kv-size; then
  server_kv=" -- --max-kv-size ${context}"
fi
cat <<EOF

${COLOR_BOLD}Next commands${COLOR_RESET}

  # Activate the environment
  source ${MLX_VENV}/bin/activate

  # One-shot generation (downloads model on first use; ≤8 GB applies the MLX cache cap)
  # generate-mlx-text.sh also passes --max-kv-size ${context} unless overridden
  ${SCRIPT_DIR}/generate-mlx-text.sh --model ${recommended} --prompt "Hello from MLX" --max-tokens 64

  # Persistent OpenAI-compatible server (preferred for repeated use)
  ${SCRIPT_DIR}/serve-mlx.sh${server_kv}

  # Re-validate / rebuild later
  make validate
  make rebuild
  make recommend   # fresh composed profile; does not rewrite config/models.env

  # Opt-in Pure MLX text-to-image (mflux)
  make install-image
  make image IMAGE_PROMPT="a red fox in snow"

  # Opt-in Pure MLX text-to-video (mlx-video)
  make install-video
  make prepare-video   # Wan 1.3B 4-bit; needs torch for .pth conversion
  make video VIDEO_PROMPT="a red fox running through snow"

  # Remove toolkit-owned .venv (does not uninstall Homebrew)
  make clean

See README.md and docs/models.md for memory-aware model guidance.
RAM is the OOM fence; chip class is the performance fence.
EOF

log_ok "Initial build completed successfully."
