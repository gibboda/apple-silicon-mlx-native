#!/usr/bin/env bash
# Constrained-tier MLX limit plan (no GPU, no model load).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_eq() {
  local label="$1"
  local got="$2"
  local want="$3"
  if [[ "${got}" == "${want}" ]]; then
    pass "${label}"
  else
    fail "${label} (got '${got}', want '${want}')"
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

expect_eq "constrained cache is 256 MiB" "${MLX_CONSTRAINED_CACHE_LIMIT_BYTES}" "268435456"
expect_eq "constrained plan applies" "$(inference_limit_plan constrained)" "1|268435456"
expect_eq "standard plan does not apply" "$(inference_limit_plan standard)" "0|"
expect_eq "high plan does not apply" "$(inference_limit_plan high)" "0|"
expect_eq "empty tier does not apply" "$(inference_limit_plan "")" "0|"

if argv_has_flag --max-kv-size --model foo --max-kv-size 32; then
  pass "argv_has_flag finds a bare flag"
else
  fail "argv_has_flag finds a bare flag"
fi
if argv_has_flag --temp --temp=0; then
  pass "argv_has_flag finds FLAG=value"
else
  fail "argv_has_flag finds FLAG=value"
fi
if argv_has_flag --port --host 127.0.0.1; then
  fail "argv_has_flag rejects a missing flag"
else
  pass "argv_has_flag rejects a missing flag"
fi

plan_field() {
  local field="$1"
  local text="$2"
  printf '%s\n' "${text}" | awk -F= -v key="${field}" '$1 == key { print substr($0, length(key) + 2); exit }'
}

assert_fence_follows_physical() {
  local label="$1"
  local text="$2"
  local physical policy apply cache device plan want_apply want_cache pol pol_apply
  physical="$(plan_field physical_tier "${text}")"
  policy="$(plan_field tier "${text}")"
  apply="$(plan_field apply_working_set_limits "${text}")"
  cache="$(plan_field cache_limit_bytes "${text}")"
  device="$(plan_field device "${text}")"
  plan="$(inference_limit_plan "${physical}")"
  IFS='|' read -r want_apply want_cache <<<"${plan}"
  expect_eq "${label} fence apply" "${apply}" "${want_apply}"
  expect_eq "${label} fence cache" "${cache}" "${want_cache}"
  if [[ "${want_apply}" == "1" ]]; then
    expect_eq "${label} fence device" "${device}" "gpu"
  else
    expect_eq "${label} fence device" "${device}" "default"
  fi
  if [[ -n "${policy}" && "${policy}" != "${physical}" ]]; then
    pol="$(inference_limit_plan "${policy}")"
    IFS='|' read -r pol_apply _ <<<"${pol}"
    if [[ "${apply}" == "${pol_apply}" ]]; then
      fail "${label} fence followed policy tier ${policy}"
    else
      pass "${label} fence ignores policy tier ${policy}"
    fi
  fi
}

text_plan="$(
  OVERRIDE_MEMORY_TIER=constrained \
    "${ROOT}/scripts/generate-mlx-text.sh" --dump-plan --model example/model --max-tokens 8 --temp 0
)"
expect_contains "text plan tier" "tier=constrained" "${text_plan}"
expect_contains "text plan model" "model=example/model" "${text_plan}"
expect_contains "text plan tokens" "max_tokens=8" "${text_plan}"
assert_fence_follows_physical "constrained override text" "${text_plan}"

standard_plan="$(
  OVERRIDE_MEMORY_TIER=standard \
    "${ROOT}/scripts/generate-mlx-text.sh" --dump-plan
)"
expect_contains "standard override is policy tier" "tier=standard" "${standard_plan}"
assert_fence_follows_physical "standard override text" "${standard_plan}"

high_plan="$(
  OVERRIDE_MEMORY_TIER=high \
    OVERRIDE_CHIP_FAMILY=3 \
    OVERRIDE_CHIP_SKU=max \
    OVERRIDE_THERMAL_CLASS=cooled \
    OVERRIDE_GPU_CORES=40 \
    "${ROOT}/scripts/generate-mlx-text.sh" --dump-plan --model example/model
)"
expect_contains "high override is policy tier" "tier=high" "${high_plan}"
expect_contains "high override recommends 14B" \
  "recommended_model=mlx-community/Qwen2.5-14B-Instruct-4bit" "${high_plan}"
expect_contains "high override recommends 8k context" "recommended_context=8192" "${high_plan}"
expect_contains "high override context reaches max-kv" "max_kv_size=8192" "${high_plan}"
assert_fence_follows_physical "high override text" "${high_plan}"

serve_plan="$(
  OVERRIDE_MEMORY_TIER=constrained \
    "${ROOT}/scripts/serve-mlx.sh" --dump-plan --host 127.0.0.1 --port 8080
)"
expect_contains "serve plan host" "host=127.0.0.1" "${serve_plan}"
expect_contains "serve plan port" "port=8080" "${serve_plan}"
assert_fence_follows_physical "constrained override serve" "${serve_plan}"

physical_env="$(
  unset MLX_APPLY_WORKING_SET_LIMITS MLX_CACHE_LIMIT_BYTES
  MLX_TIER_ID=standard
  MLX_PHYSICAL_TIER_ID=constrained
  export_inference_limit_env "${MLX_PHYSICAL_TIER_ID}"
  printf 'apply=%s\ncache=%s\n' "${MLX_APPLY_WORKING_SET_LIMITS:-}" "${MLX_CACHE_LIMIT_BYTES:-}"
)"
expect_eq "physical constrained exports the cap" "${physical_env}" $'apply=1\ncache=268435456'

policy_env="$(
  unset MLX_APPLY_WORKING_SET_LIMITS MLX_CACHE_LIMIT_BYTES
  MLX_TIER_ID=constrained
  MLX_PHYSICAL_TIER_ID=high
  export_inference_limit_env "${MLX_PHYSICAL_TIER_ID}"
  printf 'apply=%s\ncache=%s\n' "${MLX_APPLY_WORKING_SET_LIMITS-unset}" "${MLX_CACHE_LIMIT_BYTES-unset}"
)"
expect_eq "policy constrained does not export the cap" "${policy_env}" $'apply=unset\ncache=unset'

if command -v python3 >/dev/null 2>&1; then
  set +e
  python3 "${ROOT}/scripts/lib/mlx_launch.py" >/tmp/mlx-launch-usage.out 2>/tmp/mlx-launch-usage.err
  usage_rc=$?
  set -e
  if [[ "${usage_rc}" -ne 0 ]]; then
    pass "mlx_launch rejects missing command"
  else
    fail "mlx_launch rejects missing command"
  fi
  usage_err="$(cat /tmp/mlx-launch-usage.err /tmp/mlx-launch-usage.out)"
  expect_contains "mlx_launch usage" "usage: mlx_launch.py" "${usage_err}"
  rm -f /tmp/mlx-launch-usage.out /tmp/mlx-launch-usage.err

  stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/mlx-limits.XXXXXX")"
  mkdir -p "${stub_dir}/mlx" "${stub_dir}/mlx_lm"
  : >"${stub_dir}/mlx/__init__.py"
  : >"${stub_dir}/mlx_lm/__init__.py"
  cat >"${stub_dir}/mlx/core.py" <<'PY'
import os

calls = []
_marker = os.environ.get("MLX_STUB_IMPORT_MARKER", "")
if _marker:
    with open(_marker, "a", encoding="utf-8") as handle:
        handle.write("mlx.core\n")

class _Metal:
    @staticmethod
    def is_available():
        return os.environ.get("MLX_STUB_METAL", "1") == "1"

metal = _Metal()
gpu = "gpu"

def set_default_device(device):
    calls.append("set_default_device:%s" % (device,))

def device_info():
    return {
        "max_recommended_working_set_size": int(os.environ.get("MLX_STUB_WORKING_SET", "5726633984") or 0),
        "memory_size": int(os.environ.get("MLX_STUB_MEMORY_SIZE", "8589934592") or 0),
    }

def set_memory_limit(value):
    calls.append("set_memory_limit:%s" % (value,))

def set_cache_limit(value):
    calls.append("set_cache_limit:%s" % (value,))

def set_wired_limit(value):
    if os.environ.get("MLX_STUB_WIRED_RAISE") == "1":
        raise RuntimeError("wired unsupported")
    calls.append("set_wired_limit:%s" % (value,))
PY
  cat >"${stub_dir}/mlx_lm/generate.py" <<'PY'
import os

def main():
    path = os.environ.get("MLX_STUB_MLXLM_MARKER", "")
    if path:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("generate\n")
    raise SystemExit("mlx_lm ran")
PY
  cp "${stub_dir}/mlx_lm/generate.py" "${stub_dir}/mlx_lm/server.py"
  cat >"${stub_dir}/drive.py" <<'PY'
import importlib.util
import os
import sys

stub, launch, mode = sys.argv[1:4]
sys.path.insert(0, stub)
os.environ["MLX_STUB_IMPORT_MARKER"] = os.path.join(stub, "imported-mlx.txt")
os.environ["MLX_STUB_MLXLM_MARKER"] = os.path.join(stub, "imported-mlxlm.txt")

spec = importlib.util.spec_from_file_location("mlx_launch", launch)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

if mode == "off":
    os.environ.pop("MLX_APPLY_WORKING_SET_LIMITS", None)
    mod.apply_runtime_limits()
    print("mlx_imported=%s" % os.path.exists(os.environ["MLX_STUB_IMPORT_MARKER"]))
    raise SystemExit(0)

os.environ["MLX_APPLY_WORKING_SET_LIMITS"] = "1"
os.environ["MLX_CACHE_LIMIT_BYTES"] = "268435456"
if mode == "metal_off":
    os.environ["MLX_STUB_METAL"] = "0"
elif mode == "no_ws":
    os.environ["MLX_STUB_METAL"] = "1"
    os.environ["MLX_STUB_WORKING_SET"] = "0"
elif mode == "clamp":
    os.environ["MLX_STUB_METAL"] = "1"
    os.environ["MLX_STUB_WORKING_SET"] = "1000"
    os.environ["MLX_STUB_MEMORY_SIZE"] = "1000"
elif mode == "wired":
    os.environ["MLX_STUB_METAL"] = "1"
    os.environ["MLX_STUB_WORKING_SET"] = "100"
    os.environ["MLX_STUB_MEMORY_SIZE"] = "1000"
    os.environ["MLX_STUB_WIRED_RAISE"] = "1"
else:
    raise SystemExit("unknown mode")

if mode in ("metal_off", "no_ws"):
    try:
        mod.main(["generate", "--model", "example"])
    except SystemExit as exc:
        print("exit=%s" % (exc.code,))
        print("mlxlm_imported=%s" % os.path.exists(os.environ["MLX_STUB_MLXLM_MARKER"]))
        raise SystemExit(0) from exc
    print("exit=0")
    print("mlxlm_imported=%s" % os.path.exists(os.environ["MLX_STUB_MLXLM_MARKER"]))
    raise SystemExit(0)

mod.apply_runtime_limits()
import mlx.core as mx
print("calls=%s" % ",".join(mx.calls))
print("mlxlm_imported=%s" % os.path.exists(os.environ["MLX_STUB_MLXLM_MARKER"]))
PY

  run_stub() {
    local mode="$1"
    local out rc
    set +e
    out="$(python3 "${stub_dir}/drive.py" "${stub_dir}" "${ROOT}/scripts/lib/mlx_launch.py" "${mode}" 2>&1)"
    rc=$?
    set -e
    if [[ "${rc}" -ne 0 ]]; then
      fail "${mode} driver exited ${rc}: ${out}"
      printf '%s\n' "${out}"
      return
    fi
    printf '%s\n' "${out}"
  }

  off_out="$(run_stub off)"
  expect_contains "limits off does not import mlx" "mlx_imported=False" "${off_out}"

  metal_out="$(run_stub metal_off)"
  expect_contains "metal missing stops launch" "exit=mlx_runtime=metal_unavailable" "${metal_out}"
  expect_contains "metal missing does not import mlx_lm" "mlxlm_imported=False" "${metal_out}"

  nows_out="$(run_stub no_ws)"
  expect_contains "missing working set stops launch" "exit=mlx_runtime=no_working_set" "${nows_out}"
  expect_contains "missing working set does not import mlx_lm" "mlxlm_imported=False" "${nows_out}"

  clamp_out="$(run_stub clamp)"
  expect_contains "clamp sets memory limit" "set_memory_limit:1000" "${clamp_out}"
  expect_contains "clamp sets cache limit" "set_cache_limit:268435456" "${clamp_out}"
  expect_contains "clamp keeps wired below memory size" "set_wired_limit:999" "${clamp_out}"
  expect_contains "clamp does not import mlx_lm" "mlxlm_imported=False" "${clamp_out}"

  wired_out="$(run_stub wired)"
  expect_contains "wired error keeps memory limit" "set_memory_limit:100" "${wired_out}"
  expect_contains "wired error keeps cache limit" "set_cache_limit:268435456" "${wired_out}"
  expect_contains "wired error is reported" "wired_limit_error=wired unsupported" "${wired_out}"
  expect_contains "wired error does not import mlx_lm" "mlxlm_imported=False" "${wired_out}"
  if [[ "${wired_out}" == *"set_wired_limit:"* ]]; then
    fail "wired error still recorded a wired limit"
  else
    pass "wired error does not record a wired limit"
  fi

  rm -rf "${stub_dir}"
else
  fail "python3 is required to check mlx_launch.py"
fi

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: mlx-limits tests passed\n'
