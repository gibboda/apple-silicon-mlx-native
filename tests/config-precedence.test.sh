#!/usr/bin/env bash
# Config precedence: CLI > process env > models.env > composed chip policy.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEXT="${ROOT}/scripts/generate-mlx-text.sh"
SERVE="${ROOT}/scripts/serve-mlx.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

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

expect_exact_line() {
  local label="$1"
  local line="$2"
  local text="$3"
  if grep -qx -F -- "${line}" <<<"${text}"; then
    pass "${label}"
  else
    fail "${label} (missing exact line ${line})"
  fi
}

plan_field() {
  local field="$1"
  local text="$2"
  printf '%s\n' "${text}" | awk -F= -v key="${field}" '$1 == key { print substr($0, length(key) + 2); exit }'
}

empty_env="${TMP}/empty.env"
: >"${empty_env}"

run_text_plan() {
  env -u MLX_DEFAULT_MODEL -u MLX_RECOMMENDED_CONTEXT -u MLX_SERVER_PORT -u MLX_SERVER_HOST \
    "$@"
}

run_serve_plan() {
  env -u MLX_DEFAULT_MODEL -u MLX_RECOMMENDED_CONTEXT -u MLX_SERVER_PORT -u MLX_SERVER_HOST \
    "$@"
}

# --- composed default when user context unset ---

composed_plan="$(
  run_text_plan OVERRIDE_MEMORY_TIER=high OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=max \
    OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=40 \
    MLX_MODELS_ENV="${empty_env}" \
    "${TEXT}" --dump-plan --model example/model
)"
expect_eq "composed recommended_context" "$(plan_field recommended_context "${composed_plan}")" "8192"
expect_eq "composed max_kv_size" "$(plan_field max_kv_size "${composed_plan}")" "8192"

# --- models.env context only ---

file_ctx="${TMP}/ctx-file.env"
printf '%s\n' "MLX_RECOMMENDED_CONTEXT=1024" >"${file_ctx}"
file_plan="$(
  run_text_plan OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base \
    OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
    MLX_MODELS_ENV="${file_ctx}" \
    "${TEXT}" --dump-plan
)"
expect_eq "models.env context max_kv" "$(plan_field max_kv_size "${file_plan}")" "1024"
expect_eq "models.env context keeps composed recommended_context" \
  "$(plan_field recommended_context "${file_plan}")" "2048"

# --- process env context only ---

env_plan="$(
  run_text_plan OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base \
    OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
    MLX_RECOMMENDED_CONTEXT=512 \
    MLX_MODELS_ENV="${empty_env}" \
    "${TEXT}" --dump-plan
)"
expect_eq "env context max_kv" "$(plan_field max_kv_size "${env_plan}")" "512"

# --- env beats models.env for context ---

both_ctx="${TMP}/ctx-both.env"
printf '%s\n' "MLX_RECOMMENDED_CONTEXT=1024" >"${both_ctx}"
env_wins_plan="$(
  run_text_plan OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base \
    OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=10 \
    MLX_RECOMMENDED_CONTEXT=512 \
    MLX_MODELS_ENV="${both_ctx}" \
    "${TEXT}" --dump-plan
)"
expect_eq "env beats file context max_kv" "$(plan_field max_kv_size "${env_wins_plan}")" "512"

# --- CLI --max-kv-size beats env and file ---

cli_plan="$(
  run_text_plan OVERRIDE_MEMORY_TIER=standard \
    MLX_RECOMMENDED_CONTEXT=512 \
    MLX_MODELS_ENV="${both_ctx}" \
    "${TEXT}" --dump-plan --max-kv-size 256
)"
expect_eq "CLI max-kv beats env/file" "$(plan_field max_kv_size "${cli_plan}")" "256"

# --- MLX_SERVER_PORT / MLX_DEFAULT_MODEL precedence ---

port_file="${TMP}/port.env"
printf '%s\n' "MLX_SERVER_PORT=8080" "MLX_DEFAULT_MODEL=env/model" >"${port_file}"

serve_env_port="$(
  run_serve_plan MLX_SERVER_PORT=9000 MLX_MODELS_ENV="${port_file}" \
    "${SERVE}" --dump-plan
)"
expect_exact_line "env port beats models.env" "port=9000" "${serve_env_port}"

text_env_model="$(
  run_text_plan MLX_DEFAULT_MODEL=process/model MLX_MODELS_ENV="${port_file}" \
    OVERRIDE_MEMORY_TIER=constrained \
    "${TEXT}" --dump-plan
)"
expect_eq "env model beats models.env" "$(plan_field model "${text_env_model}")" "process/model"

serve_file_port="$(
  run_serve_plan MLX_MODELS_ENV="${port_file}" \
    "${SERVE}" --dump-plan
)"
expect_exact_line "models.env port when env unset" "port=8080" "${serve_file_port}"

# --- load_models_env unit: env beats file ---

# shellcheck source=scripts/lib/common.sh
source "${ROOT}/scripts/lib/common.sh"
unit_env="${TMP}/unit.env"
printf '%s\n' "MLX_DEFAULT_MODEL=file/model" "MLX_RECOMMENDED_CONTEXT=9999" >"${unit_env}"
unset MLX_DEFAULT_MODEL MLX_RECOMMENDED_CONTEXT
export MLX_DEFAULT_MODEL=shell/model
export MLX_RECOMMENDED_CONTEXT=7777
load_models_env "${unit_env}" >/dev/null 2>&1
expect_eq "load_models_env keeps env model" "${MLX_DEFAULT_MODEL}" "shell/model"
expect_eq "load_models_env keeps env context" "${MLX_RECOMMENDED_CONTEXT}" "7777"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: config-precedence self-test passed\n'
exit 0
