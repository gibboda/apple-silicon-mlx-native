#!/usr/bin/env bash
# Self-test for PIP_CONSTRAINT coverage and constraints/common.sh parity.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
CONSTRAINTS="${ROOT}/requirements/constraints.txt"

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_eq() {
  local label="$1"
  local want="$2"
  local got="$3"
  if [[ "${got}" == "${want}" ]]; then
    pass "${label}"
  else
    fail "${label} (want ${want}, got ${got})"
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

constraint_pins() {
  grep -Ev '^\s*(#|$)' "${CONSTRAINTS}" | sort
}

common_default_pins() {
  env bash -c "source \"${COMMON}\";
printf '%s\n' \
  \"\${MLX_PIP_PACKAGE}\" \
  \"\${MLX_SETUPTOOLS_PACKAGE}\" \
  \"\${MLX_WHEEL_PACKAGE}\" \
  \"\${MLX_PACKAGING_LIB_PACKAGE}\" \
  \"\${MLX_PACKAGE}\" \
  \"\${MLX_LM_PACKAGE}\" \
  \"\${MLX_AUDIO_PACKAGE}\" \
  \"\${MLX_IMAGE_PACKAGE}\"" | sort
}

expect_eq "constraints file exists" "yes" "$(test -f "${CONSTRAINTS}" && printf yes || printf no)"

shared="$(comm -12 <(constraint_pins) <(common_default_pins))"
expect_eq "constraints include all common.sh default pins" "$(common_default_pins | wc -l | tr -d ' ')" "$(printf '%s\n' "${shared}" | sed '/^$/d' | wc -l | tr -d ' ')"

for pkg in transformers numpy huggingface-hub mlx-vlm torch mlx-metal; do
  if grep -q "^${pkg}==" "${CONSTRAINTS}"; then
    pass "transitive pin ${pkg}"
  else
    fail "transitive pin ${pkg}"
  fi
done

direct_pip="$(grep -RIn --exclude-dir=lib -E '(\$\{PIP\}|-m pip)[[:space:]]+install' "${ROOT}/scripts" || true)"
if [[ -n "${direct_pip}" ]]; then
  fail "direct pip install outside mlx_pip_install: ${direct_pip}"
else
  pass "no direct pip install in scripts (use mlx_pip_install)"
fi

for installer in \
  "${ROOT}/scripts/initial-build-mlx-native-media.sh" \
  "${ROOT}/scripts/rebuild-mlx-native-media.sh" \
  "${ROOT}/scripts/install-mlx-image.sh" \
  "${ROOT}/scripts/install-mlx-video.sh"
do
  if grep -qE 'mlx_pip_install|install_core_packages' "${installer}"; then
    pass "mlx_pip_install in $(basename "${installer}")"
  else
    fail "mlx_pip_install missing in $(basename "${installer}")"
  fi
done

INSTALL_WS="$(mktemp -d)"
mkdir -p "${INSTALL_WS}/.venv/bin"
cat >"${INSTALL_WS}/.venv/bin/python" <<EOF
#!/bin/sh
if [ "\$1" = "-m" ] && [ "\$2" = "pip" ]; then
  printf 'PIP_CONSTRAINT=%s\n' "\${PIP_CONSTRAINT:-}" >> "${INSTALL_WS}/pip-env"
  shift 2
  printf '%s' "-m pip" >> "${INSTALL_WS}/pip-args"
  for arg in "\$@"; do
    printf ' %s' "\$arg" >> "${INSTALL_WS}/pip-args"
  done
  printf '\\n' >> "${INSTALL_WS}/pip-args"
  exit 0
fi
printf '%s\\n' 'pip 26.2.1' 'setuptools 84.0.0' 'wheel 0.48.0' 'packaging 26.3'
EOF
chmod +x "${INSTALL_WS}/.venv/bin/python"

: >"${INSTALL_WS}/pip-env"
: >"${INSTALL_WS}/pip-args"
MLX_WORKSPACE="${INSTALL_WS}" MLX_VENV="${INSTALL_WS}/.venv" bash -c "source \"${COMMON}\"; mlx_pip_install --upgrade mlx==0.32.4" >/dev/null
expect_contains "mlx_pip_install sets PIP_CONSTRAINT" "PIP_CONSTRAINT=${CONSTRAINTS}" "$(cat "${INSTALL_WS}/pip-env")"
expect_contains "mlx_pip_install passes upgrade" "--upgrade mlx==0.32.4" "$(cat "${INSTALL_WS}/pip-args")"

: >"${INSTALL_WS}/pip-env"
: >"${INSTALL_WS}/pip-args"
MLX_WORKSPACE="${INSTALL_WS}" MLX_VENV="${INSTALL_WS}/.venv" bash -c "source \"${COMMON}\"; install_packaging_tools" >/dev/null 2>&1
expect_contains "install_packaging_tools sets PIP_CONSTRAINT" "PIP_CONSTRAINT=${CONSTRAINTS}" "$(cat "${INSTALL_WS}/pip-env")"

rm -rf "${INSTALL_WS}"

alt_constraints="$(mktemp)"
sed 's/^mlx==.*/mlx==9.9.9/' "${CONSTRAINTS}" >"${alt_constraints}"
read_manifest_pin() {
  local constraints="$1"
  local common="$2"
  # shellcheck disable=SC2016
  MLX_PIP_CONSTRAINT_FILE="${constraints}" bash -c 'unset MLX_PACKAGE; source "$1"; printf %s "${MLX_PACKAGE}"' bash "${common}"
}
manifest_pin="$(read_manifest_pin "${alt_constraints}" "${COMMON}")"
expect_eq "common.sh mlx default comes from constraints manifest" "mlx==9.9.9" "${manifest_pin}"
rm -f "${alt_constraints}"

override_ws="$(mktemp -d)"
mkdir -p "${override_ws}/.venv/bin"
cat >"${override_ws}/.venv/bin/python" <<EOF
#!/bin/sh
if [ "\$1" = "-m" ] && [ "\$2" = "pip" ]; then
  printf 'PIP_CONSTRAINT=%s\n' "\${PIP_CONSTRAINT:-}" >> "${override_ws}/pip-env"
  exit 0
fi
printf '%s\\n' 'pip 26.2.1' 'setuptools 84.0.0' 'wheel 0.48.0' 'packaging 26.3'
EOF
chmod +x "${override_ws}/.venv/bin/python"
: >"${override_ws}/pip-env"
MLX_WORKSPACE="${override_ws}" MLX_VENV="${override_ws}/.venv" MLX_IMAGE_PACKAGE='mflux==0.20.0' \
  bash -c 'source "$1"; mlx_pip_install --upgrade mflux==0.20.0' bash "${COMMON}" >/dev/null
override_constraint="$(sed -n 's/^PIP_CONSTRAINT=//p' "${override_ws}/pip-env" | head -n 1)"
expect_contains "override constraint replaces mflux pin" "mflux==0.20.0" "$(cat "${override_constraint}")"
if grep -q '^mflux==0.19.1$' "${override_constraint}"; then
  fail "override constraint still pins mflux==0.19.1"
else
  pass "override constraint drops the manifest mflux pin"
fi
manifest_metal="$(grep -E '^mlx-metal==[^[:space:]]+$' "${CONSTRAINTS}" | head -n 1)"
expect_eq "unrelated override keeps mlx-metal pin" "${manifest_metal}" "$(grep -E '^mlx-metal==' "${override_constraint}" || true)"

: >"${override_ws}/pip-env"
MLX_WORKSPACE="${override_ws}" MLX_VENV="${override_ws}/.venv" MLX_PACKAGE='mlx==1.2.3' \
  bash -c 'source "$1"; mlx_pip_install --upgrade mlx==1.2.3' bash "${COMMON}" >/dev/null
mlx_override="$(sed -n 's/^PIP_CONSTRAINT=//p' "${override_ws}/pip-env" | head -n 1)"
expect_eq "mlx override retargets mlx" "mlx==1.2.3" "$(grep -E '^mlx==' "${mlx_override}" || true)"
expect_eq "mlx override retargets mlx-metal" "mlx-metal==1.2.3" "$(grep -E '^mlx-metal==' "${mlx_override}" || true)"
if grep -qx "${manifest_metal}" "${mlx_override}"; then
  fail "mlx override still pins ${manifest_metal}"
else
  pass "mlx override drops the manifest mlx-metal pin"
fi

: >"${override_ws}/pip-env"
MLX_WORKSPACE="${override_ws}" MLX_VENV="${override_ws}/.venv" MLX_PACKAGE='mlx>=1.2.3' \
  bash -c 'source "$1"; mlx_pip_install --upgrade mlx' bash "${COMMON}" >/dev/null
range_constraint="$(sed -n 's/^PIP_CONSTRAINT=//p' "${override_ws}/pip-env" | head -n 1)"
if grep -q '^mlx==' "${range_constraint}" || grep -q '^mlx-metal==' "${range_constraint}"; then
  fail "non-exact mlx override still constrains mlx or mlx-metal"
else
  pass "non-exact mlx override omits mlx and mlx-metal pins"
fi

: >"${override_ws}/pip-env"
MLX_WORKSPACE="${override_ws}" MLX_VENV="${override_ws}/.venv" MLX_PACKAGE='mlx' \
  bash -c 'source "$1"; mlx_pip_install --upgrade mlx' bash "${COMMON}" >/dev/null
bare_constraint="$(sed -n 's/^PIP_CONSTRAINT=//p' "${override_ws}/pip-env" | head -n 1)"
if grep -q '^mlx==' "${bare_constraint}"; then
  fail "bare mlx override still constrains mlx"
else
  pass "bare mlx override omits the mlx pin"
fi
if grep -q '^mlx-metal==' "${bare_constraint}"; then
  fail "bare mlx override still constrains mlx-metal"
else
  pass "bare mlx override omits the mlx-metal pin"
fi
rm -rf "${override_ws}"

if (( failures > 0 )); then
  printf 'FAIL: %s pip-constraint check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: pip constraints\n'
