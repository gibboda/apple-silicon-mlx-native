# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Pin **`huggingface-hub`** back to **1.33.0**. `mflux==0.23.0` requires `huggingface-hub>=1.1.6,<2.0`, so the 2.x constraint (`2.2.0` in #120, `2.3.0` in #124) makes `make install-image` fail with `ResolutionImpossible`. `transformers==5.20.2` still accepts 1.33.0 (`>=1.31.0,<3.0`). Dependabot ignores `huggingface-hub` >=2 until mflux allows hub 2.x. CI runs `uv pip compile` for the mflux stack on darwin arm64 (Python 3.12–3.14) when `uv` is available
- Keep `_pin_default` fallbacks in `scripts/lib/common.sh` aligned with `requirements/constraints.txt`; extend `tests/pip-constraints.test.sh` to fail on drift
- Scope GitHub Actions `contents: write` to the publish-release and delete-merged-branch jobs (workflow default is `contents: read`)
- Guard `rm -rf` on `MLX_VENV` in `scripts/rebuild-mlx-native-media.sh` with `${MLX_VENV:?}`

### Changed

- Bump **`mlx-vlm`** from 0.7.4 to 0.7.10 in `requirements/constraints.txt` (#122)
- Bump **`mlx-lm`** from 0.32.0 to 0.32.2 in `requirements/constraints.txt` (#121)
- Bump **`huggingface-hub`** from 1.33.0 to 2.2.0 in `requirements/constraints.txt` (#120)
- Add `.github/actionlint.yaml` for the self-hosted `xcode-27` runner label
- Bump **`pillow`** from 12.3.0 to **13.0.0** in `requirements/constraints.txt`; install **`mlx_pillow_numbers_compat`** into the venv on every pip install path (`make install`, `make rebuild`, media/image/video installers) when the pin is 13+ so Pillow/mflux imports work on CPython 3.12+
- Remove Dependabot **`pillow >=13`** ignore now that the compat shim covers every constrained venv (not image-only)

### Security

- Bump **`pillow`** to **13.0.0** in `requirements/constraints.txt` — fixes **41** Dependabot/OSV advisories that patched only in Pillow 13.0.0 (GHSA/CVE list below). **`mlx_pillow_numbers_compat`** keeps Pillow/mflux imports working on CPython 3.12+ until upstream drops the `numbers._IntegralLike` import ([#123](https://github.com/gibboda/apple-silicon-mlx-native/pull/123); docs-only audit in [#119](https://github.com/gibboda/apple-silicon-mlx-native/pull/119)).
- Fixed advisories ( **`pillow` 12.3.0 → 13.0.0** ):
  - GHSA-v9pv-5gc8-w2m6 / CVE-2026-96639 (severity 9.8)
  - GHSA-332p-7hrc-92wf / CVE-2026-112393 (severity 9.2)
  - GHSA-5x8w-8jj5-q52h / CVE-2026-112398 (severity 9.2)
  - GHSA-8g5g-8vmr-9782 / CVE-2026-112403 (severity 9.2)
  - GHSA-w889-685w-c8fh / CVE-2026-112900 (severity 9.2)
  - GHSA-c6hw-5grf-ff96 / CVE-2026-112404 (severity 8.8)
  - GHSA-pchr-8j38-3x4p / CVE-2026-112896 (severity 8.8)
  - GHSA-xvh5-g6gv-559v / CVE-2026-112902 (severity 8.8)
  - GHSA-58r4-6rv3-gfh8 / CVE-2026-112397 (severity 8.7)
  - GHSA-5xm2-6676-qcp9 / CVE-2026-112399 (severity 8.7)
  - GHSA-65qm-jvmh-6pqg / CVE-2026-112400 (severity 8.7)
  - GHSA-7mwm-ghpf-9vrm / CVE-2026-112402 (severity 8.7)
  - GHSA-cp9v-662q-vvx9 / CVE-2026-112405 (severity 8.7)
  - GHSA-f2g6-542v-9j58 / CVE-2026-112406 (severity 8.7)
  - GHSA-gg2r-wvfm-q9rx / CVE-2026-112892 (severity 8.7)
  - GHSA-jg86-v3jv-hrpm / CVE-2026-112894 (severity 8.7)
  - GHSA-p4wg-p73j-c528 / CVE-2026-112895 (severity 8.7)
  - GHSA-q45j-58j2-45rg / CVE-2026-112897 (severity 8.7)
  - GHSA-22hg-r758-rrw9 / CVE-2026-112390 (severity 8.2)
  - GHSA-27h8-gf7j-v5hc / CVE-2026-112392 (severity 8.2)
  - GHSA-j4m9-6w36-pw47 / CVE-2026-112893 (severity 8.2)
  - GHSA-mrfp-p49p-3hf2 / CVE-2026-96640 (severity 8.2)
  - GHSA-78g4-xqwv-q3g8 / — (severity 8.1)
  - GHSA-g7cr-3p24-7wf7 / CVE-2026-96778 (severity 7.7)
  - GHSA-3j72-p6qg-6xp7 / CVE-2026-96642 (severity 7.1)
  - GHSA-9v9v-9qvf-h2hj / CVE-2026-96644 (severity 7.1)
  - GHSA-g4qv-2jxx-769h / CVE-2026-96643 (severity 7.1)
  - GHSA-g842-9rc4-69pw / CVE-2026-96637 (severity 7.1)
  - GHSA-74r2-7ff9-mjj2 / CVE-2026-112401 (severity 6.9)
  - GHSA-fc9g-5qg7-mf45 / CVE-2026-112891 (severity 6.9)
  - GHSA-rfgq-q3w2-pmv2 / CVE-2026-112898 (severity 6.9)
  - GHSA-vx6w-vv9f-6gvg / CVE-2026-112899 (severity 6.9)
  - GHSA-xgh8-jp6q-p5x8 / CVE-2026-112901 (severity 6.9)
  - GHSA-24rc-8hj2-v98c / CVE-2026-96638 (severity 6.5)
  - GHSA-462x-pgg6-55fp / CVE-2026-112395 (severity 6.5)
  - GHSA-4rm8-3hmm-39fg / CVE-2026-96641 (severity 6.5)
  - GHSA-p8hx-v2p6-rp84 / CVE-2026-96636 (severity 6.5)
  - GHSA-254f-3936-288h / CVE-2026-112391 (severity 6.3)
  - GHSA-4558-3h8r-v8xp / CVE-2026-112394 (severity 6.3)
  - GHSA-654x-cwwv-5j9c / CVE-2026-114501 (severity 6.3)
  - GHSA-4rr5-89j8-mwwm / CVE-2026-112396 (severity 5.9)

## [0.4.1] - 2026-10-25

### Changed

- Bump **`mflux`** from 0.22.0 to 0.23.0 in `requirements/constraints.txt` (#112)
- Bump **`transformers`** from 5.19.0 to 5.20.2 in `requirements/constraints.txt` (#113)
- Bump **`mlx-audio`** from 0.5.8 to 0.6.1 in `requirements/constraints.txt` (#116)
- Bump **`pip`** from 26.2.1 to 26.2.2 in `requirements/constraints.txt` (#115)
- Bump **`setuptools`** from 84.1.0 to 84.2.1 in `requirements/constraints.txt` (#114)

### Fixed

- Restore the **`pillow==12.3.0`** pin in `requirements/constraints.txt`. The v0.4.0 tag shipped **`pillow==13.0.0`**, which breaks `import mflux` on Python 3.12+ (`ImportError` from `PIL._typing`). Re-run `make install-image` to apply the pin in an existing `.venv` (#111)
- Dependabot ignores **`pillow` >=13** so the pin is not bumped back accidentally (#111)

## [0.4.0] - 2026-10-24

### Breaking

- Require **macOS 26 or newer** on **Apple Silicon** for `make doctor`, `make detect`, `make venv`, and `make install`; macOS 14–15 are refused with a clear error. Versions newer than CI smoke (macOS 27 today) log a non-fatal warning

### Changed

- Bump **`setuptools`** from 84.0.0 to 84.1.0 in `requirements/constraints.txt` (#104)

### Fixed

- Document pinning **`pillow==12.3.0`** so `make image` can import mflux (Pillow 13.0.0 imports `numbers._IntegralLike`, which CPython 3.12+ stdlib does not define). The **v0.4.0 tag actually shipped `pillow==13.0.0`**; the **`pillow==12.3.0`** pin landed in **0.4.1** (#111)

## [0.3.1] - 2026-10-23

### Added

- Shell self-tests for supported `MLX_PYTHON_VERSION` range (3.12–3.14) and exact major.minor venv matching (guards against `3.1` matching `3.12`)
- Required GitHub Actions macOS smoke job on **`xcode-27`** (macOS 27 Golden Gate) alongside `macos-latest`

### Changed

- Bump **`mlx`** and **`mlx-metal`** to **0.32.4** (macOS 27 / Xcode 27 SDK fixes); pin **`mlx-metal`** in `requirements/constraints.txt`
- Enforce **`MLX_PYTHON_VERSION`** in the supported **3.12–3.14** range at `make venv` / `make install` / `make rebuild`; compare venv `pyvenv.cfg` version by exact major.minor
- Refuse **`make venv`** / **`make install`** on macOS major versions below **14**

### Fixed

- An **`MLX_PACKAGE`** override retargets **`mlx-metal`** to the same exact version, or drops that pin when the spec is not `mlx==version`, so the Metal backend is not left on the manifest release

## [0.3.0] - 2026-10-22

### Breaking

- `make install` now requires CPython 3.12–3.14. Pinning `numpy==2.5.4` drops Python 3.10 and 3.11; `mlx==0.32.2` and torch 2.14.x still have no cp315 wheels

### Added

- `requirements/constraints.txt` with MLX core pins and key transitive pins (`transformers`, `numpy`, `huggingface-hub`, `mlx-vlm`, `torch`). Every pip install path exports `PIP_CONSTRAINT` via `mlx_pip_install` so media installs cannot float core MLX packages. Dependabot watches `requirements/` for pip updates. `core-pip` disk headroom (default 12 GiB, `MLX_DISK_MIN_CORE_GIB`) runs before core installs in `make install` / `make rebuild`
- `tests/common-golden.test.sh` with composed-profile fixtures and `tests/regen-common-golden.sh` to refresh golden output for detect, catalog lists, and wrapper `--dump-plan`

### Changed

- Split `scripts/lib/common.sh` into cohesive modules (`ui`, `detect`, `policy`, `policy_fit_rules`, `catalog`, `envfile`, `venv`) with `common.sh` as the aggregator; centralize text catalog fit labels and composed text defaults in `policy_fit_rules.sh`. Move the `release.sh` Python re-exec helper to `scripts/lib/release_notes.py`
- Bump mlx-lm to 0.32.0
- Bump torch to 2.14.1
- Bump mlx-audio to 0.5.8
- Bump mflux to 0.22.0. Same-seed images change for `schnell` (FLUX.1 norm bias restored) and `z-image-turbo` (bf16 transformer; use `GENERATE_IMAGE_ARGS='-- --float32' make image` or `scripts/generate-mlx-image.sh ... -- --float32` to reproduce older images). New transitive floors: urllib3>=2.8.0, fsspec>=2026.6.0 (security)
- Pin `numpy==2.5.4`
- CI runs the full portable test suite on macOS with `/bin/bash` 3.2, audits PR titles for Conventional Commits, pins ShellCheck v0.11.0, limits duplicate ShellCheck runs on same-repo PR pushes, and serializes release publishing
- Document Python version policy in `docs/troubleshooting.md`: default Homebrew `python@3.12`, pinned `mlx` macOS arm64 wheels through CPython 3.14 (3.15 blocked until upstream ships `cp315` wheels), optional `MLX_PYTHON_VERSION=3.13` trial (`export`, rollback, macOS 14+ / torch wheel notes), README link, and a non-stale pointer comment at `MLX_PYTHON_VERSION`
- Shell self-tests share `tests/lib/assert.sh` (`expect_line`, `skip`, subshell-safe `expect_fail`). Wrapper argv is recorded via fake CLIs in `tests/wrapper-argv.test.sh`. Plan `key=value` checks use exact-line matching so mutations like `steps=40` no longer pass when asserting `steps=4`
- README: fix frame range, commit ranges, Make targets, quickstart, and output nits

### Fixed

- Non-interactive `make rebuild` now requires `--force`. `models.env` upsert preserves file mode and symlinks. Venv create lock timeout extended. Homebrew prefix matching fixed. Merged-PR branch delete skips protected branches. `mlx_lm --help` probe is captured before grep
- `make list-image` reports `cached yes` only when every diffusers weight component (transformer or UNet, text encoders, VAE) has non-empty shards, not when a partial tree or zero-byte shard is present. `make list` applies the same non-empty rule to indexed text-model shards
- Honor user `MLX_RECOMMENDED_CONTEXT` from the process environment or `config/models.env` after chip policy compose; process env now wins over `models.env` for allowlisted keys. Precedence table in `docs/models.md`
- `make image`, `make video`, and `make generate-text` pass the prompt through unchanged. Backticks, `$VAR`, `$(...)`, quotes, backslashes, and newlines stay literal on macOS Make 3.81. Make strips leading whitespace from a `VAR=value` command-line assignment; set the variable in the environment instead (e.g. `IMAGE_PROMPT='  text' make image`) to keep it
- Image and video generation reject a non-integer width, height, frames, steps, quantize, or seed from the command line, the environment, or `config/models.env` before arithmetic and before venv setup. Width, height, frames, and steps must be from 1 to 999999 so bash arithmetic cannot wrap them. Quantize must be 3, 4, 5, 6, or 8. Seed, when set, must be a non-negative integer and is printed by `--dump-plan`

## [0.2.10] - 2026-10-05

### Fixed

- MacBook Air model identifiers after M1 are fanless. Apple Support lists M2–M4 as `Mac14,2`, `Mac14,15`, `Mac15,12`, `Mac15,13`, `Mac16,12`, and `Mac16,13`. `Mac17,3` and `Mac17,4` are included from third-party M5 Air listings. A 16 GB Air stays on the 3B / 2048 / 512² 4-bit profile instead of the cooled fast path
- `make clean --purge` and `--workspace-caches` refuse `$HOME`, a parent of `$HOME`, and system roots such as `/`, `/Users`, and `/opt`, including with `--force`. The same refusal covers the macOS canonical forms `/private/var/tmp`, `/private/etc`, `/System/Volumes/Data`, and `/Users/Shared`. They also refuse a directory that is not this repository checkout and has no `.mlx-workspace` marker. A look-alike tree that only contains a `Makefile` and `scripts/lib/common.sh` is not this checkout. A workspace `.cache` that contains the Hugging Face cache or `HF_HOME` is left in place, including when `.cache` is a symlink. Top-level `huggingface/` and `.huggingface/` trees that hold `hub/` or `token` are left in place too. `--huggingface-cache` remains the only way to remove the hub cache. `--force` still prints the path list before removing anything

### Changed

- `make venv`, `make install`, and `make rebuild` write `.mlx-workspace` when `MLX_WORKSPACE` is a dedicated directory outside the clone. Docs tell you not to point `MLX_WORKSPACE` at `$HOME`

## [0.2.9] - 2026-10-02

### Added

- GitHub Actions runs an Apple Silicon smoke job on `macos-latest`: Darwin `arm64`, `detect-apple-silicon.sh --quiet`, parseable `--json`, `make recommend`, and `tests/host-safety.test.sh`. It does not download models or install MLX packages
- `make venv` (`scripts/create-mlx-venv.sh`) creates `.venv` with Homebrew `python@3.12` only. It does not install MLX packages, `git`, or `ffmpeg`, and it does not seed `config/models.env`
- `make list` (`detect-apple-silicon.sh --list`) prints this Mac's chip, RAM tier, and composed default, then labels each catalog **text** model `default`, `fits`, `tight`, or `poor`, and `cached` `yes` or `no` when the Hugging Face cache holds `config.json` and every on-disk weight shard for that repo. It does not download weights or write `config/models.env`
- `make list-image` and `make list-video` (`--list-image`, `--list-video`) do the same for the image and video catalogs. `default` is the composed checkpoint. Image `cached` is the preset's upstream Hugging Face repo (a `model_index.json` or `config.json` plus a safetensors file, and no incomplete blob). Wan `cached` is the converted `models/video/` directory. LTX `cached` is the distilled snapshot: every transformer, text-encoder, and VAE-decoder shard, text projections, and a spatial x2 upscaler. Nothing is downloaded and `config/models.env` is not written

### Fixed

- `detect-apple-silicon.sh --json` emits JSON on macOS via `scripts/lib/detect_json.py`; `log_warn` writes to stderr so chip-policy warnings no longer corrupt redirected `--json` stdout on GitHub Actions
- Chained `EXIT` traps during atomic venv create preserve the status that triggered cleanup, so a caller trap that reads `$?` still sees the original failure
- `make venv` keeps a caller's `EXIT` trap. The atomic create still removes its own temporary directory on failure, then runs the trap that was already installed. A successful create restores that trap instead of clearing it
- `make venv` and `make install` refuse a tree whose `bin/pip` script does not run, including a shebang that still points at a removed `.venv.partial.<pid>` interpreter. `python -m pip` alone is not enough to reuse that tree
- `make venv` does not claim `.venv` when `mv` nests the temporary directory inside a destination that appeared during the rename. It removes that nested temporary directory and leaves the foreign tree in place
- `make venv` rewrites the temporary `.venv.partial.<pid>` path out of `bin/pip`, `bin/activate`, and `pyvenv.cfg` before renaming that directory to `.venv`. `make clean` also removes a leftover `.venv.partial.<pid>` directory when that pid is not running and no live `.venv.create-lock` is held. The rename used to leave the temporary path in place, so activating the environment showed `(.venv.partial.<pid>)` and `make install` failed because `pip` still pointed at a missing interpreter. Overlapping creates take a per-destination lock, leave another run's in-use temporary directory alone, and remove `.venv` only after this run has renamed its own tree into place. If `.venv` appears while a partial tree is still building, the create stops instead of nesting the partial inside it or deleting unrelated files
- `make venv` creates `.venv` atomically (partial dir + pip check before rename), refuses to reuse a foreign or broken venv (wrong Python version, non-Homebrew `pyvenv.cfg` home, missing pip, or dangling `bin/python`), and reports broken interpreter symlinks with a `make rebuild` hint
- `make list-video` no longer reports a finished `prince-canuma/LTX-2-distilled` snapshot as not cached, and it does not treat one root `ltx-2-*.safetensors` file as a complete download
- `make list-image` labels FLUX.1 schnell `tight` on a 24–32 GB fanless Air, the same as `z-image-turbo`
- Catalog cache checks read safetensors index shards without `mapfile`, so a complete cache stays `cached yes` on macOS `/bin/bash` 3.2

### Changed

- The README repository tree lists the current text generation, server, release, and test paths. `tests/readme-tree.test.sh` fails when that tree drifts from the tracked files
- `make install`, `make install-image`, and `make install-video` refuse to install unless `.venv` already has `pyvenv.cfg`, an executable `bin/python`, and pip. They do not create the venv and do not require the shell to be activated. Pip still runs as `.venv/bin/pip`. Fresh clones run `make venv` once before `make install`. An existing complete `.venv` is unchanged
- Pin bootstrap packaging tools to `pip==26.2.1`, `setuptools==84.1.0`, `wheel==0.48.0`, and `packaging==26.3` (`MLX_PIP_PACKAGE`, `MLX_SETUPTOOLS_PACKAGE`, `MLX_WHEEL_PACKAGE`, `MLX_PACKAGING_LIB_PACKAGE`). Install, rebuild, and image/video installers share those pins and export `PIP_BUILD_CONSTRAINT` so PEP 517 isolated builds (for example git `mlx-video`) use the same specs. `make validate` reports the installed versions and warns only when an exact pin does not match
- Pin `actions/checkout` to the v7.0.1 commit SHA in GitHub workflows (Node 24 runtime; persisted credentials now live under `$RUNNER_TEMP`)
- Docs and help text describe `make list` as the full text catalog with fit labels (including `poor`), not only models that fit. The models matrix notes that 7B is `poor` on 8 GB in `make list`, matching the RAM fence

## [0.2.8] - 2026-09-27

### Fixed

- `generate-mlx-text.sh` and `serve-mlx.sh` reject invalid max tokens, KV size, temperature, and server port before launch, including values passed after `--` and an empty assignment. Max tokens and KV size must be positive integers, temperature must be a finite non-negative number when set, and the port must be an integer from 1 to 65535. A malformed configured `MLX_RECOMMENDED_CONTEXT` fails even though the composed default still sets the KV cap unless `--max-kv-size` is passed

## [0.2.7] - 2026-09-26

### Added

- `scripts/generate-mlx-text.sh` and `scripts/serve-mlx.sh` (`make generate-text`, `make serve`): on physical ≤8 GB RAM, pin MLX to the GPU and set memory and wired limits to the Metal working set with a 256 MiB cache cap before weights load. `OVERRIDE_MEMORY_TIER` changes model and context recommendations only. If Metal or the working set cannot be applied, the launch stops; a wired-limit error still keeps the memory and cache limits. Larger machines keep MLX defaults. Image and video paths are unchanged
- Free-space warning before `mlx-audio`, image/video package installs, Wan snapshot conversion, and image/video generation (`MLX_DISK_ENFORCE=1` aborts; `MLX_SKIP_DISK_CHECK=1` skips; caches are not deleted)
- Portable self-tests for merged-branch deletion and the Conventional Commits audit

### Changed

- Pin `mlx==0.32.2`, `mlx-lm==0.31.3`, and `mlx-audio==0.5.5` (`MLX_PACKAGE`, `MLX_LM_PACKAGE`, `MLX_AUDIO_PACKAGE`; set a spec to the bare name to track upstream)
- Pin `actions/checkout` to the v4.4.0 commit SHA in GitHub workflows

### Fixed

- `make image` / `make video` pass `GENERATE_IMAGE_ARGS` / `GENERATE_VIDEO_ARGS` as whitespace-separated flags without shell evaluation
- A caller-supplied `MLX_DISK_AVAIL_GIB` survives hardware detection, and weight/prepare disk checks measure the Hugging Face hub cache (Wan prepare uses the tighter of that cache and the workspace)
- Wan video generation checks the workspace and local model directory, not the hub cache (LTX still checks the hub cache)
- Local image checkpoints (`--model` or `MLX_IMAGE_MODEL` path) check the workspace, not the hub cache (preset and Hugging Face repo generates still check the hub cache)

## [0.2.6] - 2026-09-23

### Fixed

- `detect-apple-silicon.sh --env` exports composed `MLX_RECOMMENDED_IMAGE_PROFILE`, `MLX_RECOMMENDED_VIDEO_PROFILE`, and `MLX_VIDEO_FORCE_REQUIRED` (parity with `--json` / `--recommend`)

## [0.2.5] - 2026-09-22

### Fixed

- Initial build refuses to reuse an incomplete `.venv` (requires both `pyvenv.cfg` and `bin/python`/`bin/python3`); rebuild/cleanup still accept either marker via `looks_like_venv`
- `config/models.env` is parsed as `MLX_*` assignments (not sourced as bash); writes quote values that need it, skip `PATH`/`HF_TOKEN`/runtime identity keys without logging values, and expand a leading unquoted `~/`

## [0.2.4] - 2026-09-20

### Added

- Image/video `--dump-plan` OVERRIDE fixtures lock 18 GB M3 Pro on 768² 8-bit / 17-frame Wan (`force_required=0`) and 24 GB high M3 Pro on 1024² / 33 frames

### Fixed

- `assert_apple_silicon` and `detect --quiet` require Darwin arm64, so Linux ARM fails with a not-macOS error instead of a later `sysctl` failure
- Initial build validates workspace/venv paths before Homebrew, refuses to reuse a non-venv `.venv`, and requires `MLX_VENV` under `MLX_WORKSPACE`

## [0.2.3] - 2026-09-19

### Fixed

- `scripts/release.sh` no longer duplicates the changelog title and preamble when moving `[Unreleased]` into a version heading
- `make release` / `scripts/release.sh` publish by opening a `chore/release-x.y.z` pull request from the CHANGELOG patch bump (they never push protected `main`); after that PR merges (squash or merge commit), the tag and GitHub Release are created on the merge result
- `scripts/release.sh --dry-run --no-push` previews a local commit+tag only; the plan no longer claims it would push or create a GitHub Release

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

[Unreleased]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.10...v0.3.0
[0.2.10]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.9...v0.2.10
[0.2.9]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.8...v0.2.9
[0.2.8]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/gibboda/apple-silicon-mlx-native/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gibboda/apple-silicon-mlx-native/releases/tag/v0.1.0
