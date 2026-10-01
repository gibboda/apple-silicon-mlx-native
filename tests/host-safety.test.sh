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
chmod +x "${WS}/.venv/bin/python"
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
chmod +x "${REQ}/.venv/bin/python"
expect_ok "require venv accepts a complete venv" run_require_venv "${REQ}" "${REQ}/.venv"

rm -rf "${REQ}/.venv"
mkdir -p "${REQ}/.venv"
printf 'home = /usr/bin/python3\ninclude-system-site-packages = false\n' >"${REQ}/.venv/pyvenv.cfg"
expect_fail "require venv rejects incomplete venv" run_require_venv "${REQ}" "${REQ}/.venv"
req_incomplete="$(run_require_venv "${REQ}" "${REQ}/.venv" 2>&1)" || true
expect_contains "require incomplete mentions make venv" "make venv" "${req_incomplete}"
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
  mkdir -p "${ATOMIC}"
  rm -rf "${ATOMIC}/.venv"
  expect_ok "atomic venv create leaves a working tree" \
    run_atomic_venv "${ATOMIC}" "${ATOMIC}/.venv" "$(command -v python3)"
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
else
  pass "skip venv identity tests (python3 -m venv unavailable)"
fi

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: host-safety self-test passed\n'
exit 0
