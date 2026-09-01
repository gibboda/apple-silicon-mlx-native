# Troubleshooting

## Architecture rejected (Intel / x86_64)

```text
ERROR: Apple Silicon (arm64) required.
```

This toolkit only supports Apple Silicon. Use an M-series Mac, or a different stack on Intel hardware.

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
- Reduce max tokens / context.
- Run a single persistent `mlx_lm.server` instead of loading models repeatedly.
- Close browsers and other large apps.
- On 8 GB, avoid 7B+ models and image/video tooling.

## Model download failures

- Check network access to Hugging Face.
- Ensure disk headroom (`make detect`).
- Set `HF_TOKEN` if accessing gated repos (never commit tokens).

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
