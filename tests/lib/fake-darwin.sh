#!/usr/bin/env bash
# Minimal Darwin/arm64 stubs for running generate wrappers on Linux CI.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

fake_darwin_install() {
  local stub_root="$1"
  local mem_bytes="${2:-17179869184}"
  mkdir -p "${stub_root}"
  cat >"${stub_root}/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -m) printf '%s\n' arm64 ;;
  -s) printf '%s\n' Darwin ;;
  *) printf '%s\n' arm64 ;;
esac
EOF
  cat >"${stub_root}/sysctl" <<EOF
#!/bin/sh
key="\${2:-\$1}"
case "\${key}" in
  hw.memsize) printf '%s\n' ${mem_bytes} ;;
  hw.ncpu) printf '%s\n' 8 ;;
  hw.model) printf '%s\n' MacBookPro18,1 ;;
  machdep.cpu.brand_string) printf '%s\n' 'Apple M3 Pro' ;;
  hw.perflevel0.physicalcpu) printf '%s\n' 4 ;;
  hw.perflevel1.physicalcpu) printf '%s\n' 4 ;;
  *) printf '\n' ;;
esac
EOF
  cat >"${stub_root}/sw_vers" <<'EOF'
#!/bin/sh
printf '%s\n' 15.0
EOF
  cat >"${stub_root}/df" <<'EOF'
#!/bin/sh
printf '%s\n' "Filesystem 1G-blocks Used Available"
printf '%s\n' "/dev/disk1 900 100 800"
EOF
  cat >"${stub_root}/ffmpeg" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "${stub_root}/uname" "${stub_root}/sysctl" "${stub_root}/sw_vers" \
    "${stub_root}/df" "${stub_root}/ffmpeg"
  FAKE_DARWIN_BIN="${stub_root}"
}

fake_darwin_path() {
  printf '%s' "${FAKE_DARWIN_BIN}:${PATH}"
}
