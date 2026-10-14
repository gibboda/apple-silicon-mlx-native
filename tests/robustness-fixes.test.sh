#!/usr/bin/env bash
# Regression tests for small robustness fixes (issue #80).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
REBUILD="${ROOT}/scripts/rebuild-mlx-native-media.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# shellcheck source=scripts/lib/common.sh
source "${COMMON}"

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

# --- L1: mlx_lm_help_has_flag with large --help ---

HELP_VENV="${TMP}/help-venv"
mkdir -p "${HELP_VENV}/bin"
cat >"${HELP_VENV}/bin/python" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-m" && "${3:-}" == "--help" ]]; then
  python3 -c 'import sys; sys.stdout.write("z" * 70000); sys.stdout.write(" --max-kv-size\n")'
  exit 0
fi
exec python3 "$@"
EOF
chmod +x "${HELP_VENV}/bin/python"

if MLX_VENV="${HELP_VENV}" mlx_lm_help_has_flag mlx_lm.server --max-kv-size; then
  pass "help flag survives large --help under pipefail"
else
  fail "help flag survives large --help under pipefail"
fi

# --- L5: venv create lock timeout and live holder ---

LOCK_DEST="${TMP}/lock-dest"
LOCK_DIR="${LOCK_DEST}.create-lock"
rm -rf "${LOCK_DIR}"
mkdir -p "${LOCK_DIR}"
( sleep 30 ) &
holder_pid=$!
printf '%s\n' "${holder_pid}" >"${LOCK_DIR}/pid"

lock_err=""
set +e
lock_err="$(MLX_VENV_LOCK_TIMEOUT=2 acquire_venv_create_lock "${LOCK_DEST}" 2>&1)"
lock_status=$?
set -e
kill "${holder_pid}" 2>/dev/null || true
wait "${holder_pid}" 2>/dev/null || true

if [[ "${lock_status}" -ne 0 ]]; then
  pass "lock waits then times out when holder is alive"
else
  fail "lock waits then times out when holder is alive"
fi
expect_contains "lock timeout message" "Timed out waiting for venv create lock" "${lock_err}"
if [[ -d "${LOCK_DIR}" ]]; then
  pass "lock directory not stolen from live holder"
else
  fail "lock directory not stolen from live holder"
fi

# --- L9: Homebrew prefix boundary on pyvenv.cfg home ---

PREFIX_VENV="${TMP}/prefix-venv"
mkdir -p "${PREFIX_VENV}"
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

run_venv_home() {
  env MLX_VENV="$1" PATH="${FAKE_BREW}/bin:${PATH}" bash -c \
    "source \"${COMMON}\"; venv_home_under_homebrew"
}

printf 'home = /opt/homebrewX/evil\n' >"${PREFIX_VENV}/pyvenv.cfg"
expect_fail "homebrewX prefix rejected" run_venv_home "${PREFIX_VENV}"

printf 'home = /opt/homebrew/opt/python@3.12/bin\n' >"${PREFIX_VENV}/pyvenv.cfg"
expect_ok "opt/homebrew path accepted" run_venv_home "${PREFIX_VENV}"

# --- L8: rebuild refuses non-interactive venv removal (same guard as rebuild-mlx-native-media.sh) ---

REBUILD_VENV="${TMP}/rebuild-gate-venv"
mkdir -p "${REBUILD_VENV}/bin"
printf 'home = /opt/homebrew/opt/python@3.12/bin\n' >"${REBUILD_VENV}/pyvenv.cfg"
printf '#!/bin/sh\nexit 0\n' >"${REBUILD_VENV}/bin/python"
printf '#!/bin/sh\nexit 0\n' >"${REBUILD_VENV}/bin/pip"
chmod +x "${REBUILD_VENV}/bin/python" "${REBUILD_VENV}/bin/pip"

run_rebuild_venv_remove_gate() {
  env MLX_VENV="$1" FORCE=0 MLX_ASSUME_YES=0 bash -c \
    "set -euo pipefail
    source \"${COMMON}\"
    if [[ -e \"\${MLX_VENV}\" ]]; then
      if [[ ! -d \"\${MLX_VENV}\" ]]; then
        exit 2
      fi
      if ! looks_like_venv \"\${MLX_VENV}\"; then
        exit 3
      fi
      if (( FORCE == 0 )) && ! is_truthy \"\${MLX_ASSUME_YES:-0}\"; then
        if [[ -t 0 ]]; then
          exit 4
        else
          die \"Refusing to remove \${MLX_VENV} without a TTY. Re-run with --force or MLX_ASSUME_YES=1.\"
        fi
      fi
      rm -rf \"\${MLX_VENV}\"
    fi" </dev/null
}

gate_err=""
set +e
gate_err="$(run_rebuild_venv_remove_gate "${REBUILD_VENV}" 2>&1)"
gate_status=$?
set -e

if [[ "${gate_status}" -ne 0 ]]; then
  pass "rebuild gate non-interactive without force exits non-zero"
else
  fail "rebuild gate non-interactive without force exits non-zero"
fi
expect_contains "rebuild gate mentions non-interactive refusal" "without a TTY" "${gate_err}"
if [[ -d "${REBUILD_VENV}" && -f "${REBUILD_VENV}/pyvenv.cfg" ]]; then
  pass "rebuild gate leaves venv intact"
else
  fail "rebuild gate leaves venv intact"
fi

if grep -q 'Refusing to remove.*without a TTY' "${REBUILD}"; then
  pass "rebuild script contains non-interactive venv guard"
else
  fail "rebuild script contains non-interactive venv guard"
fi

if (( failures > 0 )); then
  printf 'FAIL: %s robustness check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: robustness-fixes\n'
