#!/usr/bin/env bash
# Self-test for disk floors and pinned MLX package specs.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="${ROOT}/scripts/lib/common.sh"

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_eq() {
  local label="$1"
  local want="$2"
  local got="$3"
  if [[ "${got}" == "${want}" ]]; then
    pass "${label}"
  else
    fail "${label} (want ${want}, got ${got})"
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

floor_of() {
  local profile="$1"
  shift
  env "$@" bash -c "source \"${COMMON}\"; disk_floor_gib \"${profile}\""
}

status_of() {
  bash -c "source \"${COMMON}\"; disk_headroom_status \"$1\" \"$2\""
}

run_check() {
  local avail="$1"
  local profile="$2"
  shift 2
  env MLX_DISK_AVAIL_GIB="${avail}" "$@" bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom \"${profile}\""
}

expect_eq "media floor default" "4" "$(floor_of media-pip)"
expect_eq "image pip floor default" "8" "$(floor_of image-pip)"
expect_eq "video pip floor default" "8" "$(floor_of video-pip)"
expect_eq "image weights floor default" "12" "$(floor_of image-weights)"
expect_eq "video weights floor default" "20" "$(floor_of video-weights)"
expect_eq "wan floor default" "40" "$(floor_of wan-prepare)"
expect_eq "wan floor override" "7" "$(floor_of wan-prepare MLX_DISK_MIN_WAN_GIB=7)"
expect_fail "unknown disk profile" bash -c "source \"${COMMON}\"; disk_floor_gib nope"

expect_eq "status low" "low" "$(status_of 3 8)"
expect_eq "status equal is ok" "ok" "$(status_of 8 8)"
expect_eq "status above is ok" "ok" "$(status_of 41 40)"
expect_eq "status blank is unknown" "unknown" "$(status_of '' 8)"
expect_eq "status junk is unknown" "unknown" "$(status_of abc 8)"

ok_out="$(run_check 100 media-pip)"
expect_contains "enough disk warns nothing" "Disk headroom: 100 GiB free" "${ok_out}"

low_out="$(run_check 1 wan-prepare)"
expect_contains "low disk warns" "at least 40 GiB" "${low_out}"
expect_contains "low disk does not claim caches were deleted" "not deleted automatically" "${low_out}"

skip_out="$(run_check 1 wan-prepare MLX_SKIP_DISK_CHECK=1)"
expect_contains "skip disk check" "Disk headroom check skipped" "${skip_out}"

expect_fail "enforce aborts when low" run_check 1 wan-prepare MLX_DISK_ENFORCE=1
enforce_out="$(run_check 1 media-pip MLX_DISK_ENFORCE=1 MLX_DISK_MIN_MEDIA_GIB=9 2>&1 || true)"
expect_contains "enforce names the floor" "at least 9 GiB" "${enforce_out}"

pins="$(env bash -c "source \"${COMMON}\"; printf '%s\n' \"\${MLX_CORE_PACKAGES[@]}\" \"\${MLX_MEDIA_PACKAGES[@]}\"")"
expect_contains "mlx pin" "mlx==0.32.2" "${pins}"
expect_contains "mlx-lm pin" "mlx-lm==0.31.3" "${pins}"
expect_contains "mlx-audio pin" "mlx-audio==0.5.5" "${pins}"

overridden="$(MLX_PACKAGE=mlx MLX_LM_PACKAGE=mlx-lm MLX_AUDIO_PACKAGE=mlx-audio bash -c "source \"${COMMON}\"; printf '%s\n' \"\${MLX_CORE_PACKAGES[@]}\" \"\${MLX_MEDIA_PACKAGES[@]}\"")"
expect_eq "unpinned override" "$(printf '%s\n' mlx mlx-lm mlx-audio)" "${overridden}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
BIN="${TMP}/bin"
CACHE="${TMP}/hf/hub"
WS="${TMP}/ws"
mkdir -p "${BIN}" "${CACHE}" "${WS}"

cat >"${BIN}/sysctl" <<'EOF'
#!/bin/sh
if [ "$1" = "-n" ]; then
  case "$2" in
    hw.memsize) printf '%s\n' 17179869184 ;;
    hw.ncpu) printf '%s\n' 8 ;;
    hw.model) printf '%s\n' MacBookPro18,1 ;;
    machdep.cpu.brand_string) printf '%s\n' 'Apple M3 Pro' ;;
    *) printf '\n' ;;
  esac
fi
exit 0
EOF
cat >"${BIN}/sw_vers" <<'EOF'
#!/bin/sh
printf '%s\n' 15.0
EOF
cat >"${BIN}/df" <<'EOF'
#!/bin/sh
target=""
for arg in "$@"; do
  case "$arg" in
    -*) ;;
    *) target="$arg" ;;
  esac
done
printf '%s\n' "Filesystem 1G-blocks Used Available"
case "$target" in
  *hub*|*huggingface*)
    printf '%s\n' "/dev/disk2 100 90 2"
    ;;
  *)
    printf '%s\n' "/dev/disk1 900 100 800"
    ;;
esac
EOF
chmod +x "${BIN}/sysctl" "${BIN}/sw_vers" "${BIN}/df"

detect_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_DISK_AVAIL_GIB=1 \
    MLX_DISK_ENFORCE=1 \
    MLX_SKIP_DEVICE_PROBE=1 \
    bash -c "source \"${COMMON}\"; export_detect_env; printf 'fact=%s\n' \"\${MLX_DISK_AVAIL_GIB}\"; warn_or_die_disk_headroom wan-prepare" \
    2>&1 || true
)"
expect_contains "detect still records workspace df" "fact=800" "${detect_out}"
expect_contains "enforce after detect uses the caller override" "Only 1 GiB free" "${detect_out}"
expect_contains "override is named in the enforce error" "MLX_DISK_AVAIL_GIB override" "${detect_out}"

nosysctl_out="$(
  MLX_DISK_AVAIL_GIB=1 \
    MLX_DISK_ENFORCE=1 \
    bash -c "source \"${COMMON}\"; load_runtime_profile_without_sysctl; printf 'fact=%s\n' \"\${MLX_DISK_AVAIL_GIB}\"; warn_or_die_disk_headroom media-pip" \
    2>&1 || true
)"
expect_contains "no-sysctl detect clears the reported fact" $'fact=\n' "${nosysctl_out}"
expect_contains "no-sysctl detect still enforces the override" "Only 1 GiB free" "${nosysctl_out}"

image_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_WORKSPACE="${WS}" \
    HF_HUB_CACHE="${CACHE}" \
    bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom image-weights" \
    2>&1 || true
)"
expect_contains "image weights measure the hub cache" "Only 2 GiB free" "${image_out}"
expect_contains "image weights name the hub path" "${CACHE}" "${image_out}"

media_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_WORKSPACE="${WS}" \
    HF_HUB_CACHE="${CACHE}" \
    bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom media-pip" \
    2>&1 || true
)"
expect_contains "pip install measures the workspace" "800 GiB free" "${media_out}"
expect_contains "pip install names the workspace" "${WS}" "${media_out}"

wan_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_WORKSPACE="${WS}" \
    HF_HUB_CACHE="${CACHE}" \
    bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom wan-prepare" \
    2>&1 || true
)"
expect_contains "wan prepare uses the tighter hub volume" "Only 2 GiB free" "${wan_out}"
expect_contains "wan prepare names the hub path" "${CACHE}" "${wan_out}"

if (( failures > 0 )); then
  printf 'FAIL: %s disk/pin check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: disk headroom and package pins\n'
