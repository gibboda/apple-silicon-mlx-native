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
