#!/usr/bin/env bash
# Self-test for disk floors and pinned MLX and packaging-tool specs.
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
expect_eq "image generate floor default" "4" "$(floor_of image-generate)"
expect_eq "image generate floor override" "2" "$(floor_of image-generate MLX_DISK_MIN_IMAGE_GENERATE_GIB=2)"
expect_eq "video weights floor default" "20" "$(floor_of video-weights)"
expect_eq "wan generate floor default" "4" "$(floor_of wan-generate)"
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

packaging="$(env bash -c "source \"${COMMON}\"; printf '%s\n' \"\${MLX_PACKAGING_PACKAGES[@]}\"")"
expect_eq "packaging pins" "$(printf '%s\n' 'pip==26.2.1' 'setuptools==84.0.0' 'wheel==0.48.0' 'packaging==26.3')" "${packaging}"

packaging_override="$(MLX_PIP_PACKAGE=pip MLX_SETUPTOOLS_PACKAGE=setuptools MLX_WHEEL_PACKAGE=wheel MLX_PACKAGING_LIB_PACKAGE=packaging bash -c "source \"${COMMON}\"; printf '%s\n' \"\${MLX_PACKAGING_PACKAGES[@]}\"")"
expect_eq "packaging override" "$(printf '%s\n' pip setuptools wheel packaging)" "${packaging_override}"

BUILD_CONSTRAINT_WS="$(mktemp -d)"
constraint_out="$(MLX_WORKSPACE="${BUILD_CONSTRAINT_WS}" bash -c "source \"${COMMON}\"; export_pip_build_constraint; printf '%s\n' \"\${PIP_BUILD_CONSTRAINT}\"; cat \"\${PIP_BUILD_CONSTRAINT}\"")"
rm -rf "${BUILD_CONSTRAINT_WS}"
expect_eq "PIP_BUILD_CONSTRAINT file" "$(printf '%s\n' "${BUILD_CONSTRAINT_WS}/.mlx-pip-build-constraint.txt" 'pip==26.2.1' 'setuptools==84.0.0' 'wheel==0.48.0' 'packaging==26.3')" "${constraint_out}"

for installer in \
  "${ROOT}/scripts/initial-build-mlx-native-media.sh" \
  "${ROOT}/scripts/rebuild-mlx-native-media.sh" \
  "${ROOT}/scripts/install-mlx-image.sh" \
  "${ROOT}/scripts/install-mlx-video.sh"
do
  if grep -q 'install_packaging_tools' "${installer}"; then
    pass "shared packaging install in $(basename "${installer}")"
  else
    fail "shared packaging install missing in $(basename "${installer}")"
  fi
done

unpinned_hits="$(grep -E -n 'pip install[[:space:]].*(--upgrade|-U).*(^|[^[:alnum:]_])(pip|setuptools|wheel)([^[:alnum:]_]|$)' \
  "${ROOT}/Makefile" "${ROOT}/scripts/"*.sh "${ROOT}/scripts/lib/"*.sh || true)"
expect_eq "no unpinned packaging upgrade" "" "${unpinned_hits}"

INSTALL_WS="$(mktemp -d)"
mkdir -p "${INSTALL_WS}/.venv/bin"
cat >"${INSTALL_WS}/.venv/bin/python" <<EOF
#!/bin/sh
if [ "\$1" = "-m" ] && [ "\$2" = "pip" ]; then
  printf '%s' "\$1" >> "${INSTALL_WS}/pip-args"
  shift
  for arg in "\$@"; do
    printf ' %s' "\$arg" >> "${INSTALL_WS}/pip-args"
  done
  printf '\\n' >> "${INSTALL_WS}/pip-args"
  exit 0
fi
printf '%s\\n' 'pip 26.2.1' 'setuptools 84.0.0' 'wheel 0.48.0' 'packaging 26.3'
EOF
chmod +x "${INSTALL_WS}/.venv/bin/python"
install_out="$(MLX_WORKSPACE="${INSTALL_WS}" MLX_VENV="${INSTALL_WS}/.venv" bash -c "source \"${COMMON}\"; install_packaging_tools")"
expect_eq "packaging install argv" "-m pip install --disable-pip-version-check --upgrade pip==26.2.1 setuptools==84.0.0 wheel==0.48.0 packaging==26.3" "$(cat "${INSTALL_WS}/pip-args")"
expect_contains "installed pip is OK" "OK: Packaging tool pip 26.2.1" "${install_out}"
expect_contains "installed setuptools is OK" "OK: Packaging tool setuptools 84.0.0" "${install_out}"
expect_contains "installed wheel is OK" "OK: Packaging tool wheel 0.48.0" "${install_out}"
expect_contains "installed packaging is OK" "OK: Packaging tool packaging 26.3" "${install_out}"
if [[ "${install_out}" == *"WARN: Packaging tool pip"* ]]; then
  fail "matching pip pin must not warn"
else
  pass "matching pip pin does not warn"
fi

rm -f "${INSTALL_WS}/pip-args"
override_out="$(MLX_WORKSPACE="${INSTALL_WS}" MLX_VENV="${INSTALL_WS}/.venv" MLX_PIP_PACKAGE='pip==1' MLX_SETUPTOOLS_PACKAGE='setuptools==2' MLX_WHEEL_PACKAGE='wheel==3' MLX_PACKAGING_LIB_PACKAGE='packaging==4' bash -c "source \"${COMMON}\"; install_packaging_tools")"
expect_eq "packaging install override argv" "-m pip install --disable-pip-version-check --upgrade pip==1 setuptools==2 wheel==3 packaging==4" "$(cat "${INSTALL_WS}/pip-args")"
expect_contains "override pip warns" "WARN: Packaging tool pip 26.2.1 (pin pip==1)" "${override_out}"

wild_out="$(MLX_WORKSPACE="${INSTALL_WS}" MLX_VENV="${INSTALL_WS}/.venv" MLX_SETUPTOOLS_PACKAGE='setuptools==84.*' MLX_WHEEL_PACKAGE='wheel===0.48.0' bash -c "source \"${COMMON}\"; report_packaging_tools")"
expect_contains "wildcard spec is info" "INFO: Packaging tool setuptools 84.0.0 (spec setuptools==84.*)" "${wild_out}"
expect_contains "triple-equal spec is info" "INFO: Packaging tool wheel 0.48.0 (spec wheel===0.48.0)" "${wild_out}"
if [[ "${wild_out}" == *"WARN: Packaging tool setuptools"* || "${wild_out}" == *"WARN: Packaging tool wheel"* ]]; then
  fail "non-exact specs must not warn"
else
  pass "non-exact specs do not warn"
fi
rm -rf "${INSTALL_WS}"

FAKE_VENV="$(mktemp -d)"
mkdir -p "${FAKE_VENV}/bin"
cat >"${FAKE_VENV}/bin/python" <<'EOF'
#!/bin/sh
printf '%s\n' 'pip 26.2.1' 'setuptools 84.0.0' 'wheel 0.47.0' 'packaging 26.3'
EOF
chmod +x "${FAKE_VENV}/bin/python"
packaging_report="$(MLX_VENV="${FAKE_VENV}" bash -c "source \"${COMMON}\"; report_packaging_tools")"
rm -rf "${FAKE_VENV}"
expect_contains "matching pip pin" "OK: Packaging tool pip 26.2.1" "${packaging_report}"
expect_contains "matching setuptools pin" "OK: Packaging tool setuptools 84.0.0" "${packaging_report}"
expect_contains "matching packaging pin" "OK: Packaging tool packaging 26.3" "${packaging_report}"
expect_contains "wheel pin mismatch" "WARN: Packaging tool wheel 0.47.0 (pin wheel==0.48.0)" "${packaging_report}"
if [[ "${packaging_report}" == *"WARN: Packaging tool pip"* ]]; then
  fail "OK pip line must not also count as a warning"
else
  pass "OK pip line is not a warning"
fi

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
  *lowvol*)
    printf '%s\n' "/dev/disk3 10 7 3"
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

image_gen_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_WORKSPACE="${WS}" \
    HF_HUB_CACHE="${CACHE}" \
    bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom image-generate" \
    2>&1 || true
)"
expect_contains "local image generate ignores a full hub cache" "800 GiB free" "${image_gen_out}"
expect_contains "local image generate names the workspace" "${WS}" "${image_gen_out}"
if [[ "${image_gen_out}" == *"${CACHE}"* ]]; then
  fail "local image generate named the hub cache"
else
  pass "local image generate does not name the hub cache"
fi

model_is_local() {
  local model="$1"
  if bash -c 'source "$1"; image_model_is_local "$2"' _ "${COMMON}" "${model}"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}
disk_profile_for() {
  local model="$1"
  bash -c 'source "$1"; image_generate_disk_profile "$2"' _ "${COMMON}" "${model}"
}
expect_eq "preset is not a local checkpoint" "no" "$(model_is_local flux2-klein-4b)"
expect_eq "hf repo is not a local checkpoint" "no" "$(model_is_local org/does-not-exist-mlx-disk-test)"
expect_eq "absolute path is a local checkpoint" "yes" "$(model_is_local /var/empty/mlx-ckpt)"
expect_eq "dot path is a local checkpoint" "yes" "$(model_is_local ./models/flux)"
expect_eq "parent path is a local checkpoint" "yes" "$(model_is_local ../models/flux)"
expect_eq "tilde path is a local checkpoint" "yes" "$(model_is_local ~/models/flux)"
mkdir -p "${TMP}/relckpt"
expect_eq "existing relative dir is a local checkpoint" "yes" "$(cd "${TMP}" && model_is_local relckpt)"
expect_eq "preset uses image-weights" "image-weights" "$(disk_profile_for z-image-turbo)"
expect_eq "local path uses image-generate" "image-generate" "$(disk_profile_for "${TMP}/relckpt")"

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

ltx_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_WORKSPACE="${WS}" \
    HF_HUB_CACHE="${CACHE}" \
    bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom video-weights" \
    2>&1 || true
)"
expect_contains "LTX weights still measure the hub cache" "Only 2 GiB free" "${ltx_out}"

wan_gen_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_WORKSPACE="${WS}" \
    HF_HUB_CACHE="${CACHE}" \
    bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom wan-generate" \
    2>&1 || true
)"
expect_contains "Wan generate ignores a full hub cache" "800 GiB free" "${wan_gen_out}"
expect_contains "Wan generate names the workspace" "${WS}" "${wan_gen_out}"
if [[ "${wan_gen_out}" == *"${CACHE}"* ]]; then
  fail "Wan generate named the hub cache"
else
  pass "Wan generate does not name the hub cache"
fi

LOW="${TMP}/lowvol/wan"
mkdir -p "${LOW}"
wan_model_out="$(
  PATH="${BIN}:/usr/bin:/bin" \
    MLX_WORKSPACE="${WS}" \
    HF_HUB_CACHE="${CACHE}" \
    MLX_WAN_GENERATE_DIR="${LOW}" \
    bash -c "source \"${COMMON}\"; warn_or_die_disk_headroom wan-generate" \
    2>&1 || true
)"
expect_contains "Wan generate uses the tighter model volume" "Only 3 GiB free" "${wan_model_out}"
expect_contains "Wan generate names the model directory" "${LOW}" "${wan_model_out}"

if (( failures > 0 )); then
  printf 'FAIL: %s disk/pin check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: disk headroom and package pins\n'
