#!/usr/bin/env bash
# Make image/video extra args must not be evaluated as shell.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

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

help_out="$(make -C "${ROOT}" help)"
expect_contains "help still lists image" "make image" "${help_out}"
expect_contains "help still lists video" "make video" "${help_out}"

plan="$(make -C "${ROOT}" image IMAGE_PROMPT='a red fox' GENERATE_IMAGE_ARGS='--family schnell --dump-plan')"
expect_contains "image args reach the generator" "family=schnell" "${plan}"

sentinel="${TMP}/pwned"
rm -f "${sentinel}"
set +e
make -C "${ROOT}" image IMAGE_PROMPT='a fox' GENERATE_IMAGE_ARGS="; touch ${sentinel}" >/dev/null 2>&1
set -e
if [[ -e "${sentinel}" ]]; then
  fail "semicolon in GENERATE_IMAGE_ARGS was executed"
else
  pass "semicolon in GENERATE_IMAGE_ARGS was not executed"
fi

rm -f "${sentinel}"
set +e
make -C "${ROOT}" image IMAGE_PROMPT='a fox' GENERATE_IMAGE_ARGS='`touch '"${sentinel}"'`' >/dev/null 2>&1
set -e
if [[ -e "${sentinel}" ]]; then
  fail "backticks in GENERATE_IMAGE_ARGS were executed"
else
  pass "backticks in GENERATE_IMAGE_ARGS were not executed"
fi

rm -f "${sentinel}"
set +e
# Two dollar signs so Make receives a literal $(touch ...) and the recipe shell does not run it.
touch_expr="$(printf '%b%b(touch %s)' '\044' '\044' "${sentinel}")"
make -C "${ROOT}" video VIDEO_PROMPT='a fox' GENERATE_VIDEO_ARGS="${touch_expr}" >/dev/null 2>&1
set -e
if [[ -e "${sentinel}" ]]; then
  fail "command substitution in GENERATE_VIDEO_ARGS was executed"
else
  pass "command substitution in GENERATE_VIDEO_ARGS was not executed"
fi

plan_video="$(make -C "${ROOT}" video VIDEO_PROMPT='a fox' GENERATE_VIDEO_ARGS='--dump-plan')"
expect_contains "video args reach the generator" "family=" "${plan_video}"

# Prompts go through as one argv word. Make 3.81 must not expand $VAR or $(...)
# and must not split newlines. A stub records the exact --prompt value.
stub_dir="${TMP}/stub-scripts"
stub_out="${TMP}/stub-out"
mkdir -p "${stub_dir}" "${stub_out}"
cat >"${stub_dir}/record-prompt.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out="${STUB_OUT:?}"
base="$(basename "$0")"
if [[ "$#" -gt 0 ]]; then
  printf '%s\0' "$@" >"${out}/${base}.argv"
else
  : >"${out}/${base}.argv"
fi
EOF
chmod +x "${stub_dir}/record-prompt.sh"
for stub_name in generate-mlx-image.sh generate-mlx-video.sh generate-mlx-text.sh; do
  cp "${stub_dir}/record-prompt.sh" "${stub_dir}/${stub_name}"
  chmod +x "${stub_dir}/${stub_name}"
done

prompt_marker="${TMP}/prompt-marker"
# Literal payload: quotes, backtick command, $HOME, $(id), Make $(shell …), comma,
# hash, backslash, and a newline. Escapes keep this shell from expanding any of that.
prompt_payload="say \"hi\" 'x' \`touch ${prompt_marker}\` \$HOME \$(id) \$(shell touch ${prompt_marker}) a,b #hash back\\slash"$'\n''second'
# Exercises mlx_lit backslash doubling: $'…' escapes and a trailing backslash.
prompt_escape_payload=$'a\nb \t \\ \047 end\\'

argv_prompt() {
  local file="$1"
  local arg seen=0
  PROMPT_ARG=""
  while IFS= read -r -d '' arg || [[ -n "${arg}" ]]; do
    if [[ "${seen}" -eq 1 ]]; then
      PROMPT_ARG="${arg}"
      return 0
    fi
    if [[ "${arg}" == "--prompt" ]]; then
      seen=1
    fi
  done <"${file}"
  return 1
}

expect_make_prompt() {
  local label="$1"
  local target="$2"
  local var_name="$3"
  local script_name="$4"
  local mode="$5"
  local payload="$6"
  local argv_file="${stub_out}/${script_name}.argv"
  rm -f "${prompt_marker}" "${argv_file}"
  local rc=0
  if [[ "${mode}" == "env" ]]; then
    env "${var_name}=${payload}" STUB_OUT="${stub_out}" \
      make -C "${ROOT}" "${target}" SCRIPTS="${stub_dir}" >/dev/null 2>&1 || rc=$?
  else
    STUB_OUT="${stub_out}" \
      make -C "${ROOT}" "${target}" SCRIPTS="${stub_dir}" "${var_name}=${payload}" >/dev/null 2>&1 || rc=$?
  fi
  if [[ "${rc}" -ne 0 ]]; then
    fail "${label} (make exited ${rc})"
    return
  fi
  if [[ -e "${prompt_marker}" ]]; then
    fail "${label} (prompt was executed)"
    return
  fi
  if ! argv_prompt "${argv_file}"; then
    fail "${label} (missing --prompt)"
    return
  fi
  if [[ "${PROMPT_ARG}" == "${payload}" ]]; then
    pass "${label}"
  else
    fail "${label} (prompt bytes differ)"
  fi
}

expect_make_prompt "image command-line prompt is literal" image IMAGE_PROMPT generate-mlx-image.sh cmdline "${prompt_payload}"
expect_make_prompt "video command-line prompt is literal" video VIDEO_PROMPT generate-mlx-video.sh cmdline "${prompt_payload}"
expect_make_prompt "text command-line prompt is literal" generate-text PROMPT generate-mlx-text.sh cmdline "${prompt_payload}"
expect_make_prompt "image environment prompt is literal" image IMAGE_PROMPT generate-mlx-image.sh env "${prompt_payload}"
expect_make_prompt "video environment prompt is literal" video VIDEO_PROMPT generate-mlx-video.sh env "${prompt_payload}"
expect_make_prompt "text environment prompt is literal" generate-text PROMPT generate-mlx-text.sh env "${prompt_payload}"

expect_make_prompt "image command-line mlx_lit escapes preserved" image IMAGE_PROMPT generate-mlx-image.sh cmdline "${prompt_escape_payload}"
expect_make_prompt "video command-line mlx_lit escapes preserved" video VIDEO_PROMPT generate-mlx-video.sh cmdline "${prompt_escape_payload}"
expect_make_prompt "text command-line mlx_lit escapes preserved" generate-text PROMPT generate-mlx-text.sh cmdline "${prompt_escape_payload}"
expect_make_prompt "image environment mlx_lit escapes preserved" image IMAGE_PROMPT generate-mlx-image.sh env "${prompt_escape_payload}"
expect_make_prompt "video environment mlx_lit escapes preserved" video VIDEO_PROMPT generate-mlx-video.sh env "${prompt_escape_payload}"
expect_make_prompt "text environment mlx_lit escapes preserved" generate-text PROMPT generate-mlx-text.sh env "${prompt_escape_payload}"

rm -f "${stub_out}/generate-mlx-image.sh.argv"
set +e
make -C "${ROOT}" image SCRIPTS="${stub_dir}" STUB_OUT="${stub_out}" >/dev/null 2>&1
missing_rc=$?
set -e
if [[ "${missing_rc}" -eq 0 ]]; then
  fail "image without IMAGE_PROMPT succeeded"
elif [[ -e "${stub_out}/generate-mlx-image.sh.argv" ]]; then
  fail "image without IMAGE_PROMPT invoked the generator"
else
  pass "image without IMAGE_PROMPT does not run the generator"
fi

if (( failures > 0 )); then
  printf 'FAIL: %s generate-args check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf 'OK: generate args are not a shell\n'
