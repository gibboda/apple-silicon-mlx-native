# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.2] - 2026-09-19

### Added

- `scripts/release.sh` / `make release` cuts SemVer from `[Unreleased]` by patch-bumping the latest CHANGELOG heading (optional `VERSION=` / `--minor` / `--major`; annotated tag; no push by default; `--push` requires `gh` up front)

### Fixed

- Linux/no-sysctl detect keeps `MLX_PHYSICAL_TIER_LABEL` as physical RAM, so an `OVERRIDE_MEMORY_TIER` no longer looks like installed memory
- Unknown `OVERRIDE_MEMORY_TIER`, `OVERRIDE_CHIP_SKU`, `OVERRIDE_THERMAL_CLASS`, or non-numeric `OVERRIDE_CHIP_FAMILY` values fail instead of silently mapping to the 8 GB path
- mlx-video self-test outside-workspace image fixture uses a per-run temp path instead of a shared `/tmp` file
- README no longer repeats the hardware-tiers details line
- Document GPU NAX only as a `high`-tier Wan frame bump (33→49 when GPU cores ≥ 24), not as an image-default upgrade
- README and models tables describe the `standard` memory tier as ≤18 GB (`< 24` GB), matching `classify_memory_tier`
- Disable markdownlint MD024 on Keep a Changelog repeated `Added`/`Changed`/`Fixed` headings
- `python3 scripts/release.sh` re-execs bash instead of raising a SyntaxError

# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-09-17

### Fixed

- 18 GB Macs stay on the `standard` (16 GB conservative) memory tier; `high` now starts at 24 GB so image/video do not recommend the 24 GB profile on 18 GB unified memory
- Fanless 16 GB machines stay on the RAM-only 3B default model; throughput no longer upgrades them to 7B
- `classify_memory_tier` no longer emits a leading space on the large-memory (`>64 GB`) label
- Document JSON/env detect output as `scripts/detect-apple-silicon.sh --json` / `--env` (`make detect` does not forward those flags)
- `detect-apple-silicon.sh --env` / `--json` keep `MLX_TIER_ID` / `memory_tier_id` as the policy tier and emit physical RAM as `MLX_PHYSICAL_TIER_ID` / `physical_memory_tier_id`, so sourcing `--env` cannot wipe `OVERRIDE_MEMORY_TIER`

## [0.2.0] - 2026-09-12

### Added

- Chip-aware Apple Silicon defaults: detect family/SKU, GPU cores, thermal class, and look up bandwidth to compose LLM/image/video recommendations with existing RAM tiers (`make detect`, `make recommend`)
- `MLX_RECOMMENDED_CONTEXT` is a real exported default; bootstrap seeds it into `config/models.env` (rebuild never overwrites that file)
- Portable chip parser/compose fixtures in `tests/chip-profile.test.sh`

### Changed

- Image/video gates now match LLM: 8-bit image and video without `--force` require `fast` throughput; 16 GB M2/M3/M4 base (`moderate`) stay on 3B / 768² 4-bit / `--force` like 16 GB M1
- Document throughput bandwidth buckets as half-open ranges (`100 ≤ bw < 150` moderate, `150 ≤ bw < 300` fast) to match `classify_throughput_class`
- Video generate also refuses on 16 GB slow/moderate base chips and fanless Airs unless `--force` (UMT5 ~11 GB)
- `make validate` probes `mx.device_info()` and the wired/memory/cache limit APIs from the Metal recommended working set; generate wrappers do not inherit those process-local limits

### Fixed

- Unknown 16 GB chips use the conservative RAM-only path (3B, context 2048, 4-bit image), not the fast 8-bit / 4096 defaults
- Video install warning and generate `--force` copy cover 16 GB slow/moderate base chips (M1–M4), not only M1

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

[Unreleased]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gibboda/apple-silicon-mlx-native/releases/tag/v0.1.0
