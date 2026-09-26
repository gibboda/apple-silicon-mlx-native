# apple-silicon-mlx-native — convenience targets delegate to scripts.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

SCRIPTS := scripts
.DEFAULT_GOAL := help

# Single-quote a Make value so the recipe shell does not evaluate metacharacters.
sq = '$(subst ','\'',$(1))'

.PHONY: help detect recommend install rebuild validate clean uninstall audit lint test install-image image install-video prepare-video video generate-text serve release

help: ## Show available targets
	@printf '%s\n' \
		'make help      — show this help' \
		'make detect    — detect Apple Silicon hardware, chip class, and memory tier' \
		'make recommend — print composed LLM/image/video defaults (does not write models.env)' \
		'make install   — initial MLX-native bootstrap (Homebrew + venv + packages)' \
		'make rebuild   — recreate .venv and reinstall MLX packages' \
		'make validate  — validate mlx / mlx-lm and run a fast computation check' \
		'make install-image — install Pure MLX text-to-image (mflux) into .venv' \
		'make image     — generate an image (IMAGE_PROMPT="...")' \
		'make install-video — install Pure MLX text-to-video (mlx-video) into .venv' \
		'make prepare-video — download and convert Wan2.1 T2V 1.3B for mlx-video' \
		'make video     — generate a video (VIDEO_PROMPT="...")' \
		'make generate-text — mlx_lm text generation (PROMPT="..."); 8 GB cache cap' \
		'make serve     — resident mlx_lm.server; 8 GB uses the Metal working-set cap' \
		'make clean     — remove .venv (toolkit-owned environment); reports leftovers' \
		'make uninstall — same as make clean' \
		'make audit     — audit commit subjects for Conventional Commits' \
		'make lint      — run ShellCheck on repository shell scripts' \
		'make test      — run portable shell self-tests' \
		'make release   — cut next SemVer from CHANGELOG Unreleased and open a PR'

detect: ## Detect Apple Silicon hardware
	@$(SCRIPTS)/detect-apple-silicon.sh

recommend: ## Print composed defaults for this Mac (does not write models.env)
	@$(SCRIPTS)/detect-apple-silicon.sh --recommend

install: ## Bootstrap MLX-native environment
	@$(SCRIPTS)/initial-build-mlx-native-media.sh

rebuild: ## Rebuild Python MLX environment
	@$(SCRIPTS)/rebuild-mlx-native-media.sh --force

validate: ## Validate MLX installation
	@$(SCRIPTS)/validate-mlx.sh

install-image: ## Install mflux into the existing venv (does not recreate .venv)
	@$(SCRIPTS)/install-mlx-image.sh

image: ## Generate a PNG with mflux (IMAGE_PROMPT required)
	@test -n "$(IMAGE_PROMPT)" || { echo 'Set IMAGE_PROMPT=... e.g. make image IMAGE_PROMPT="a red fox in snow"'; exit 1; }
	@extra=$(call sq,$(GENERATE_IMAGE_ARGS)); \
	if [[ -n "$$extra" ]]; then \
	  read -r -a image_args <<<"$$extra"; \
	  "$(SCRIPTS)/generate-mlx-image.sh" --prompt "$(IMAGE_PROMPT)" "$${image_args[@]}"; \
	else \
	  "$(SCRIPTS)/generate-mlx-image.sh" --prompt "$(IMAGE_PROMPT)"; \
	fi

install-video: ## Install mlx-video into the existing venv (does not recreate .venv)
	@$(SCRIPTS)/install-mlx-video.sh

prepare-video: ## Download and convert Wan2.1 T2V 1.3B (needs torch in .venv)
	@$(SCRIPTS)/prepare-mlx-video-wan.sh

generate-text: ## Generate text with mlx_lm (PROMPT required); caps MLX cache on ≤8 GB
	@test -n "$(PROMPT)" || { echo 'Set PROMPT=... e.g. make generate-text PROMPT="Hello from MLX"'; exit 1; }
	@"$(SCRIPTS)/generate-mlx-text.sh" --prompt "$(PROMPT)"

serve: ## Start mlx_lm.server; on ≤8 GB pin GPU and cap MLX memory to the Metal working set
	@"$(SCRIPTS)/serve-mlx.sh"

video: ## Generate an MP4 with mlx-video (VIDEO_PROMPT required)
	@test -n "$(VIDEO_PROMPT)" || { echo 'Set VIDEO_PROMPT=... e.g. make video VIDEO_PROMPT="a red fox running through snow"'; exit 1; }
	@extra=$(call sq,$(GENERATE_VIDEO_ARGS)); \
	if [[ -n "$$extra" ]]; then \
	  read -r -a video_args <<<"$$extra"; \
	  "$(SCRIPTS)/generate-mlx-video.sh" --prompt "$(VIDEO_PROMPT)" "$${video_args[@]}"; \
	else \
	  "$(SCRIPTS)/generate-mlx-video.sh" --prompt "$(VIDEO_PROMPT)"; \
	fi

clean uninstall: ## Remove toolkit-owned .venv; do not uninstall Homebrew
	@$(SCRIPTS)/cleanup-mlx-native.sh --force

audit: ## Conventional Commits audit
	@$(SCRIPTS)/conventional-commits-audit.sh

release: ## Cut next SemVer from CHANGELOG Unreleased and open a PR (RELEASE_ARGS=--dry-run|--minor|--major|--no-push)
	@$(SCRIPTS)/release.sh $(RELEASE_ARGS)

lint: ## ShellCheck all scripts
	@command -v shellcheck >/dev/null 2>&1 || { \
	  echo 'ERROR: shellcheck not found. Install with: brew install shellcheck'; \
	  exit 1; \
	}
	@status=0; \
	while IFS= read -r -d '' script; do \
	  shellcheck -x "$$script" || status=1; \
	done < <(find scripts tests -type f -name '*.sh' -print0); \
	exit $$status

test: ## Run portable shell self-tests
	@status=0; \
	for t in tests/*.test.sh; do \
	  "$$t" || status=1; \
	done; \
	exit $$status
