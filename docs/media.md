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
| [`mflux`](https://github.com/filipstrand/mflux) | **PURE MLX** | **Opt-in only** (`MLX_INSTALL_IMAGE=1`) | Practical from ~16 GB+; many models want 24 GB+ |
| Diffusers + PyTorch/MPS | FALLBACK / NON-MLX | Not installed | Heavy; not MLX-native |
| Cloud image APIs | FALLBACK / NON-MLX | Not installed | N/A |

Why not default-install `mflux`?

- Large download and disk footprint.
- Peak unified-memory use often dwarfs LLM 3B–4B workloads.
- Unsafe default on 8 GB machines (swap thrash).

Opt in:

```bash
MLX_INSTALL_IMAGE=1 make install
# or
MLX_INSTALL_IMAGE=1 make rebuild
```

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
| Image | Generally avoid; opt-in `mflux` only if you accept swap risk |
| Video | Not recommended |

---

## Policy

1. Scripts never install PyTorch as part of the normal MLX media path.
2. README and docs must label Pure MLX vs MLX-first vs fallback clearly.
3. New media dependencies require an explicit rationale in the PR template checklist.
