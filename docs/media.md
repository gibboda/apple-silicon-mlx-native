# Media tooling (image, video, speech)

This repository installs **only deliberately selected** media dependencies. Gaps are documented instead of silently pulling non-MLX runtimes (especially PyTorch/MPS).

## Classification legend

| Class | Meaning |
| --- | --- |
| **PURE MLX** | Implemented on MLX; no PyTorch runtime required for inference |
| **MLX-FIRST / APPLE-SILICON NATIVE** | Targets Apple Silicon / Metal with MLX as primary path; verify transitive deps |
| **FALLBACK / NON-MLX** | Other stacks (PyTorch, CUDA ports, cloud APIs). **Not installed** by this toolkit |

---

## Speech / audio

| Path | Class | Status in this toolkit | Memory notes |
| --- | --- | --- | --- |
| [`mlx-audio`](https://github.com/Blaizzy/mlx-audio) | **PURE MLX** | **Selected** — installed by default bootstrap/rebuild | Small TTS/STT models can fit on 8 GB; keep other models unloaded |
| Cloud TTS/STT APIs | FALLBACK / NON-MLX | Not installed | N/A |
| PyTorch audio stacks | FALLBACK / NON-MLX | Not installed | Often large |

Bootstrap installs `mlx-audio` and Homebrew `ffmpeg` (encoding/decoding support). Extra TTS feature extras may be needed for some models; install those intentionally after reading upstream docs.

Example (after `source .venv/bin/activate`):

```bash
python -c "import mlx_audio; print('mlx-audio OK')"
```

---

## Text-to-image

| Path | Class | Status in this toolkit | Memory notes |
| --- | --- | --- | --- |
| [`mflux`](https://github.com/filipstrand/mflux) | **PURE MLX** generate path | **Opt-in** (`make install-image`) | 8 GB: FLUX.2 Klein **4B 4-bit**, 512², `--low-ram` (expect swap). Practical from ~16 GB+; many models want 24 GB+ |
| Diffusers + PyTorch/MPS | FALLBACK / NON-MLX | Not installed | Heavy; not MLX-native |
| Cloud image APIs | FALLBACK / NON-MLX | Not installed | N/A |

Why not default-install `mflux`?

- Large download and disk footprint (weights arrive on **first generate**).
- Peak unified-memory use often dwarfs LLM 3B–4B workloads.
- Unsafe default on 8 GB machines (swap thrash).

Install into an existing `.venv` (does not rebuild):

```bash
make install-image
```

Or at bootstrap/rebuild time:

```bash
MLX_INSTALL_IMAGE=1 make install
# or
MLX_INSTALL_IMAGE=1 make rebuild
```

Generate (defaults follow memory tier):

```bash
make image IMAGE_PROMPT="a red fox in snow"
# equivalent: scripts/generate-mlx-image.sh --prompt "a red fox in snow"
```

| Tier | Default family / model | Size / quant | Notes |
| --- | --- | --- | --- |
| ≤8 GB constrained | `flux2` / `flux2-klein-4b` | 4-bit, 512², 4 steps, `--low-ram` | Stop `mlx_lm.server` first; expect swap |
| ≤16 GB standard | `flux2` / `flux2-klein-4b` | 8-bit, 768² | Still tight with a loaded LLM |
| ≥24 GB | `z-image-turbo` | 8-bit, 1024², 9 steps | Higher quality default |

Override with `--family`, `--model`, `--quantize`, `--width`, `--height`, `--seed`, or `MLX_IMAGE_*` in `config/models.env`. Extra mflux flags go after `--`. PNGs land in `outputs/images/` (gitignored).

Upstream models and CLIs: [mflux](https://github.com/filipstrand/mflux). Current `mflux` still depends on `torch` for checkpoint loading (`safetensors.torch`); it does not use PyTorch/MPS to denoise. This toolkit does not install Diffusers+MPS image stacks.

---

## Text-to-video

| Path | Class | Status in this toolkit | Memory notes |
| --- | --- | --- | --- |
| Community MLX video ports (e.g. Wan-oriented MLX forks such as mlx-gen) | **MLX-FIRST / APPLE-SILICON NATIVE** | **Documented only — not installed** | Typically workstation-class RAM (often 32 GB+); verify each project’s deps |
| PyTorch video Diffusers | FALLBACK / NON-MLX | Not installed | Not in scope |
| Cloud video APIs | FALLBACK / NON-MLX | Not installed | N/A |

There is **no** default video package in this toolkit today. If you evaluate an MLX-first video project, install it in a **separate** venv first, confirm it does not pull PyTorch as a required runtime, and treat 8–16 GB machines as unsuitable.

---

## 8 GB machines

| Workload | Guidance |
| --- | --- |
| Speech (small models) | Possible with care; unload LLMs first |
| Image | Opt-in `mflux` only; constrained default is 4B 4-bit 512² with `--low-ram`. Expect swap. |
| Video | Not recommended |

---

## Policy

1. Scripts never install PyTorch as the LLM or image **generation** backend.
2. Opt-in `mflux` currently pulls `torch` because its weight loader uses `safetensors.torch`. Denoising still runs on MLX. Do not add Diffusers+MPS stacks.
3. README and docs must label Pure MLX vs MLX-first vs fallback clearly.
4. New media dependencies require an explicit rationale in the PR template checklist.
