#!/usr/bin/env bash
# Generate text with mlx_lm on the GPU, with constrained-tier MLX memory limits.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/generate-mlx-text.sh --prompt "Hello from MLX"
#   make generate-text PROMPT="Hello from MLX"
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PROMPT=""
MODEL=""
MAX_TOKENS=""
MAX_KV=""
TEMP=""
DUMP_PLAN=0
PASSTHRU=()

usage() {
  cat <<'EOF'
Usage: generate-mlx-text.sh --prompt TEXT [options]

One-shot text generation with mlx_lm.generate. On the constrained (≤8 GB)
tier this process pins MLX to the GPU and sets the memory and wired limits
to the Metal recommended working set and the cache limit to 256 MiB before
weights load. Larger tiers keep MLX defaults. mlx_lm.generate itself is
unchanged if you call it directly.

Options:
  --prompt TEXT       Prompt (required unless --dump-plan)
  --model NAME        Model id or local path (default: MLX_DEFAULT_MODEL or composed recommendation)
  --max-tokens N      Generation cap (default: MLX_MAX_TOKENS when set in models.env)
  --max-kv-size N     KV cache cap (default: MLX_RECOMMENDED_CONTEXT)
  --temp T            Sampling temperature (default: MLX_TEMPERATURE when set)
  --dump-plan         Print the resolved plan and exit
  --                  Extra args passed through to mlx_lm.generate
  -h, --help          Show this help

config/models.env is parsed as MLX_* assignments (not executed).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt|-p)
      [[ $# -ge 2 ]] || die "--prompt requires TEXT"
      PROMPT="$2"
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || die "--model requires NAME"
      MODEL="$2"
      shift 2
      ;;
    --max-tokens)
      [[ $# -ge 2 ]] || die "--max-tokens requires N"
      MAX_TOKENS="$2"
      shift 2
      ;;
    --max-kv-size)
      [[ $# -ge 2 ]] || die "--max-kv-size requires N"
      MAX_KV="$2"
      shift 2
      ;;
    --temp)
      [[ $# -ge 2 ]] || die "--temp requires T"
      TEMP="$2"
      shift 2
      ;;
    --dump-plan) DUMP_PLAN=1; shift ;;
    --)
      shift
      PASSTHRU+=("$@")
      break
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use -- to pass flags through to mlx_lm.generate)" ;;
  esac
done

load_models_env "${MLX_MODELS_ENV}"
if (( DUMP_PLAN == 1 )); then
  MLX_SKIP_DEVICE_PROBE=1
fi
load_runtime_profile

MODEL="${MODEL:-${MLX_DEFAULT_MODEL:-${MLX_RECOMMENDED_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}}}"
MAX_TOKENS="${MAX_TOKENS:-${MLX_MAX_TOKENS:-}}"
MAX_KV="${MAX_KV:-${MLX_RECOMMENDED_CONTEXT:-2048}}"
TEMP="${TEMP:-${MLX_TEMPERATURE:-}}"

plan="$(inference_limit_plan "${MLX_TIER_ID:-}")"
IFS='|' read -r apply_limits cache_limit <<<"${plan}"

if (( DUMP_PLAN == 1 )); then
  printf 'tier=%s\ndevice=%s\napply_working_set_limits=%s\ncache_limit_bytes=%s\nmodel=%s\nmax_tokens=%s\nmax_kv_size=%s\ntemp=%s\n' \
    "${MLX_TIER_ID:-}" \
    "$([[ "${apply_limits}" == "1" ]] && echo gpu || echo default)" \
    "${apply_limits}" \
    "${cache_limit}" \
    "${MODEL}" \
    "${MAX_TOKENS}" \
    "${MAX_KV}" \
    "${TEMP}"
  exit 0
fi

if [[ -z "${PROMPT}" ]]; then
  usage >&2
  die "Missing --prompt. Example: scripts/generate-mlx-text.sh --prompt \"Hello from MLX\""
fi
assert_apple_silicon
py="$(venv_python)"
if [[ ! -x "${py}" ]]; then
  die "Python venv not found at ${MLX_VENV}. Run: make install"
fi

args=(--model "${MODEL}" --prompt "${PROMPT}")
if [[ -n "${MAX_TOKENS}" ]] && ! argv_has_flag --max-tokens "${PASSTHRU[@]+"${PASSTHRU[@]}"}"; then
  args+=(--max-tokens "${MAX_TOKENS}")
fi
if [[ -n "${MAX_KV}" ]] && ! argv_has_flag --max-kv-size "${PASSTHRU[@]+"${PASSTHRU[@]}"}"; then
  args+=(--max-kv-size "${MAX_KV}")
fi
if [[ -n "${TEMP}" ]] && ! argv_has_flag --temp "${PASSTHRU[@]+"${PASSTHRU[@]}"}"; then
  args+=(--temp "${TEMP}")
fi
if ((${#PASSTHRU[@]} > 0)); then
  args+=("${PASSTHRU[@]}")
fi

export_inference_limit_env "${MLX_TIER_ID:-}"
if [[ "${apply_limits}" == "1" ]]; then
  log_info "Constrained tier: GPU, memory and wired limits at the Metal working set, cache ${cache_limit} bytes" >&2
fi

exec "${py}" "${SCRIPT_DIR}/lib/mlx_launch.py" generate "${args[@]}"
