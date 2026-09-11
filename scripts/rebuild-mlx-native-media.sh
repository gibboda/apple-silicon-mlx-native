#!/usr/bin/env bash
# Reproducibly rebuild a damaged, stale, or reset Python MLX environment.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Assumes Homebrew and the MLX workspace already exist.
# Preserves config/models.env when present.
#
# Usage:
#   scripts/rebuild-mlx-native-media.sh
#   MLX_SKIP_MEDIA=1 scripts/rebuild-mlx-native-media.sh
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MLX_SKIP_MEDIA="${MLX_SKIP_MEDIA:-0}"
MLX_INSTALL_IMAGE="${MLX_INSTALL_IMAGE:-0}"

usage() {
  cat <<'EOF'
Usage: rebuild-mlx-native-media.sh [-h|--help] [--force]

Rebuild the Python .venv for the MLX workspace.

  --force   Skip interactive confirmation when removing .venv
  -h        Show this help

Fails safely if Apple Silicon, Homebrew, or the workspace cannot be validated.
EOF
}

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

log_header "Apple Silicon MLX native — rebuild"

assert_apple_silicon
export_detect_env

ensure_homebrew_in_path
[[ -n "$(homebrew_prefix)" ]] || die "Homebrew not found. Run the initial build script first."
require_cmd brew
if [[ "$(homebrew_prefix)" == "/usr/local" ]]; then
  die "Homebrew prefix is /usr/local (Intel/Rosetta). Install Apple Silicon Homebrew at /opt/homebrew, then re-run."
fi
log_ok "Homebrew validated at $(homebrew_prefix)"

# Validate expected workspace
assert_workspace_safe
assert_venv_under_workspace

log_ok "Workspace validated: ${MLX_WORKSPACE}"

# Preserve configuration
mkdir -p "${MLX_CONFIG_DIR}"
if [[ -f "${MLX_MODELS_ENV}" ]]; then
  log_ok "Preserving ${MLX_MODELS_ENV}"
elif [[ -f "${MLX_MODELS_EXAMPLE}" ]]; then
  cp "${MLX_MODELS_EXAMPLE}" "${MLX_MODELS_ENV}"
  log_ok "Restored ${MLX_MODELS_ENV} from example"
fi

BREW_PY="$(homebrew_prefix)/opt/python@${MLX_PYTHON_VERSION}/bin/python${MLX_PYTHON_VERSION}"
if [[ ! -x "${BREW_PY}" ]]; then
  BREW_PY="$(command -v "python${MLX_PYTHON_VERSION}" || true)"
fi
[[ -n "${BREW_PY}" && -x "${BREW_PY}" ]] || die "Python ${MLX_PYTHON_VERSION} not found. Install via: brew install python@${MLX_PYTHON_VERSION}"

# Remove / recreate venv
if [[ -e "${MLX_VENV}" ]]; then
  if [[ ! -d "${MLX_VENV}" ]]; then
    die "MLX_VENV exists but is not a directory: ${MLX_VENV}"
  fi
  if ! looks_like_venv "${MLX_VENV}"; then
    die "Refusing to remove path that does not look like a venv: ${MLX_VENV}"
  fi
  if (( FORCE == 0 )) && [[ -t 0 ]]; then
    printf 'Remove and recreate %s? [y/N] ' "${MLX_VENV}"
    read -r answer
    case "${answer}" in
      y|Y|yes|YES) ;;
      *) die "Aborted by user." ;;
    esac
  fi
  log_info "Removing ${MLX_VENV}"
  rm -rf "${MLX_VENV}"
fi

log_info "Creating venv with ${BREW_PY}"
"${BREW_PY}" -m venv "${MLX_VENV}"

PY="$(venv_python)"
PIP="$(venv_pip)"
"${PY}" -m pip install --upgrade pip setuptools wheel
"${PIP}" install --upgrade "${MLX_CORE_PACKAGES[@]}"

if ! is_truthy "${MLX_SKIP_MEDIA}"; then
  "${PIP}" install --upgrade "${MLX_MEDIA_PACKAGES[@]}"
fi

if is_truthy "${MLX_INSTALL_IMAGE}"; then
  "${PIP}" install --upgrade mflux
fi

log_header "Validation"
"${SCRIPT_DIR}/validate-mlx.sh" --venv "${MLX_VENV}"

log_header "Package versions"
"${PIP}" show mlx mlx-lm 2>/dev/null | awk '/^Name:|^Version:/{print}' || true

log_header "Hardware"
print_hardware_summary

# Explicit small MLX computation (beyond validate)
log_header "MLX smoke computation"
"${PY}" - <<'PY'
import mlx.core as mx
x = mx.arange(16.0).reshape((4, 4))
y = mx.matmul(x, x.T)
mx.eval(y)
print("smoke_sum=", float(mx.sum(y)))
print("REBUILD_RESULT=success")
PY

log_ok "Rebuild completed successfully."
