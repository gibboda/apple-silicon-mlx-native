# Architecture

This repository is a **toolkit**, not an inference server product. It standardizes how an Apple Silicon Mac becomes a reproducible **MLX-native** ML workstation.

## Why MLX-native

Apple Silicon exposes a unified memory architecture and a Metal GPU. [MLX](https://github.com/ml-explore/mlx) is designed for that stack: arrays live in unified memory, ops run on Metal, and the Python API stays close to NumPy/PyTorch ergonomics without requiring CUDA or a discrete GPU.

Priorities for this toolkit:

1. Prefer **Pure MLX** packages (`mlx`, `mlx-lm`, selected `mlx-audio`, optional `mflux` / `mlx-video`).
2. Prefer models published by [`mlx-community`](https://huggingface.co/mlx-community).
3. Prefer a **persistent** `mlx_lm.server` process over repeatedly loading weights.
4. Reject Intel/x86_64 Macs and Rosetta-only package paths on the normal install flow.
5. Keep the dependency graph small; document gaps instead of silently installing PyTorch/MPS stacks.

## What this is not

| Avoided by default | Why |
| --- | --- |
| Ollama | Separate runtime; not required for MLX-native operation |
| `llama.cpp` | Different stack; out of scope for this toolkit |
| PyTorch + MPS as a core dependency | Cross-platform fallback, not Pure MLX |
| Rosetta/x86 wheels | Defeat Apple Silicon native performance |

## Layering

```text
┌─────────────────────────────────────────────┐
│  Clients (curl, OpenAI SDK, local agents)   │
├─────────────────────────────────────────────┤
│  mlx_lm.server  (OpenAI-compatible HTTP)    │
│  mlx_lm.generate / Python mlx-lm API        │
├─────────────────────────────────────────────┤
│  mlx-lm  +  mlx-community model weights     │
├─────────────────────────────────────────────┤
│  mlx  (Metal / unified memory)              │
├─────────────────────────────────────────────┤
│  macOS + Apple Silicon                      │
└─────────────────────────────────────────────┘
```

Optional media layers (speech/image/video) sit beside the LLM path. Only **deliberately selected** packages are installed by bootstrap scripts. See [media.md](media.md).

## Workspace layout

By default the workspace is the repository root:

```text
apple-silicon-mlx-native/
  .venv/                 # Python environment (gitignored; removed by cleanup)
  config/models.env      # local overrides (gitignored; kept unless --config/--purge)
  scripts/               # bootstrap, rebuild, cleanup, image, video, detect, validate, audit
  docs/                  # deep documentation
```

Override `MLX_WORKSPACE` when you want the environment outside the clone. `MLX_VENV` must stay under that workspace (default `$MLX_WORKSPACE/.venv`); pointing `MLX_VENV` outside it is rejected.

Cleanup (`scripts/cleanup-mlx-native.sh`) is the reverse of **toolkit-owned** state, not a full workstation uninstall. Homebrew, Xcode Command Line Tools, and brew formulae stay installed; Hugging Face hub caches are reported unless `--huggingface-cache` is passed.

## Script responsibilities

| Script | Role |
| --- | --- |
| `detect-apple-silicon.sh` | Hardware facts, chip class, memory tier, composed defaults (`--recommend`) |
| `initial-build-mlx-native-media.sh` | First-time bootstrap; seeds `models.env` from the composed profile |
| `rebuild-mlx-native-media.sh` | Recreate `.venv` safely; never clobbers existing `models.env` |
| `install-mlx-image.sh` | Opt-in `mflux` into the existing venv |
| `generate-mlx-image.sh` | Text-to-image via mflux with composed chip+RAM defaults |
| `install-mlx-video.sh` | Opt-in `mlx-video` into the existing venv |
| `prepare-mlx-video-wan.sh` | Download + convert Wan2.1 1.3B to MLX 4-bit (torch for .pth load only) |
| `generate-mlx-video.sh` | Text-to-video via mlx-video with composed chip+RAM defaults |
| `cleanup-mlx-native.sh` | Remove `.venv` and optional caches; never Homebrew |
| `validate-mlx.sh` | Fast correctness checks plus `mx.device_info()` working-set limits |
| `conventional-commits-audit.sh` | Commit subject policy |

Shared helpers live in `scripts/lib/common.sh` so detection and compose logic stay consistent. **RAM is the OOM fence; chip class is the performance fence.** Unknown chips warn and fall back to RAM-only defaults; install does not fail. See [hardware-tiers.md](hardware-tiers.md).

## Memory accounting (design constraint)

Unified memory is shared by the OS, apps, model weights, KV cache, and framework scratch space:

```text
model weights
+ KV cache
+ runtime allocations
+ macOS / system memory
= real unified-memory requirement
```

On-disk model size is **not** total RAM use. Model guidance in [models.md](models.md) and [hardware-tiers.md](hardware-tiers.md) is built around this identity.
