#!/usr/bin/env bash
# Bootstrap a pure Apple Silicon MLX-native workstation environment.
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
#   OVERRIDE_MEMORY_TIER    Force tier id: constrained|standard|high|workstation|large

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MLX_INSTALL_HOMEBREW="${MLX_INSTALL_HOMEBREW:-0}"
MLX_SKIP_MEDIA="${MLX_SKIP_MEDIA:-0}"
MLX_INSTALL_IMAGE="${MLX_INSTALL_IMAGE:-0}"

usage() {
  cat <<'EOF'
Usage: initial-build-mlx-native-media.sh [-h|--help]

Bootstrap MLX-native tooling on a new Apple Silicon Mac.

Steps:
  1. Verify arm64 / detect hardware & memory tier
  2. Verify/install Xcode CLT guidance
  3. Detect (or optionally install) Homebrew
  4. Install Homebrew packages (python, git, ffmpeg)
  5. Create workspace + Python venv
  6. Upgrade packaging tools; install mlx, mlx-lm, selected media
  7. Validate MLX; print versions, hardware, next commands

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

if [[ -n "${OVERRIDE_MEMORY_TIER:-}" ]]; then
  MLX_TIER_ID="${OVERRIDE_MEMORY_TIER}"
  log_warn "OVERRIDE_MEMORY_TIER=${OVERRIDE_MEMORY_TIER} (recommendations may differ from physical RAM)"
fi

log_info "Detected chip: ${MLX_CHIP}"
log_info "Memory: ${MLX_MEM_GIB} GiB — tier: ${MLX_TIER_LABEL}"
log_info "Recommendation: ${MLX_TIER_HINT}"

if (( MLX_MEM_GIB <= 8 )); then
  log_warn "8 GB systems: prefer ~3B–4B 4-bit models and conservative context lengths."
fi

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

# Reject obvious x86 Homebrew on Apple Silicon hosts.
if [[ "$(homebrew_prefix)" == "/usr/local" ]]; then
  log_warn "Homebrew prefix is /usr/local (often Intel/Rosetta). Prefer /opt/homebrew on Apple Silicon."
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

# --- Workspace ---
log_header "Workspace"
mkdir -p "${MLX_WORKSPACE}"
mkdir -p "${MLX_CONFIG_DIR}"
if [[ ! -f "${MLX_MODELS_ENV}" ]]; then
  if [[ -f "${MLX_MODELS_EXAMPLE}" ]]; then
    cp "${MLX_MODELS_EXAMPLE}" "${MLX_MODELS_ENV}"
    log_ok "Created ${MLX_MODELS_ENV} from example"
  else
    cat >"${MLX_MODELS_ENV}" <<EOF
# Local model preferences (not committed)
MLX_DEFAULT_MODEL=$(recommended_model_for_tier "${MLX_TIER_ID}")
MLX_SERVER_HOST=127.0.0.1
MLX_SERVER_PORT=8080
EOF
    log_ok "Created ${MLX_MODELS_ENV}"
  fi
else
  log_ok "Preserving existing ${MLX_MODELS_ENV}"
fi

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
"${PIP}" install --upgrade "${MLX_CORE_PACKAGES[@]}"

if ! is_truthy "${MLX_SKIP_MEDIA}"; then
  log_header "Selected MLX-native media packages"
  log_info "Installing Pure MLX speech/audio: mlx-audio"
  "${PIP}" install --upgrade "${MLX_MEDIA_PACKAGES[@]}"
else
  log_warn "Skipping media packages (MLX_SKIP_MEDIA=1)"
fi

if is_truthy "${MLX_INSTALL_IMAGE}"; then
  if (( MLX_MEM_GIB < 16 )); then
    log_warn "Image generation (mflux) typically needs ≥16 GB unified memory; proceeding due to MLX_INSTALL_IMAGE=1"
  fi
  log_info "Installing Pure MLX image tooling: mflux (opt-in)"
  "${PIP}" install --upgrade mflux
else
  log_info "Image tooling (mflux) not installed by default. Set MLX_INSTALL_IMAGE=1 to opt in."
  log_info "Video tooling is documented in docs/media.md and is not installed by default."
fi

# --- Validate ---
log_header "Validation"
"${SCRIPT_DIR}/validate-mlx.sh" --venv "${MLX_VENV}"

log_header "Installed versions"
"${PIP}" show mlx mlx-lm mlx-audio 2>/dev/null | awk '/^Name:|^Version:/{print}' || true

log_header "Hardware"
print_hardware_summary

recommended="$(recommended_model_for_tier "${MLX_TIER_ID}")"
cat <<EOF

${COLOR_BOLD}Next commands${COLOR_RESET}

  # Activate the environment
  source ${MLX_VENV}/bin/activate

  # One-shot generation (downloads model on first use)
  mlx_lm.generate --model ${recommended} --prompt "Hello from MLX" --max-tokens 64

  # Persistent OpenAI-compatible server (preferred for repeated use)
  mlx_lm.server --model ${recommended} --host 127.0.0.1 --port 8080

  # Re-validate / rebuild later
  make validate
  make rebuild

See README.md and docs/models.md for memory-aware model guidance.
EOF

log_ok "Initial build completed successfully."
