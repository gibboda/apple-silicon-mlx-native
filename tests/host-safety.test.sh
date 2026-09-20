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
expect_ok "install paths reuse a real venv" run_install_paths "${WS}" "${WS}/.venv"

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

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: host-safety self-test passed\n'
exit 0
