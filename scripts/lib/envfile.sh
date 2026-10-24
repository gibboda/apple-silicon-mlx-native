#!/usr/bin/env bash
# models.env parsing, quoting, upsert, and seeding.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only



_file_mode_octal() {
  local path="$1"
  local mode=""
  if mode="$(stat -f '%Lp' "${path}" 2>/dev/null)"; then
    :
  elif mode="$(stat -c '%a' "${path}" 2>/dev/null)"; then
    :
  fi
  [[ -n "${mode}" ]] || return 1
  printf '%s' "${mode}"
}

# Final write target for models.env when the path is a symlink chain.

# Final write target for models.env when the path is a symlink chain.
env_file_write_target() {
  local file="$1"
  local target link_dir next seen=""
  [[ -n "${file}" ]] || return 1
  target="${file}"
  while [[ -L "${target}" ]]; do
    link_dir="$(dirname "${target}")"
    next="$(readlink "${target}")"
    [[ -n "${next}" ]] || die "Refusing to follow empty symlink: ${target}"
    if [[ "${next}" != /* ]]; then
      next="${link_dir}/${next}"
    fi
    case " ${seen} " in
      *" ${next} "*) die "Refusing to follow symlink loop in ${file}" ;;
    esac
    seen="${seen} ${next}"
    target="${next}"
  done
  printf '%s' "${target}"
}


upsert_env_assignment() {
  local file="$1"
  local key="$2"
  local value="$3"
  local quoted tmp target mode
  is_models_env_key "${key}" || die "Refusing to write non-MLX key to models.env: ${key}"
  quoted="$(quote_env_value "${value}")"
  target="$(env_file_write_target "${file}")"
  tmp="$(mktemp "${target}.XXXXXX")"
  mode=""
  if [[ -f "${target}" ]]; then
    mode="$(_file_mode_octal "${target}" || true)"
  fi
  # Pass via ENVIRON so awk -v does not interpret backslashes in POSIX '\'' quoting.
  if ! MLX_UPSERT_KEY="${key}" MLX_UPSERT_VALUE="${quoted}" awk '
    BEGIN { k=ENVIRON["MLX_UPSERT_KEY"]; v=ENVIRON["MLX_UPSERT_VALUE"]; done=0 }
    index($0, k "=") == 1 && !done { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "${file}" >"${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  if ! mv "${tmp}" "${target}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  if [[ -n "${mode}" ]]; then
    chmod "${mode}" "${target}"
  fi
}


is_models_env_key() {
  [[ "${1:-}" =~ ^MLX_[A-Z0-9_]+$ ]]
}

# Unquoted when the value is a simple token (model ids, numbers, hosts).
# Otherwise POSIX single quotes so the file stays source-able without eval.

# Unquoted when the value is a simple token (model ids, numbers, hosts).
# Otherwise POSIX single quotes so the file stays source-able without eval.
quote_env_value() {
  local value="$1"
  local out c
  local -i i
  if [[ "${value}" =~ ^[A-Za-z0-9._:/=@%+-]+$ ]]; then
    printf '%s' "${value}"
    return 0
  fi
  out="'"
  for (( i = 0; i < ${#value}; i++ )); do
    c="${value:i:1}"
    if [[ "${c}" == "'" ]]; then
      out+="'\\''"
    else
      out+="${c}"
    fi
  done
  out+="'"
  printf '%s' "${out}"
}

# Strip surrounding quotes without executing the value. Returns 1 if unsafe.
# Single-quoted values accept POSIX concatenation: 'Bob'\''s-model' → Bob's-model.

# Strip surrounding quotes without executing the value. Returns 1 if unsafe.
# Single-quoted values accept POSIX concatenation: 'Bob'\''s-model' → Bob's-model.
unquote_env_value() {
  local raw="$1"
  local inner
  if [[ "${raw:0:1}" == "'" ]]; then
    unquote_posix_single "${raw}"
    return $?
  fi
  if (( ${#raw} >= 2 )) && [[ "${raw:0:1}" == '"' && "${raw: -1}" == '"' ]]; then
    inner="${raw:1:${#raw}-2}"
    case "${inner}" in
      *'$'* | *'`'* | *\\*) return 1 ;;
    esac
    printf '%s' "${inner}"
    return 0
  fi
  if [[ "${raw}" =~ [][\$\`\;\|\&\<\>\(\)\{\}\\\'\"[:space:]] ]]; then
    return 1
  fi
  if [[ -n "${HOME:-}" && "${raw}" == "~" ]]; then
    printf '%s' "${HOME}"
  elif [[ -n "${HOME:-}" && "${raw:0:2}" == $'~/' ]]; then
    printf '%s' "${HOME}/${raw:2}"
  else
    printf '%s' "${raw}"
  fi
}


unquote_posix_single() {
  local raw="$1"
  local out="" c nxt
  local -i i=0 n=${#raw}
  (( n >= 2 )) || return 1
  while (( i < n )); do
    c="${raw:i:1}"
    if [[ "${c}" == "'" ]]; then
      i+=1
      while (( i < n )); do
        c="${raw:i:1}"
        [[ "${c}" == "'" ]] && break
        out+="${c}"
        i+=1
      done
      (( i < n )) || return 1
      i+=1
    elif [[ "${c}" == "\\" ]]; then
      i+=1
      (( i < n )) || return 1
      nxt="${raw:i:1}"
      [[ "${nxt}" == "'" ]] || return 1
      out+="'"
      i+=1
    else
      return 1
    fi
  done
  printf '%s' "${out}"
}

# Pipe-delimited MLX_* names set in the shell before load_models_env reads the file.
MODELS_ENV_PROCESS_ENV_KEYS=""

# Snapshot process env once per load. Later duplicate lines in models.env still win;
# only keys set before parsing are locked out of the file.

# Snapshot process env once per load. Later duplicate lines in models.env still win;
# only keys set before parsing are locked out of the file.
models_env_snapshot_process_env() {
  local name marker
  MODELS_ENV_PROCESS_ENV_KEYS="|"
  while IFS= read -r name; do
    [[ "${name}" =~ ^MLX_[A-Z0-9_]+$ ]] || continue
    eval "marker=\${${name}+x}"
    if [[ -n "${marker}" ]]; then
      MODELS_ENV_PROCESS_ENV_KEYS+="${name}|"
    fi
  done < <(compgen -A variable 2>/dev/null || true)
}


models_env_key_locked_from_process_env() {
  case "${MODELS_ENV_PROCESS_ENV_KEYS}" in
    *"|${1}|"*) return 0 ;;
    *) return 1 ;;
  esac
}

# User-set MLX_RECOMMENDED_CONTEXT (CLI/env/models.env) before compose overwrites
# the exported composed default. Cleared by capture_user_recommended_context.

# User-set MLX_RECOMMENDED_CONTEXT (CLI/env/models.env) before compose overwrites
# the exported composed default. Cleared by capture_user_recommended_context.
capture_user_recommended_context() {
  unset USER_MLX_RECOMMENDED_CONTEXT
  if [[ -n "${MLX_RECOMMENDED_CONTEXT+x}" ]]; then
    USER_MLX_RECOMMENDED_CONTEXT="${MLX_RECOMMENDED_CONTEXT}"
  fi
}

# CLI --max-kv-size > user MLX_RECOMMENDED_CONTEXT > composed default.

# CLI --max-kv-size > user MLX_RECOMMENDED_CONTEXT > composed default.
resolve_text_max_kv_size() {
  local cli_max_kv="${1:-}"
  if [[ -n "${cli_max_kv}" ]]; then
    printf '%s' "${cli_max_kv}"
    return 0
  fi
  if [[ -n "${USER_MLX_RECOMMENDED_CONTEXT+x}" ]]; then
    printf '%s' "${USER_MLX_RECOMMENDED_CONTEXT}"
    return 0
  fi
  printf '%s' "${MLX_RECOMMENDED_CONTEXT:-2048}"
}

# Effective server context cap (no server --max-kv-size in mlx-lm 0.31.3).

# Effective server context cap (no server --max-kv-size in mlx-lm 0.31.3).
resolve_serve_context() {
  if [[ -n "${USER_MLX_RECOMMENDED_CONTEXT+x}" ]]; then
    printf '%s' "${USER_MLX_RECOMMENDED_CONTEXT}"
    return 0
  fi
  printf '%s' "${MLX_RECOMMENDED_CONTEXT:-2048}"
}

# Parse config/models.env as data. Only documented MLX_* config keys are
# exported. Lines are never executed (no command substitution, PATH=, or
# HF_TOKEN). Runtime identity keys (workspace/venv/paths) are skipped.
# Process environment beats file for each allowlisted key. Duplicate keys in the
# file still last-win unless the process env set the key before load. Missing file is OK.

# Parse config/models.env as data. Only documented MLX_* config keys are
# exported. Lines are never executed (no command substitution, PATH=, or
# HF_TOKEN). Runtime identity keys (workspace/venv/paths) are skipped.
# Process environment beats file for each allowlisted key. Duplicate keys in the
# file still last-win unless the process env set the key before load. Missing file is OK.
load_models_env() {
  local file="${1:-${MLX_MODELS_ENV}}"
  local line key value decoded
  [[ -f "${file}" ]] || return 0
  models_env_snapshot_process_env
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    if [[ "${line}" == export[[:space:]]* ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      if ! is_models_env_key "${key}"; then
        log_warn "Skipping non-MLX key ${key} in ${file}"
        continue
      fi
      value="$(strip_unquoted_assignment_comment "${value}")"
      if ! decoded="$(unquote_env_value "${value}")"; then
        log_warn "Skipping unsafe ${key} assignment in ${file}"
        continue
      fi
      if is_models_env_runtime_key "${key}"; then
        log_warn "Skipping runtime key ${key} in ${file}"
        continue
      fi
      if models_env_key_locked_from_process_env "${key}"; then
        continue
      fi
      printf -v "${key}" '%s' "${decoded}"
      export "${key?}"
    fi
  done <"${file}"
}


is_models_env_runtime_key() {
  case "${1:-}" in
    MLX_WORKSPACE|MLX_VENV|MLX_CONFIG_DIR|MLX_MODELS_ENV|MLX_MODELS_EXAMPLE|MLX_PYTHON_VERSION|MLX_SKIP_DEVICE_PROBE)
      return 0
      ;;
    *) return 1 ;;
  esac
}

# Drop an unquoted " # comment" suffix. Quoted values are left intact.

# Drop an unquoted " # comment" suffix. Quoted values are left intact.
strip_unquoted_assignment_comment() {
  local value="$1"
  local comment_re='^(.*)[[:space:]]+#'
  if [[ "${value:0:1}" == "'" || "${value:0:1}" == '"' ]]; then
    printf '%s' "${value}"
    return 0
  fi
  if [[ "${value}" =~ ${comment_re} ]]; then
    value="${BASH_REMATCH[1]}"
    value="${value%"${value##*[![:space:]]}"}"
  fi
  printf '%s' "${value}"
}

# Create config/models.env once from the composed profile. Never overwrite an existing file.

# Create config/models.env once from the composed profile. Never overwrite an existing file.
seed_models_env_if_missing() {
  local model context
  mkdir -p "${MLX_CONFIG_DIR}"
  if [[ -f "${MLX_MODELS_ENV}" ]]; then
    log_ok "Preserving existing ${MLX_MODELS_ENV}"
    return 0
  fi
  model="${MLX_RECOMMENDED_MODEL:-$(recommended_model_for_tier "${MLX_TIER_ID:-constrained}")}"
  context="${MLX_RECOMMENDED_CONTEXT:-2048}"
  if [[ -f "${MLX_MODELS_EXAMPLE}" ]]; then
    cp "${MLX_MODELS_EXAMPLE}" "${MLX_MODELS_ENV}"
    upsert_env_assignment "${MLX_MODELS_ENV}" MLX_DEFAULT_MODEL "${model}"
    upsert_env_assignment "${MLX_MODELS_ENV}" MLX_RECOMMENDED_CONTEXT "${context}"
    log_ok "Created ${MLX_MODELS_ENV} from composed profile (model=${model} context=${context})"
    log_info "Rebuild preserves this file. After moving this clone to another Mac, run: make recommend"
  else
    cat >"${MLX_MODELS_ENV}" <<EOF
# Local model preferences (not committed)
MLX_DEFAULT_MODEL=$(quote_env_value "${model}")
MLX_RECOMMENDED_CONTEXT=$(quote_env_value "${context}")
MLX_SERVER_HOST=127.0.0.1
MLX_SERVER_PORT=8080
EOF
    log_ok "Created ${MLX_MODELS_ENV}"
  fi
}

