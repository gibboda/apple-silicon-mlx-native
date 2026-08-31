# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Apple Silicon hardware detection with human, JSON, and env output modes (`scripts/detect-apple-silicon.sh`)
- Memory-tier classification (constrained → large-memory workstation) to drive model recommendations
- Initial MLX-native bootstrap (`scripts/initial-build-mlx-native-media.sh`) for Homebrew, venv, `mlx`, `mlx-lm`, and selected `mlx-audio`
- Reproducible environment rebuild (`scripts/rebuild-mlx-native-media.sh`)
- Fast MLX validation including arm64 Python, imports, array compute, and Metal observability (`scripts/validate-mlx.sh`)
- Conventional Commits audit script and pull-request workflow
- ShellCheck workflow and Makefile targets (`detect`, `install`, `rebuild`, `validate`, `audit`, `lint`, `help`)
- Documentation for architecture, hardware tiers, models, media tooling status, and troubleshooting
- Example model/server configuration (`config/models.example.env`)
- Repository governance: CODEOWNERS, pull request template, Keep a Changelog policy
- GitHub Actions workflow that deletes same-repo pull-request head branches after merge (`delete-merged-branch.yml`; skips forks, `main`/default, and stacked bases)

### Changed

- Relicensed from MIT to [GNU General Public License v3.0](LICENSE) (`SPDX-License-Identifier: GPL-3.0-only`)

### Deprecated

- N/A

### Removed

- N/A

### Fixed

- Conventional Commits CI no longer fails on GitHub Actions PR merge commits (`Merge <sha> into <sha>`); audit range uses `AUDIT_HEAD_SHA` instead of reserved `GITHUB_SHA`
- Quote `detect-apple-silicon.sh --env` values for safe sourcing
- Use two-dot commit ranges for PR/base audits so base-only commits are not included
- Abort bootstrap when Homebrew is the Intel `/usr/local` prefix on Apple Silicon
- Correct PR template Conventional Commits link to repository-root `README.md`

### Security

- Reject Intel/x86_64 hosts and discourage Rosetta-only Homebrew/Python paths on the normal install flow
- Never use `sudo pip`; isolate packages in a project virtual environment
