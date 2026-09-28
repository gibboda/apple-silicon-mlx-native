#!/usr/bin/env bash
# Catalog fit labels for make list (no sysctl, no download).
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

list_column() {
  local model="$1"
  local column="$2"
  local text="$3"
  printf '%s\n' "${text}" | awk -F '\t' -v id="${model}" -v col="${column}" '$3 == id { print $col; exit }'
}

expect_eq "8 GB fanless default is 3B" \
  "$(model_list_fit mlx-community/Llama-3.2-3B-Instruct-4bit constrained slow fanless)" \
  "default"
expect_eq "8 GB fanless 1B fits" \
  "$(model_list_fit mlx-community/Llama-3.2-1B-Instruct-4bit constrained slow fanless)" \
  "fits"
expect_eq "8 GB fanless Phi fits" \
  "$(model_list_fit mlx-community/Phi-3.5-mini-instruct-4bit constrained slow fanless)" \
  "fits"
expect_eq "8 GB fanless Qwen 3B fits" \
  "$(model_list_fit mlx-community/Qwen2.5-3B-Instruct-4bit constrained slow fanless)" \
  "fits"
expect_eq "8 GB fanless 7B is poor" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit constrained slow fanless)" \
  "poor"
expect_eq "8 GB fanless 8B is poor" \
  "$(model_list_fit mlx-community/Meta-Llama-3.1-8B-Instruct-4bit constrained slow fanless)" \
  "poor"
expect_eq "8 GB fanless 14B is poor" \
  "$(model_list_fit mlx-community/Qwen2.5-14B-Instruct-4bit constrained slow fanless)" \
  "poor"
expect_eq "8 GB fanless 32B is poor" \
  "$(model_list_fit mlx-community/Qwen2.5-32B-Instruct-4bit constrained slow fanless)" \
  "poor"

expect_eq "16 GB slow cooled default stays 3B" \
  "$(model_list_fit mlx-community/Llama-3.2-3B-Instruct-4bit standard moderate cooled)" \
  "default"
expect_eq "16 GB slow cooled 7B is tight" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit standard moderate cooled)" \
  "tight"
expect_eq "16 GB fanless 7B is tight" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit standard slow fanless)" \
  "tight"

expect_eq "16 GB fast cooled default is 7B" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit standard fast cooled)" \
  "default"
expect_eq "16 GB fast cooled 8B fits" \
  "$(model_list_fit mlx-community/Meta-Llama-3.1-8B-Instruct-4bit standard fast cooled)" \
  "fits"
expect_eq "16 GB fast cooled 3B still fits" \
  "$(model_list_fit mlx-community/Llama-3.2-3B-Instruct-4bit standard fast cooled)" \
  "fits"
expect_eq "16 GB fast cooled 14B is poor" \
  "$(model_list_fit mlx-community/Qwen2.5-14B-Instruct-4bit standard fast cooled)" \
  "poor"

expect_eq "24 GB cooled default is 7B" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit high fast cooled)" \
  "default"
expect_eq "24 GB cooled 14B is tight" \
  "$(model_list_fit mlx-community/Qwen2.5-14B-Instruct-4bit high fast cooled)" \
  "tight"
expect_eq "32 GB very_fast default is 14B" \
  "$(model_list_fit mlx-community/Qwen2.5-14B-Instruct-4bit high very_fast cooled)" \
  "default"
expect_eq "32 GB very_fast 7B still fits" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit high very_fast cooled)" \
  "fits"
expect_eq "32 GB very_fast 32B is poor" \
  "$(model_list_fit mlx-community/Qwen2.5-32B-Instruct-4bit high very_fast cooled)" \
  "poor"

expect_eq "workstation default is 14B" \
  "$(model_list_fit mlx-community/Qwen2.5-14B-Instruct-4bit workstation fast cooled)" \
  "default"
expect_eq "workstation 32B fits" \
  "$(model_list_fit mlx-community/Qwen2.5-32B-Instruct-4bit workstation fast cooled)" \
  "fits"
expect_eq "large default is 32B" \
  "$(model_list_fit mlx-community/Qwen2.5-32B-Instruct-4bit large extreme cooled)" \
  "default"
expect_eq "large 14B fits" \
  "$(model_list_fit mlx-community/Qwen2.5-14B-Instruct-4bit large extreme cooled)" \
  "fits"
expect_eq "fanless high default stays 7B" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit high very_fast fanless)" \
  "default"

empty_cache="$(mktemp -d "${TMPDIR:-/tmp}/mlx-list-empty.XXXXXX")"
air="$(
  HF_HUB_CACHE="${empty_cache}" \
    print_recommended_model_list constrained slow fanless "Apple M1" 8 2048 1 base constrained
)"
expect_contains "list names the chip" "Apple chip:       Apple M1" "${air}"
expect_contains "list names 8 GiB" "Memory:           8 GiB" "${air}"
expect_contains "list names constrained tier" "Memory tier:      constrained (physical constrained)" "${air}"
expect_contains "list names fanless" "Thermal class:    fanless" "${air}"
expect_contains "list default model" "Default model:    mlx-community/Llama-3.2-3B-Instruct-4bit" "${air}"
expect_contains "list default context" "Default context:  2048" "${air}"
expect_eq "printed 8 GB 7B row is poor" \
  "$(list_column mlx-community/Mistral-7B-Instruct-v0.3-4bit 1 "${air}")" \
  "poor"
expect_eq "printed 8 GB 3B row is default" \
  "$(list_column mlx-community/Llama-3.2-3B-Instruct-4bit 1 "${air}")" \
  "default"
expect_eq "empty cache marks 3B not cached" \
  "$(list_column mlx-community/Llama-3.2-3B-Instruct-4bit 2 "${air}")" \
  "no"
expect_contains "list tells how to serve one model" "scripts/serve-mlx.sh --model MODEL" "${air}"

cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/mlx-list-cache.XXXXXX")"
complete="${cache_dir}/models--mlx-community--Llama-3.2-3B-Instruct-4bit/snapshots/abc"
partial="${cache_dir}/models--mlx-community--Qwen2.5-3B-Instruct-4bit/snapshots/abc"
mkdir -p "${complete}" "${partial}"
printf '{}\n' >"${complete}/config.json"
printf 'weights\n' >"${complete}/model.safetensors"
printf '{}\n' >"${partial}/config.json"
printf 'partial\n' >"${partial}/model.safetensors.incomplete"
cached_list="$(
  HF_HUB_CACHE="${cache_dir}" \
    print_recommended_model_list constrained slow fanless "Apple M1" 8 2048 1 base constrained
)"
expect_eq "complete snapshot is cached" \
  "$(list_column mlx-community/Llama-3.2-3B-Instruct-4bit 2 "${cached_list}")" \
  "yes"
expect_eq "incomplete snapshot is not cached" \
  "$(list_column mlx-community/Qwen2.5-3B-Instruct-4bit 2 "${cached_list}")" \
  "no"
expect_eq "missing repo is not cached" \
  "$(list_column mlx-community/Mistral-7B-Instruct-v0.3-4bit 2 "${cached_list}")" \
  "no"

broken="${cache_dir}/models--mlx-community--Meta-Llama-3.1-8B-Instruct-4bit/snapshots/broken"
sharded="${cache_dir}/models--mlx-community--Qwen2.5-14B-Instruct-4bit/snapshots/sharded"
partial_sharded="${cache_dir}/models--mlx-community--Qwen2.5-32B-Instruct-4bit/snapshots/partial"
mkdir -p "${broken}" "${sharded}" "${partial_sharded}"
printf '{}\n' >"${broken}/config.json"
ln -sf /nonexistent "${broken}/model.safetensors"
printf '{}\n' >"${sharded}/config.json"
cat >"${sharded}/model.safetensors.index.json" <<'EOF'
{"weight_map":{"layer.a":"model-00001-of-00002.safetensors","layer.b":"model-00002-of-00002.safetensors"}}
EOF
printf 'shard1\n' >"${sharded}/model-00001-of-00002.safetensors"
printf 'shard2\n' >"${sharded}/model-00002-of-00002.safetensors"
printf '{}\n' >"${partial_sharded}/config.json"
cat >"${partial_sharded}/model.safetensors.index.json" <<'EOF'
{"weight_map":{"layer.a":"model-00001-of-00002.safetensors","layer.b":"model-00002-of-00002.safetensors"}}
EOF
printf 'shard1\n' >"${partial_sharded}/model-00001-of-00002.safetensors"
ln -sf /nonexistent "${partial_sharded}/model-00002-of-00002.safetensors"

expect_eq "dangling weight symlink is not cached" \
  "$(HF_HUB_CACHE="${cache_dir}" model_weights_cached mlx-community/Meta-Llama-3.1-8B-Instruct-4bit && echo yes || echo no)" \
  "no"
expect_eq "all index shards present is cached" \
  "$(HF_HUB_CACHE="${cache_dir}" model_weights_cached mlx-community/Qwen2.5-14B-Instruct-4bit && echo yes || echo no)" \
  "yes"
expect_eq "missing index shard is not cached" \
  "$(HF_HUB_CACHE="${cache_dir}" model_weights_cached mlx-community/Qwen2.5-32B-Instruct-4bit && echo yes || echo no)" \
  "no"
rm -rf "${empty_cache}" "${cache_dir}"

help_out="$("${ROOT}/scripts/detect-apple-silicon.sh" --help)"
expect_contains "detect help documents --list" "--list" "${help_out}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: model-list tests passed\n'
