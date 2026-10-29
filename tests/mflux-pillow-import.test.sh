#!/usr/bin/env bash
# Regression: Pillow 13 numbers._IntegralLike compat shim (CPython 3.12+).
#
# Default (make test): offline — venv shim install + numbers._IntegralLike via .pth.
# Online Pillow 13 import checks: CI=true or MLX_PILLOW_ONLINE_TEST=1 (PyPI download).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"
TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"

pillow_online=0
if [[ "${CI:-}" == "true" || "${MLX_PILLOW_ONLINE_TEST:-}" == "1" ]]; then
  pillow_online=1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

if ! python3 -m venv "${TMP}/.venv" >/dev/null 2>&1; then
  if [[ "${CI:-}" == "true" ]]; then
    fail "python3 venv unavailable in CI (install python3-venv for Pillow 13 import test)"
    assert_finish "mflux-pillow-import"
  fi
  printf 'SKIP: python3 venv unavailable (need python3-venv for Pillow 13 import test)\n'
  exit 0
fi

export MLX_WORKSPACE="${TMP}"
export MLX_VENV="${TMP}/.venv"
PY="${MLX_VENV}/bin/python"

if (( pillow_online )); then
  if ! "${PY}" -m pip install --disable-pip-version-check -q "pillow==13.0.0"; then
    fail "pip install pillow==13.0.0 failed (online Pillow 13 integration)"
  else
    # mflux uses StrOrBytesPath from PIL._typing (not a bare import PIL._typing).
    if "${PY}" -c 'import numbers; numbers._IntegralLike' >/dev/null 2>&1; then
      skip "Pillow 13 imports without numbers._IntegralLike shim (mlx_pillow_numbers_compat may be removable)"
    elif "${PY}" -c 'from PIL._typing import StrOrBytesPath' >/dev/null 2>&1; then
      skip "Pillow 13 imports without numbers._IntegralLike shim (mlx_pillow_numbers_compat may be removable)"
    else
      pass "Pillow 13 fails StrOrBytesPath without compat (baseline)"
    fi
  fi
else
  skip "Pillow 13 PyPI integration (set CI=true or MLX_PILLOW_ONLINE_TEST=1)"
fi

bash -c "source \"${COMMON}\"; ensure_pillow_numbers_compat"

site="$("${PY}" -c 'import site; print(site.getsitepackages()[0])')"
if [[ -f "${site}/mlx_pillow_numbers_compat.py" && -f "${site}/mlx_pillow_numbers_compat.pth" ]]; then
  pass "compat module and .pth installed in venv site-packages"
else
  fail "install_pillow_numbers_compat did not install shim under ${site}"
fi

if "${PY}" -c 'import numbers; numbers._IntegralLike' >/dev/null 2>&1; then
  pass "numbers._IntegralLike available after venv python startup"
else
  fail "mlx_pillow_numbers_compat.pth did not define numbers._IntegralLike"
fi

if (( pillow_online )) && "${PY}" -m pip show pillow >/dev/null 2>&1; then
  if "${PY}" -c 'from PIL._typing import StrOrBytesPath' >/dev/null 2>&1; then
    pass "StrOrBytesPath importable with venv compat shim"
  else
    fail "StrOrBytesPath still fails after install_pillow_numbers_compat"
  fi
fi

assert_finish "mflux-pillow-import"
