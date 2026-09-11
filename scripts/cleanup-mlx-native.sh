#!/usr/bin/env bash
# Remove toolkit-owned MLX environment state without uninstalling shared system tools.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Default: delete the project .venv.
# Does not uninstall Homebrew, Xcode CLT, or brew formulae (python, git, ffmpeg).
#
# Usage:
#   scripts/cleanup-mlx-native.sh
#   scripts/cleanup-mlx-native.sh --dry-run
#   scripts/cleanup-mlx-native.sh --purge --force
#
# Environment:
#   MLX_WORKSPACE     Workspace root (default: repository root)
#   MLX_VENV          Virtualenv path (default: $MLX_WORKSPACE/.venv)
#   MLX_MODELS_ENV    Local config file (default: $MLX_WORKSPACE/config/models.env)
#   HF_HOME           Hugging Face home (default: ~/.cache/huggingface)
#   HF_HUB_CACHE      Hub/model cache (default: $HF_HOME/hub)
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DRY_RUN=0
FORCE=0
REMOVE_CONFIG=0
REMOVE_WORKSPACE_CACHES=0
REMOVE_HF_CACHE=0
KEEP_VENV=0

# Workspace-local directories that usage/gitignore treat as generated caches.
# Never includes config/ or the committed tree.
MLX_WORKSPACE_CACHE_NAMES=(
  models
  .cache
  huggingface
  .huggingface
  transformers
  mlx_models
  outputs
  generated
  tmp
  temp
  .tmp
)

usage() {
  cat <<'EOF'
Usage: cleanup-mlx-native.sh [options]

Remove toolkit-owned MLX environment state.

This is a cleanup, not a nuclear uninstall. Homebrew, Xcode Command Line
Tools, and shared brew formulae (python, git, ffmpeg) stay installed.
Downloaded Hugging Face models are only removed with --huggingface-cache.

Options:
  --dry-run              Print planned removals; change nothing
  --force                Do not prompt (required when stdin is not a TTY)
  --keep-venv            Do not remove .venv
  --config               Also remove config/models.env (never the committed example)
  --workspace-caches     Also remove workspace-local cache/output directories
  --huggingface-cache    Also remove the Hugging Face hub cache (downloaded models)
  --purge                --config + --workspace-caches (not Hugging Face, not Homebrew)
  -h, --help             Show this help

Default: remove .venv only.

Environment:
  MLX_WORKSPACE, MLX_VENV, MLX_MODELS_ENV, HF_HOME, HF_HUB_CACHE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    --keep-venv) KEEP_VENV=1; shift ;;
    --config) REMOVE_CONFIG=1; shift ;;
    --workspace-caches) REMOVE_WORKSPACE_CACHES=1; shift ;;
    --huggingface-cache) REMOVE_HF_CACHE=1; shift ;;
    --purge)
      REMOVE_CONFIG=1
      REMOVE_WORKSPACE_CACHES=1
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

huggingface_hub_cache() {
  local hf_home="${HF_HOME:-${HOME}/.cache/huggingface}"
  echo "${HF_HUB_CACHE:-${hf_home}/hub}"
}

assert_huggingface_hub_cache_safe() {
  local orig="$1"
  local path home_c hf_home_raw hf_home_c ws_c base depth home_cache
  path="$(canonical_path "${orig}")" || die "Cannot resolve Hugging Face hub cache path: ${orig}"
  home_c="$(canonical_path "${HOME}")" || die "Cannot resolve HOME"
  hf_home_raw="${HF_HOME:-${HOME}/.cache/huggingface}"
  hf_home_c="$(canonical_path "${hf_home_raw}")" || die "Cannot resolve HF_HOME: ${hf_home_raw}"
  ws_c="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  home_cache="$(canonical_path "${home_c}/.cache")" || home_cache="${home_c}/.cache"

  [[ -n "${path}" ]] || die "Hugging Face hub cache path is empty"
  [[ "${path}" != "/" ]] || die "Refusing to remove /"
  if path_is_within "${home_c}" "${path}"; then
    die "Refusing to remove \$HOME or a parent of it as Hugging Face cache: ${orig} (resolves to ${path})"
  fi
  [[ "${path}" != "${home_cache}" ]] || die "Refusing to remove entire ~/.cache"
  if path_is_within "${ws_c}" "${path}"; then
    die "Refusing to remove the workspace (or a parent of it) as Hugging Face cache: ${orig} (resolves to ${path})"
  fi
  if path_is_within "${hf_home_c}" "${path}"; then
    die "Refusing to remove Hugging Face home (tokens/config) or a parent of it: ${orig} (resolves to ${path})"
  fi
  depth="$(awk -F/ '{print NF-1}' <<<"${path}")"
  (( depth >= 3 )) || die "Hugging Face hub cache path is too shallow to remove safely: ${path}"
  base="$(basename "${path}")"
  if [[ "${base}" != "hub" && "${path}" != *huggingface* ]]; then
    die "Refusing to remove path that does not look like a Hugging Face hub cache: ${path}"
  fi
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

PLANNED_PATHS=()
PLANNED_REASONS=()

queue_remove() {
  local orig="$1"
  local why="$2"
  local path
  path_exists "${orig}" || return 0
  path="$(canonical_path "${orig}")" || die "Cannot resolve path for removal: ${orig}"
  path_exists "${path}" || return 0
  PLANNED_PATHS+=("${path}")
  PLANNED_REASONS+=("${why}")
  log_info "Plan: remove ${path} (${why}; $(human_du "${path}"))"
}

remove_path() {
  local path="$1"
  if (( DRY_RUN )); then
    log_info "DRY-RUN: would remove ${path}"
    return
  fi
  log_info "Removing ${path}"
  rm -rf -- "${path}"
  if path_exists "${path}"; then
    die "Failed to remove ${path}"
  fi
  log_ok "Removed ${path}"
}

confirm_unless_forced() {
  local i
  if (( DRY_RUN )); then
    return 0
  fi
  if (( FORCE )); then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "Refusing non-interactive cleanup without --force"
  fi
  printf '\n%sThe following paths will be removed:%s\n' "${COLOR_BOLD}" "${COLOR_RESET}"
  for i in "${!PLANNED_PATHS[@]}"; do
    printf '  %s  (%s)\n' "${PLANNED_PATHS[$i]}" "${PLANNED_REASONS[$i]}"
  done
  printf 'Proceed? [y/N] '
  read -r answer
  case "${answer}" in
    y|Y|yes|YES) ;;
    *) die "Aborted by user." ;;
  esac
}

print_leftovers() {
  local brew_prefix pkg hf_hub hf_home xcode_path
  hf_home="${HF_HOME:-${HOME}/.cache/huggingface}"
  hf_hub="$(huggingface_hub_cache)"

  log_header "Left in place (not exclusively owned by this toolkit)"

  ensure_homebrew_in_path
  brew_prefix="$(homebrew_prefix)"
  if [[ -n "${brew_prefix}" ]]; then
    log_info "Homebrew: ${brew_prefix}"
    if command -v brew >/dev/null 2>&1; then
      for pkg in "${MLX_HOMEBREW_PACKAGES[@]}"; do
        if brew list --versions "${pkg}" >/dev/null 2>&1; then
          log_info "Homebrew formula still installed: ${pkg}"
        else
          log_info "Homebrew formula not installed: ${pkg}"
        fi
      done
    fi
  else
    log_info "Homebrew: not found"
  fi

  if command -v xcode-select >/dev/null 2>&1 && xcode_path="$(xcode-select -p 2>/dev/null)"; then
    log_info "Xcode Command Line Tools: ${xcode_path}"
  else
    log_info "Xcode Command Line Tools: not found"
  fi

  if [[ -f "${MLX_MODELS_ENV}" ]]; then
    log_info "Local config kept: ${MLX_MODELS_ENV}"
  fi

  if path_exists "${hf_hub}"; then
    log_info "Hugging Face hub cache: ${hf_hub} ($(human_du "${hf_hub}"))"
    log_info "Reclaim model disk with: scripts/cleanup-mlx-native.sh --huggingface-cache --keep-venv --force"
  else
    log_info "Hugging Face hub cache: absent (${hf_hub})"
  fi
  if path_exists "${hf_home}"; then
    log_info "Hugging Face home (tokens/config may live here; not removed by default): ${hf_home}"
  fi

  cat <<EOF

${COLOR_BOLD}Policy${COLOR_RESET}
  Cleanup reverses toolkit-owned state (.venv, optional local caches/config).
  It does not uninstall Homebrew, Xcode CLT, or shared formulae
  (python@${MLX_PYTHON_VERSION}, git, ffmpeg).

  Extra options:
    scripts/cleanup-mlx-native.sh --config --force
    scripts/cleanup-mlx-native.sh --workspace-caches --force
    scripts/cleanup-mlx-native.sh --purge --force
    scripts/cleanup-mlx-native.sh --huggingface-cache --keep-venv --force
EOF
}

log_header "Apple Silicon MLX native — cleanup"

assert_workspace_safe
assert_venv_under_workspace
log_ok "Workspace validated: ${MLX_WORKSPACE}"

# --- .venv (default) ---
if (( KEEP_VENV )); then
  log_info "Keeping venv at ${MLX_VENV} (--keep-venv)"
elif path_exists "${MLX_VENV}"; then
  if [[ ! -d "${MLX_VENV}" ]]; then
    die "MLX_VENV exists but is not a directory: ${MLX_VENV}"
  fi
  if ! looks_like_venv "${MLX_VENV}"; then
    die "Refusing to remove path that does not look like a venv: ${MLX_VENV}"
  fi
  queue_remove "${MLX_VENV}" "project virtualenv"
else
  log_info "No venv to remove at ${MLX_VENV}"
fi

# --- local config (opt-in) ---
if (( REMOVE_CONFIG )); then
  if [[ "${MLX_MODELS_ENV}" == "${MLX_MODELS_EXAMPLE}" ]]; then
    die "Refusing to remove the committed example env: ${MLX_MODELS_EXAMPLE}"
  fi
  if [[ "$(basename "${MLX_MODELS_ENV}")" == "models.example.env" ]]; then
    die "Refusing to remove committed example env: ${MLX_MODELS_ENV}"
  fi
  assert_path_under_workspace "${MLX_MODELS_ENV}" "config"
  queue_remove "${MLX_MODELS_ENV}" "local model/server config"
else
  if [[ -f "${MLX_MODELS_ENV}" ]]; then
    log_info "Preserving ${MLX_MODELS_ENV} (pass --config or --purge to remove)"
  fi
fi

# --- workspace caches (opt-in) ---
if (( REMOVE_WORKSPACE_CACHES )); then
  for cache_name in "${MLX_WORKSPACE_CACHE_NAMES[@]}"; do
    cache_path="${MLX_WORKSPACE%/}/${cache_name}"
    assert_path_under_workspace "${cache_path}" "workspace cache"
    if path_exists "${cache_path}"; then
      if [[ ! -d "${cache_path}" ]]; then
        log_warn "Skipping non-directory workspace cache path: ${cache_path}"
        continue
      fi
      queue_remove "${cache_path}" "workspace cache/output"
    fi
  done
fi

# --- Hugging Face hub cache (opt-in, shared with other tools) ---
if (( REMOVE_HF_CACHE )); then
  hf_hub="$(canonical_path "$(huggingface_hub_cache)")" || die "Cannot resolve Hugging Face hub cache"
  assert_huggingface_hub_cache_safe "${hf_hub}"
  queue_remove "${hf_hub}" "Hugging Face hub cache (downloaded models; shared with other tools)"
fi

if (( ${#PLANNED_PATHS[@]} == 0 )); then
  log_ok "Nothing to remove."
  print_leftovers
  if (( DRY_RUN )); then
    log_ok "Dry-run completed; no files were removed."
  else
    log_ok "Cleanup completed successfully."
  fi
  exit 0
fi

confirm_unless_forced

log_header "Removals"
for idx in "${!PLANNED_PATHS[@]}"; do
  remove_path "${PLANNED_PATHS[$idx]}"
done

print_leftovers
if (( DRY_RUN )); then
  log_ok "Dry-run completed; no files were removed."
else
  log_ok "Cleanup completed successfully."
fi
