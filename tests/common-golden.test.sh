#!/usr/bin/env bash
# Byte-stable golden output for detect/list and wrapper --dump-plan (issue #82).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN="${ROOT}/tests/fixtures/common-golden"
DETECT="${ROOT}/scripts/detect-apple-silicon.sh"
TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"
# shellcheck source=tests/lib/fake-darwin.sh
source "${TEST_LIB}/fake-darwin.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
WS="${TMP}/ws"
VENV="${WS}/.venv"
mkdir -p "${WS}/.venv/bin" "${WS}/outputs/images" "${WS}/models/video/wan21-t2v-1.3b-q4"
touch "${WS}/models/video/wan21-t2v-1.3b-q4/config.json" \
  "${WS}/models/video/wan21-t2v-1.3b-q4/model.safetensors" \
  "${WS}/models/video/wan21-t2v-1.3b-q4/t5_encoder.safetensors" \
  "${WS}/models/video/wan21-t2v-1.3b-q4/vae.safetensors"
cp "${TEST_LIB}/fake_venv_python.py" "${VENV}/bin/python3"
chmod +x "${VENV}/bin/python3"
ln -sf python3 "${VENV}/bin/python"
for cli in mflux-generate-flux2 mflux-generate-z-image-turbo; do
  printf '#!/bin/sh\nexit 0\n' >"${VENV}/bin/${cli}"
  chmod +x "${VENV}/bin/${cli}"
done

fake_darwin_install "${TMP}/darwin-stub" 17179869184
PATH="$(fake_darwin_path)"
export PATH
export MLX_WORKSPACE="${WS}" MLX_VENV="${VENV}" MLX_SKIP_DEVICE_PROBE=1 MLX_DISK_AVAIL_GIB=800

normalize_volatile() {
  sed \
    -e 's/^MLX_PYTHON_VERSION_DETECTED=.*/MLX_PYTHON_VERSION_DETECTED=<PYTHON>/' \
    -e 's|^MLX_WORKSPACE=.*|MLX_WORKSPACE=<WORKSPACE>|' \
    -e 's/"python_detected": "[^"]*"/"python_detected": "<PYTHON>"/' \
    -e 's/"workspace": "[^"]*"/"workspace": "<WORKSPACE>"/'
}

compare_golden() {
  local name="$1"
  local got="$2"
  local want="${GOLDEN}/${name}"
  local norm_kind="${3:-plain}"
  if [[ ! -f "${want}" ]]; then
    fail "missing golden fixture ${name}"
    return
  fi
  if [[ "${norm_kind}" == "detect" ]]; then
    got="$(printf '%s\n' "${got}" | normalize_volatile)"
  fi
  if diff -u "${want}" <(printf '%s\n' "${got}") >/dev/null 2>&1; then
    pass "golden ${name}"
  else
    fail "golden drift ${name}"
    diff -u "${want}" <(printf '%s\n' "${got}") | head -40 || true
  fi
}

run_fixture() {
  local slug="$1"
  shift
  eval "export $*"
  compare_golden "${slug}-detect-env.txt" "$("${DETECT}" --env 2>/dev/null || true)" detect
  compare_golden "${slug}-detect-json.txt" "$("${DETECT}" --json 2>/dev/null || true)" detect
  compare_golden "${slug}-list.txt" "$("${DETECT}" --list 2>/dev/null || true)"
  compare_golden "${slug}-list-image.txt" "$("${DETECT}" --list-image 2>/dev/null || true)"
  compare_golden "${slug}-list-video.txt" "$("${DETECT}" --list-video 2>/dev/null || true)"
  compare_golden "${slug}-text-dump-plan.txt" \
    "$("${ROOT}/scripts/generate-mlx-text.sh" --dump-plan --prompt x 2>/dev/null || true)"
  compare_golden "${slug}-image-dump-plan.txt" \
    "$("${ROOT}/scripts/generate-mlx-image.sh" --dump-plan --prompt x 2>/dev/null || true)"
  compare_golden "${slug}-video-dump-plan.txt" \
    "$("${ROOT}/scripts/generate-mlx-video.sh" --dump-plan --prompt x 2>/dev/null \
      | sed 's|^model_dir=.*|model_dir=<WORKSPACE>/models/video/wan21-t2v-1.3b-q4|' || true)"
}

run_fixture constrained_fanless \
  "OVERRIDE_MEMORY_TIER=constrained OVERRIDE_THERMAL_CLASS=fanless OVERRIDE_CHIP_FAMILY=1 OVERRIDE_GPU_CORES=8"
run_fixture standard_fast_cooled \
  "OVERRIDE_MEMORY_TIER=standard OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_CHIP_FAMILY=5 OVERRIDE_GPU_CORES=10"
run_fixture high_very_fast \
  "OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_CHIP_FAMILY=5 OVERRIDE_GPU_CORES=24"
run_fixture workstation_cooled \
  "OVERRIDE_MEMORY_TIER=workstation OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_CHIP_FAMILY=3 OVERRIDE_GPU_CORES=18"

echo "OK: common-golden self-test passed"
