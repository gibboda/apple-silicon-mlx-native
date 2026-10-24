#!/usr/bin/env bash
# Fast platform guard for Apple Silicon macOS 26–27 before venv/install work.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Usage:
#   scripts/doctor-mlx-native.sh
#   make doctor
#
# shellcheck source=scripts/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: doctor-mlx-native.sh [-h|--help]

Verify this Mac meets the toolkit platform requirements (Apple Silicon,
macOS 26–27) before make venv / make install.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

assert_apple_silicon
assert_minimum_macos_for_mlx

ver="$(detect_macos_version)"
log_ok "Platform OK: Apple Silicon macOS ${ver} (supported ${MLX_MACOS_VERSION_MIN_MAJOR}–${MLX_MACOS_VERSION_MAX_MAJOR})"
