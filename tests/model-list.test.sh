#!/usr/bin/env bash
# Catalog fit labels for make list (no sysctl, no download).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="${ROOT}/scripts/detect-apple-silicon.sh"
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

expect_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${label} (expected non-zero exit)"
  else
    pass "${label}"
  fi
}

list_column() {
  local model="$1"
  local column="$2"
  local text="$3"
  printf '%s\n' "${text}" | awk -F '\t' -v id="${model}" -v col="${column}" '$3 == id { print $col; exit }'
}

model_list_catalog_id_handled() {
  case "${1:-}" in
    mlx-community/Llama-3.2-3B-Instruct-4bit|\
    mlx-community/Llama-3.2-1B-Instruct-4bit|\
    mlx-community/Phi-3.5-mini-instruct-4bit|\
    mlx-community/Qwen2.5-3B-Instruct-4bit|\
    mlx-community/Mistral-7B-Instruct-v0.3-4bit|\
    mlx-community/Meta-Llama-3.1-8B-Instruct-4bit|\
    mlx-community/Qwen2.5-14B-Instruct-4bit|\
    mlx-community/Qwen2.5-32B-Instruct-4bit)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

catalog_id_in_list() {
  local want="$1"
  local id
  for id in "${catalog_ids[@]}"; do
    [[ "${id}" == "${want}" ]] && return 0
  done
  return 1
}

catalog_ids=()
while IFS='|' read -r row_id _ _; do
  [[ -n "${row_id}" ]] || continue
  catalog_ids+=("${row_id}")
done < <(model_catalog_rows)

for catalog_id in "${catalog_ids[@]}"; do
  if model_list_catalog_id_handled "${catalog_id}"; then
    pass "catalog id handled in model_list_fit (${catalog_id})"
  else
    fail "catalog id handled in model_list_fit (${catalog_id})"
  fi
done
expect_eq "unhandled catalog id falls through to poor" \
  "$(model_list_fit mlx-community/__not-in-catalog__ standard fast cooled)" \
  "poor"

matrix_tiers=(constrained standard high workstation large)
matrix_throughputs=(slow moderate fast very_fast extreme unknown)
matrix_thermals=(fanless cooled "")
matrix_profiles=0
for matrix_tier in "${matrix_tiers[@]}"; do
  for matrix_throughput in "${matrix_throughputs[@]}"; do
    for matrix_thermal in "${matrix_thermals[@]}"; do
      matrix_profiles=$((matrix_profiles + 1))
      profile_label="tier=${matrix_tier} throughput=${matrix_throughput:-empty} thermal=${matrix_thermal:-empty}"
      default_id="$(recommended_model_for_profile "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}" 0)"
      if catalog_id_in_list "${default_id}"; then
        pass "matrix recommended model in catalog (${profile_label})"
      else
        fail "matrix recommended model in catalog (${profile_label}) (got '${default_id}')"
      fi
      default_fit="$(model_list_fit "${default_id}" "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}")"
      expect_eq "matrix recommended row is default (${profile_label})" \
        "${default_fit}" "default"
      default_count=0
      for catalog_id in "${catalog_ids[@]}"; do
        fit="$(model_list_fit "${catalog_id}" "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}")"
        case "${fit}" in
          default|fits|tight|poor) ;;
          *)
            fail "matrix fit label valid (${profile_label} ${catalog_id}) (got '${fit}')"
            ;;
        esac
        if [[ "${fit}" == "default" ]]; then
          default_count=$((default_count + 1))
        fi
      done
      expect_eq "matrix exactly one default (${profile_label})" \
        "${default_count}" "1"
    done
  done
done
pass "matrix invariants over ${matrix_profiles} profiles"

expect_eq "unknown throughput standard default is 3B" \
  "$(recommended_model_for_profile standard unknown cooled 0)" \
  "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "unknown throughput standard 7B is tight" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit standard unknown cooled)" \
  "tight"
expect_eq "16 GB fanless fast default stays 3B" \
  "$(recommended_model_for_profile standard fast fanless 0)" \
  "mlx-community/Llama-3.2-3B-Instruct-4bit"
expect_eq "16 GB fanless fast 7B is tight" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit standard fast fanless)" \
  "tight"

for air_model in MacBookAir10,1 Mac14,2 Mac14,15 Mac15,12 Mac15,13 Mac16,12 Mac16,13 Mac17,3 Mac17,4; do
  air_thermal="$(classify_thermal_class "${air_model}")"
  expect_eq "${air_model} list thermal is fanless" "${air_thermal}" "fanless"
  expect_eq "${air_model} list default stays 3B" \
    "$(model_list_fit mlx-community/Llama-3.2-3B-Instruct-4bit standard fast "${air_thermal}")" \
    "default"
  expect_eq "${air_model} list 7B is tight" \
    "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit standard fast "${air_thermal}")" \
    "tight"
done
expect_eq "Mac14,7 list thermal is cooled" "$(classify_thermal_class Mac14,7)" "cooled"
expect_eq "Mac14,7 list 7B is the cooled fast default" \
  "$(model_list_fit mlx-community/Mistral-7B-Instruct-v0.3-4bit standard fast cooled)" \
  "default"

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
policy_air="$(
  OVERRIDE_MEMORY_TIER=standard \
    HF_HUB_CACHE="${empty_cache}" \
    print_recommended_model_list constrained slow fanless "Apple M1" 8 '' 1 base constrained
)"
expect_contains "override labels chip family policy" \
  "Chip family/SKU (policy):" "${policy_air}"
expect_contains "list composes default context not models.env" \
  "Default context:  2048" \
  "$(MLX_RECOMMENDED_CONTEXT=8192 HF_HUB_CACHE="${empty_cache}" \
    print_recommended_model_list constrained slow fanless "Apple M1" 8 '' 1 base constrained)"
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

help_out="$("${DETECT}" --help)"
expect_contains "detect help documents --list" "--list" "${help_out}"

cli_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mlx-list-cli.XXXXXX")"
cli_bin="${cli_tmp}/bin"
cli_ws="${cli_tmp}/ws"
cli_hf="${cli_tmp}/hf"
mkdir -p "${cli_bin}" "${cli_ws}" "${cli_hf}/hub"
real_uname="$(command -v uname)"
cat >"${cli_bin}/uname" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  -m) printf '%s\\n' "\${FAKE_UNAME_M:-arm64}" ;;
  -s) printf '%s\\n' "\${FAKE_UNAME_S:-Darwin}" ;;
  *) exec "${real_uname}" "\$@" ;;
esac
EOF
chmod +x "${cli_bin}/uname"

with_uname() {
  local kernel="$1"
  local arch="$2"
  shift 2
  FAKE_UNAME_S="${kernel}" FAKE_UNAME_M="${arch}" PATH="${cli_bin}:${PATH}" "$@"
}

cat >"${cli_bin}/sysctl" <<'EOF'
#!/bin/sh
if [ "$1" = "-n" ]; then
  case "$2" in
    hw.memsize) printf '%s\n' 8589934592 ;;
    hw.ncpu) printf '%s\n' 8 ;;
    hw.model) printf '%s\n' MacBookAir10,1 ;;
    machdep.cpu.brand_string) printf '%s\n' 'Apple M1' ;;
    *) printf '\n' ;;
  esac
fi
exit 0
EOF
cat >"${cli_bin}/sw_vers" <<'EOF'
#!/bin/sh
printf '%s\n' 15.0
EOF
cat >"${cli_bin}/df" <<'EOF'
#!/bin/sh
printf '%s\n' "Filesystem 1G-blocks Used Available"
printf '%s\n' "/dev/disk1 900 100 800"
EOF
chmod +x "${cli_bin}/sysctl" "${cli_bin}/sw_vers" "${cli_bin}/df"

expect_fail "detect --list rejects Linux x86_64" \
  with_uname Linux x86_64 "${DETECT}" --list

cli_list_out="$(
  with_uname Darwin arm64 \
    env MLX_SKIP_DEVICE_PROBE=1 \
      MLX_WORKSPACE="${cli_ws}" \
      HF_HUB_CACHE="${cli_hf}/hub" \
      OVERRIDE_MEMORY_TIER=standard \
      PATH="${cli_bin}:${PATH}:/usr/bin:/bin" \
      "${DETECT}" --list 2>/dev/null
)"
expect_contains "cli list prints fit table" $'fit\tcached\tmodel' "${cli_list_out}"
expect_eq "cli list 3B row is default" \
  "$(list_column mlx-community/Llama-3.2-3B-Instruct-4bit 1 "${cli_list_out}")" \
  "default"
expect_eq "cli list 7B row is tight with override standard" \
  "$(list_column mlx-community/Mistral-7B-Instruct-v0.3-4bit 1 "${cli_list_out}")" \
  "tight"
expect_eq "cli list 14B row is poor" \
  "$(list_column mlx-community/Qwen2.5-14B-Instruct-4bit 1 "${cli_list_out}")" \
  "poor"
if [[ ! -f "${cli_ws}/config/models.env" ]]; then
  pass "cli list does not create models.env"
else
  fail "cli list does not create models.env (file exists)"
fi
rm -rf "${cli_tmp}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: model-list tests passed\n'
