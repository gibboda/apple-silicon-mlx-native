#!/usr/bin/env bash
# Image and video catalog fit labels (no sysctl, no download).
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

image_catalog_id_handled() {
  case "${1:-}" in
    flux2-klein-4b|z-image-turbo|schnell) return 0 ;;
    *) return 1 ;;
  esac
}

video_catalog_id_handled() {
  case "${1:-}" in
    "${MLX_VIDEO_WAN_MODEL_NAME}"|"${MLX_VIDEO_LTX_REPO}") return 0 ;;
    *) return 1 ;;
  esac
}

catalog_id_in_list() {
  local want="$1"
  shift
  local id
  for id in "$@"; do
    [[ "${id}" == "${want}" ]] && return 0
  done
  return 1
}

image_ids=()
video_ids=()
while IFS='|' read -r row_id _; do
  [[ -n "${row_id}" ]] || continue
  image_ids+=("${row_id}")
done < <(image_catalog_rows)
while IFS='|' read -r row_id _; do
  [[ -n "${row_id}" ]] || continue
  video_ids+=("${row_id}")
done < <(video_catalog_rows)

for catalog_id in "${image_ids[@]}"; do
  if image_catalog_id_handled "${catalog_id}"; then
    pass "image catalog id handled in image_list_fit (${catalog_id})"
  else
    fail "image catalog id handled in image_list_fit (${catalog_id})"
  fi
done
for catalog_id in "${video_ids[@]}"; do
  if video_catalog_id_handled "${catalog_id}"; then
    pass "video catalog id handled in video_list_fit (${catalog_id})"
  else
    fail "video catalog id handled in video_list_fit (${catalog_id})"
  fi
done

expect_eq "unhandled image id is poor" \
  "$(image_list_fit __not-in-catalog__ standard fast cooled)" \
  "poor"
expect_eq "unhandled video id is poor" \
  "$(video_list_fit __not-in-catalog__ standard fast cooled)" \
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
      image_default="$(image_list_default_id "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}" 0)"
      if catalog_id_in_list "${image_default}" "${image_ids[@]}"; then
        pass "matrix image default in catalog (${profile_label})"
      else
        fail "matrix image default in catalog (${profile_label}) (got '${image_default}')"
      fi
      expect_eq "matrix image recommended row is default (${profile_label})" \
        "$(image_list_fit "${image_default}" "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}" 0)" \
        "default"
      video_default="$(video_list_default_id "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}" 0 0)"
      if catalog_id_in_list "${video_default}" "${video_ids[@]}"; then
        pass "matrix video default in catalog (${profile_label})"
      else
        fail "matrix video default in catalog (${profile_label}) (got '${video_default}')"
      fi
      expect_eq "matrix video recommended row is default (${profile_label})" \
        "$(video_list_fit "${video_default}" "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}" 0 0)" \
        "default"
      image_defaults=0
      video_defaults=0
      for catalog_id in "${image_ids[@]}"; do
        fit="$(image_list_fit "${catalog_id}" "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}" 0)"
        case "${fit}" in
          default|fits|tight|poor) ;;
          *) fail "matrix image fit label valid (${profile_label} ${catalog_id}) (got '${fit}')" ;;
        esac
        [[ "${fit}" == "default" ]] && image_defaults=$((image_defaults + 1))
      done
      for catalog_id in "${video_ids[@]}"; do
        fit="$(video_list_fit "${catalog_id}" "${matrix_tier}" "${matrix_throughput}" "${matrix_thermal}" 0 24)"
        case "${fit}" in
          default|fits|tight|poor) ;;
          *) fail "matrix video fit label valid (${profile_label} ${catalog_id}) (got '${fit}')" ;;
        esac
        [[ "${fit}" == "default" ]] && video_defaults=$((video_defaults + 1))
      done
      expect_eq "matrix exactly one image default (${profile_label})" "${image_defaults}" "1"
      expect_eq "matrix exactly one video default (${profile_label})" "${video_defaults}" "1"
    done
  done
done
pass "matrix invariants over ${matrix_profiles} profiles"

expect_eq "8 GB image default is klein 4b" \
  "$(image_list_fit flux2-klein-4b constrained slow fanless)" "default"
expect_eq "8 GB z-image is poor" \
  "$(image_list_fit z-image-turbo constrained slow fanless)" "poor"
expect_eq "8 GB schnell is poor" \
  "$(image_list_fit schnell constrained slow fanless)" "poor"
expect_eq "16 GB slow image default stays klein" \
  "$(image_list_fit flux2-klein-4b standard moderate cooled)" "default"
expect_eq "16 GB slow z-image is tight" \
  "$(image_list_fit z-image-turbo standard moderate cooled)" "tight"
expect_eq "16 GB fast cooled image default stays klein" \
  "$(image_list_fit flux2-klein-4b standard fast cooled)" "default"
expect_eq "16 GB fast cooled z-image is tight" \
  "$(image_list_fit z-image-turbo standard fast cooled)" "tight"
expect_eq "16 GB fast cooled schnell is tight" \
  "$(image_list_fit schnell standard fast cooled)" "tight"
expect_eq "24 GB cooled image default is z-image" \
  "$(image_list_fit z-image-turbo high fast cooled)" "default"
expect_eq "24 GB cooled klein still fits" \
  "$(image_list_fit flux2-klein-4b high fast cooled)" "fits"
expect_eq "24 GB cooled schnell fits" \
  "$(image_list_fit schnell high fast cooled)" "fits"
expect_eq "fanless 24 GB image default stays klein" \
  "$(image_list_fit flux2-klein-4b high fast fanless)" "default"
expect_eq "fanless 24 GB z-image is tight" \
  "$(image_list_fit z-image-turbo high fast fanless)" "tight"
expect_eq "fanless workstation z-image fits" \
  "$(image_list_fit z-image-turbo workstation very_fast fanless)" "fits"
expect_eq "unknown throughput standard image stays klein" \
  "$(image_list_default_id standard unknown cooled)" "flux2-klein-4b"
expect_eq "unknown throughput high image is z-image" \
  "$(image_list_default_id high unknown cooled)" "z-image-turbo"

expect_eq "8 GB video default stays wan" \
  "$(video_list_fit "${MLX_VIDEO_WAN_MODEL_NAME}" constrained slow fanless)" "default"
expect_eq "8 GB LTX is poor" \
  "$(video_list_fit "${MLX_VIDEO_LTX_REPO}" constrained slow fanless)" "poor"
expect_eq "16 GB fast cooled video default stays wan" \
  "$(video_list_fit "${MLX_VIDEO_WAN_MODEL_NAME}" standard fast cooled)" "default"
expect_eq "16 GB fast cooled LTX is poor" \
  "$(video_list_fit "${MLX_VIDEO_LTX_REPO}" standard fast cooled)" "poor"
expect_eq "24 GB video default stays wan" \
  "$(video_list_fit "${MLX_VIDEO_WAN_MODEL_NAME}" high fast cooled 3 18)" "default"
expect_eq "24 GB LTX is poor" \
  "$(video_list_fit "${MLX_VIDEO_LTX_REPO}" high very_fast cooled 4 40)" "poor"
expect_eq "workstation cooled LTX is default" \
  "$(video_list_fit "${MLX_VIDEO_LTX_REPO}" workstation fast cooled)" "default"
expect_eq "workstation cooled wan fits" \
  "$(video_list_fit "${MLX_VIDEO_WAN_MODEL_NAME}" workstation fast cooled)" "fits"
expect_eq "fanless workstation video stays wan" \
  "$(video_list_fit "${MLX_VIDEO_WAN_MODEL_NAME}" workstation very_fast fanless)" "default"
expect_eq "fanless workstation LTX is tight" \
  "$(video_list_fit "${MLX_VIDEO_LTX_REPO}" workstation very_fast fanless)" "tight"
expect_eq "unknown throughput workstation video is LTX" \
  "$(video_list_default_id workstation unknown cooled)" "${MLX_VIDEO_LTX_REPO}"

empty_cache="$(mktemp -d "${TMPDIR:-/tmp}/mlx-media-list-empty.XXXXXX")"
empty_ws="$(mktemp -d "${TMPDIR:-/tmp}/mlx-media-list-ws.XXXXXX")"
air="$(
  HF_HUB_CACHE="${empty_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_image_list constrained slow fanless "Apple M1" 8 1 base constrained
)"
expect_contains "image list names the chip" "Apple chip:       Apple M1" "${air}"
expect_contains "image list default is klein" "Default image:    flux2-klein-4b" "${air}"
expect_contains "image list 8 GB size" "Size:             512x512" "${air}"
expect_contains "image list 8 GB quantize" "Quantize:         4-bit" "${air}"
expect_contains "image list 8 GB low ram" "Low RAM:          yes" "${air}"
expect_eq "printed 8 GB klein row is default" \
  "$(list_column flux2-klein-4b 1 "${air}")" "default"
expect_eq "printed 8 GB z-image row is poor" \
  "$(list_column z-image-turbo 1 "${air}")" "poor"
expect_eq "empty cache marks klein not cached" \
  "$(list_column flux2-klein-4b 2 "${air}")" "no"
expect_contains "image list tells how to generate" 'make image IMAGE_PROMPT="..."' "${air}"

m5="$(
  HF_HUB_CACHE="${empty_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_image_list standard fast cooled "Apple M5" 16 5 base standard
)"
expect_contains "16 GB fast image is 8-bit" "Quantize:         8-bit" "${m5}"
expect_contains "16 GB fast image is 768" "Size:             768x768" "${m5}"
expect_eq "printed 16 GB fast z-image is tight" \
  "$(list_column z-image-turbo 1 "${m5}")" "tight"

hi="$(
  HF_HUB_CACHE="${empty_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_image_list high fast cooled "Apple M3 Pro" 24 3 pro high
)"
expect_contains "24 GB image default is z-image" "Default image:    z-image-turbo" "${hi}"
expect_contains "24 GB image size is 1024" "Size:             1024x1024" "${hi}"
expect_contains "24 GB image steps are 9" "Steps:            9" "${hi}"
expect_contains "24 GB image low ram off" "Low RAM:          no" "${hi}"
expect_eq "printed 24 GB klein fits" "$(list_column flux2-klein-4b 1 "${hi}")" "fits"

policy_air="$(
  OVERRIDE_MEMORY_TIER=standard \
    HF_HUB_CACHE="${empty_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_image_list constrained slow fanless "Apple M1" 8 1 base constrained
)"
expect_contains "image override labels chip family policy" \
  "Chip family/SKU (policy):" "${policy_air}"

vid_air="$(
  HF_HUB_CACHE="${empty_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_video_list constrained slow fanless "Apple M1" 8 1 base constrained 8
)"
expect_contains "video list default is wan" "Default video:    ${MLX_VIDEO_WAN_MODEL_NAME}" "${vid_air}"
expect_contains "video list 8 GB frames" "Frames:           17" "${vid_air}"
expect_contains "video list 8 GB refuses" "Generate:         refused unless --force (UMT5 ~11 GB)" "${vid_air}"
expect_eq "printed 8 GB wan row is default" \
  "$(list_column "${MLX_VIDEO_WAN_MODEL_NAME}" 1 "${vid_air}")" "default"
expect_eq "printed 8 GB LTX row is poor" \
  "$(list_column "${MLX_VIDEO_LTX_REPO}" 1 "${vid_air}")" "poor"
expect_eq "empty workspace marks wan not cached" \
  "$(list_column "${MLX_VIDEO_WAN_MODEL_NAME}" 2 "${vid_air}")" "no"
expect_contains "video list tells how to generate" 'make video VIDEO_PROMPT="..."' "${vid_air}"
expect_contains "video list tells how to convert wan" "make prepare-video" "${vid_air}"

vid_max="$(
  HF_HUB_CACHE="${empty_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_video_list high very_fast cooled "Apple M4 Max" 32 4 max high 24
)"
expect_contains "high very_fast video is 49 frames" "Frames:           49" "${vid_max}"
expect_contains "high very_fast video generate allowed" "Generate:         allowed" "${vid_max}"
expect_eq "printed high LTX is poor" \
  "$(list_column "${MLX_VIDEO_LTX_REPO}" 1 "${vid_max}")" "poor"

vid_ws="$(
  HF_HUB_CACHE="${empty_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_video_list workstation fast cooled "Apple M3 Ultra" 64 3 ultra workstation 60
)"
expect_contains "workstation video default is LTX" "Default video:    ${MLX_VIDEO_LTX_REPO}" "${vid_ws}"
expect_contains "workstation video steps are pipeline default" "Steps:            pipeline default" "${vid_ws}"
expect_eq "printed workstation wan fits" \
  "$(list_column "${MLX_VIDEO_WAN_MODEL_NAME}" 1 "${vid_ws}")" "fits"

cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/mlx-media-list-cache.XXXXXX")"
klein="${cache_dir}/models--black-forest-labs--FLUX.2-klein-4B/snapshots/abc/transformer"
mkdir -p "${klein}"
printf '{}\n' >"${klein}/../model_index.json"
printf 'weights\n' >"${klein}/diffusion_model.safetensors"
expect_eq "diffusers klein snapshot is cached" \
  "$(HF_HUB_CACHE="${cache_dir}" media_repo_cached black-forest-labs/FLUX.2-klein-4B && echo yes || echo no)" \
  "yes"

dangling="${cache_dir}/models--Tongyi-MAI--Z-Image-Turbo/snapshots/abc"
mkdir -p "${dangling}"
printf '{}\n' >"${dangling}/model_index.json"
ln -sf /nonexistent "${dangling}/model.safetensors"
expect_eq "dangling image weight symlink is not cached" \
  "$(HF_HUB_CACHE="${cache_dir}" media_repo_cached Tongyi-MAI/Z-Image-Turbo && echo yes || echo no)" \
  "no"

partial="${cache_dir}/models--black-forest-labs--FLUX.1-schnell/snapshots/abc"
mkdir -p "${partial}" "${cache_dir}/models--black-forest-labs--FLUX.1-schnell/blobs"
printf '{}\n' >"${partial}/model_index.json"
printf 'weights\n' >"${partial}/flux1-schnell.safetensors"
printf 'partial\n' >"${cache_dir}/models--black-forest-labs--FLUX.1-schnell/blobs/x.incomplete"
expect_eq "incomplete image blob is not cached" \
  "$(HF_HUB_CACHE="${cache_dir}" media_repo_cached black-forest-labs/FLUX.1-schnell && echo yes || echo no)" \
  "no"

ltx="${cache_dir}/models--prince-canuma--LTX-2-distilled/snapshots/abc"
mkdir -p "${ltx}"
printf '{}\n' >"${ltx}/config.json"
printf 'weights\n' >"${ltx}/model.safetensors"
expect_eq "LTX mlx snapshot is cached" \
  "$(HF_HUB_CACHE="${cache_dir}" media_repo_cached "${MLX_VIDEO_LTX_REPO}" && echo yes || echo no)" \
  "yes"

partial_ltx_cache="$(mktemp -d "${TMPDIR:-/tmp}/mlx-media-list-ltx.XXXXXX")"
partial_ltx="${partial_ltx_cache}/models--prince-canuma--LTX-2-distilled/snapshots/partial"
mkdir -p "${partial_ltx}"
printf '{}\n' >"${partial_ltx}/config.json"
cat >"${partial_ltx}/model.safetensors.index.json" <<'EOF'
{"weight_map":{"layer.a":"model-00001-of-00002.safetensors","layer.b":"model-00002-of-00002.safetensors"}}
EOF
printf 'shard1\n' >"${partial_ltx}/model-00001-of-00002.safetensors"
expect_eq "LTX index missing a shard is not cached" \
  "$(HF_HUB_CACHE="${partial_ltx_cache}" media_repo_cached "${MLX_VIDEO_LTX_REPO}" && echo yes || echo no)" \
  "no"
ln -sf /nonexistent "${partial_ltx}/model-00002-of-00002.safetensors"
expect_eq "LTX index with a dangling shard is not cached" \
  "$(HF_HUB_CACHE="${partial_ltx_cache}" media_repo_cached "${MLX_VIDEO_LTX_REPO}" && echo yes || echo no)" \
  "no"
partial_video="$(
  HF_HUB_CACHE="${partial_ltx_cache}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_video_list constrained slow fanless "Apple M1" 8 1 base constrained 8
)"
expect_eq "printed partial LTX index is not cached" \
  "$(list_column "${MLX_VIDEO_LTX_REPO}" 2 "${partial_video}")" "no"
rm -rf "${partial_ltx_cache}"

cached_image="$(
  HF_HUB_CACHE="${cache_dir}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_image_list constrained slow fanless "Apple M1" 8 1 base constrained
)"
expect_eq "printed klein row is cached" \
  "$(list_column flux2-klein-4b 2 "${cached_image}")" "yes"
expect_eq "printed z-image dangling row is not cached" \
  "$(list_column z-image-turbo 2 "${cached_image}")" "no"
expect_eq "printed schnell incomplete row is not cached" \
  "$(list_column schnell 2 "${cached_image}")" "no"

wan_dir="${empty_ws}/models/video/${MLX_VIDEO_WAN_MODEL_NAME}"
mkdir -p "${wan_dir}"
printf '{}\n' >"${wan_dir}/config.json"
printf 'w\n' >"${wan_dir}/model.safetensors"
printf 'v\n' >"${wan_dir}/vae.safetensors"
expect_eq "wan dir missing t5 is not cached" \
  "$(MLX_WORKSPACE="${empty_ws}" video_catalog_cached "${MLX_VIDEO_WAN_MODEL_NAME}" local && echo yes || echo no)" \
  "no"
printf 't\n' >"${wan_dir}/t5_encoder.safetensors"
cached_video="$(
  HF_HUB_CACHE="${cache_dir}" MLX_WORKSPACE="${empty_ws}" \
    print_recommended_video_list constrained slow fanless "Apple M1" 8 1 base constrained 8
)"
expect_eq "printed wan row is cached" \
  "$(list_column "${MLX_VIDEO_WAN_MODEL_NAME}" 2 "${cached_video}")" "yes"
expect_eq "printed LTX row is cached" \
  "$(list_column "${MLX_VIDEO_LTX_REPO}" 2 "${cached_video}")" "yes"
rm -rf "${empty_cache}" "${empty_ws}" "${cache_dir}"

help_out="$("${DETECT}" --help)"
expect_contains "detect help documents --list-image" "--list-image" "${help_out}"
expect_contains "detect help documents --list-video" "--list-video" "${help_out}"

cli_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mlx-media-list-cli.XXXXXX")"
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

expect_fail "detect --list-image rejects Linux x86_64" \
  with_uname Linux x86_64 "${DETECT}" --list-image
expect_fail "detect --list-video rejects Linux x86_64" \
  with_uname Linux x86_64 "${DETECT}" --list-video

cli_image="$(
  with_uname Darwin arm64 \
    env MLX_SKIP_DEVICE_PROBE=1 \
      MLX_WORKSPACE="${cli_ws}" \
      HF_HUB_CACHE="${cli_hf}/hub" \
      OVERRIDE_MEMORY_TIER=high \
      OVERRIDE_CHIP_FAMILY=3 \
      OVERRIDE_CHIP_SKU=pro \
      OVERRIDE_GPU_CORES=18 \
      OVERRIDE_THERMAL_CLASS=cooled \
      PATH="${cli_bin}:${PATH}:/usr/bin:/bin" \
      "${DETECT}" --list-image 2>/dev/null
)"
expect_contains "cli image list prints fit table" $'fit\tcached\tmodel' "${cli_image}"
expect_eq "cli image list z-image row is default" \
  "$(list_column z-image-turbo 1 "${cli_image}")" "default"
expect_eq "cli image list klein row fits on high cooled" \
  "$(list_column flux2-klein-4b 1 "${cli_image}")" "fits"

cli_video="$(
  with_uname Darwin arm64 \
    env MLX_SKIP_DEVICE_PROBE=1 \
      MLX_WORKSPACE="${cli_ws}" \
      HF_HUB_CACHE="${cli_hf}/hub" \
      OVERRIDE_MEMORY_TIER=high \
      OVERRIDE_CHIP_FAMILY=3 \
      OVERRIDE_CHIP_SKU=pro \
      OVERRIDE_GPU_CORES=18 \
      OVERRIDE_THERMAL_CLASS=cooled \
      PATH="${cli_bin}:${PATH}:/usr/bin:/bin" \
      "${DETECT}" --list-video 2>/dev/null
)"
expect_contains "cli video list prints fit table" $'fit\tcached\tmodel' "${cli_video}"
expect_eq "cli video list wan row is default" \
  "$(list_column "${MLX_VIDEO_WAN_MODEL_NAME}" 1 "${cli_video}")" "default"
expect_eq "cli video list LTX row is poor on high" \
  "$(list_column "${MLX_VIDEO_LTX_REPO}" 1 "${cli_video}")" "poor"
expect_contains "cli video list allows generate on cooled high" "Generate:         allowed" "${cli_video}"
if [[ ! -f "${cli_ws}/config/models.env" ]]; then
  pass "cli media lists do not create models.env"
else
  fail "cli media lists do not create models.env (file exists)"
fi
rm -rf "${cli_tmp}"

if (( failures > 0 )); then
  printf 'FAIL: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'OK: media-list tests passed\n'
