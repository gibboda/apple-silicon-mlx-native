# Troubleshooting

## Architecture rejected (Intel / x86_64)

```text
ERROR: Apple Silicon (arm64) required.
```

This toolkit only supports Apple Silicon macOS. Use an M-series Mac, or a different stack on Intel hardware.

## Not macOS (Linux ARM / other kernels)

```text
ERROR: Apple Silicon macOS (Darwin arm64) required.
```

`assert_apple_silicon` and `scripts/detect-apple-silicon.sh --quiet` require Darwin, not only `uname -m == arm64`. Linux ARM hosts fail immediately instead of dying later on `sysctl`. Portable `--dump-plan` / OVERRIDE fixtures still skip that live-host check.

## Homebrew missing

Install Apple Silicon Homebrew (`/opt/homebrew`), then re-run `make install`.

To let the bootstrap script install Homebrew:

```bash
MLX_INSTALL_HOMEBREW=1 make install
```

If `brew` resolves to `/usr/local` on an arm64 Mac, you may be on an Intel Homebrew prefix (often via Rosetta). Prefer `/opt/homebrew`.

## Xcode Command Line Tools missing

```bash
xcode-select --install
```

Re-run `make install` after the installer finishes.

## `make validate` fails: mlx not importable

```bash
make rebuild
make validate
```

Confirm the venv Python is arm64:

```bash
.venv/bin/python -c 'import platform; print(platform.machine())'
```

Expected: `arm64`.

## Metal status inconclusive or unavailable

- Ensure you are on Apple Silicon macOS with recent updates.
- Quit other GPU-heavy apps and retry.
- Reinstall MLX inside the venv: `make rebuild`.

## Out-of-memory / heavy swap during generation

- Drop to a smaller 4-bit model (see [models.md](models.md)).
- Reduce max tokens / context (`MLX_RECOMMENDED_CONTEXT`; pass `--max-kv-size` to `mlx_lm.generate`).
- Run a single persistent `mlx_lm.server` instead of loading models repeatedly.
- Close browsers and other large apps.
- On 8 GB / fanless M1, avoid 7B+ models and image/video tooling.
- Confirm `make detect` working-set is near Metal `max_recommended_working_set_size` (~5.33 GB on 8 GB M1).

## Model download failures

- Check network access to Hugging Face.
- Ensure disk headroom (`make detect`). See [Low disk space](#low-disk-space-before-install-or-download) below.
- Set `HF_TOKEN` if accessing gated repos (never commit tokens).

## Low disk space before install or download

`make detect` prints free GiB on the workspace volume. Before selected media installs and large downloads, scripts warn when free space is under a floor. They do not delete Hugging Face caches, `models/`, or `.venv` to make room.

| Profile | Default floor | When |
| --- | --- | --- |
| `media-pip` | 4 GiB | `mlx-audio` during `make install` / `make rebuild` |
| `image-pip` | 8 GiB | `make install-image` (mflux and its torch wheel) |
| `video-pip` | 8 GiB | `make install-video` |
| `image-weights` | 12 GiB | `make image` (skipped for `--dump-plan`) |
| `video-weights` | 20 GiB | `make video` (skipped for `--dump-plan`) |
| `wan-prepare` | 40 GiB | `make prepare-video` (upstream snapshot plus converted copy) |

Override a floor with `MLX_DISK_MIN_MEDIA_GIB`, `MLX_DISK_MIN_IMAGE_GIB`, `MLX_DISK_MIN_VIDEO_GIB`, `MLX_DISK_MIN_IMAGE_WEIGHTS_GIB`, `MLX_DISK_MIN_VIDEO_WEIGHTS_GIB`, or `MLX_DISK_MIN_WAN_GIB`. `MLX_DISK_ENFORCE=1` aborts instead of warning. `MLX_SKIP_DISK_CHECK=1` skips the check. `MLX_DISK_AVAIL_GIB` overrides the measured free space (whole GiB).

## ShellCheck not found locally

```bash
brew install shellcheck
make lint
```

## Conventional Commits audit fails

Subjects must match:

```text
<type>[optional-scope][!]: <description>
```

Allowed types: `feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`.

GitHub merge commits are exempt by default. See `scripts/conventional-commits-audit.sh --help`.

## Install refused to reuse `.venv`

`make install` will not reuse a directory that is not a complete virtualenv. It requires both `pyvenv.cfg` and `bin/python` (or `bin/python3`). A half-created tree — for example after a crashed `python -m venv` — may have only one of those markers; remove or rename that path, then re-run `make install`. `make rebuild` and `make clean` still use the looser `looks_like_venv` check (either marker is enough to identify a venv for removal).

A venv must resolve under `MLX_WORKSPACE`. To keep the environment outside the clone, set `MLX_WORKSPACE` to that enclosing directory (and optionally `MLX_VENV` under it). `MLX_VENV` alone pointing outside the workspace is rejected.

## Rebuild refused to delete `.venv`

The rebuild script only removes a path that looks like a virtualenv under the workspace. Check `MLX_WORKSPACE` / `MLX_VENV` and re-run with `--force` via `make rebuild`.

## Cleanup / uninstall

```bash
make clean
# or: make uninstall
scripts/cleanup-mlx-native.sh --dry-run
```

Default cleanup only removes `.venv`. It **does not** uninstall Homebrew, Xcode Command Line Tools, or brew formulae (`python@3.12`, `git`, `ffmpeg`).

To also drop local config and workspace caches (`models/`, `.cache/`, and other gitignored output dirs):

```bash
scripts/cleanup-mlx-native.sh --purge --force
```

Downloaded models usually live in the Hugging Face hub cache (`~/.cache/huggingface/hub`, or `$HF_HUB_CACHE`). That directory is shared with other tools, so cleanup only reports its size unless you opt in:

```bash
scripts/cleanup-mlx-native.sh --huggingface-cache --keep-venv --force
```

`--huggingface-cache` removes the **hub** (weights), not `HF_HOME` tokens/config.

If cleanup refuses a path, it is protecting you: the target is outside the workspace, does not look like a venv, is the committed `models.example.env`, resolves through `..` to a location outside the workspace, or is too shallow / is `HF_HOME` (tokens) rather than the hub cache. Non-interactive runs require `--force` (`make clean` passes it).

Stop `mlx_lm.server` (and any other process using `.venv`) before removing the environment.

## Text-to-image (`mflux`) missing or generate fails

Install into the existing venv (does not rebuild):

```bash
make install-image
make validate
```

Then:

```bash
make image IMAGE_PROMPT="a red fox in snow"
```

On 8 GB, stop `mlx_lm.server`, close browsers and other large apps, and keep the constrained defaults (FLUX.2 Klein 4B, 4-bit, 512px, `--low-ram`). The wrapper also enables `--vae-tiling` on constrained and standard tiers unless you pass it yourself. For explicit control:

```bash
make image IMAGE_PROMPT="a red fox in snow" GENERATE_IMAGE_ARGS='-- --vae-tiling'
```

`GENERATE_IMAGE_ARGS` is split on whitespace. Semicolons, pipes, and quotes are literal flag text, not a shell command.

First generate downloads several GB of weights. If the process is killed or the machine swaps heavily, drop `--width`/`--height` further or wait until you have more unified memory.

If generate fails with `'flux2-klein-4b' is not Tongyi-MAI/Z-Image-Turbo`, the wrapper mixed families. Use one family only:

```bash
scripts/generate-mlx-image.sh --prompt "a red fox in snow"              # FLUX.2 Klein 4B on 8 GB
scripts/generate-mlx-image.sh --prompt "a red fox in snow" --family z-image-turbo
```

`--family` does not switch to the high-tier size/steps. On 8 GB, `--family z-image-turbo` still uses the constrained 512² / 4-step / 4-bit profile unless you also pass `--width`/`--height`/`--steps`/`--quantize`. Check the plan with `--dump-plan` before a long download.

Do not pass `--model flux2-klein-4b` with `--family z-image-turbo`.

`mflux` is not a default bootstrap package. See [media.md](media.md).

## Text-to-video (`mlx-video`) missing or generate fails

Install into the existing venv (does not rebuild):

```bash
make install-video
make validate
```

Wan2.1 1.3B (default on ≤32 GB) also needs a converted MLX directory:

```bash
huggingface-cli login   # accept Wan-AI/Wan2.1-T2V-1.3B license on Hugging Face first
# Conversion loads original .pth T5/VAE with torch (not a generation backend).
# Reuse torch from make install-image when present; otherwise:
.venv/bin/pip install 'torch==2.14.0'
make prepare-video
```

Then:

```bash
make video VIDEO_PROMPT="a red fox running through snow"
```

On 8 GB, generate is refused unless you pass `--force` or `MLX_VIDEO_FORCE=1` (UMT5 ~11 GB). On 16 GB, stop `mlx_lm.server`, close browsers, and keep the short 17-frame 832×480 plan. Check the plan first:

```bash
scripts/generate-mlx-video.sh --dump-plan --prompt "a red fox running through snow"
```

If generate fails with `Wan MLX model directory is not ready`, run `make prepare-video`. `--family` does not switch to the workstation LTX size/frames. On 8 GB, `--family ltx2` still starts from the constrained 832×480 / 17-frame profile (height snaps to 448).

Do not pass `--model wan21-t2v-1.3b-q4` with `--family ltx2`.

Do not `pip install mlx-gen` into this venv; it is an mflux fork and collides with pinned `mflux`.

`make clean` removes `.venv` only. Converted Wan weights under `models/video/` are kept. Remove with `rm -rf models/video` or `scripts/cleanup-mlx-native.sh --workspace-caches --force`.

`mlx-video` is not a default bootstrap package. See [media.md](media.md).
