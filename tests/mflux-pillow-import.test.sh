#!/usr/bin/env bash
# Regression: Pillow 13 + mflux image imports on CPython 3.12+ (numbers._IntegralLike shim).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

if ! python3 -m venv "${TMP}/.venv" >/dev/null 2>&1; then
  if [[ "${CI:-}" == "true" ]]; then
    fail "python3 venv unavailable in CI (install python3-venv for Pillow 13 import test)"
  fi
  printf 'SKIP: python3 venv unavailable (need python3-venv for Pillow 13 import test)\n'
  exit 0
fi

export MLX_WORKSPACE="${TMP}"
export MLX_VENV="${TMP}/.venv"
PY="${MLX_VENV}/bin/python"

"${PY}" -m pip install --disable-pip-version-check -q "pillow==13.0.0"

if python3 -c 'import numbers; numbers._IntegralLike' >/dev/null 2>&1; then
  pass "stdlib already defines numbers._IntegralLike (skip Pillow 13 baseline)"
elif "${PY}" -c 'from PIL import _typing' >/dev/null 2>&1; then
  fail "expected Pillow 13 to fail PIL._typing without compat shim on this interpreter"
else
  pass "Pillow 13 fails PIL._typing without compat (baseline)"
fi

bash -c "source \"${COMMON}\"; ensure_pillow_numbers_compat"

site="$("${PY}" -c 'import site; print(site.getsitepackages()[0])')"
if [[ -f "${site}/mlx_pillow_numbers_compat.py" && -f "${site}/mlx_pillow_numbers_compat.pth" ]]; then
  pass "compat module and .pth installed in venv site-packages"
else
  fail "install_pillow_numbers_compat did not install shim under ${site}"
fi

# .pth auto-import runs on every venv python start (same path as mflux CLIs).
if "${PY}" -c 'from PIL._typing import StrOrBytesPath' >/dev/null 2>&1; then
  pass "PIL._typing importable with venv compat shim"
else
  fail "PIL._typing still fails after install_pillow_numbers_compat"
fi

printf 'OK: mflux-pillow-import\n'
