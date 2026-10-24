#!/usr/bin/env bash
# Homebrew, venv lifecycle, pip constraints, and core package installs.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only



homebrew_prefix() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    echo "/opt/homebrew"
  elif [[ -x /usr/local/bin/brew ]]; then
    echo "/usr/local"
  elif command -v brew >/dev/null 2>&1; then
    brew --prefix
  else
    echo ""
  fi
}


ensure_homebrew_in_path() {
  local prefix
  prefix="$(homebrew_prefix)"
  if [[ -n "${prefix}" && -x "${prefix}/bin/brew" ]]; then
    export PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
  fi
}


check_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Python for short helper scripts (JSON emit, safetensors index). Prefer the project
# venv or Homebrew python so macOS /usr/bin/python3 does not trigger the CLT stub.

# Python for short helper scripts (JSON emit, safetensors index). Prefer the project
# venv or Homebrew python so macOS /usr/bin/python3 does not trigger the CLT stub.
resolve_auxiliary_python() {
  local py prefix
  if [[ -x "${MLX_VENV}/bin/python" ]]; then
    printf '%s\n' "${MLX_VENV}/bin/python"
    return 0
  fi
  ensure_homebrew_in_path
  prefix="$(homebrew_prefix)"
  if [[ -n "${prefix}" ]]; then
    py="${prefix}/opt/python@${MLX_PYTHON_VERSION}/bin/python${MLX_PYTHON_VERSION}"
    if [[ -x "${py}" ]]; then
      printf '%s\n' "${py}"
      return 0
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    py="$(command -v python3)"
    if [[ "$(uname -s)" == "Darwin" && "${py}" == "/usr/bin/python3" ]] && ! check_xcode_clt; then
      return 1
    fi
    printf '%s\n' "${py}"
    return 0
  fi
  return 1
}


venv_python() {
  echo "${MLX_VENV}/bin/python"
}


venv_pip() {
  echo "${MLX_VENV}/bin/pip"
}

# Print installed pip/setuptools/wheel versions. Warn when an exact pin does
# not match. Does not fail the caller; install_packaging_tools still fails
# if the install itself fails.

# Print installed pip/setuptools/wheel versions. Warn when an exact pin does
# not match. Does not fail the caller; install_packaging_tools still fails
# if the install itself fails.
report_packaging_tools() {
  local py="${1:-$(venv_python)}"
  local versions name installed spec pin line
  if [[ ! -x "${py}" ]]; then
    log_warn "Packaging tools not reported; Python not found at ${py}"
    return 0
  fi
  if ! versions="$("${py}" -c 'import importlib.metadata as m
for name in ("pip", "setuptools", "wheel", "packaging"):
    try:
        print(name + " " + m.version(name))
    except m.PackageNotFoundError:
        print(name + " missing")
')"; then
    log_warn "Could not read pip, setuptools, wheel, and packaging versions"
    return 0
  fi
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    name="${line%% *}"
    installed="${line#* }"
    case "${name}" in
      pip) spec="${MLX_PIP_PACKAGE}" ;;
      setuptools) spec="${MLX_SETUPTOOLS_PACKAGE}" ;;
      wheel) spec="${MLX_WHEEL_PACKAGE}" ;;
      packaging) spec="${MLX_PACKAGING_LIB_PACKAGE}" ;;
      *) spec="" ;;
    esac
    # Exact pins only. Wildcard specs (setuptools==84.*) and === are not
    # plain string compares, so they are reported as the configured spec.
    if [[ "${spec}" == *==* && "${spec}" != *===* && "${spec}" != *'*'* ]]; then
      pin="${spec#*==}"
      if [[ "${installed}" == "${pin}" ]]; then
        log_ok "Packaging tool ${name} ${installed}"
      else
        log_warn "Packaging tool ${name} ${installed} (pin ${spec})"
      fi
    elif [[ -n "${spec}" ]]; then
      log_info "Packaging tool ${name} ${installed} (spec ${spec})"
    else
      log_info "Packaging tool ${name} ${installed}"
    fi
  done <<< "${versions}"
}

# Live MLX_* specs that may replace a line in the pin manifest.

# Live MLX_* specs that may replace a line in the pin manifest.
_constraint_override_specs() {
  printf '%s\n' \
    "${MLX_PIP_PACKAGE}" \
    "${MLX_SETUPTOOLS_PACKAGE}" \
    "${MLX_WHEEL_PACKAGE}" \
    "${MLX_PACKAGING_LIB_PACKAGE}" \
    "${MLX_PACKAGE}" \
    "${MLX_LM_PACKAGE}" \
    "${MLX_AUDIO_PACKAGE}" \
    "${MLX_IMAGE_PACKAGE}"
  _mlx_metal_companion_spec
}

# mlx requires mlx-metal at the same release. When MLX_PACKAGE overrides the
# manifest mlx pin, retarget that backend pin to the same exact version, or
# drop it when the override is not name==version. A bare MLX_PACKAGE=mlx would
# otherwise stay locked to the old mlx-metal pin.
_mlx_metal_companion_spec() {
  local spec="${MLX_PACKAGE}"
  local manifest metal_line version
  manifest="$(_pin_default mlx "")"
  metal_line="$(_pin_default mlx-metal "")"
  [[ -n "${manifest}" && -n "${metal_line}" ]] || return 0
  [[ "${spec}" == "${manifest}" ]] && return 0
  if [[ "${spec}" =~ ^mlx==[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
    version="${spec#mlx==}"
    printf 'mlx-metal==%s\n' "${version}"
    return 0
  fi
  # Any other mlx spec (bare name or a range) must not keep the old backend pin.
  # Patterns are split so bash 3.2 does not treat '<' as a redirection.
  case "${spec}" in
    mlx|mlx=*|'mlx>'*|'mlx<'*|mlx'!'*|mlx'~'*)
      printf 'mlx-metal\n'
      ;;
  esac
}

# Export PIP_CONSTRAINT for dependency installs (core, media, and packaging).
# Unchanged specs use requirements/constraints.txt. A one-off override writes
# a workspace copy that replaces or drops that package's pin so pip does not
# force the manifest version (ResolutionImpossible, or a bare name stuck on
# the old pin). An MLX_PACKAGE override also retargets or drops mlx-metal.

# Export PIP_CONSTRAINT for dependency installs (core, media, and packaging).
# Unchanged specs use requirements/constraints.txt. A one-off override writes
# a workspace copy that replaces or drops that package's pin so pip does not
# force the manifest version (ResolutionImpossible, or a bare name stuck on
# the old pin). An MLX_PACKAGE override also retargets or drops mlx-metal.
export_pip_constraint() {
  local spec name file_line rewritten=0
  local effective="${MLX_WORKSPACE}/.mlx-pip-constraint.txt"
  if [[ ! -f "${MLX_PIP_CONSTRAINT_FILE}" ]]; then
    die "Missing pip constraints file: ${MLX_PIP_CONSTRAINT_FILE}"
  fi
  cp "${MLX_PIP_CONSTRAINT_FILE}" "${effective}"
  while IFS= read -r spec; do
    [[ -n "${spec}" ]] || continue
    name="${spec%%[=<>!~]*}"
    [[ -n "${name}" ]] || continue
    file_line="$(grep -E "^${name}==[^[:space:]]+$" "${MLX_PIP_CONSTRAINT_FILE}" | head -n 1 || true)"
    [[ -n "${file_line}" ]] || continue
    [[ "${spec}" == "${file_line}" ]] && continue
    rewritten=1
    grep -Ev "^${name}==[^[:space:]]+$" "${effective}" >"${effective}.tmp"
    mv "${effective}.tmp" "${effective}"
    if [[ "${spec}" =~ ^[A-Za-z0-9_.-]+==[^[:space:]]+$ ]]; then
      printf '%s\n' "${spec}" >>"${effective}"
    fi
  done < <(_constraint_override_specs)
  if (( rewritten == 0 )); then
    rm -f "${effective}" "${effective}.tmp"
    export PIP_CONSTRAINT="${MLX_PIP_CONSTRAINT_FILE}"
    return 0
  fi
  rm -f "${effective}.tmp"
  export PIP_CONSTRAINT="${effective}"
}

# Write MLX_PACKAGING_PACKAGES to a constraints file and export PIP_BUILD_CONSTRAINT
# so PEP 517 isolated builds (for example git mlx-video) use the same specs.

# Write MLX_PACKAGING_PACKAGES to a constraints file and export PIP_BUILD_CONSTRAINT
# so PEP 517 isolated builds (for example git mlx-video) use the same specs.
export_pip_build_constraint() {
  local pkg
  local constraint_file="${MLX_PIP_BUILD_CONSTRAINT_FILE}"
  : >"${constraint_file}"
  for pkg in "${MLX_PACKAGING_PACKAGES[@]}"; do
    printf '%s\n' "${pkg}" >>"${constraint_file}"
  done
  export PIP_BUILD_CONSTRAINT="${constraint_file}"
}

# Run pip in the project venv with PIP_CONSTRAINT and PIP_BUILD_CONSTRAINT set.

# Run pip in the project venv with PIP_CONSTRAINT and PIP_BUILD_CONSTRAINT set.
mlx_pip_install() {
  local py
  py="$(venv_python)"
  if [[ ! -x "${py}" ]]; then
    if [[ -d "${MLX_VENV}" ]]; then
      die "Python venv at ${MLX_VENV} is not usable. Run: make rebuild"
    fi
    die "Python venv not found at ${py}. Run: make venv && make install"
  fi
  export_pip_constraint
  export_pip_build_constraint
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  "${py}" -m pip install --disable-pip-version-check "$@"
}

# Install the shared packaging-tool pins into the active venv.

# Install the shared packaging-tool pins into the active venv.
install_packaging_tools() {
  local py
  py="$(venv_python)"
  if [[ ! -x "${py}" ]]; then
    if [[ -d "${MLX_VENV}" ]]; then
      die "Python venv at ${MLX_VENV} is not usable. Run: make rebuild"
    fi
    die "Python venv not found at ${py}. Run: make venv && make install"
  fi
  log_info "Installing pinned packaging tools: ${MLX_PACKAGING_PACKAGES[*]}"
  mlx_pip_install --upgrade "${MLX_PACKAGING_PACKAGES[@]}"
  log_info "Dependency installs constrained via PIP_CONSTRAINT=${PIP_CONSTRAINT}"
  log_info "PEP 517 build isolation constrained via PIP_BUILD_CONSTRAINT=${MLX_PIP_BUILD_CONSTRAINT_FILE}"
  report_packaging_tools "${py}"
}

# Shared core/media/image/video pip installs for initial-build and rebuild.
# Scope: all (default), core, media, image, or video.
install_core_packages() {
  local scope="${1:-all}"
  case "${scope}" in
    all)
      install_core_packages core
      if ! is_truthy "${MLX_SKIP_MEDIA:-0}"; then
        install_core_packages media
      fi
      if is_truthy "${MLX_INSTALL_IMAGE:-0}"; then
        install_core_packages image
      fi
      if is_truthy "${MLX_INSTALL_VIDEO:-0}"; then
        install_core_packages video
      fi
      ;;
    core)
      log_info "Installing pinned core: ${MLX_CORE_PACKAGES[*]}"
      warn_or_die_disk_headroom core-pip
      mlx_pip_install --upgrade "${MLX_CORE_PACKAGES[@]}"
      ;;
    media)
      log_info "Installing Pure MLX speech/audio: ${MLX_MEDIA_PACKAGES[*]}"
      warn_or_die_disk_headroom media-pip
      mlx_pip_install --upgrade "${MLX_MEDIA_PACKAGES[@]}"
      ;;
    image)
      if is_truthy "${MLX_INSTALL_IMAGE:-0}"; then
        warn_or_die_disk_headroom image-pip
        mlx_pip_install --upgrade "${MLX_IMAGE_PACKAGE}"
      fi
      ;;
    video)
      if is_truthy "${MLX_INSTALL_VIDEO:-0}"; then
        warn_or_die_disk_headroom video-pip
        mlx_pip_install --upgrade "${MLX_VIDEO_PACKAGE}"
      fi
      ;;
    *)
      die "install_core_packages: unknown scope '${scope}' (use all, core, media, image, or video)"
      ;;
  esac
}

# Absolute physical path: resolve . / .. and follow existing directory symlinks.
# Missing final components are appended to the longest existing ancestor.

assert_venv_under_workspace() {
  local orig="${MLX_VENV:-}"
  local ws venv
  [[ -n "${orig}" ]] || die "MLX_VENV is empty"
  ws="$(canonical_path "${MLX_WORKSPACE}")" || die "Cannot resolve workspace: ${MLX_WORKSPACE}"
  venv="$(canonical_path "${orig}")" || die "Cannot resolve venv path: ${orig}"
  MLX_VENV="${venv}"
  [[ "${venv}" != "${ws}" ]] || die "Refusing to treat the workspace root as a venv: ${orig}"
  [[ "${venv}" == "${ws}/"* ]] || die "Refusing to remove venv outside workspace: ${orig} (resolves to ${venv})"
}


looks_like_venv() {
  local dir="${1:-${MLX_VENV}}"
  [[ -d "${dir}" ]] || return 1
  [[ -f "${dir}/pyvenv.cfg" || -f "${dir}/bin/python" ]]
}


has_venv_interpreter() {
  local dir="${1:-${MLX_VENV}}"
  [[ -f "${dir}/bin/python" || -f "${dir}/bin/python3" ]]
}


venv_project_python() {
  echo "${1:-${MLX_VENV}}/bin/python"
}

# True when bin/python or bin/python3 is a dangling symlink.

# True when bin/python or bin/python3 is a dangling symlink.
venv_interpreter_symlink_broken() {
  local dir="${1:-${MLX_VENV}}"
  local name py
  for name in python python3; do
    py="${dir}/bin/${name}"
    if [[ -L "${py}" && ! -e "${py}" ]]; then
      return 0
    fi
  done
  return 1
}


pyvenv_cfg_value() {
  local dir="$1"
  local key="$2"
  [[ -f "${dir}/pyvenv.cfg" ]] || return 1
  awk -v k="${key}" -F' = ' '$1 == k { sub(/^ +| +$/, "", $2); print $2; exit }' "${dir}/pyvenv.cfg"
}


venv_python_has_pip() {
  local dir="${1:-${MLX_VENV}}"
  local py
  py="$(venv_project_python "${dir}")"
  [[ -x "${py}" ]] || return 1
  "${py}" -m pip --version >/dev/null 2>&1
}

# True when bin/pip itself runs. python -m pip can succeed while the script's
# shebang still points at a directory that was renamed away.

# True when bin/pip itself runs. python -m pip can succeed while the script's
# shebang still points at a directory that was renamed away.
venv_pip_script_runs() {
  local dir="${1:-${MLX_VENV}}"
  local pip="${dir}/bin/pip"
  [[ -f "${pip}" && -x "${pip}" ]] || return 1
  "${pip}" --version >/dev/null 2>&1
}


python_major_minor() {
  local ver="$1"
  local rest minor
  rest="${ver#*.}"
  minor="${rest%%.*}"
  printf '%s.%s' "${ver%%.*}" "${minor}"
}

_python_minor_ge() {
  local have want
  have="$1"
  want="$2"
  awk -v h="${have}" -v w="${want}" 'BEGIN {
    split(h, H, ".");
    split(w, W, ".");
    if ((H[1] + 0) > (W[1] + 0)) { exit 0; }
    if ((H[1] + 0) < (W[1] + 0)) { exit 1; }
    if ((H[2] + 0) >= (W[2] + 0)) { exit 0; }
    exit 1;
  }'
}

_python_minor_le() {
  local have want
  have="$1"
  want="$2"
  awk -v h="${have}" -v w="${want}" 'BEGIN {
    split(h, H, ".");
    split(w, W, ".");
    if ((H[1] + 0) < (W[1] + 0)) { exit 0; }
    if ((H[1] + 0) > (W[1] + 0)) { exit 1; }
    if ((H[2] + 0) <= (W[2] + 0)) { exit 0; }
    exit 1;
  }'
}

assert_mlx_python_version_supported() {
  local ver minor
  ver="${MLX_PYTHON_VERSION}"
  case "${ver}" in
    *.*.*)
      die "MLX_PYTHON_VERSION must be major.minor (for example 3.12), not a patch release: ${ver}"
      ;;
    *.*) ;;
    *)
      die "MLX_PYTHON_VERSION must be major.minor (for example 3.12), got: ${ver}"
      ;;
  esac
  minor="$(python_major_minor "${ver}")"
  _python_minor_ge "${minor}" "${MLX_PYTHON_VERSION_MIN}" \
    || die "MLX_PYTHON_VERSION=${ver} is below the supported range (${MLX_PYTHON_VERSION_MIN}–${MLX_PYTHON_VERSION_MAX}). See docs/troubleshooting.md#python-version-venv"
  _python_minor_le "${minor}" "${MLX_PYTHON_VERSION_MAX}" \
    || die "MLX_PYTHON_VERSION=${ver} is above the supported range (${MLX_PYTHON_VERSION_MIN}–${MLX_PYTHON_VERSION_MAX}). See docs/troubleshooting.md#python-version-venv"
}

assert_minimum_macos_for_mlx() {
  local ver major
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  ver="$(detect_macos_version)"
  major="${ver%%.*}"
  [[ -n "${major}" && "${major}" -ge 14 ]] \
    || die "macOS ${ver} is below the minimum supported major version (14). See docs/troubleshooting.md"
}

venv_version_matches_expected() {
  local dir="${1:-${MLX_VENV}}"
  local cfg_ver cfg_minor expected_minor
  cfg_ver="$(pyvenv_cfg_value "${dir}" version)" || return 1
  [[ -n "${cfg_ver}" ]] || return 1
  cfg_minor="$(python_major_minor "${cfg_ver}")"
  expected_minor="$(python_major_minor "${MLX_PYTHON_VERSION}")"
  [[ "${cfg_minor}" == "${expected_minor}" ]]
}


venv_home_under_homebrew() {
  local dir="${1:-${MLX_VENV}}"
  local prefix cfg_home
  prefix="$(homebrew_prefix)"
  [[ -n "${prefix}" ]] || return 1
  cfg_home="$(pyvenv_cfg_value "${dir}" home)" || return 1
  [[ -n "${cfg_home}" ]] || return 1
  [[ "${cfg_home}" == "${prefix}" || "${cfg_home}" == "${prefix}/"* ]]
}

# make venv reuse: Homebrew python@MLX_PYTHON_VERSION with a working pip.

# make venv reuse: Homebrew python@MLX_PYTHON_VERSION with a working pip.
assert_reusable_brew_venv_for_make_venv() {
  local dir="${1:-${MLX_VENV}}"
  local cfg_ver cfg_home prefix
  if venv_interpreter_symlink_broken "${dir}"; then
    die "Refusing to reuse broken venv (interpreter symlink is broken): ${dir}. Run: make rebuild"
  fi
  [[ -x "$(venv_project_python "${dir}")" ]] || die "Refusing to reuse incomplete venv at ${dir}. Run: make rebuild"
  if ! venv_python_has_pip "${dir}"; then
    die "Refusing to reuse incomplete venv (pip is missing or broken) at ${dir}. Run: make rebuild"
  fi
  if ! venv_pip_script_runs "${dir}"; then
    die "Refusing to reuse incomplete venv (bin/pip does not run) at ${dir}. Run: make rebuild"
  fi
  if ! venv_version_matches_expected "${dir}"; then
    cfg_ver="$(pyvenv_cfg_value "${dir}" version || echo unknown)"
    die "Refusing to reuse venv (Python ${cfg_ver} does not match expected ${MLX_PYTHON_VERSION}): ${dir}. Run: make rebuild"
  fi
  prefix="$(homebrew_prefix)"
  if ! venv_home_under_homebrew "${dir}"; then
    cfg_home="$(pyvenv_cfg_value "${dir}" home || echo unknown)"
    die "Refusing to reuse venv (pyvenv.cfg home ${cfg_home} is not under Homebrew prefix ${prefix}): ${dir}. Run: make rebuild"
  fi
}

# Sibling directories left when an atomic create is killed before rename:
# <dest>.partial.<pid>. Names that are not that pattern are ignored.

# Sibling directories left when an atomic create is killed before rename:
# <dest>.partial.<pid>. Names that are not that pattern are ignored.
list_stale_venv_partials() {
  local dest="$1"
  local stale base name suffix nullglob_state
  base="$(basename "${dest}")"
  [[ -n "${base}" && "${base}" != "/" && "${base}" != "." && "${base}" != ".." ]] || return 0
  nullglob_state="$(shopt -p nullglob || true)"
  shopt -s nullglob
  for stale in "${dest}.partial."*; do
    [[ -d "${stale}" && ! -L "${stale}" ]] || continue
    name="$(basename "${stale}")"
    suffix="${name#"${base}.partial."}"
    [[ "${name}" == "${base}.partial.${suffix}" ]] || continue
    case "${suffix}" in
      ''|*[!0-9]*) continue ;;
    esac
    printf '%s\n' "${stale}"
  done
  _restore_nullglob "${nullglob_state}"
}

# Python's venv records the creation path in bin/pip, bin/activate, and
# pyvenv.cfg. Rewrite that temporary path to the final destination before rename.

# Python's venv records the creation path in bin/pip, bin/activate, and
# pyvenv.cfg. Rewrite that temporary path to the final destination before rename.
rewrite_relocated_venv_paths() {
  local brew_py="$1"
  local partial="$2"
  local dest="$3"
  local old_base new_base
  old_base="$(basename "${partial}")"
  new_base="$(basename "${dest}")"
  [[ "${partial}" == "${dest}.partial."* ]] || die "Refusing to relocate venv with unexpected temporary path: ${partial}"
  [[ -n "${old_base}" && "${old_base}" != "${new_base}" ]] || die "Refusing to relocate venv onto the same path: ${dest}"
  "${brew_py}" - "${partial}" "${dest}" "${old_base}" "${new_base}" "${partial}" <<'PY' || die "Venv creation failed: could not rewrite temporary path in ${partial}"
import os
import sys

old_path, new_path, old_base, new_base, root = sys.argv[1:]
old_path_b = old_path.encode()
new_path_b = new_path.encode()
old_base_b = old_base.encode()
new_base_b = new_base.encode()
if not old_path_b or not new_path_b or not old_base_b or old_base_b == new_base_b:
    sys.stderr.write("refusing empty venv path rewrite\n")
    sys.exit(1)

for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
    dirnames[:] = [entry for entry in dirnames if not os.path.islink(os.path.join(dirpath, entry))]
    for name in filenames:
        path = os.path.join(dirpath, name)
        if os.path.islink(path):
            continue
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError as exc:
            sys.stderr.write(f"cannot read {path}: {exc}\n")
            sys.exit(1)
        if old_path_b not in data and old_base_b not in data:
            continue
        # Compiled files record the creation path as co_filename. Their string
        # lengths are prefixed, so a byte replace would corrupt them. They are
        # removed below and recreated on the next import from the final path.
        if b"\0" in data:
            continue
        updated = data.replace(old_path_b, new_path_b).replace(old_base_b, new_base_b)
        with open(path, "wb") as handle:
            handle.write(updated)

for dirpath, _dirnames, _filenames in os.walk(root, topdown=False, followlinks=False):
    if os.path.basename(dirpath) != "__pycache__" or os.path.islink(dirpath):
        continue
    for name in os.listdir(dirpath):
        cache_path = os.path.join(dirpath, name)
        if os.path.islink(cache_path) or os.path.isfile(cache_path):
            os.remove(cache_path)
    os.rmdir(dirpath)
PY
}

# True when pid is running. kill -0 EPERM (another user's process) is treated as alive.

# True when pid is running. kill -0 EPERM (another user's process) is treated as alive.
pid_is_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] || return 1
  if kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  ps -p "${pid}" >/dev/null 2>&1
}

# Exclusive lock for one destination: ${dest}.create-lock/pid.
# mkdir is atomic. A live pid owns the lock; a dead pid is abandoned and replaced.
# Before removing a stale lock, re-read pid so two waiters cannot both delete a
# fresh lock another process just created. Prints the lock directory. Callers
# must remove it on the success path; the EXIT trap removes it when create fails.

# Exclusive lock for one destination: ${dest}.create-lock/pid.
# mkdir is atomic. A live pid owns the lock; a dead pid is abandoned and replaced.
# Before removing a stale lock, re-read pid so two waiters cannot both delete a
# fresh lock another process just created. Prints the lock directory. Callers
# must remove it on the success path; the EXIT trap removes it when create fails.
acquire_venv_create_lock() {
  local dest="$1"
  local lock pid stale_owner current_owner empty_seen waited logged_wait lock_timeout deadline
  lock="${dest}.create-lock"
  empty_seen=0
  waited=0
  logged_wait=0
  lock_timeout="${MLX_VENV_LOCK_TIMEOUT:-300}"
  case "${lock_timeout}" in
    ''|*[!0-9]*) lock_timeout=300 ;;
  esac
  deadline=$((SECONDS + lock_timeout))
  while (( SECONDS < deadline )); do
    if mkdir -- "${lock}" 2>/dev/null; then
      if printf '%s\n' "$$" >"${lock}/pid"; then
        printf '%s\n' "${lock}"
        return 0
      fi
      rm -rf -- "${lock}"
      die "Could not record venv create lock owner in ${lock}"
    fi
    if [[ -L "${lock}" || ! -d "${lock}" ]]; then
      die "Refusing to replace venv create lock that is not a directory: ${lock}"
    fi
    pid=""
    if [[ -f "${lock}/pid" && ! -L "${lock}/pid" ]]; then
      IFS= read -r pid <"${lock}/pid" || pid=""
    fi
    case "${pid}" in
      ''|*[!0-9]*) pid="" ;;
    esac
    if [[ -z "${pid}" ]]; then
      empty_seen=$((empty_seen + 1))
      if (( empty_seen < 5 )); then
        sleep 0.2
        waited=$((waited + 1))
        continue
      fi
    elif pid_is_alive "${pid}"; then
      if (( logged_wait == 0 )); then
        printf 'INFO: Waiting for venv create lock held by pid %s\n' "${pid}" >&2
        logged_wait=1
      fi
      empty_seen=0
      sleep 0.2
      waited=$((waited + 1))
      continue
    fi
    stale_owner="${pid}"
    current_owner=""
    if [[ -f "${lock}/pid" && ! -L "${lock}/pid" ]]; then
      IFS= read -r current_owner <"${lock}/pid" || current_owner=""
    fi
    case "${current_owner}" in
      ''|*[!0-9]*) current_owner="" ;;
    esac
    if [[ -n "${stale_owner}" ]]; then
      if [[ "${current_owner}" != "${stale_owner}" ]]; then
        empty_seen=0
        sleep 0.2
        waited=$((waited + 1))
        continue
      fi
      if pid_is_alive "${stale_owner}"; then
        empty_seen=0
        sleep 0.2
        waited=$((waited + 1))
        continue
      fi
    elif [[ -n "${current_owner}" ]]; then
      empty_seen=0
      sleep 0.2
      waited=$((waited + 1))
      continue
    fi
    rm -rf -- "${lock}"
    empty_seen=0
  done
  die "Timed out waiting for venv create lock: ${lock}"
}

# True when a finished venv still mentions the temporary directory name.

# True when a finished venv still mentions the temporary directory name.
venv_records_temporary_path() {
  local dest="$1"
  local marker="$2"
  local file nullglob_state
  [[ -n "${marker}" ]] || return 1
  if [[ -f "${dest}/pyvenv.cfg" ]] && grep -F -q -- "${marker}" "${dest}/pyvenv.cfg"; then
    return 0
  fi
  nullglob_state="$(shopt -p nullglob || true)"
  shopt -s nullglob
  for file in "${dest}/bin/"*; do
    [[ -f "${file}" && ! -L "${file}" ]] || continue
    if grep -F -q -- "${marker}" "${file}"; then
      _restore_nullglob "${nullglob_state}"
      return 0
    fi
  done
  _restore_nullglob "${nullglob_state}"
  return 1
}

# `trap -p EXIT` text. Empty when the caller has no EXIT trap.

# `trap -p EXIT` text. Empty when the caller has no EXIT trap.
_exit_trap_spec() {
  trap -p EXIT || true
}

# Install an EXIT trap that removes paths this create owns, then runs the
# caller's EXIT command. Bash traps are process-global, so replacing EXIT
# without chaining would drop the caller's cleanup when create fails.
# saved_spec is the caller's trap from before this function installed its own.

# Install an EXIT trap that removes paths this create owns, then runs the
# caller's EXIT command. Bash traps are process-global, so replacing EXIT
# without chaining would drop the caller's cleanup when create fails.
# saved_spec is the caller's trap from before this function installed its own.
_install_owned_exit_trap() {
  local cleanup="$1"
  local saved_spec="$2"
  local raw body quoted_body
  if [[ -z "${saved_spec}" ]]; then
    # shellcheck disable=SC2064,SC2154
    trap 'rc=$?; '"${cleanup}"'; exit "$rc"' EXIT
    return 0
  fi
  raw="${saved_spec#trap -- }"
  raw="${raw% EXIT}"
  eval "body=${raw}"
  if [[ -z "${body}" ]]; then
    # shellcheck disable=SC2064,SC2154
    trap 'rc=$?; '"${cleanup}"'; exit "$rc"' EXIT
    return 0
  fi
  quoted_body="$(printf '%q' "${body}")"
  # Capture $? before owned rm -rf so a caller trap that reads $? still sees
  # the failure that triggered EXIT, not the cleanup status. set +e around
  # (exit "$rc") keeps errexit from aborting the trap before the saved handler.
  # shellcheck disable=SC2064,SC2154
  trap 'rc=$?; '"${cleanup}"'; set +e; (exit "$rc"); eval '"${quoted_body}"'; set -e; exit "$rc"' EXIT
}

# Put back the EXIT trap captured by _exit_trap_spec. Empty means unset.

# Put back the EXIT trap captured by _exit_trap_spec. Empty means unset.
_restore_exit_trap() {
  local saved_spec="$1"
  if [[ -n "${saved_spec}" ]]; then
    eval "${saved_spec}"
  else
    trap - EXIT
  fi
}

# Create .venv atomically: build in a sibling temp dir, point scripts at the
# final path, verify pip, then rename. One create lock per destination stops a
# second run from deleting the first run's temporary directory. The EXIT trap
# removes that temporary directory until rename; it removes the destination
# only after this run owns the renamed tree. Success restores the caller's
# EXIT trap. Failure still runs that trap after this run's cleanup.

# Create .venv atomically: build in a sibling temp dir, point scripts at the
# final path, verify pip, then rename. One create lock per destination stops a
# second run from deleting the first run's temporary directory. The EXIT trap
# removes that temporary directory until rename; it removes the destination
# only after this run owns the renamed tree. Success restores the caller's
# EXIT trap. Failure still runs that trap after this run's cleanup.
create_atomic_project_venv() {
  local brew_py="$1"
  local dest="$2"
  local partial py stale stale_pid lock quoted_partial quoted_dest quoted_lock old_base saved_exit_trap nested

  [[ -n "${brew_py}" && -x "${brew_py}" ]] || die "Refusing to create venv without a Python interpreter"
  [[ -n "${dest}" ]] || die "Refusing to create venv with an empty destination"
  while [[ "${dest}" != "/" && "${dest}" == */ ]]; do
    dest="${dest%/}"
  done
  [[ ! -e "${dest}" ]] || die "Refusing to overwrite existing path: ${dest}"

  partial="${dest}.partial.$$"
  lock="$(acquire_venv_create_lock "${dest}")"
  quoted_partial="$(printf '%q' "${partial}")"
  quoted_dest="$(printf '%q' "${dest}")"
  quoted_lock="$(printf '%q' "${lock}")"
  saved_exit_trap="$(_exit_trap_spec)"
  # Paths are fixed at registration; the trap must not depend on a nested function.
  # Do not remove the destination yet: this run does not own it.
  _install_owned_exit_trap "rm -rf -- ${quoted_partial} ${quoted_lock}" "${saved_exit_trap}"
  if [[ -e "${dest}" ]]; then
    die "Refusing to overwrite existing path: ${dest}"
  fi
  while IFS= read -r stale; do
    [[ -n "${stale}" ]] || continue
    stale_pid="${stale##*.}"
    if [[ "${stale_pid}" != "$$" ]] && pid_is_alive "${stale_pid}"; then
      die "Refusing to remove in-use temporary venv ${stale} (pid ${stale_pid} is running). If no other make venv/rebuild is active, remove it or run: make clean"
    fi
    rm -rf -- "${stale}"
  done < <(list_stale_venv_partials "${dest}")
  rm -rf -- "${partial}"
  "${brew_py}" -m venv "${partial}"
  py="${partial}/bin/python"
  [[ -x "${py}" ]] || die "Venv creation failed: ${py} is not executable"
  "${py}" -m pip --version >/dev/null || die "Venv creation failed: pip is not available in ${partial}"
  rewrite_relocated_venv_paths "${brew_py}" "${partial}" "${dest}"
  if [[ -e "${dest}" || -L "${dest}" ]]; then
    die "Refusing to overwrite ${dest}: it appeared while building ${partial}"
  fi
  # Re-check under the create lock immediately before rename. A foreign dest can
  # still appear in the tiny window after this check (accepted: lock + nested detection).
  if [[ -e "${dest}" || -L "${dest}" ]]; then
    die "Refusing to overwrite ${dest}: it appeared while building ${partial}"
  fi
  mv "${partial}" "${dest}"
  # If dest appears as a directory in the gap before mv, mv nests the partial
  # inside it. Remove only the nested partial and do not claim dest, preserving
  # the foreign tree during this failure.
  nested="${dest}/$(basename "${partial}")"
  if [[ -e "${nested}" || -L "${nested}" ]]; then
    rm -rf -- "${nested}"
    die "Refusing to claim ${dest}: it appeared during rename"
  fi
  # This run now owns the renamed tree. A later failure may remove it.
  _install_owned_exit_trap "rm -rf -- ${quoted_dest} ${quoted_lock}" "${saved_exit_trap}"
  old_base="$(basename "${partial}")"
  if venv_records_temporary_path "${dest}" "${old_base}"; then
    die "Venv creation failed: temporary path remains in ${dest}"
  fi
  [[ -x "${dest}/bin/pip" ]] || die "Venv creation failed: ${dest}/bin/pip is not executable"
  venv_pip_script_runs "${dest}" || die "Venv creation failed: ${dest}/bin/pip does not run"
  rm -rf -- "${lock}"
  _restore_exit_trap "${saved_exit_trap}"
}

# Homebrew python@MLX_PYTHON_VERSION on arm64. No PATH fallback.

# Homebrew python@MLX_PYTHON_VERSION on arm64. No PATH fallback.
resolve_homebrew_python() {
  local py mach prefix
  prefix="$(homebrew_prefix)"
  [[ -n "${prefix}" ]] || die "Homebrew not found. Run: make venv"
  py="${prefix}/opt/python@${MLX_PYTHON_VERSION}/bin/python${MLX_PYTHON_VERSION}"
  if [[ ! -x "${py}" ]]; then
    die "Python ${MLX_PYTHON_VERSION} not found at ${py}. Install via: brew install python@${MLX_PYTHON_VERSION}"
  fi
  mach="$("${py}" -c 'import platform; print(platform.machine())')" || die "Could not read the architecture of ${py}"
  if [[ "${mach}" != "arm64" ]]; then
    die "Homebrew Python at ${py} reports ${mach}, not arm64."
  fi
  printf '%s\n' "${py}"
}

# Detect Homebrew, optionally install it, and reject an Intel prefix.
# rerun_cmd is printed when Homebrew is missing.

# Detect Homebrew, optionally install it, and reject an Intel prefix.
# rerun_cmd is printed when Homebrew is missing.
install_homebrew_install_script() {
  local url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  local tmp sha saved_exit_trap quoted_tmp
  tmp="$(mktemp)"
  quoted_tmp="$(printf '%q' "${tmp}")"
  saved_exit_trap="$(_exit_trap_spec)"
  # Chain onto the caller EXIT trap so a failed download still cleans the temp
  # file without dropping the caller's cleanup.
  _install_owned_exit_trap "rm -f -- ${quoted_tmp}" "${saved_exit_trap}"
  curl -fsSL "${url}" -o "${tmp}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha="$(sha256sum "${tmp}" | awk '{print $1}')"
  else
    sha="$(shasum -a 256 "${tmp}" | awk '{print $1}')"
  fi
  log_info "Homebrew install script SHA-256: ${sha}"
  log_info "Homebrew install script URL: ${url}"
  NONINTERACTIVE=1 /bin/bash "${tmp}"
  rm -f -- "${tmp}"
  _restore_exit_trap "${saved_exit_trap}"
}


ensure_homebrew_ready() {
  local rerun_cmd="$1"
  local brew_arch
  ensure_homebrew_in_path
  if [[ -z "$(homebrew_prefix)" ]]; then
    if is_truthy "${MLX_INSTALL_HOMEBREW:-0}"; then
      log_info "Installing Homebrew (NONINTERACTIVE=1)..."
      install_homebrew_install_script
      ensure_homebrew_in_path
    else
      cat <<EOF
Homebrew was not found.

Install Homebrew (Apple Silicon default prefix /opt/homebrew), then re-run:

  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "\$(/opt/homebrew/bin/brew shellenv)"

Or allow the venv step to install it:

  ${rerun_cmd}
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
}

# True when install can use this tree: pyvenv.cfg, executable bin/python, and pip.

# True when install can use this tree: pyvenv.cfg, executable bin/python, and pip.
venv_install_ready() {
  local dir="${1:-${MLX_VENV}}"
  [[ -f "${dir}/pyvenv.cfg" ]] || return 1
  [[ -x "$(venv_project_python "${dir}")" ]] || return 1
  venv_python_has_pip "${dir}" || return 1
  venv_pip_script_runs "${dir}"
}

# Callers mkdir -p the workspace first. Missing .venv is OK (create). An
# existing path must be install-ready under the workspace. bin/python3 alone,
# a non-executable bin/python, or a venv without pip is not enough.

# Callers mkdir -p the workspace first. Missing .venv is OK (create). An
# existing path must be install-ready under the workspace. bin/python3 alone,
# a non-executable bin/python, or a venv without pip is not enough.
assert_install_venv_paths() {
  local py
  assert_workspace_safe
  assert_venv_under_workspace
  if [[ ! -e "${MLX_VENV}" ]]; then
    return 0
  fi
  if [[ ! -d "${MLX_VENV}" ]]; then
    die "MLX_VENV exists but is not a directory: ${MLX_VENV}"
  fi
  if venv_interpreter_symlink_broken "${MLX_VENV}"; then
    die "Refusing to reuse broken venv (interpreter symlink is broken): ${MLX_VENV}. Run: make rebuild"
  fi
  if venv_install_ready "${MLX_VENV}"; then
    return 0
  fi
  py="$(venv_project_python "${MLX_VENV}")"
  if [[ -f "${MLX_VENV}/pyvenv.cfg" && -e "${py}" && ! -x "${py}" ]]; then
    die "Refusing to reuse incomplete venv (bin/python is not executable): ${MLX_VENV}. Run: make rebuild"
  fi
  if [[ -f "${MLX_VENV}/pyvenv.cfg" && -x "${py}" ]]; then
    if venv_python_has_pip "${MLX_VENV}" && ! venv_pip_script_runs "${MLX_VENV}"; then
      die "Refusing to reuse incomplete venv (bin/pip does not run): ${MLX_VENV}. Run: make rebuild"
    fi
    die "Refusing to reuse incomplete venv (pip is missing or broken): ${MLX_VENV}. Run: make rebuild"
  fi
  if [[ -f "${MLX_VENV}/pyvenv.cfg" ]]; then
    die "Refusing to reuse incomplete venv (missing bin/python): ${MLX_VENV}. Remove or rename it, then run: make rebuild"
  fi
  if has_venv_interpreter "${MLX_VENV}"; then
    die "Refusing to reuse incomplete venv (missing pyvenv.cfg): ${MLX_VENV}. Remove or rename it, then run: make rebuild"
  fi
  die "Refusing to reuse path that does not look like a venv: ${MLX_VENV}. Remove or rename it."
}

# Install paths must already have a complete venv. Does not create one.

# Install paths must already have a complete venv. Does not create one.
require_install_venv() {
  assert_install_venv_paths
  if [[ ! -d "${MLX_VENV}" ]]; then
    die "Python venv not found at ${MLX_VENV}. Run: make venv"
  fi
}

