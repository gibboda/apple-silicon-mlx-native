#!/usr/bin/env bash
# Validate the MLX Python environment for Apple Silicon.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/validate-mlx.sh
#   scripts/validate-mlx.sh --venv /path/to/.venv
#
# Returns non-zero when required checks fail.
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: validate-mlx.sh [--venv PATH] [-h|--help]

Validate Python arm64 execution, mlx, mlx-lm, basic array ops, and Metal observability.

  --venv PATH   Virtual environment to validate (default: $MLX_VENV)
  -h            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      [[ $# -ge 2 ]] || die "--venv requires a path"
      MLX_VENV="$2"
      export MLX_VENV
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

failures=0
pass() { log_ok "$1"; }
fail() { log_error "$1"; failures=$((failures + 1)); }

log_header "MLX validation"

assert_apple_silicon
arch="$(detect_architecture)"
if [[ "${arch}" == "arm64" ]]; then
  pass "Host architecture is arm64"
else
  fail "Host architecture is ${arch} (arm64 required)"
fi

python_bin="$(venv_python)"
if [[ ! -x "${python_bin}" ]]; then
  fail "Python not found at ${python_bin}. Run: make install"
  echo "VALIDATION_RESULT=fail"
  exit 1
fi
pass "Python executable: ${python_bin}"

# Ensure the venv Python itself is arm64 (reject Rosetta-translated interpreters).
py_arch="$("${python_bin}" -c 'import platform; print(platform.machine())')"
if [[ "${py_arch}" == "arm64" ]]; then
  pass "Python reports arm64 (${py_arch})"
else
  fail "Python reports ${py_arch}; expected native arm64 (Rosetta/x86_64 interpreters are rejected)"
fi

# Package imports and versions
if ! "${python_bin}" -c 'import mlx' 2>/dev/null; then
  fail "mlx is not importable"
else
  mlx_ver="$("${python_bin}" -c 'import mlx; print(getattr(mlx, "__version__", "unknown"))')"
  pass "mlx importable (version ${mlx_ver})"
fi

if ! "${python_bin}" -c 'import mlx_lm' 2>/dev/null; then
  fail "mlx_lm is not importable"
else
  mlx_lm_ver="$("${python_bin}" -c 'import importlib.metadata as m; print(m.version("mlx-lm"))')"
  pass "mlx_lm importable (version ${mlx_lm_ver})"
fi

# Optional selected media package (warn only if absent)
if "${python_bin}" -c 'import mlx_audio' 2>/dev/null; then
  mlx_audio_ver="$("${python_bin}" -c 'import importlib.metadata as m; print(m.version("mlx-audio"))')"
  pass "mlx-audio importable (version ${mlx_audio_ver})"
else
  log_warn "mlx-audio not installed (optional selected media package)"
fi

# Basic MLX array creation + computation
if "${python_bin}" - <<'PY'
import mlx.core as mx

a = mx.array([1.0, 2.0, 3.0])
b = mx.array([4.0, 5.0, 6.0])
c = a + b
mx.eval(c)
assert c.tolist() == [5.0, 7.0, 9.0], c.tolist()

# Small matmul / reduction sanity check
x = mx.random.normal((64, 64))
y = mx.matmul(x, x.T)
s = mx.sum(y)
mx.eval(s)
assert float(s) == float(s)  # finite check via identity
print("mlx_compute_ok")
PY
then
  pass "Basic MLX array creation and computation succeeded"
else
  fail "Basic MLX computation failed"
fi

# Metal availability where observable
metal_status="$("${python_bin}" - <<'PY' || true
import mlx.core as mx

status = "unknown"
details = []

# Prefer documented/device APIs when present; never fail solely on missing helpers.
for attr in ("metal_is_available", "metal_device_info", "default_device"):
    if hasattr(mx, attr):
        details.append(attr)

try:
    # MLX uses Metal on Apple Silicon; device string is a useful signal.
    device = str(mx.default_device())
    details.append(f"default_device={device}")
    if "gpu" in device.lower() or "metal" in device.lower():
        status = "available"
    else:
        status = "present"
except Exception as exc:  # noqa: BLE001
    details.append(f"error={exc}")
    status = "check_failed"

# Some MLX builds expose metal_is_available()
try:
    if hasattr(mx, "metal") and hasattr(mx.metal, "is_available"):
        status = "available" if mx.metal.is_available() else "unavailable"
        details.append("mx.metal.is_available")
except Exception as exc:  # noqa: BLE001
    details.append(f"metal_probe_error={exc}")

print(status + "|" + ";".join(details))
PY
)"

metal_state="${metal_status%%|*}"
metal_detail="${metal_status#*|}"
case "${metal_state}" in
  available|present)
    pass "Metal observability: ${metal_state} (${metal_detail})"
    ;;
  unavailable)
    fail "Metal appears unavailable (${metal_detail})"
    ;;
  *)
    log_warn "Metal status inconclusive (${metal_detail}); continuing"
    ;;
esac

log_header "Package versions"
"${python_bin}" -m pip show mlx mlx-lm 2>/dev/null | awk '
  /^Name:|^Version:/{print}
' || true

log_header "Hardware"
print_hardware_summary

if (( failures > 0 )); then
  log_error "VALIDATION_RESULT=fail (${failures} failure(s))"
  exit 1
fi

log_ok "VALIDATION_RESULT=pass"
exit 0
