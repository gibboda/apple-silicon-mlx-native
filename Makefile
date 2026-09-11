# apple-silicon-mlx-native — convenience targets delegate to scripts.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

SCRIPTS := scripts
.DEFAULT_GOAL := help

.PHONY: help detect install rebuild validate clean uninstall audit lint test

help: ## Show available targets
	@printf '%s\n' \
		'make help      — show this help' \
		'make detect    — detect Apple Silicon hardware and memory tier' \
		'make install   — initial MLX-native bootstrap (Homebrew + venv + packages)' \
		'make rebuild   — recreate .venv and reinstall MLX packages' \
		'make validate  — validate mlx / mlx-lm and run a fast computation check' \
		'make clean     — remove .venv (toolkit-owned environment); reports leftovers' \
		'make uninstall — same as make clean' \
		'make audit     — audit commit subjects for Conventional Commits' \
		'make lint      — run ShellCheck on repository shell scripts' \
		'make test      — run portable shell self-tests'

detect: ## Detect Apple Silicon hardware
	@$(SCRIPTS)/detect-apple-silicon.sh

install: ## Bootstrap MLX-native environment
	@$(SCRIPTS)/initial-build-mlx-native-media.sh

rebuild: ## Rebuild Python MLX environment
	@$(SCRIPTS)/rebuild-mlx-native-media.sh --force

validate: ## Validate MLX installation
	@$(SCRIPTS)/validate-mlx.sh

clean uninstall: ## Remove toolkit-owned .venv; do not uninstall Homebrew
	@$(SCRIPTS)/cleanup-mlx-native.sh --force

audit: ## Conventional Commits audit
	@$(SCRIPTS)/conventional-commits-audit.sh

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
	@tests/cleanup-mlx-native.test.sh
