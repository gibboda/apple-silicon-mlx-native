#!/usr/bin/env bash
# Portable fixtures for Darwin host checks and initial-build venv guards.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="${ROOT}/scripts/detect-apple-silicon.sh"
COMMON="${ROOT}/scripts/lib/common.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "${label}"
  else
    fail "${label} (expected success)"
  fi
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${label} (expected non-zero exit)"
  else
    pass "${label}"
  fi
}

expect_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    pass "${label}"
  else
    fail "${label} (missing ${needle})"
  fi
}

BIN="${TMP}/bin"
mkdir -p "${BIN}"
REAL_UNAME="$(command -v uname)"
cat >"${BIN}/uname" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  -m) printf '%s\\n' "\${FAKE_UNAME_M:-arm64}" ;;
  -s) printf '%s\\n' "\${FAKE_UNAME_S:-Darwin}" ;;
  *) exec "${REAL_UNAME}" "\$@" ;;
esac
EOF
chmod +x "${BIN}/uname"

with_uname() {
  local kernel="$1"
  local arch="$2"
  shift 2
  FAKE_UNAME_S="${kernel}" FAKE_UNAME_M="${arch}" PATH="${BIN}:${PATH}" "$@"
}

run_assert_apple_silicon() {
  with_uname "$1" "$2" bash -c "source \"${COMMON}\"; assert_apple_silicon"
}

run_install_paths() {
  env MLX_WORKSPACE="$1" MLX_VENV="$2" bash -c "source \"${COMMON}\"; assert_install_venv_paths"
}

run_require_venv() {
  env MLX_WORKSPACE="$1" MLX_VENV="$2" bash -c "source \"${COMMON}\"; require_install_venv"
}

# --- Darwin arm64 is required; Linux ARM must not look like Apple Silicon ---

expect_ok "quiet Darwin arm64" with_uname Darwin arm64 "${DETECT}" --quiet
expect_fail "quiet Linux arm64" with_uname Linux arm64 "${DETECT}" --quiet
expect_fail "quiet Darwin x86_64" with_uname Darwin x86_64 "${DETECT}" --quiet
expect_fail "quiet Linux x86_64" with_uname Linux x86_64 "${DETECT}" --quiet

expect_ok "assert Darwin arm64" run_assert_apple_silicon Darwin arm64
expect_fail "assert Linux arm64" run_assert_apple_silicon Linux arm64
expect_fail "assert Darwin x86_64" run_assert_apple_silicon Darwin x86_64

linux_err="$(run_assert_apple_silicon Linux arm64 2>&1)" || true
expect_contains "Linux ARM names macOS" "macOS" "${linux_err}"
expect_contains "Linux ARM names Darwin" "Darwin" "${linux_err}"
expect_contains "Linux ARM reports Linux" "OS: Linux" "${linux_err}"

intel_err="$(run_assert_apple_silicon Darwin x86_64 2>&1)" || true
expect_contains "Intel Mac names arm64" "arm64" "${intel_err}"
expect_contains "Intel Mac names x86_64" "x86_64" "${intel_err}"

if host_kernel="$(uname -s)" && host_arch="$(uname -m)"; then
  if [[ "${host_kernel}" == "Darwin" && "${host_arch}" == "arm64" ]]; then
    expect_ok "quiet succeeds on this Darwin arm64 host" "${DETECT}" --quiet
  else
    expect_fail "quiet fails on this non-Apple-Silicon host" "${DETECT}" --quiet
  fi
fi

# --- Initial-build path guards (no live brew / venv create) ---

WS="${TMP}/ws"
mkdir -p "${WS}"

expect_ok "install paths allow missing venv" run_install_paths "${WS}" "${WS}/.venv"

mkdir -p "${WS}/.venv/bin"
printf 'home = /usr/bin/python3\ninclude-system-site-packages = false\n' >"${WS}/.venv/pyvenv.cfg"
printf '#!/bin/sh\nexit 0\n' >"${WS}/.venv/bin/python"
printf '#!/bin/sh\nexit 0\n' >"${WS}/.venv/bin/pip"
chmod +x "${WS}/.venv/bin/python" "${WS}/.venv/bin/pip"
expect_ok "install paths reuse a real venv" run_install_paths "${WS}" "${WS}/.venv"

rm -rf "${WS}/.venv"
mkdir -p "${WS}/.venv"
printf 'home = /usr/bin/python3\ninclude-system-site-packages = false\n' >"${WS}/.venv/pyvenv.cfg"
expect_fail "install paths refuse pyvenv.cfg without bin/python" run_install_paths "${WS}" "${WS}/.venv"
cfg_only_err="$(run_install_paths "${WS}" "${WS}/.venv" 2>&1)" || true
expect_contains "cfg-only error mentions bin/python" "bin/python" "${cfg_only_err}"
expect_contains "cfg-only error says remove or rename" "Remove or rename" "${cfg_only_err}"
if [[ -f "${WS}/.venv/pyvenv.cfg" && ! -f "${WS}/.venv/bin/python" && ! -f "${WS}/.venv/bin/python3" ]]; then
  pass "cfg-only venv directory left in place"
else
  fail "cfg-only venv directory was modified"
fi

rm -rf "${WS}/.venv"
mkdir -p "${WS}/.venv/bin"
printf '#!/bin/sh\nexit 0\n' >"${WS}/.venv/bin/python"
chmod +x "${WS}/.venv/bin/python"
expect_fail "install paths refuse bin/python without pyvenv.cfg" run_install_paths "${WS}" "${WS}/.venv"
incomplete_err="$(run_install_paths "${WS}" "${WS}/.venv" 2>&1)" || true
expect_contains "incomplete venv error mentions pyvenv.cfg" "pyvenv.cfg" "${incomplete_err}"
expect_contains "incomplete venv error says remove or rename" "Remove or rename" "${incomplete_err}"
if [[ -x "${WS}/.venv/bin/python" && ! -f "${WS}/.venv/pyvenv.cfg" ]]; then
  pass "incomplete venv directory left in place"
else
  fail "incomplete venv directory was modified"
fi

rm -rf "${WS}/.venv"
mkdir -p "${WS}/.venv"
printf 'not a venv\n' >"${WS}/.venv/readme.txt"
expect_fail "install paths refuse a non-venv directory" run_install_paths "${WS}" "${WS}/.venv"
non_venv_err="$(run_install_paths "${WS}" "${WS}/.venv" 2>&1)" || true
expect_contains "non-venv error mentions reuse" "reuse" "${non_venv_err}"
expect_contains "non-venv error says remove or rename" "Remove or rename" "${non_venv_err}"
if [[ -f "${WS}/.venv/readme.txt" ]]; then
  pass "non-venv directory left in place"
else
  fail "non-venv directory was removed"
fi

mkdir -p "${TMP}/outside"
expect_fail "install paths refuse venv outside workspace" \
  run_install_paths "${WS}" "${TMP}/outside/.venv"

rm -rf "${WS}/.venv"
printf 'not a directory\n' >"${WS}/.venv"
expect_fail "install paths refuse a venv file" run_install_paths "${WS}" "${WS}/.venv"

# --- require_install_venv (install must not create a missing venv) ---

REQ="${TMP}/req"
mkdir -p "${REQ}"

req_missing="$(run_require_venv "${REQ}" "${REQ}/.venv" 2>&1)" || true
expect_fail "require venv rejects missing" run_require_venv "${REQ}" "${REQ}/.venv"
expect_contains "missing venv mentions make venv" "make venv" "${req_missing}"

mkdir -p "${REQ}/.venv/bin"
printf 'home = /usr/bin/python3\ninclude-system-site-packages = false\n' >"${REQ}/.venv/pyvenv.cfg"
printf '#!/bin/sh\nexit 0\n' >"${REQ}/.venv/bin/python"
printf '#!/bin/sh\nexit 0\n' >"${REQ}/.venv/bin/pip"
chmod +x "${REQ}/.venv/bin/python" "${REQ}/.venv/bin/pip"
expect_ok "require venv accepts a complete venv" run_require_venv "${REQ}" "${REQ}/.venv"

rm -rf "${REQ}/.venv"
mkdir -p "${REQ}/.venv"
printf 'home = /usr/bin/python3\ninclude-system-site-packages = false\n' >"${REQ}/.venv/pyvenv.cfg"
expect_fail "require venv rejects incomplete venv" run_require_venv "${REQ}" "${REQ}/.venv"
req_incomplete="$(run_require_venv "${REQ}" "${REQ}/.venv" 2>&1)" || true
expect_contains "require incomplete mentions make rebuild" "make rebuild" "${req_incomplete}"
if [[ -f "${REQ}/.venv/pyvenv.cfg" && ! -f "${REQ}/.venv/bin/python" ]]; then
  pass "require incomplete venv directory left in place"
else
  fail "require incomplete venv directory was modified"
fi

expect_fail "require venv rejects outside workspace" \
  run_require_venv "${REQ}" "${TMP}/outside/.venv"

run_reusable_brew_venv() {
  env MLX_WORKSPACE="$1" MLX_VENV="$2" MLX_PYTHON_VERSION="${3:-3.12}" PATH="$4" bash -c \
    "source \"${COMMON}\"; assert_reusable_brew_venv_for_make_venv"
}

run_atomic_venv() {
  env MLX_WORKSPACE="$1" MLX_VENV="$2" ATOMIC_BREW_PY="$3" bash -c \
    "source \"${COMMON}\"; create_atomic_project_venv \"\${ATOMIC_BREW_PY}\" \"\${MLX_VENV}\""
}

run_rewrite_relocated_venv_paths() {
  # shellcheck disable=SC2317
  env REWRITE_PY="$1" REWRITE_PARTIAL="$2" REWRITE_DEST="$3" bash -c \
    "source \"${COMMON}\"; rewrite_relocated_venv_paths \"\${REWRITE_PY}\" \"\${REWRITE_PARTIAL}\" \"\${REWRITE_DEST}\""
}

assert_no_venv_partial_names_in_tree() {
  local tree="$1"
  local label="$2"
  if grep -rlaF '.venv.partial.' "${tree}" >/dev/null 2>&1; then
    fail "${label}"
  else
    pass "${label}"
  fi
}

# --- broken interpreter symlink ---

rm -rf "${WS}/.venv"
mkdir -p "${WS}/.venv/bin"
printf 'home = /opt/homebrew/opt/python@3.12/bin\nversion = 3.12.0\n' >"${WS}/.venv/pyvenv.cfg"
ln -sf /nonexistent/interpreter "${WS}/.venv/bin/python"
expect_fail "install paths refuse dangling interpreter symlink" run_install_paths "${WS}" "${WS}/.venv"
broken_err="$(run_install_paths "${WS}" "${WS}/.venv" 2>&1)" || true
expect_contains "broken symlink mentions rebuild" "make rebuild" "${broken_err}"
expect_contains "broken symlink mentions interpreter" "interpreter symlink is broken" "${broken_err}"

# --- make venv reuse identity (Homebrew python@MLX_PYTHON_VERSION + pip) ---

FAKE_BREW="${TMP}/fakebrew"
mkdir -p "${FAKE_BREW}/bin"
cat >"${FAKE_BREW}/bin/brew" <<'EOF'
#!/bin/sh
case "$1" in
  --prefix) echo /opt/homebrew ;;
esac
exit 0
EOF
chmod +x "${FAKE_BREW}/bin/brew"
BREW_PATH="${FAKE_BREW}/bin:${BIN}:${PATH}"

IDENT="${TMP}/ident"
mkdir -p "${IDENT}"
if command -v python3 >/dev/null 2>&1 && python3 -m venv "${IDENT}/.venv-probe" >/dev/null 2>&1; then
  rm -rf "${IDENT}/.venv-probe"
  python3 -m venv "${IDENT}/.venv"
  printf 'home = /opt/homebrew/opt/python@3.12/bin\ninclude-system-site-packages = false\nversion = 3.12.9\n' \
    >"${IDENT}/.venv/pyvenv.cfg"
  expect_ok "make venv reuse accepts matching Homebrew cfg" \
    run_reusable_brew_venv "${IDENT}" "${IDENT}/.venv" 3.12 "${BREW_PATH}"

  printf 'home = /usr/bin\ninclude-system-site-packages = false\nversion = 3.13.5\n' \
    >"${IDENT}/.venv/pyvenv.cfg"
  expect_fail "make venv reuse refuses foreign Python version" \
    run_reusable_brew_venv "${IDENT}" "${IDENT}/.venv" 3.12 "${BREW_PATH}"
  foreign_ver_err="$(run_reusable_brew_venv "${IDENT}" "${IDENT}/.venv" 3.12 "${BREW_PATH}" 2>&1)" || true
  expect_contains "foreign version mentions make rebuild" "make rebuild" "${foreign_ver_err}"
  expect_contains "foreign version mentions 3.13" "3.13" "${foreign_ver_err}"

  printf 'home = /usr/bin\ninclude-system-site-packages = false\nversion = 3.12.9\n' \
    >"${IDENT}/.venv/pyvenv.cfg"
  expect_fail "make venv reuse refuses non-Homebrew pyvenv home" \
    run_reusable_brew_venv "${IDENT}" "${IDENT}/.venv" 3.12 "${BREW_PATH}"
  foreign_home_err="$(run_reusable_brew_venv "${IDENT}" "${IDENT}/.venv" 3.12 "${BREW_PATH}" 2>&1)" || true
  expect_contains "foreign home mentions Homebrew prefix" "Homebrew prefix" "${foreign_home_err}"

  ATOMIC="${TMP}/atomic"
  dead_partial_pid=2147483646
  while kill -0 "${dead_partial_pid}" 2>/dev/null; do
    dead_partial_pid=$((dead_partial_pid - 1))
  done
  mkdir -p "${ATOMIC}/.venv.partial.${dead_partial_pid}" "${ATOMIC}/.venv.partial.notes"
  printf 'stale\n' >"${ATOMIC}/.venv.partial.${dead_partial_pid}/marker"
  printf 'keep\n' >"${ATOMIC}/.venv.partial.notes/marker"
  rm -rf "${ATOMIC}/.venv"
  if run_atomic_venv "${ATOMIC}" "${ATOMIC}/.venv" "$(command -v python3)"; then
    pass "atomic venv create leaves a working tree"
  else
    fail "atomic venv create leaves a working tree"
  fi
  if [[ -f "${ATOMIC}/.venv/pyvenv.cfg" && -x "${ATOMIC}/.venv/bin/python" ]]; then
    pass "atomic venv has pyvenv.cfg and bin/python"
  else
    fail "atomic venv missing expected markers"
  fi
  if "${ATOMIC}/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
    pass "atomic venv pip works"
  else
    fail "atomic venv pip missing"
  fi
  pip_shebang="$(head -n 1 "${ATOMIC}/.venv/bin/pip")"
  if [[ "${pip_shebang}" == "#!${ATOMIC}/.venv/bin/python"* && "${pip_shebang}" != *".partial."* ]]; then
    pass "atomic venv pip shebang points at .venv"
  else
    fail "atomic venv pip shebang points at .venv (${pip_shebang})"
  fi
  if "${ATOMIC}/.venv/bin/pip" --version >/dev/null 2>&1; then
    pass "atomic venv pip script runs"
  else
    fail "atomic venv pip script runs"
  fi
  # Debian/Ubuntu activate scripts indent assignments; Homebrew may not.
  prompt_line="$(
    grep 'VIRTUAL_ENV_PROMPT=' "${ATOMIC}/.venv/bin/activate" 2>/dev/null \
      | sed -n 's/^[[:space:]]*//p' \
      | head -n 1 \
      || true
  )"
  if grep -F -q "export VIRTUAL_ENV=${ATOMIC}/.venv" "${ATOMIC}/.venv/bin/activate" \
    && [[ "${prompt_line}" == "VIRTUAL_ENV_PROMPT=.venv" || "${prompt_line}" == "VIRTUAL_ENV_PROMPT='(.venv)"* ]] \
    && ! grep -F -q '.partial.' "${ATOMIC}/.venv/bin/activate" \
    && ! grep -F -q '.partial.' "${ATOMIC}/.venv/pyvenv.cfg"; then
    pass "atomic venv activate and pyvenv.cfg record .venv"
  else
    fail "atomic venv activate and pyvenv.cfg record .venv (${prompt_line})"
  fi
  assert_no_venv_partial_names_in_tree "${ATOMIC}/.venv" \
    "atomic venv tree has no temporary path"
  if [[ -d "${ATOMIC}/.venv.partial.${dead_partial_pid}" ]]; then
    fail "atomic venv left a stale partial directory"
  else
    pass "atomic venv removed a stale partial directory"
  fi
  if [[ -d "${ATOMIC}/.venv.create-lock" ]]; then
    fail "atomic venv left the create lock"
  else
    pass "atomic venv released the create lock"
  fi
  if [[ -f "${ATOMIC}/.venv.partial.notes/marker" ]]; then
    pass "atomic venv left an unrelated partial-named directory"
  else
    fail "atomic venv removed an unrelated partial-named directory"
  fi
  if compgen -G "${ATOMIC}/.venv.partial.[0-9]*" >/dev/null; then
    fail "atomic venv left a partial directory"
  else
    pass "atomic venv left no partial directory"
  fi

  LIVE="${TMP}/live-partial"
  mkdir -p "${LIVE}"
  sleep 30 &
  live_partial_pid=$!
  mkdir -p "${LIVE}/.venv.partial.${live_partial_pid}"
  printf 'live\n' >"${LIVE}/.venv.partial.${live_partial_pid}/marker"
  live_partial_err="$(run_atomic_venv "${LIVE}" "${LIVE}/.venv" "$(command -v python3)" 2>&1)" || true
  expect_fail "create refuses an in-use partial directory" \
    run_atomic_venv "${LIVE}" "${LIVE}/.venv" "$(command -v python3)"
  expect_contains "in-use partial error names the directory" "in-use temporary venv" "${live_partial_err}"
  expect_contains "in-use partial error suggests make clean" "make clean" "${live_partial_err}"
  if [[ -f "${LIVE}/.venv.partial.${live_partial_pid}/marker" ]]; then
    pass "create left an in-use partial directory in place"
  else
    fail "create removed an in-use partial directory"
  fi
  kill "${live_partial_pid}" 2>/dev/null || true
  wait "${live_partial_pid}" 2>/dev/null || true

  RACE="${TMP}/race"
  mkdir -p "${RACE}"
  sleep 30 &
  race_sleep=$!
  mkdir -p "${RACE}/.venv.create-lock"
  printf '%s\n' "${race_sleep}" >"${RACE}/.venv.create-lock/pid"
  # A background function inherits this script's EXIT trap. Clear it so the
  # waiter cannot delete the test directory when it exits.
  (
    trap - EXIT
    run_atomic_venv "${RACE}" "${RACE}/.venv" "$(command -v python3)" >"${RACE}/out" 2>&1
  ) &
  race_create=$!
  race_waited=0
  while (( race_waited < 50 )); do
    if grep -q "Waiting for venv create lock held by pid ${race_sleep}" "${RACE}/out" 2>/dev/null; then
      break
    fi
    sleep 0.2
    race_waited=$((race_waited + 1))
  done
  race_lock_pid="$(cat "${RACE}/.venv.create-lock/pid" 2>/dev/null || true)"
  if grep -q "Waiting for venv create lock held by pid ${race_sleep}" "${RACE}/out" 2>/dev/null \
    && kill -0 "${race_create}" 2>/dev/null \
    && [[ "${race_lock_pid}" == "${race_sleep}" && ! -e "${RACE}/.venv" ]]; then
    pass "create waits while another pid holds the lock"
  else
    fail "create waits while another pid holds the lock"
  fi
  mkdir -p "${RACE}/.venv"
  printf 'owned\n' >"${RACE}/.venv/marker"
  kill "${race_sleep}" 2>/dev/null || true
  wait "${race_sleep}" 2>/dev/null || true
  wait "${race_create}" 2>/dev/null || true
  if [[ -f "${RACE}/.venv/marker" ]]; then
    pass "waiting create left an existing .venv in place"
  else
    fail "waiting create removed an existing .venv"
  fi
  race_out="$(cat "${RACE}/out" 2>/dev/null || true)"
  expect_contains "waiting create refuses an existing .venv" "Refusing to overwrite" "${race_out}"

  rewrite_bad="${TMP}/rewrite-bad"
  mkdir -p "${rewrite_bad}/.venv.partial.1"
  expect_fail "rewrite refuses unexpected temporary partial path" \
    run_rewrite_relocated_venv_paths "$(command -v python3)" \
    "${rewrite_bad}/wrong.partial.1" "${rewrite_bad}/.venv"
  rewrite_fail="${TMP}/rewrite-fail"
  mkdir -p "${rewrite_fail}"
  rm -rf "${rewrite_fail}/.venv.partial.1"
  python3 -m venv "${rewrite_fail}/.venv.partial.1"
  chmod 000 "${rewrite_fail}/.venv.partial.1/bin/activate"
  mkdir -p "${rewrite_fail}/.venv/foreign"
  printf 'keep\n' >"${rewrite_fail}/.venv/foreign/keep.txt"
  expect_fail "rewrite fails when a venv file is unreadable" \
    run_rewrite_relocated_venv_paths "$(command -v python3)" \
    "${rewrite_fail}/.venv.partial.1" "${rewrite_fail}/.venv"
  chmod 644 "${rewrite_fail}/.venv.partial.1/bin/activate" 2>/dev/null || true
  if [[ -f "${rewrite_fail}/.venv/foreign/keep.txt" ]]; then
    pass "rewrite failure leaves an unrelated existing .venv in place"
  else
    fail "rewrite failure removed an unrelated existing .venv"
  fi

  MID="${TMP}/mid-build"
  mkdir -p "${MID}/bin"
  cat >"${MID}/bin/python3-slow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
real_py="$(command -v python3)"
if [[ "${1:-}" == "-m" && "${2:-}" == "venv" ]]; then
  "${real_py}" "$@"
  sleep 3
  exit 0
fi
exec "${real_py}" "$@"
EOF
  chmod +x "${MID}/bin/python3-slow"
  rm -rf "${MID}/.venv" "${MID}/.venv.create-lock"
  rm -rf "${MID}"/.venv.partial.*
  mid_out="${MID}/mid.out"
  : >"${mid_out}"
  (
    trap - EXIT
    run_atomic_venv "${MID}" "${MID}/.venv" "${MID}/bin/python3-slow" >>"${mid_out}" 2>&1
  ) &
  mid_create=$!
  mid_injected=0
  mid_waited=0
  while (( mid_waited < 100 )); do
    if compgen -G "${MID}/.venv.partial.*/bin/python" >/dev/null; then
      mkdir -p "${MID}/.venv/userstuff"
      printf 'keep\n' >"${MID}/.venv/userstuff/keep.txt"
      mid_injected=1
      break
    fi
    if ! kill -0 "${mid_create}" 2>/dev/null; then
      break
    fi
    sleep 0.1
    mid_waited=$((mid_waited + 1))
  done
  wait "${mid_create}" 2>/dev/null || true
  mid_err="$(cat "${mid_out}" 2>/dev/null || true)"
  if (( mid_injected == 1 )); then
    if [[ -f "${MID}/.venv/userstuff/keep.txt" ]]; then
      pass "mid-build .venv marker survives when destination appears during create"
    else
      fail "mid-build .venv marker was removed"
    fi
    expect_contains "mid-build create refuses destination that appeared during build" \
      "appeared while building" "${mid_err}"
    if compgen -G "${MID}/.venv/.venv.partial.*" >/dev/null \
      || compgen -G "${MID}/.venv/.venv.partial.*/bin" >/dev/null; then
      fail "mid-build create nested partial inside an existing .venv"
    else
      pass "mid-build create did not nest partial inside .venv"
    fi
  else
    fail "mid-build test could not inject .venv while partial was building"
  fi
  rm -rf "${MID}"

  BREAK="${TMP}/break-pip"
  mkdir -p "${BREAK}/bin"
  cat >"${BREAK}/bin/python3-break" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
real_py="$(command -v python3)"
if [[ "${1:-}" == "-m" && "${2:-}" == "venv" ]]; then
  "${real_py}" "$@"
  exit 0
fi
if [[ "${1:-}" == "-" ]]; then
  partial="${2:-}"
  "${real_py}" "$@"
  if [[ -n "${partial}" && -f "${partial}/bin/pip" ]]; then
    chmod a-x "${partial}/bin/pip"
  fi
  exit 0
fi
exec "${real_py}" "$@"
EOF
  chmod +x "${BREAK}/bin/python3-break"
  rm -rf "${BREAK}/.venv" "${BREAK}/.venv.create-lock"
  rm -rf "${BREAK}"/.venv.partial.*
  break_err="$(
    run_atomic_venv "${BREAK}" "${BREAK}/.venv" "${BREAK}/bin/python3-break" 2>&1
  )" || true
  expect_contains "post-rename pip check fails on broken pip script" \
    "bin/pip is not executable" "${break_err}"
  if [[ ! -e "${BREAK}/.venv" ]]; then
    pass "failed post-rename check removes only this run's .venv tree"
  else
    fail "failed post-rename check left a broken .venv tree behind"
  fi
  if compgen -G "${BREAK}/.venv.partial.*" >/dev/null; then
    fail "failed post-rename check left a partial directory"
  else
    pass "failed post-rename check left no partial directory"
  fi
  if [[ -d "${BREAK}/.venv.create-lock" ]]; then
    fail "failed post-rename check left the create lock"
  else
    pass "failed post-rename check released the create lock"
  fi

  BROKEN_PIP="${TMP}/broken-pip-shebang"
  rm -rf "${BROKEN_PIP}"
  python3 -m venv "${BROKEN_PIP}/.venv"
  printf 'home = /opt/homebrew/opt/python@3.12/bin\ninclude-system-site-packages = false\nversion = 3.12.9\n' \
    >"${BROKEN_PIP}/.venv/pyvenv.cfg"
  pip_script="${BROKEN_PIP}/.venv/bin/pip"
  if [[ -f "${pip_script}" && ! -L "${pip_script}" ]]; then
    { printf '#!%s\n' "${BROKEN_PIP}/missing-python"; tail -n +2 "${pip_script}"; } >"${pip_script}.new"
    mv "${pip_script}.new" "${pip_script}"
    chmod +x "${pip_script}"
    if "${BROKEN_PIP}/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
      pass "broken pip shebang still has python -m pip"
    else
      fail "broken pip shebang still has python -m pip"
    fi
    broken_pip_err="$(run_install_paths "${BROKEN_PIP}" "${BROKEN_PIP}/.venv" 2>&1)" || true
    expect_fail "install paths refuse a pip script with a missing interpreter" \
      run_install_paths "${BROKEN_PIP}" "${BROKEN_PIP}/.venv"
    expect_contains "broken pip shebang mentions bin/pip" "bin/pip does not run" "${broken_pip_err}"
    broken_reuse_err="$(run_reusable_brew_venv "${BROKEN_PIP}" "${BROKEN_PIP}/.venv" 3.12 "${BREW_PATH}" 2>&1)" || true
    expect_fail "make venv reuse refuses a pip script with a missing interpreter" \
      run_reusable_brew_venv "${BROKEN_PIP}" "${BROKEN_PIP}/.venv" 3.12 "${BREW_PATH}"
    expect_contains "broken pip reuse mentions bin/pip" "bin/pip does not run" "${broken_reuse_err}"
  else
    fail "broken pip shebang fixture has a regular bin/pip script"
  fi

  EXIT_OK="${TMP}/exit-trap-ok"
  rm -rf "${EXIT_OK}"
  mkdir -p "${EXIT_OK}"
  ok_flag="${EXIT_OK}/caller-ran"
  ok_out="${EXIT_OK}/out"
  (
    flag="${ok_flag}"
    trap 'touch "${flag}"' EXIT
    # shellcheck disable=SC1090
    source "${COMMON}"
    saved="$(trap -p EXIT)"
    create_atomic_project_venv "$(command -v python3)" "${EXIT_OK}/.venv"
    now="$(trap -p EXIT)"
    if [[ "${now}" == "${saved}" ]]; then
      printf 'restored\n'
    else
      printf 'not-restored\n'
    fi
    if [[ -e "${flag}" ]]; then
      printf 'ran-early\n'
    else
      printf 'not-yet\n'
    fi
  ) >"${ok_out}" 2>&1 || true
  if grep -q '^restored$' "${ok_out}" && grep -q '^not-yet$' "${ok_out}"; then
    pass "successful atomic create restores the caller EXIT trap"
  else
    fail "successful atomic create restores the caller EXIT trap ($(tr '\n' ' ' <"${ok_out}"))"
  fi
  if [[ -e "${ok_flag}" ]]; then
    pass "caller EXIT trap still runs after atomic create returns"
  else
    fail "caller EXIT trap was dropped after atomic create returned"
  fi
  if [[ -x "${EXIT_OK}/.venv/bin/python" ]]; then
    pass "EXIT trap restore left the created venv in place"
  else
    fail "EXIT trap restore removed the created venv"
  fi
else
  pass "skip venv identity tests (python3 -m venv unavailable)"
fi

# Failure after the create trap is installed must still run the caller's EXIT trap.
EXIT_FAIL="${TMP}/exit-trap-fail"
rm -rf "${EXIT_FAIL}"
mkdir -p "${EXIT_FAIL}/bin"
cat >"${EXIT_FAIL}/bin/python-fail" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${EXIT_FAIL}/bin/python-fail"
fail_flag="${EXIT_FAIL}/caller-ran"
(
  flag="${fail_flag}"
  trap 'touch "${flag}"' EXIT
  # shellcheck disable=SC1090
  source "${COMMON}"
  create_atomic_project_venv "${EXIT_FAIL}/bin/python-fail" "${EXIT_FAIL}/.venv"
) >/dev/null 2>&1 || true
if [[ -e "${fail_flag}" ]]; then
  pass "failed atomic create still runs the caller EXIT trap"
else
  fail "failed atomic create dropped the caller EXIT trap"
fi
if compgen -G "${EXIT_FAIL}/.venv.partial.*" >/dev/null || [[ -e "${EXIT_FAIL}/.venv" ]]; then
  fail "failed atomic create left a partial or destination tree"
else
  pass "failed atomic create removed its temporary tree"
fi
if [[ -d "${EXIT_FAIL}/.venv.create-lock" ]]; then
  fail "failed atomic create left the create lock"
else
  pass "failed atomic create removed the create lock"
fi

# --- real install / venv scripts (stubs; no live Homebrew) ---

SCRIPT_STUB="${TMP}/script-stub"
mkdir -p "${SCRIPT_STUB}"
cat >"${SCRIPT_STUB}/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -m) printf '%s\n' arm64 ;;
  -s) printf '%s\n' Darwin ;;
  *) printf '%s\n' arm64 ;;
esac
EOF
cat >"${SCRIPT_STUB}/sysctl" <<'EOF'
#!/bin/sh
key="${2:-$1}"
case "${key}" in
  hw.memsize) printf '%s\n' 8589934592 ;;
  hw.ncpu) printf '%s\n' 8 ;;
  hw.model) printf '%s\n' MacBookAir10,1 ;;
  machdep.cpu.brand_string) printf '%s\n' "Apple M1" ;;
  hw.perflevel0.physicalcpu) printf '%s\n' 4 ;;
  hw.perflevel1.physicalcpu) printf '%s\n' 4 ;;
  *) printf '\n' ;;
esac
EOF
cat >"${SCRIPT_STUB}/sw_vers" <<'EOF'
#!/bin/sh
printf '%s\n' 15.0
EOF
cat >"${SCRIPT_STUB}/df" <<'EOF'
#!/bin/sh
printf '%s\n' "Filesystem 1G-blocks Used Available"
printf '%s\n' "/dev/disk1 100 50 40"
EOF
cat >"${SCRIPT_STUB}/xcode-select" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-p" ]; then
  printf '%s\n' /Library/Developer/CommandLineTools
  exit 0
fi
exit 1
EOF
cat >"${SCRIPT_STUB}/ioreg" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${SCRIPT_STUB}/uname" "${SCRIPT_STUB}/sysctl" "${SCRIPT_STUB}/sw_vers" \
  "${SCRIPT_STUB}/df" "${SCRIPT_STUB}/xcode-select" "${SCRIPT_STUB}/ioreg"

run_stubbed() {
  local ws="$1"
  shift
  env -u MLX_INSTALL_HOMEBREW \
    MLX_WORKSPACE="${ws}" MLX_VENV="${ws}/.venv" MLX_SKIP_DEVICE_PROBE=1 \
    PATH="${SCRIPT_STUB}:${PATH}" "$@"
}

FRESH="${TMP}/fresh-install"
mkdir -p "${FRESH}"
fresh_canon="$(cd "${FRESH}" && pwd -P)"
fresh_status=0
fresh_out="$(run_stubbed "${FRESH}" "${ROOT}/scripts/initial-build-mlx-native-media.sh" 2>&1)" || fresh_status=$?
if [[ "${fresh_status}" -ne 0 ]]; then
  pass "fresh install exits non-zero"
else
  fail "fresh install exits non-zero (got ${fresh_status})"
fi
expect_contains "fresh install names the missing venv" \
  "Python venv not found at ${fresh_canon}/.venv. Run: make venv" "${fresh_out}"
if [[ ! -e "${FRESH}/config/models.env" ]]; then
  pass "fresh install does not write models.env"
else
  fail "fresh install wrote models.env"
fi

LOOP="${TMP}/loop"
mkdir -p "${LOOP}/.venv/bin"
printf 'home = /opt/homebrew/opt/python@3.12/bin\nversion = 3.12.0\n' >"${LOOP}/.venv/pyvenv.cfg"
printf '#!/bin/sh\nexit 0\n' >"${LOOP}/.venv/bin/python3"
chmod +x "${LOOP}/.venv/bin/python3"
loop_out="$(run_stubbed "${LOOP}" "${ROOT}/scripts/create-mlx-venv.sh" 2>&1)" || true
expect_contains "python3-only venv is not ready" "missing bin/python" "${loop_out}"
expect_contains "python3-only venv points at rebuild" "make rebuild" "${loop_out}"
if [[ "${loop_out}" == *"Venv ready"* ]]; then
  fail "python3-only venv was reported ready"
else
  pass "python3-only venv was not reported ready"
fi
install_loop="$(run_stubbed "${LOOP}" "${ROOT}/scripts/initial-build-mlx-native-media.sh" 2>&1)" || true
expect_contains "install does not send python3-only back to make venv" "make rebuild" "${install_loop}"
if [[ "${install_loop}" == *"Run: make venv"* ]]; then
  fail "install told a python3-only venv to run make venv"
else
  pass "install did not tell a python3-only venv to run make venv"
fi

rm -rf "${LOOP}/.venv"
mkdir -p "${LOOP}/.venv/bin"
printf 'home = /opt/homebrew/opt/python@3.12/bin\nversion = 3.12.0\n' >"${LOOP}/.venv/pyvenv.cfg"
printf '#!/bin/sh\nexit 0\n' >"${LOOP}/.venv/bin/python"
chmod a-x "${LOOP}/.venv/bin/python"
nox_out="$(run_stubbed "${LOOP}" "${ROOT}/scripts/initial-build-mlx-native-media.sh" 2>&1)" || true
expect_contains "non-executable python points at rebuild" "not executable" "${nox_out}"
expect_contains "non-executable python mentions rebuild" "make rebuild" "${nox_out}"

rm -rf "${LOOP}/.venv"
mkdir -p "${LOOP}/.venv/bin"
printf 'home = /opt/homebrew/opt/python@3.12/bin\nversion = 3.12.0\n' >"${LOOP}/.venv/pyvenv.cfg"
cat >"${LOOP}/.venv/bin/python" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pip" ]; then
  printf '%s\n' "No module named pip" >&2
  exit 1
fi
exit 0
EOF
chmod +x "${LOOP}/.venv/bin/python"
nopip_out="$(run_stubbed "${LOOP}" "${ROOT}/scripts/initial-build-mlx-native-media.sh" 2>&1)" || true
expect_contains "pip-less venv points at rebuild" "pip is missing or broken" "${nopip_out}"

CFG_ONLY="${TMP}/cfg-only-script"
mkdir -p "${CFG_ONLY}/.venv"
printf 'home = /opt/homebrew/opt/python@3.12/bin\nversion = 3.12.0\n' >"${CFG_ONLY}/.venv/pyvenv.cfg"
cfg_script_out="$(run_stubbed "${CFG_ONLY}" "${ROOT}/scripts/create-mlx-venv.sh" 2>&1)" || true
expect_contains "script refuses cfg-only venv" "missing bin/python" "${cfg_script_out}"
if [[ -f "${CFG_ONLY}/.venv/pyvenv.cfg" && ! -e "${CFG_ONLY}/.venv/bin/python" ]]; then
  pass "script left cfg-only venv in place"
else
  fail "script modified cfg-only venv"
fi

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: host-safety self-test passed\n'
exit 0
