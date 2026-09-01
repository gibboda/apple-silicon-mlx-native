# apple-silicon-mlx-native

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Reproducible toolkit for installing, rebuilding, validating, and operating a **pure Apple Silicon MLX-native** machine-learning environment.

## Purpose

Bootstrap a workstation that prioritizes:

1. `mlx`
2. `mlx-lm`
3. [MLX Community](https://huggingface.co/mlx-community) models
4. `mlx_lm.server`
5. MLX-native speech/audio where appropriate (`mlx-audio`)
6. MLX image tooling where practical (opt-in `mflux`)
7. MLX video tooling where practical (**documented**, not default-installed)

**Not in scope:** Ollama, `llama.cpp`, or PyTorch/MPS as a core dependency.

## Why MLX-native

MLX targets unified memory and Metal on Apple Silicon. This toolkit standardizes a small, auditable install path so local LLM (and selected media) workloads stay **native** instead of routing through generic cross-platform stacks. See [docs/architecture.md](docs/architecture.md).

### Pure MLX vs MLX-first vs fallback

| Class | Meaning | This repo |
| --- | --- | --- |
| **Pure MLX** | MLX runtime; no PyTorch required | `mlx`, `mlx-lm`, `mlx-audio`; optional `mflux` |
| **MLX-first / Apple Silicon native** | Primary path is MLX/Metal; verify deps | Video community ports — **documented only** |
| **Fallback / non-MLX** | Other runtimes | **Not advertised as native; not installed** |

## Supported hardware

- macOS on **Apple Silicon** (`arm64`) only
- Intel/x86_64 Macs are **rejected** with a clear error
- Memory tiers drive recommendations (8 GB → large-memory workstation) without hard-blocking overrides

Details: [docs/hardware-tiers.md](docs/hardware-tiers.md).

## Requirements

- Apple Silicon Mac
- Xcode Command Line Tools
- Homebrew (script can install with `MLX_INSTALL_HOMEBREW=1`)
- Network access to install packages and (later) download models

## Quick start

```bash
git clone https://github.com/gibboda/apple-silicon-mlx-native.git
cd apple-silicon-mlx-native
make detect
make install
make validate
```

## Initial installation

```bash
make install
# equivalent: scripts/initial-build-mlx-native-media.sh
```

The bootstrap script verifies `arm64`, detects chip/memory tier, ensures Homebrew packages (`python@3.12`, `git`, `ffmpeg`), creates `.venv`, installs `mlx`, `mlx-lm`, and selected `mlx-audio`, then validates.

Optional:

```bash
MLX_INSTALL_HOMEBREW=1 make install   # install Homebrew if missing
MLX_SKIP_MEDIA=1 make install         # skip mlx-audio
MLX_INSTALL_IMAGE=1 make install      # opt-in Pure MLX image (mflux)
```

## Environment rebuild

```bash
make rebuild
# equivalent: scripts/rebuild-mlx-native-media.sh --force
```

Recreates `.venv`, reinstalls packages, validates, and runs a small MLX computation. Preserves `config/models.env` when present.

## Validation

```bash
make validate
```

Checks native arm64 Python, `mlx` / `mlx-lm` imports, versions, basic array compute, and Metal observability. Non-zero on required failures.

## Hardware detection

```bash
make detect
scripts/detect-apple-silicon.sh --json
scripts/detect-apple-silicon.sh --env
```

## LLM inference

```bash
source .venv/bin/activate
mlx_lm.generate \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit \
  --prompt "Hello from MLX" \
  --max-tokens 64
```

Model matrix and memory notes: [docs/models.md](docs/models.md).

## Persistent `mlx_lm.server`

Prefer one long-lived server so weights stay resident (lower latency, less memory churn than reload-per-prompt):

```bash
source .venv/bin/activate
source config/models.env  # if present
mlx_lm.server \
  --model "${MLX_DEFAULT_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}" \
  --host 127.0.0.1 \
  --port 8080
```

OpenAI-compatible example:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community/Llama-3.2-3B-Instruct-4bit",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 64
  }'
```

Do **not** use Ollama as an API compatibility layer for this toolkit.

## MLX Community models

Use Hugging Face repos under [`mlx-community`](https://huggingface.co/mlx-community). Convert or quantize others with `mlx_lm.convert` when needed (advanced).

## Model / memory recommendations

Real requirement:

```text
weights + KV cache + runtime + macOS ≈ unified memory needed
```

On-disk size ≠ RAM use. Defaults by tier (see [docs/models.md](docs/models.md)):

| Tier | Default posture |
| --- | --- |
| ≤8 GB constrained | 3B–4B 4-bit, short context |
| ≤16 GB standard | 3B–8B 4-bit |
| ≤32 GB high | 7B–14B 4-bit |
| ≤64 GB workstation | 14B–32B 4-bit |
| >64 GB large | 30B+ quantized |

## 8 GB Apple Silicon limitations

- Prefer ~3B–4B **4-bit** models.
- Keep context conservative.
- Avoid concurrent heavy apps and multiple loaded models.
- Treat 7B+ and image/video as high swap risk.

## Image generation

**Pure MLX:** `mflux` (opt-in only). Not installed by default.

```bash
MLX_INSTALL_IMAGE=1 make rebuild
```

See [docs/media.md](docs/media.md). Unsuitable as a default on 8 GB.

## Video generation

No default install. Community **MLX-first** video ports exist but need separate evaluation (memory + dependencies). Documented in [docs/media.md](docs/media.md); not silently installed.

## Repository structure

```text
apple-silicon-mlx-native/
├── .github/
│   ├── CODEOWNERS
│   ├── pull_request_template.md
│   └── workflows/
│       ├── conventional-commits.yml
│       ├── delete-merged-branch.yml
│       └── shellcheck.yml
├── config/
│   └── models.example.env
├── docs/
│   ├── architecture.md
│   ├── hardware-tiers.md
│   ├── media.md
│   ├── models.md
│   └── troubleshooting.md
├── scripts/
│   ├── lib/common.sh
│   ├── initial-build-mlx-native-media.sh
│   ├── rebuild-mlx-native-media.sh
│   ├── detect-apple-silicon.sh
│   ├── validate-mlx.sh
│   ├── conventional-commits-audit.sh
│   └── delete-merged-pr-branch.sh
├── .gitignore
├── CHANGELOG.md
├── LICENSE
├── Makefile
└── README.md
```

`scripts/lib/common.sh` holds shared detection/tier helpers (engineering reason for the extra path).

## Make targets

| Target | Action |
| --- | --- |
| `make help` | Describe commands |
| `make detect` | Hardware detection |
| `make install` | Initial bootstrap |
| `make rebuild` | Recreate `.venv` |
| `make validate` | MLX validation |
| `make audit` | Conventional Commits audit |
| `make lint` | ShellCheck |

## Conventional Commits policy

Subjects must match:

```text
<type>[optional-scope][!]: <description>
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

Examples:

```text
feat: add Apple Silicon hardware detection
feat(mlx): add environment validation
docs(models): document 8 GB recommendations
ci(commits): enforce conventional commits
```

## Conventional Commits audit

```bash
make audit
scripts/conventional-commits-audit.sh --range origin/main...HEAD
```

GitHub Actions runs the same script on pull requests. GitHub-generated merge commits are exempt by default. Full syntax: `scripts/conventional-commits-audit.sh --help`.

## CHANGELOG / release policy

- Follow [Keep a Changelog](https://keepachangelog.com/) in `CHANGELOG.md`
- Use Semantic Versioning for tagged releases
- Record user-visible work under `[Unreleased]` during development
- On release: move `[Unreleased]` notes into a versioned section and tag

## CODEOWNERS

Default owner: `@gibboda` (see `.github/CODEOWNERS`).

## Merged pull request branches

When a pull request is **merged**, `.github/workflows/delete-merged-branch.yml` deletes the head branch in this repository. It skips forks, never deletes `main` (or the repository default/base branch), leaves the branch in place if another open PR still uses it as a base (stacked PRs), skips deletion when the ref no longer points at the merged head SHA, and treats a confirmed already-deleted ref (`Reference does not exist`) as success.

This is the in-repo guarantee. GitHub’s repository setting “Automatically delete head branches” may also be enabled; the workflow still succeeds if the branch is already gone.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Security / safety considerations

- Never commit `.venv`, model weights, HF tokens, or `config/models.env`
- `mlx_lm.server` is a local development server with basic checks — bind to `127.0.0.1` unless you intentionally expose it
- Do not use `sudo pip`
- Review new dependencies for PyTorch or unexpected native code before adding them
- Generated model outputs can be wrong or unsafe; treat local models like any other untrusted software capability

## License

[GNU General Public License v3.0](LICENSE) — Copyright (C) 2026 Dona Gibbons (gibboda).

`SPDX-License-Identifier: GPL-3.0-only`
