#!/usr/bin/env bash
# Shared fit rules and text default selection for catalog list labels.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
#
# Text list fit labels and composed text defaults share profile_* predicates
# and rule keys (issue #61 / #82). Image/video list fit labels live here;
# image_list_default_id / video_list_default_id stay in policy.sh.

# 7B and 8B: poor on <=8 GB, tight on a 16 GB Air or slow/moderate chip, fits when cooled and fast.
_model_list_fit_7b_8b() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  case "${tier}" in
    constrained|"") printf '%s\n' poor; return ;;
  esac
  if [[ "${thermal}" == "fanless" ]]; then
    if [[ "${tier}" == "standard" ]]; then
      printf '%s\n' tight
    else
      printf '%s\n' fits
    fi
    return
  fi
  if [[ "${tier}" == "standard" ]] && ! profile_standard_fast_cooled "${throughput}" "${thermal}"; then
    printf '%s\n' tight
    return
  fi
  printf '%s\n' fits
}

# --- Shared profile predicates ---

profile_fanless_or_unknown_throughput() {
  local throughput="${1:-unknown}"
  local thermal="${2:-}"
  [[ "${thermal}" == "fanless" ]] || [[ "${throughput}" == "unknown" || -z "${throughput}" ]]
}

profile_standard_fast_cooled() {
  local throughput="${1:-unknown}"
  local thermal="${2:-}"
  [[ "${thermal}" != "fanless" ]] && throughput_at_least "${throughput}" fast
}

profile_high_very_fast_cooled() {
  local throughput="${1:-unknown}"
  local thermal="${2:-}"
  [[ "${thermal}" != "fanless" ]] && throughput_at_least "${throughput}" very_fast
}

# --- Text catalog: model_id|rule_key ---

text_model_rule_key() {
  case "${1:-}" in
    mlx-community/Llama-3.2-3B-Instruct-4bit|\
    mlx-community/Llama-3.2-1B-Instruct-4bit|\
    mlx-community/Phi-3.5-mini-instruct-4bit|\
    mlx-community/Qwen2.5-3B-Instruct-4bit)
      printf '%s\n' text_small
      ;;
    mlx-community/Mistral-7B-Instruct-v0.3-4bit|\
    mlx-community/Meta-Llama-3.1-8B-Instruct-4bit)
      printf '%s\n' text_7b_8b
      ;;
    mlx-community/Qwen2.5-14B-Instruct-4bit)
      printf '%s\n' text_14b
      ;;
    mlx-community/Qwen2.5-32B-Instruct-4bit)
      printf '%s\n' text_32b
      ;;
    *)
      printf '%s\n' text_unknown
      ;;
  esac
}

# Canonical catalog model for each text rule key (tier defaults derive from these).
_text_canonical_model_for_rule_key() {
  case "${1:-}" in
    text_small) printf '%s\n' "mlx-community/Llama-3.2-3B-Instruct-4bit" ;;
    text_7b_8b) printf '%s\n' "mlx-community/Mistral-7B-Instruct-v0.3-4bit" ;;
    text_14b) printf '%s\n' "mlx-community/Qwen2.5-14B-Instruct-4bit" ;;
    text_32b) printf '%s\n' "mlx-community/Qwen2.5-32B-Instruct-4bit" ;;
    *) return 1 ;;
  esac
}

text_default_rule_key_for_profile() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  case "${tier}" in
    constrained|"")
      printf '%s\n' text_small
      ;;
    standard)
      if profile_standard_fast_cooled "${throughput}" "${thermal}"; then
        printf '%s\n' text_7b_8b
      else
        printf '%s\n' text_small
      fi
      ;;
    high)
      if profile_high_very_fast_cooled "${throughput}" "${thermal}"; then
        printf '%s\n' text_14b
      else
        printf '%s\n' text_7b_8b
      fi
      ;;
    workstation)
      printf '%s\n' text_14b
      ;;
    large)
      printf '%s\n' text_32b
      ;;
    *)
      printf '%s\n' text_unknown
      ;;
  esac
}

text_model_fit_from_rule() {
  local id="${1:-}"
  local tier="${2:-}"
  local throughput="${3:-unknown}"
  local thermal="${4:-}"
  local key
  key="$(text_model_rule_key "${id}")"
  case "${key}" in
    text_small)
      printf '%s\n' fits
      ;;
    text_7b_8b)
      _model_list_fit_7b_8b "${tier}" "${throughput}" "${thermal}"
      ;;
    text_14b)
      case "${tier}" in
        workstation|large)
          printf '%s\n' fits
          ;;
        high)
          if profile_high_very_fast_cooled "${throughput}" "${thermal}"; then
            printf '%s\n' fits
          else
            printf '%s\n' tight
          fi
          ;;
        *)
          printf '%s\n' poor
          ;;
      esac
      ;;
    text_32b)
      case "${tier}" in
        workstation|large) printf '%s\n' fits ;;
        *) printf '%s\n' poor ;;
      esac
      ;;
    *)
      printf '%s\n' poor
      ;;
  esac
}

text_default_model_for_profile() {
  local tier="${1:-}"
  local throughput="${2:-unknown}"
  local thermal="${3:-}"
  local key model
  if profile_fanless_or_unknown_throughput "${throughput}" "${thermal}"; then
    recommended_model_for_tier "${tier}"
    return
  fi
  key="$(text_default_rule_key_for_profile "${tier}" "${throughput}" "${thermal}")"
  if model="$(_text_canonical_model_for_rule_key "${key}")"; then
    printf '%s\n' "${model}"
  else
    recommended_model_for_tier "${tier}"
  fi
}

# --- Image catalog: checkpoint id|rule_key ---

image_model_rule_key() {
  case "${1:-}" in
    flux2-klein-4b) printf '%s\n' image_flux2 ;;
    z-image-turbo) printf '%s\n' image_z_turbo ;;
    schnell) printf '%s\n' image_schnell ;;
    *) printf '%s\n' image_unknown ;;
  esac
}

image_model_fit_from_rule() {
  local id="${1:-}"
  local tier="${2:-}"
  local throughput="${3:-unknown}"
  local thermal="${4:-}"
  local _chip_family="${5:-0}"
  local key
  key="$(image_model_rule_key "${id}")"
  case "${key}" in
    image_flux2)
      printf '%s\n' fits
      ;;
    image_z_turbo)
      case "${tier}" in
        constrained|"") printf '%s\n' poor ;;
        standard|high) printf '%s\n' tight ;;
        workstation|large) printf '%s\n' fits ;;
        *) printf '%s\n' poor ;;
      esac
      ;;
    image_schnell)
      case "${tier}" in
        constrained|"") printf '%s\n' poor ;;
        standard) printf '%s\n' tight ;;
        high)
          if [[ "${thermal}" == "fanless" ]]; then
            printf '%s\n' tight
          else
            printf '%s\n' fits
          fi
          ;;
        workstation|large) printf '%s\n' fits ;;
        *) printf '%s\n' poor ;;
      esac
      ;;
    *)
      printf '%s\n' poor
      ;;
  esac
}

# --- Video catalog: model id|rule_key ---

video_model_rule_key() {
  case "${1:-}" in
    "${MLX_VIDEO_WAN_MODEL_NAME}")
      printf '%s\n' video_wan
      ;;
    "${MLX_VIDEO_LTX_REPO}")
      printf '%s\n' video_ltx
      ;;
    *)
      printf '%s\n' video_unknown
      ;;
  esac
}

video_model_fit_from_rule() {
  local id="${1:-}"
  local tier="${2:-}"
  local throughput="${3:-unknown}"
  local thermal="${4:-}"
  local _chip_family="${5:-0}"
  local _gpu_cores="${6:-0}"
  local key
  key="$(video_model_rule_key "${id}")"
  case "${key}" in
    video_wan)
      printf '%s\n' fits
      ;;
    video_ltx)
      case "${tier}" in
        workstation|large)
          if [[ "${thermal}" == "fanless" ]]; then
            printf '%s\n' tight
          else
            printf '%s\n' fits
          fi
          ;;
        *)
          printf '%s\n' poor
          ;;
      esac
      ;;
    *)
      printf '%s\n' poor
      ;;
  esac
}
