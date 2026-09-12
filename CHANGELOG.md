# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Chip-aware Apple Silicon defaults: detect family/SKU, GPU cores, thermal class, and look up bandwidth to compose LLM/image/video recommendations with existing RAM tiers (`make detect`, `make recommend`)
- `MLX_RECOMMENDED_CONTEXT` is a real exported default; bootstrap seeds it into `config/models.env` (rebuild never overwrites that file)
- Portable chip parser/compose fixtures in `tests/chip-profile.test.sh`

### Changed

- Image/video generate wrappers compose defaults from RAM + throughput + thermal class; 16 GB M1 stays conservative while 16 GB M5 may use 7B / 768² 8-bit
- Video generate also refuses on 16 GB base M1 and fanless Airs unless `--force` (UMT5 ~11 GB)
- `make validate` probes `mx.device_info()` and applies wired/memory/cache limits from the Metal recommended working set on constrained machines

## [0.1.0] - 2026-09-11

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
- GitHub Actions workflow that deletes same-repo pull-request head branches after merge (`delete-merged-branch.yml`; skips forks, `main`/default, stacked bases, and refs that no longer match the merged head SHA)
- Conservative uninstall/cleanup for toolkit-owned state (`scripts/cleanup-mlx-native.sh`, `make clean` / `make uninstall`) with `--dry-run`, `--keep-venv`, `--purge`, leftover reporting, and an opt-in Hugging Face hub cache removal; Homebrew and Xcode CLT are never uninstalled
- Portable cleanup self-test (`tests/cleanup-mlx-native.test.sh`, `make test`)
- Opt-in Pure MLX text-to-image via `mflux` (`make install-image`, `make image IMAGE_PROMPT=...`) with memory-tier defaults (8 GB: FLUX.2 Klein 4B 4-bit 512² `--low-ram`). `mflux` currently pulls `torch` for safetensors weight loading; denoising remains MLX.
- Opt-in Pure MLX text-to-video via `mlx-video` (`make install-video`, `make video VIDEO_PROMPT=...`) with memory-tier defaults (≤32 GB: Wan2.1 T2V 1.3B 4-bit 832×480; ≥36 GB: LTX-2 distilled). Pinned to git SHA `87db56a51758fefb748a359b90a5283bb8ba4837`. Wan conversion (`scripts/prepare-mlx-video-wan.sh`) needs `torch` to load original `.pth` files; generation remains MLX.

### Changed

- Relicensed from MIT to [GNU General Public License v3.0](LICENSE) (`SPDX-License-Identifier: GPL-3.0-only`)
- Pin opt-in `mflux` to `0.19.1` by default (`MLX_IMAGE_PACKAGE` in `scripts/lib/common.sh`; override with env)
- LTX text-to-video pipeline is configurable via `MLX_VIDEO_LTX_PIPELINE` / `--pipeline` (default `distilled`) instead of hardcoded in the generate wrapper

### Fixed

- Refuse mlx-video generate on ≤8 GB unless `--force` or `MLX_VIDEO_FORCE=1`; require `ffmpeg`, validate `--image` under `MLX_WORKSPACE`, and add `make prepare-video`
- Conventional Commits CI no longer fails on GitHub Actions PR merge commits (`Merge <sha> into <sha>`); audit range uses `AUDIT_HEAD_SHA` instead of reserved `GITHUB_SHA`
- Quote `detect-apple-silicon.sh --env` values for safe sourcing
- Use two-dot commit ranges for PR/base audits so base-only commits are not included
- Abort bootstrap when Homebrew is the Intel `/usr/local` prefix on Apple Silicon
- Correct PR template Conventional Commits link to repository-root `README.md`
- Canonicalize cleanup/rebuild removal paths so `..` cannot escape the workspace; `--huggingface-cache` refuses `HF_HOME` (tokens/config) and parent directories
- Do not pass the constrained FLUX.2 default model into `mflux-generate-z-image-turbo` when `--family z-image-turbo` is set
- Require custom `--output` paths to resolve under `MLX_WORKSPACE` (prevents path escape via symlinks or `..`)
- `--dump-plan` follows detected memory tier (or `OVERRIDE_MEMORY_TIER`) instead of always assuming constrained; print size/steps/`vae_tiling` and validate custom `--output` without generating
- ShellCheck workflow posts a job named `ShellCheck` (required by Protect main) and always runs on pull requests so path filters cannot leave the check waiting

### Security

- Reject Intel/x86_64 hosts and discourage Rosetta-only Homebrew/Python paths on the normal install flow
- Never use `sudo pip`; isolate packages in a project virtual environment

[Unreleased]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gibboda/apple-silicon-mlx-native/releases/tag/v0.1.0
