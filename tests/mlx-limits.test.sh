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

text_plan="$(
  OVERRIDE_MEMORY_TIER=constrained \
    "${ROOT}/scripts/generate-mlx-text.sh" --dump-plan --model example/model --max-tokens 8 --temp 0
)"
expect_contains "text plan tier" "tier=constrained" "${text_plan}"
expect_contains "text plan applies limits" "apply_working_set_limits=1" "${text_plan}"
expect_contains "text plan cache" "cache_limit_bytes=268435456" "${text_plan}"
expect_contains "text plan device" "device=gpu" "${text_plan}"
expect_contains "text plan model" "model=example/model" "${text_plan}"
expect_contains "text plan tokens" "max_tokens=8" "${text_plan}"

standard_plan="$(
  OVERRIDE_MEMORY_TIER=standard \
    "${ROOT}/scripts/generate-mlx-text.sh" --dump-plan
)"
expect_contains "standard text plan skips limits" "apply_working_set_limits=0" "${standard_plan}"
expect_contains "standard text plan keeps default device" "device=default" "${standard_plan}"
expect_contains "standard text plan has empty cache" $'cache_limit_bytes=\n' "${standard_plan}"

serve_plan="$(
  OVERRIDE_MEMORY_TIER=constrained \
    "${ROOT}/scripts/serve-mlx.sh" --dump-plan --host 127.0.0.1 --port 8080
)"
expect_contains "serve plan applies limits" "apply_working_set_limits=1" "${serve_plan}"
expect_contains "serve plan cache" "cache_limit_bytes=268435456" "${serve_plan}"
expect_contains "serve plan host" "host=127.0.0.1" "${serve_plan}"
expect_contains "serve plan port" "port=8080" "${serve_plan}"

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
else
  fail "python3 is required to check mlx_launch.py"
fi

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: mlx-limits tests passed\n'
