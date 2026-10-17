#!/usr/bin/env bash
# Helpers to compare NUL-separated argv recordings (bash 3.2+).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

# shellcheck source=tests/lib/assert.sh
if [[ -z "${pass:-}" ]]; then
  _argv_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=tests/lib/assert.sh
  source "${_argv_lib_dir}/assert.sh"
fi

read_argv_file() {
  local file="$1"
  ARGV_RECORD=()
  [[ -f "${file}" ]] || return 1
  while IFS= read -r -d '' arg || [[ -n "${arg}" ]]; do
    ARGV_RECORD+=("${arg}")
  done <"${file}"
}

argv_record_to_lines() {
  local i
  for i in "${!ARGV_RECORD[@]}"; do
    printf '%s\n' "${ARGV_RECORD[${i}]}"
  done
}

expect_argv_eq() {
  local label="$1"
  local file="$2"
  shift 2
  local -a want=("$@")
  if ! read_argv_file "${file}"; then
    fail "${label} (missing argv recording ${file})"
    return
  fi
  if ((${#want[@]} != ${#ARGV_RECORD[@]})); then
    fail "${label} (want ${#want[@]} args, got ${#ARGV_RECORD[@]}: $(argv_record_to_lines | tr '\n' ' '))"
    return
  fi
  local i
  for i in "${!want[@]}"; do
    if [[ "${want[${i}]}" != "${ARGV_RECORD[${i}]}" ]]; then
      fail "${label} (arg $((i + 1)): want ${want[${i}]}, got ${ARGV_RECORD[${i}]})"
      return
    fi
  done
  pass "${label}"
}
