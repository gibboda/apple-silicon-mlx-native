#!/usr/bin/env bash
# Run a resident mlx_lm.server with constrained-tier MLX memory limits.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/serve-mlx.sh
#   make serve
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

MODEL=""
HOST=""
PORT=""
DUMP_PLAN=0
PASSTHRU=()

usage() {
  cat <<'EOF'
Usage: serve-mlx.sh [options]

Start one mlx_lm.server process so weights stay resident. On physical ≤8 GB
RAM this process pins MLX to the GPU and sets the memory and wired limits
to the Metal recommended working set and the cache limit to 256 MiB before
weights load. OVERRIDE_MEMORY_TIER changes the recommended model and context
only. If Metal or the working set cannot be applied, the launch stops.
Larger machines keep MLX defaults.

Options:
  --model NAME     Model id or local path (default: MLX_DEFAULT_MODEL or composed recommendation)
  --host HOST      Bind address (default: MLX_SERVER_HOST or 127.0.0.1)
  --port PORT      Bind port (default: MLX_SERVER_PORT or 8080)
  --dump-plan      Print the resolved plan and exit
  --               Extra args passed through to mlx_lm.server
  -h, --help       Show this help

mlx-lm 0.31.3 server has no --max-kv-size flag. Cap client context to
MLX_RECOMMENDED_CONTEXT. config/models.env is parsed as MLX_* assignments.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      [[ $# -ge 2 ]] || die "--model requires NAME"
      MODEL="$2"
      shift 2
      ;;
    --host)
      [[ $# -ge 2 ]] || die "--host requires HOST"
      HOST="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port requires PORT"
      PORT="$2"
      shift 2
      ;;
    --dump-plan) DUMP_PLAN=1; shift ;;
    --)
      shift
      PASSTHRU+=("$@")
      break
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use -- to pass flags through to mlx_lm.server)" ;;
  esac
done

load_models_env "${MLX_MODELS_ENV}"
if (( DUMP_PLAN == 1 )); then
  MLX_SKIP_DEVICE_PROBE=1
fi
load_runtime_profile

MODEL="${MODEL:-${MLX_DEFAULT_MODEL:-${MLX_RECOMMENDED_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}}}"
HOST="${HOST:-${MLX_SERVER_HOST:-127.0.0.1}}"
PORT="${PORT:-${MLX_SERVER_PORT:-8080}}"

plan="$(inference_limit_plan "${MLX_PHYSICAL_TIER_ID:-}")"
IFS='|' read -r apply_limits cache_limit <<<"${plan}"

if (( DUMP_PLAN == 1 )); then
  printf 'tier=%s\nphysical_tier=%s\ndevice=%s\napply_working_set_limits=%s\ncache_limit_bytes=%s\nmodel=%s\nrecommended_model=%s\nhost=%s\nport=%s\ncontext=%s\n' \
    "${MLX_TIER_ID:-}" \
    "${MLX_PHYSICAL_TIER_ID:-}" \
    "$([[ "${apply_limits}" == "1" ]] && echo gpu || echo default)" \
    "${apply_limits}" \
    "${cache_limit}" \
    "${MODEL}" \
    "${MLX_RECOMMENDED_MODEL:-}" \
    "${HOST}" \
    "${PORT}" \
    "${MLX_RECOMMENDED_CONTEXT:-2048}"
  exit 0
fi

assert_apple_silicon
py="$(venv_python)"
if [[ ! -x "${py}" ]]; then
  die "Python venv not found at ${MLX_VENV}. Run: make install"
fi

args=(--model "${MODEL}")
if [[ -n "${HOST}" ]] && ! argv_has_flag --host "${PASSTHRU[@]+"${PASSTHRU[@]}"}"; then
  args+=(--host "${HOST}")
fi
if [[ -n "${PORT}" ]] && ! argv_has_flag --port "${PASSTHRU[@]+"${PASSTHRU[@]}"}"; then
  args+=(--port "${PORT}")
fi
if ((${#PASSTHRU[@]} > 0)); then
  args+=("${PASSTHRU[@]}")
fi

export_inference_limit_env "${MLX_PHYSICAL_TIER_ID:-}"
if [[ "${apply_limits}" == "1" ]]; then
  log_info "Constrained tier: GPU, memory and wired limits at the Metal working set, cache ${cache_limit} bytes" >&2
fi

exec "${py}" "${SCRIPT_DIR}/lib/mlx_launch.py" server "${args[@]}"
