#!/usr/bin/env bash
# Logging, validation helpers, workspace path guards, and argv parsing.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

log_info()  { printf '%s%s%s\n' "${COLOR_BLUE}" "INFO: $*" "${COLOR_RESET}"; }
log_ok()    { printf '%s%s%s\n' "${COLOR_GREEN}" "OK: $*" "${COLOR_RESET}"; }
log_warn()  { printf '%s%s%s\n' "${COLOR_YELLOW}" "WARN: $*" "${COLOR_RESET}" >&2; }
log_error() { printf '%s%s%s\n' "${COLOR_RED}" "ERROR: $*" "${COLOR_RESET}" >&2; }
log_header() {
  printf '\n%s%s%s\n' "${COLOR_BOLD}" "=== $* ===" "${COLOR_RESET}"
}


die() {
  log_error "$*"
  exit 1
}


require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    if [[ -n "${hint}" ]]; then
      die "Required command not found: ${cmd}. ${hint}"
    fi
    die "Required command not found: ${cmd}"
  fi
}


is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Positive decimal integer with no sign and no leading zero: 1, 2, 2048.

# Positive decimal integer with no sign and no leading zero: 1, 2, 2048.
require_positive_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    die "${name} must be a positive integer (got '${value}')"
  fi
}

# Image/video width, height, frames, and steps. Six digits stay inside bash's
# signed 64-bit arithmetic, so a longer value cannot wrap and look valid.

# Image/video width, height, frames, and steps. Six digits stay inside bash's
# signed 64-bit arithmetic, so a longer value cannot wrap and look valid.
require_media_count() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[1-9][0-9]{0,5}$ ]]; then
    die "${name} must be a positive integer from 1 to 999999 (got '${value}')"
  fi
}

# Non-negative decimal integer with no sign and no leading zero: 0, 1, 42.

# Non-negative decimal integer with no sign and no leading zero: 0, 1, 42.
require_nonnegative_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^(0|[1-9][0-9]*)$ ]]; then
    die "${name} must be a non-negative integer (got '${value}')"
  fi
}

# mflux --quantize bits. 7 is not a supported weight width.

# mflux --quantize bits. 7 is not a supported weight width.
require_quantize_bits() {
  local name="$1"
  local value="$2"
  case "${value}" in
    3|4|5|6|8) ;;
    *) die "${name} must be 3, 4, 5, 6, or 8 (got '${value}')" ;;
  esac
}

# Finite non-negative decimal: 0, 0.7, 10, .5, 5., 1.
# Signs, exponents, nan, inf, and strings longer than 16 characters are
# rejected so Python cannot turn the value into infinity.

# Finite non-negative decimal: 0, 0.7, 10, .5, 5., 1.
# Signs, exponents, nan, inf, and strings longer than 16 characters are
# rejected so Python cannot turn the value into infinity.
require_nonnegative_number() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^([0-9]+(\.[0-9]*)?|\.[0-9]+)$ ]] || (( ${#value} > 16 )); then
    die "${name} must be a finite non-negative number (got '${value}')"
  fi
}

# Integer TCP port in 1..65535. Leading zeros are rejected.

# Integer TCP port in 1..65535. Leading zeros are rejected.
require_tcp_port() {
  local name="$1"
  local value="$2"
  local port
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]] || (( ${#value} > 5 )); then
    die "${name} must be an integer TCP port from 1 to 65535 (got '${value}')"
  fi
  port=$((10#${value}))
  if (( port < 1 || port > 65535 )); then
    die "${name} must be an integer TCP port from 1 to 65535 (got '${value}')"
  fi
}


trim_whitespace() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

# Parse machdep.cpu.brand_string. Longest SKU match: Ultra, then Max, then Pro, then base.
# "Apple M1 Pro" → family 1, sku pro (not base). "Apple M10" → family 10 (not 1).
# Emit: family|sku   (empty fields on failure)

# True when argv contains FLAG or FLAG=value.
argv_has_flag() {
  local flag="$1"
  shift
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "${flag}" || "${arg}" == "${flag}="* ]]; then
      return 0
    fi
  done
  return 1
}

# Print each value bound to FLAG in argv (--flag VALUE and --flag=VALUE).

# Print each value bound to FLAG in argv (--flag VALUE and --flag=VALUE).
argv_flag_values() {
  local flag="$1"
  shift
  local argc=$#
  local i=1
  local arg
  while (( i <= argc )); do
    arg="${!i}"
    if [[ "${arg}" == "${flag}" ]]; then
      (( i++ ))
      if (( i <= argc )); then
        printf '%s\n' "${!i}"
      fi
      (( i++ ))
      continue
    fi
    if [[ "${arg}" == "${flag}="* ]]; then
      printf '%s\n' "${arg#"${flag}="}"
    fi
    (( i++ ))
  done
}

# Probe mx.set_wired_limit / set_memory_limit / set_cache_limit from the Metal working set.
# Limits are process-local: this subprocess cannot enforce them on later CLI processes.
# Used by validate-mlx.sh as an API/working-set check. Constrained never exceeds
# max_recommended_working_set_size and uses MLX_CONSTRAINED_CACHE_LIMIT_BYTES.
# Prints KEY=value lines. No-op when mlx/Metal is missing.

# Absolute physical path: resolve . / .. and follow existing directory symlinks.
# Missing final components are appended to the longest existing ancestor.
canonical_path() {
  local path="${1:-}"
  local current next suffix resolved part rest
  [[ -n "${path}" ]] || return 1

  if [[ "${path}" != /* ]]; then
    path="${PWD%/}/${path}"
  fi
  while [[ "${path}" != "/" && "${path}" == */ ]]; do
    path="${path%/}"
  done

  if [[ -d "${path}" ]]; then
    (cd "${path}" && pwd -P)
    return 0
  fi

  if [[ -e "${path}" || -L "${path}" ]]; then
    next="$(cd "$(dirname "${path}")" && pwd -P)" || return 1
    printf '%s/%s\n' "${next}" "$(basename "${path}")"
    return 0
  fi

  suffix=""
  current="${path}"
  while [[ "${current}" != "/" && ! -d "${current}" ]]; do
    next="$(basename "${current}")"
    current="$(dirname "${current}")"
    suffix="/${next}${suffix}"
  done

  if [[ -d "${current}" ]]; then
    resolved="$(cd "${current}" && pwd -P)" || return 1
  else
    resolved="/"
  fi

  rest="${suffix#/}"
  while [[ -n "${rest}" ]]; do
    if [[ "${rest}" == */* ]]; then
      part="${rest%%/*}"
      rest="${rest#*/}"
    else
      part="${rest}"
      rest=""
    fi
    if [[ -z "${part}" || "${part}" == "." ]]; then
      continue
    fi
    if [[ "${part}" == ".." ]]; then
      if [[ "${resolved}" != "/" ]]; then
        resolved="$(dirname "${resolved}")"
      fi
      continue
    fi
    resolved="${resolved%/}/${part}"
    if [[ -d "${resolved}" ]]; then
      resolved="$(cd "${resolved}" && pwd -P)" || return 1
    fi
  done
  printf '%s\n' "${resolved}"
}

# True when inner is outer, or a path under outer (after callers canonicalize).
# An outer of / contains every path. Strip trailing slashes only after that
# check: ${path%/} turns / into the empty string.

# True when inner is outer, or a path under outer (after callers canonicalize).
# An outer of / contains every path. Strip trailing slashes only after that
# check: ${path%/} turns / into the empty string.
path_is_within() {
  local inner="$1"
  local outer="$2"
  [[ -n "${inner}" && -n "${outer}" ]] || return 1
  if [[ "${outer}" == "/" ]]; then
    return 0
  fi
  inner="${inner%/}"
  outer="${outer%/}"
  [[ -n "${inner}" && -n "${outer}" ]] || return 1
  [[ "${inner}" == "${outer}" || "${inner}" == "${outer}/"* ]]
}


assert_workspace_safe() {
  local orig="${MLX_WORKSPACE:-}"
  [[ -n "${orig}" ]] || die "MLX_WORKSPACE is empty"
  [[ -d "${orig}" ]] || die "Expected workspace missing: ${orig}"
  MLX_WORKSPACE="$(canonical_path "${orig}")" || die "Cannot resolve workspace: ${orig}"
  [[ "${MLX_WORKSPACE}" != "/" ]] || die "Refusing to operate on workspace /"
}

# Volume roots and other directories that are not a project workspace.
# macOS canonicalizes /var/tmp to /private/var/tmp and /etc to /private/etc.

# Volume roots and other directories that are not a project workspace.
# macOS canonicalizes /var/tmp to /private/var/tmp and /etc to /private/etc.
workspace_is_system_root() {
  local ws="$1"
  [[ "${ws}" == "/" ]] && return 0
  ws="${ws%/}"
  [[ -n "${ws}" ]] || return 0
  case "${ws}" in
    /|/Users|/home|/Volumes|/opt|/private|/tmp|/var|/usr|/bin|/sbin|/etc|/System|/Library|/Applications|/dev|/proc|/private/tmp|/private/var|/private/etc|/private/var/tmp|/private/var/folders|/var/tmp|/opt/homebrew|/usr/local|/System/Volumes/Data|/System/Volumes/Data/Users|/Users/Shared)
      return 0
      ;;
  esac
  if [[ "${ws}" == /Volumes/* && "${ws#/Volumes/}" != */* ]]; then
    return 0
  fi
  return 1
}

# True when purging this workspace could delete home or system files.

# True when purging this workspace could delete home or system files.
workspace_purge_forbidden() {
  local ws="$1"
  local home
  home="$(canonical_path "${HOME}")" || return 0
  if path_is_within "${home}" "${ws}"; then
    return 0
  fi
  workspace_is_system_root "${ws}"
}

# True only for this checkout. Another tree that happens to contain a Makefile
# and scripts/lib/common.sh is not this repository and needs .mlx-workspace.

# True only for this checkout. Another tree that happens to contain a Makefile
# and scripts/lib/common.sh is not this repository and needs .mlx-workspace.
workspace_is_repo_root() {
  local ws="${1:-${MLX_WORKSPACE}}"
  local ws_c root_c
  ws_c="$(canonical_path "${ws}")" || return 1
  root_c="$(canonical_path "${REPO_ROOT}")" || return 1
  [[ "${ws_c}" == "${root_c}" ]]
}


workspace_has_purge_marker() {
  local ws="${1:-${MLX_WORKSPACE}}"
  local marker
  if workspace_is_repo_root "${ws}"; then
    return 0
  fi
  marker="${ws}/${MLX_WORKSPACE_SENTINEL_NAME}"
  [[ -f "${marker}" && ! -L "${marker}" ]]
}

# Refuse --purge / --workspace-caches on $HOME, a parent of $HOME, a system
# root, or a directory the toolkit has not marked.

# Refuse --purge / --workspace-caches on $HOME, a parent of $HOME, a system
# root, or a directory the toolkit has not marked.
assert_workspace_purge_safe() {
  local ws home
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  home="$(canonical_path "${HOME}")" || die "Cannot resolve HOME"
  if path_is_within "${home}" "${ws}"; then
    die "Refusing to purge workspace that is \$HOME or a parent of it: ${ws}"
  fi
  if workspace_is_system_root "${ws}"; then
    die "Refusing to purge system path: ${ws}"
  fi
  if ! workspace_has_purge_marker "${ws}"; then
    die "Refusing to purge ${ws} without a toolkit marker (${MLX_WORKSPACE_SENTINEL_NAME} or this repository checkout)"
  fi
}

# Claim a dedicated non-repo workspace. Does not write the marker into $HOME
# or a system root; purge stays refused there.

# Claim a dedicated non-repo workspace. Does not write the marker into $HOME
# or a system root; purge stays refused there.
ensure_mlx_workspace_marker() {
  local ws dest
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  if workspace_is_repo_root "${ws}"; then
    return 0
  fi
  if workspace_purge_forbidden "${ws}"; then
    log_warn "Not writing ${MLX_WORKSPACE_SENTINEL_NAME} in ${ws}; make clean --purge will refuse this workspace."
    return 0
  fi
  dest="${ws}/${MLX_WORKSPACE_SENTINEL_NAME}"
  if [[ -L "${dest}" ]]; then
    die "Refusing to follow symlink workspace marker: ${dest}"
  fi
  if [[ -e "${dest}" && ! -f "${dest}" ]]; then
    die "Workspace marker exists but is not a file: ${dest}"
  fi
  if [[ -f "${dest}" ]]; then
    return 0
  fi
  printf '%s\n' \
    "# apple-silicon-mlx-native workspace" \
    "# make clean --purge may remove toolkit caches in this directory." \
    >"${dest}"
  log_info "Wrote workspace marker ${dest}"
}

# True when root itself is a Hugging Face tree: a hub directory or a token file.

# True when root itself is a Hugging Face tree: a hub directory or a token file.
path_is_hf_tree() {
  local root="$1"
  [[ -n "${root}" ]] || return 1
  [[ -d "${root}/hub" || -f "${root}/token" ]]
}

# True when root is an HF tree, or contains huggingface/ or .huggingface/ that is.
# Callers pass both the unresolved path and its canonical path. A .cache symlink
# canonicalizes to another basename, so the unresolved path must be checked too.

# True when root is an HF tree, or contains huggingface/ or .huggingface/ that is.
# Callers pass both the unresolved path and its canonical path. A .cache symlink
# canonicalizes to another basename, so the unresolved path must be checked too.
path_contains_hf_tree() {
  local root="$1"
  local name base
  [[ -n "${root}" ]] || return 1
  base="$(basename "${root}")"
  case "${base}" in
    huggingface|.huggingface)
      path_is_hf_tree "${root}" && return 0
      ;;
  esac
  for name in huggingface .huggingface; do
    path_is_hf_tree "${root}/${name}" && return 0
  done
  return 1
}

# True when removing this directory would also remove Hugging Face home,
# the hub cache, or a huggingface tree (including through a .cache symlink
# and a top-level huggingface/ or .huggingface/ workspace cache).

# True when removing this directory would also remove Hugging Face home,
# the hub cache, or a huggingface tree (including through a .cache symlink
# and a top-level huggingface/ or .huggingface/ workspace cache).
workspace_cache_holds_huggingface() {
  local cache="$1"
  local cache_c hf_home hf_home_c hf_hub hf_hub_c
  [[ -n "${cache}" ]] || return 1
  cache_c="$(canonical_path "${cache}")" || return 1
  hf_home="${HF_HOME:-${HOME}/.cache/huggingface}"
  hf_home_c="$(canonical_path "${hf_home}")" || return 1
  hf_hub="$(huggingface_hub_cache_dir)"
  hf_hub_c="$(canonical_path "${hf_hub}")" || return 1
  if path_is_within "${hf_home_c}" "${cache_c}"; then
    return 0
  fi
  if path_is_within "${hf_hub_c}" "${cache_c}"; then
    return 0
  fi
  if path_contains_hf_tree "${cache}"; then
    return 0
  fi
  path_contains_hf_tree "${cache_c}"
}


assert_path_under_workspace() {
  local orig="$1"
  local label="${2:-path}"
  local path ws
  [[ -n "${orig}" ]] || die "Refusing empty ${label}"
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  path="$(canonical_path "${orig}")" || die "Cannot resolve ${label}: ${orig}"
  [[ "${path}" != "/" ]] || die "Refusing to remove /"
  [[ "${path}" != "${ws}" ]] || die "Refusing to remove workspace root as ${label}: ${orig}"
  [[ "${path}" == "${ws}/"* ]] || die "Refusing to remove ${label} outside workspace: ${orig} (resolves to ${path})"
}


human_du() {
  local target="$1"
  if [[ -e "${target}" ]]; then
    du -sh "${target}" 2>/dev/null | awk '{print $1}'
  else
    echo "absent"
  fi
}


model_list_chip_family_label() {
  if [[ -n "${OVERRIDE_MEMORY_TIER:-}" || -n "${OVERRIDE_CHIP_FAMILY:-}" || -n "${OVERRIDE_CHIP_SKU:-}" \
    || -n "${OVERRIDE_GPU_CORES:-}" || -n "${OVERRIDE_THERMAL_CLASS:-}" ]]; then
    printf '%s\n' "Chip family/SKU (policy):"
  else
    printf '%s\n' "Chip family/SKU:"
  fi
}

# Catalog rows for make list-image. id|family|upstream repo|weights|use
# Upstream repos are what mflux downloads for that preset. Fit is computed.
