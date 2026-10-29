#!/usr/bin/env bash
# GNU Make recipes must run under bash -eu -o pipefail on Make 3.81 (macOS).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=tests/lib/assert.sh
source "${TEST_LIB}/assert.sh"

wrapper="${ROOT}/scripts/lib/make-recipe-shell.sh"
expect_ok "make-recipe-shell wrapper is executable" test -x "${wrapper}"

# Recipe shell flags (errexit, nounset, pipefail) via the repo Makefile SHELL wiring.
set +e
make -C "${ROOT}" -f Makefile -f - _mlx_strict_shell_probe >/dev/null 2>&1 <<'EOF'
.PHONY: _mlx_strict_shell_probe
_mlx_strict_shell_probe:
	@case "$$-:" in *e*) ;; *) exit 11;; esac
	@case "$$-:" in *u*) ;; *) exit 12;; esac
	@if set -o | grep -Eq '^pipefail[[:space:]]+on'; then :; else exit 13; fi
EOF
probe_rc=$?
set -e
case "${probe_rc}" in
  0) pass "make recipes run under errexit, nounset, and pipefail" ;;
  11) fail "make recipe shell missing errexit (-e)" ;;
  12) fail "make recipe shell missing nounset (-u)" ;;
  13) fail "make recipe shell missing pipefail" ;;
  *) fail "make strict shell probe failed (exit ${probe_rc})" ;;
esac

# Unbound variables in recipes must fail (guards against silent Make 3.81 .SHELLFLAGS gap).
set +e
make -C "${ROOT}" -f Makefile -f - _mlx_nounset_fail >/dev/null 2>&1 <<'EOF'
.PHONY: _mlx_nounset_fail
_mlx_nounset_fail:
	@echo "$${MLX_MAKE_TEST_UNSET_VAR:?}"
EOF
nounset_rc=$?
set -e
if [[ "${nounset_rc}" -ne 0 ]]; then
  pass "make recipe nounset rejects unset variables"
else
  fail "make recipe nounset did not reject unset variable"
fi

assert_finish "make-recipe-shell"
