#!/usr/bin/env bash
# Record and assert exact argv launched by image/video/text/serve wrappers.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"

# shellcheck source=tests/lib/argv.sh
source "${TEST_LIB}/argv.sh"
# shellcheck source=tests/lib/fake-darwin.sh
source "${TEST_LIB}/fake-darwin.sh"

GENERATE_IMAGE="${ROOT}/scripts/generate-mlx-image.sh"
GENERATE_VIDEO="${ROOT}/scripts/generate-mlx-video.sh"
GENERATE_TEXT="${ROOT}/scripts/generate-mlx-text.sh"
SERVE="${ROOT}/scripts/serve-mlx.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

WS="${TMP}/ws"
VENV="${WS}/.venv"
RECORD="${TMP}/record.argv"
mkdir -p "${WS}/outputs/images" "${WS}/outputs/videos" "${WS}/models/video/wan21-t2v-1.3b-q4" \
  "${VENV}/bin"

fake_darwin_install "${TMP}/darwin-stub" 17179869184
STUB_PATH="$(fake_darwin_path)"

install_mflux_stub() {
  local cli_name="$1"
  cat >"${VENV}/bin/${cli_name}" <<EOF
#!/usr/bin/env bash
printf '%s\\0' "\$0" "\$@" >"${RECORD}"
exit 0
EOF
  chmod +x "${VENV}/bin/${cli_name}"
}

install_fake_python() {
  cp "${TEST_LIB}/fake_venv_python.py" "${VENV}/bin/python3"
  chmod +x "${VENV}/bin/python3"
  ln -sf python3 "${VENV}/bin/python"
}

touch "${WS}/models/video/wan21-t2v-1.3b-q4/config.json" \
  "${WS}/models/video/wan21-t2v-1.3b-q4/model.safetensors" \
  "${WS}/models/video/wan21-t2v-1.3b-q4/t5_encoder.safetensors" \
  "${WS}/models/video/wan21-t2v-1.3b-q4/vae.safetensors"

install_fake_python

run_wrapper() {
  rm -f "${RECORD}"
  env MLX_WORKSPACE="${WS}" MLX_VENV="${VENV}" MLX_SKIP_DISK_CHECK=1 \
    MLX_TEST_RECORD_ARGV="${RECORD}" \
    PATH="${STUB_PATH}" \
    "$@"
}

IMG_OUT="${WS}/outputs/images/argv-test.png"
VID_OUT="${WS}/outputs/videos/argv-test.mp4"

# --- image: default (constrained cooled), high tier override, fanless, passthrough ---

install_mflux_stub "mflux-generate-flux2"
run_wrapper env OVERRIDE_MEMORY_TIER=constrained OVERRIDE_THERMAL_CLASS=cooled \
  "${GENERATE_IMAGE}" --prompt "argv-default" --output "${IMG_OUT}"
expect_argv_eq "image default argv" "${RECORD}" \
  "${VENV}/bin/mflux-generate-flux2" \
  --prompt argv-default \
  --width 512 --height 512 --steps 4 --quantize 4 \
  --output "${IMG_OUT}" \
  --model flux2-klein-4b \
  --low-ram \
  --vae-tiling

install_mflux_stub "mflux-generate-z-image-turbo"
run_wrapper env OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled \
  "${GENERATE_IMAGE}" --prompt "argv-high" --output "${IMG_OUT}"
expect_argv_eq "image high tier override argv" "${RECORD}" \
  "${VENV}/bin/mflux-generate-z-image-turbo" \
  --prompt argv-high \
  --width 1024 --height 1024 --steps 9 --quantize 8 \
  --output "${IMG_OUT}" \
  --model z-image-turbo

install_mflux_stub "mflux-generate-flux2"
run_wrapper env OVERRIDE_MEMORY_TIER=standard OVERRIDE_THERMAL_CLASS=fanless \
  OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_GPU_CORES=10 \
  "${GENERATE_IMAGE}" --prompt "argv-fanless" --output "${IMG_OUT}"
expect_argv_eq "image fanless argv adds vae-tiling" "${RECORD}" \
  "${VENV}/bin/mflux-generate-flux2" \
  --prompt argv-fanless \
  --width 512 --height 512 --steps 4 --quantize 4 \
  --output "${IMG_OUT}" \
  --model flux2-klein-4b \
  --low-ram \
  --vae-tiling

install_mflux_stub "mflux-generate-flux2"
run_wrapper env OVERRIDE_MEMORY_TIER=constrained OVERRIDE_THERMAL_CLASS=cooled \
  "${GENERATE_IMAGE}" --prompt "argv-passthrough" --output "${IMG_OUT}" -- --extra-mflux-flag yes
expect_argv_eq "image passthrough argv" "${RECORD}" \
  "${VENV}/bin/mflux-generate-flux2" \
  --prompt argv-passthrough \
  --width 512 --height 512 --steps 4 --quantize 4 \
  --output "${IMG_OUT}" \
  --model flux2-klein-4b \
  --low-ram \
  --vae-tiling \
  --extra-mflux-flag yes

# --- video: standard default, high tier, fanless (+force), passthrough ---

run_wrapper env OVERRIDE_MEMORY_TIER=standard OVERRIDE_THERMAL_CLASS=cooled \
  OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_GPU_CORES=10 \
  "${GENERATE_VIDEO}" --prompt "argv-default" --output "${VID_OUT}"
expect_argv_eq "video standard default argv" "${RECORD}" \
  "${VENV}/bin/python3" -m mlx_video.models.wan_2.generate \
  --prompt argv-default \
  --width 832 --height 480 \
  --model-dir "${WS}/models/video/wan21-t2v-1.3b-q4" \
  --num-frames 17 \
  --output-path "${VID_OUT}" \
  --tiling auto \
  --steps 10

run_wrapper env OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled \
  "${GENERATE_VIDEO}" --prompt "argv-high" --output "${VID_OUT}"
expect_argv_eq "video high tier override argv" "${RECORD}" \
  "${VENV}/bin/python3" -m mlx_video.models.wan_2.generate \
  --prompt argv-high \
  --width 832 --height 480 \
  --model-dir "${WS}/models/video/wan21-t2v-1.3b-q4" \
  --num-frames 33 \
  --output-path "${VID_OUT}" \
  --tiling auto \
  --steps 10

run_wrapper env OVERRIDE_MEMORY_TIER=standard OVERRIDE_THERMAL_CLASS=fanless \
  OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_GPU_CORES=10 \
  "${GENERATE_VIDEO}" --prompt "argv-fanless" --output "${VID_OUT}" --force
expect_argv_eq "video fanless argv" "${RECORD}" \
  "${VENV}/bin/python3" -m mlx_video.models.wan_2.generate \
  --prompt argv-fanless \
  --width 832 --height 480 \
  --model-dir "${WS}/models/video/wan21-t2v-1.3b-q4" \
  --num-frames 17 \
  --output-path "${VID_OUT}" \
  --tiling auto \
  --steps 10

run_wrapper env OVERRIDE_MEMORY_TIER=standard OVERRIDE_THERMAL_CLASS=cooled \
  OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_GPU_CORES=10 \
  "${GENERATE_VIDEO}" --prompt "argv-passthrough" --output "${VID_OUT}" -- --wan-extra 1
expect_argv_eq "video passthrough argv" "${RECORD}" \
  "${VENV}/bin/python3" -m mlx_video.models.wan_2.generate \
  --prompt argv-passthrough \
  --width 832 --height 480 \
  --model-dir "${WS}/models/video/wan21-t2v-1.3b-q4" \
  --num-frames 17 \
  --output-path "${VID_OUT}" \
  --tiling auto \
  --steps 10 \
  --wan-extra 1

# --- text: constrained default, high override, fanless policy, passthrough ---

run_wrapper env OVERRIDE_MEMORY_TIER=constrained OVERRIDE_THERMAL_CLASS=cooled \
  "${GENERATE_TEXT}" --prompt "argv-default" --model example/text-model
expect_argv_eq "text default argv" "${RECORD}" \
  generate \
  --model example/text-model \
  --prompt argv-default \
  --max-kv-size 2048

run_wrapper env OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled \
  "${GENERATE_TEXT}" --prompt "argv-high" --model example/high-model
expect_argv_eq "text high tier override argv" "${RECORD}" \
  generate \
  --model example/high-model \
  --prompt argv-high \
  --max-kv-size 4096

run_wrapper env OVERRIDE_MEMORY_TIER=standard OVERRIDE_THERMAL_CLASS=fanless \
  OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_GPU_CORES=10 \
  "${GENERATE_TEXT}" --prompt "argv-fanless" --model example/fanless-model
expect_argv_eq "text fanless argv" "${RECORD}" \
  generate \
  --model example/fanless-model \
  --prompt argv-fanless \
  --max-kv-size 2048

run_wrapper env OVERRIDE_MEMORY_TIER=constrained OVERRIDE_THERMAL_CLASS=cooled \
  "${GENERATE_TEXT}" --prompt "argv-passthrough" --model example/text-model -- --temp 0.1
expect_argv_eq "text passthrough argv" "${RECORD}" \
  generate \
  --model example/text-model \
  --prompt argv-passthrough \
  --max-kv-size 2048 \
  --temp 0.1

# --- serve: default, high override, fanless, passthrough ---

run_wrapper env OVERRIDE_MEMORY_TIER=constrained OVERRIDE_THERMAL_CLASS=cooled \
  "${SERVE}" --model example/serve-model
expect_argv_eq "serve default argv" "${RECORD}" \
  server \
  --model example/serve-model \
  --host 127.0.0.1 \
  --port 8080

run_wrapper env OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled \
  "${SERVE}" --model example/high-serve
expect_argv_eq "serve high tier override argv" "${RECORD}" \
  server \
  --model example/high-serve \
  --host 127.0.0.1 \
  --port 8080

run_wrapper env OVERRIDE_MEMORY_TIER=standard OVERRIDE_THERMAL_CLASS=fanless \
  OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_GPU_CORES=10 \
  "${SERVE}" --model example/fanless-serve --port 9090
expect_argv_eq "serve fanless argv" "${RECORD}" \
  server \
  --model example/fanless-serve \
  --host 127.0.0.1 \
  --port 9090

run_wrapper env OVERRIDE_MEMORY_TIER=constrained OVERRIDE_THERMAL_CLASS=cooled \
  "${SERVE}" --model example/serve-model -- --log-level debug
expect_argv_eq "serve passthrough argv" "${RECORD}" \
  server \
  --model example/serve-model \
  --host 127.0.0.1 \
  --port 8080 \
  --log-level debug

assert_finish "wrapper-argv self-test passed"
