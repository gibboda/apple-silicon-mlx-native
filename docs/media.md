# Media tooling (image, video, speech)

This repository installs **only deliberately selected** media dependencies. Gaps are documented instead of silently pulling non-MLX runtimes (especially PyTorch/MPS).

## Classification legend

| Class | Meaning |
| --- | --- |
| **PURE MLX** | Implemented on MLX; no PyTorch/MPS generation backend (opt-in `mflux` / Wan convert may pull `torch` for weight loading) |
| **MLX-FIRST / APPLE-SILICON NATIVE** | Targets Apple Silicon / Metal with MLX as primary path; verify transitive deps |
| **FALLBACK / NON-MLX** | Other stacks (PyTorch, CUDA ports, cloud APIs). **Not installed** by this toolkit |

---

## Speech / audio

| Path | Class | Status in this toolkit | Memory notes |
| --- | --- | --- | --- |
| [`mlx-audio`](https://github.com/Blaizzy/mlx-audio) | **PURE MLX** | **Selected** — installed by default bootstrap/rebuild | Small TTS/STT models can fit on 8 GB; keep other models unloaded |
| Cloud TTS/STT APIs | FALLBACK / NON-MLX | Not installed | N/A |
| PyTorch audio stacks | FALLBACK / NON-MLX | Not installed | Often large |

Bootstrap installs `mlx-audio` and Homebrew `ffmpeg` (encoding/decoding support). **`mlx`**, **`mlx-lm`**, and **`mlx-audio` are pinned** in `scripts/lib/common.sh` (`mlx==0.32.2`, `mlx-lm==0.31.3`, `mlx-audio==0.5.5`). Override a spec before install or rebuild, including an unpinned name to track upstream:

```bash
MLX_PACKAGE=mlx MLX_LM_PACKAGE=mlx-lm MLX_AUDIO_PACKAGE=mlx-audio make rebuild
```

Extra TTS feature extras may be needed for some models; install those intentionally after reading upstream docs.

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

- Large download and disk footprint: `make install-image` pulls a `torch` wheel (often hundreds of MB to a few GB) for safetensors loading, and weights arrive on **first generate**.
- Peak unified-memory use often dwarfs LLM 3B–4B workloads.
- Unsafe default on 8 GB machines (swap thrash).

Install into an existing `.venv` (does not rebuild). **`mflux` is pinned** to `0.19.1` by default (`MLX_IMAGE_PACKAGE` in `scripts/lib/common.sh`); override before install, e.g. `MLX_IMAGE_PACKAGE=mflux==0.20.0 make install-image`.

```bash
make install-image
```

Or at bootstrap/rebuild time:

```bash
MLX_INSTALL_IMAGE=1 make install
# or
MLX_INSTALL_IMAGE=1 make rebuild
```

Generate (defaults follow the composed profile: RAM tier + chip class):

```bash
make image IMAGE_PROMPT="a red fox in snow"
# equivalent: scripts/generate-mlx-image.sh --prompt "a red fox in snow"
```

| Memory / chip | Default family / model | Size / quant | Notes |
| --- | --- | --- | --- |
| constrained, or fanless Air | `flux2` / `flux2-klein-4b` | 4-bit, 512², 4 steps, `--low-ram` | This M1 is the floor; later Airs stay here for image |
| standard + slow / moderate (16 GB M1, M2/M3/M4 base) | `flux2` / `flux2-klein-4b` | 4-bit, 768², `--low-ram` | Same gate as LLM: needs `fast` throughput for 8-bit |
| standard + fast+ cooled (16 GB M5, 18 GB Pro) | `flux2` / `flux2-klein-4b` | 8-bit, 768² | 18 GB SKUs stay here; not the 24 GB `z-image-turbo` 1024² profile |
| high+ cooled (≥24 GB) | `z-image-turbo` | 8-bit, 1024², 9 steps | Higher quality default |

Override with `--family`, `--model`, `--quantize`, `--width`, `--height`, `--seed`, or `MLX_IMAGE_*` / `MLX_IMAGE_SEED` in `config/models.env`. **`--family` selects the mflux CLI and default checkpoint only**; width, height, steps, quantize, and `--low-ram` still follow the composed profile unless you set those flags or `MLX_IMAGE_*`. So `--family z-image-turbo` on 8 GB still uses 512² / 4 steps / 4-bit, not the ≥24 GB 1024² / 9-step profile.

Inspect the resolved plan without generating:

```bash
scripts/generate-mlx-image.sh --dump-plan --prompt "a red fox in snow"
OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled scripts/generate-mlx-image.sh --dump-plan --prompt "a red fox in snow"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=1 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled \
  scripts/generate-mlx-image.sh --dump-plan --prompt "plan"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled \
  scripts/generate-mlx-image.sh --dump-plan --prompt "plan"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled \
  scripts/generate-mlx-image.sh --dump-plan --prompt "plan"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro \
  OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  scripts/generate-mlx-image.sh --dump-plan --prompt "plan"
OVERRIDE_MEMORY_TIER=high OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro \
  OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  scripts/generate-mlx-image.sh --dump-plan --prompt "plan"
```

`--dump-plan` uses detected RAM/chip when `sysctl` works, honors `OVERRIDE_*` when set, and falls back to constrained / RAM-only when detection is unavailable (Linux CI). Extra mflux flags go after `--` (e.g. `GENERATE_IMAGE_ARGS='-- --vae-tiling'`). `GENERATE_IMAGE_ARGS` is split on whitespace and is not a shell command, so `;`, pipes, and quotes stay literal flag text. On constrained and standard memory tiers (and fanless), the generate wrapper adds `--vae-tiling` automatically unless you already pass it. Custom `--output` paths must resolve under `MLX_WORKSPACE`. PNGs land in `outputs/images/` (gitignored).

Upstream models and CLIs: [mflux](https://github.com/filipstrand/mflux). Current `mflux` still depends on `torch` for checkpoint loading (`safetensors.torch`); it does not use PyTorch/MPS to denoise. This toolkit does not install Diffusers+MPS image stacks.

---

## Text-to-video

| Path | Class | Status in this toolkit | Memory notes |
| --- | --- | --- | --- |
| [`mlx-video`](https://github.com/Blaizzy/mlx-video) (Blaizzy / Prince Canuma) | **PURE MLX** generate path | **Opt-in** (`make install-video`) | Wan2.1 **1.3B 4-bit** is the first profile (UMT5 encoder ~11 GB). Practical from ~24 GB+; 8 GB is out of scope. LTX-2 distilled is the ≥36 GB quality path |
| [`mlx-gen`](https://github.com/lpalbou/mlx-gen) (mflux fork, Wan2.2) | MLX-FIRST / APPLE-SILICON NATIVE | Documented specialist — **not installed** | Hard `torch` dep; collides with pinned `mflux`. Use a **separate** venv only |
| [`ltx-2-mlx`](https://github.com/dgrauet/ltx-2-mlx) | **PURE MLX**, LTX-only | Documented specialist — **not installed** | 32 GB+ recommended; not a small-model on-ramp |
| PyTorch video Diffusers | FALLBACK / NON-MLX | Not installed | Not in scope |
| Cloud video APIs | FALLBACK / NON-MLX | Not installed | N/A |

Why not default-install `mlx-video`?

- Peak unified-memory use dwarfs 3B–4B LLM workloads. Wan 1.3B still loads **UMT5-XXL** (~11 GB) plus VAE and diffusion scratch.
- Git-only package (pinned SHA); pulls `mlx-vlm`, `transformers`, OpenCV, librosa.
- Wan weights are **not** preconverted on Hugging Face in mlx-video layout. `scripts/prepare-mlx-video-wan.sh` converts `Wan-AI/Wan2.1-T2V-1.3B` and needs `torch` to load original `.pth` T5/VAE files. Denoising remains MLX.
- Unsafe default on 8–16 GB machines (swap thrash).

Install into an existing `.venv` (does not rebuild). **`mlx-video` is pinned** to git SHA `87db56a51758fefb748a359b90a5283bb8ba4837` by default (`MLX_VIDEO_PACKAGE` in `scripts/lib/common.sh`).

```bash
make install-video
make prepare-video   # Wan 1.3B 4-bit; once; needs torch in the venv
```

Before `make prepare-video`, run `huggingface-cli login` and accept the [Wan-AI/Wan2.1-T2V-1.3B](https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B) license on Hugging Face. Reuse `torch` from `make install-image` when present; otherwise install manually (see [troubleshooting.md](troubleshooting.md)).

Or at bootstrap/rebuild time:

```bash
MLX_INSTALL_VIDEO=1 make install
# or
MLX_INSTALL_VIDEO=1 make rebuild
```

`MLX_INSTALL_VIDEO=1` installs the package only; it does **not** download or convert Wan weights.

Generate (defaults follow the composed profile: RAM tier + chip class):

```bash
make video VIDEO_PROMPT="a red fox running through snow"
# equivalent: scripts/generate-mlx-video.sh --prompt "a red fox running through snow"
```

| Memory / chip | Default family / model | Size / frames | Notes |
| --- | --- | --- | --- |
| constrained, 16 GB slow/moderate base chips, or fanless | `wan21` / `wan21-t2v-1.3b-q4` | 832×480, 17 frames, 10 steps | Generate refuses unless `--force` (UMT5 ~11 GB). Do not advertise LTX |
| standard + fast cooled (16 GB M5, 18 GB Pro) | `wan21` / `wan21-t2v-1.3b-q4` | 832×480, 17 frames, 10 steps | Swap-heavy; stop `mlx_lm.server`. 18 GB stays on 17 frames, not the 24 GB 33-frame profile. RAM still too small for LTX |
| high cooled (24–32 GB) | `wan21` / `wan21-t2v-1.3b-q4` | 832×480, 33–49 frames | First practical Wan profile; 49 frames only when throughput is known, GPU cores ≥ 24, and (`very_fast` or M5+ NAX) — see [hardware tiers](hardware-tiers.md) |
| workstation cooled (≤64 GB) | `ltx2` / `prince-canuma/LTX-2-distilled` | 512², 33 frames | HF download on first generate; no Wan convert |
| large | `ltx2` / `prince-canuma/LTX-2-distilled` | 768×512, 65 frames | Quality path |

Override with `--family`, `--model`, `--model-dir`, `--model-repo`, `--width`, `--height`, `--frames`, `--steps`, `--seed`, `--pipeline`, or `MLX_VIDEO_*` / `MLX_VIDEO_SEED` in `config/models.env`. **`--family` selects the mlx-video module and default checkpoint only**; width, height, frames, steps, and tiling still follow the composed profile unless you set those flags or `MLX_VIDEO_*`. LTX pipeline defaults to `distilled` (`MLX_VIDEO_LTX_PIPELINE` or `--pipeline`). Dimensions/frames are then aligned to the family (Wan: 4n+1 frames; LTX: 8n+1 frames and 64px). So `--family ltx2` on 8 GB still starts from 832×480 / 17 frames: 832 is already 64-aligned, height snaps to 448, and 17 frames is already 8n+1 — not the workstation 512² / 33-frame profile.

On ≤8 GB, 16 GB slow/moderate base chips (M1, M2/M3/M4 base), and fanless Airs, `scripts/generate-mlx-video.sh` refuses to generate unless you pass `--force` or set `MLX_VIDEO_FORCE=1` (UMT5 ~11 GB). `--dump-plan` always works for inspecting defaults without generating.

Inspect the resolved plan without generating:

```bash
scripts/generate-mlx-video.sh --dump-plan --prompt "a red fox running through snow"
OVERRIDE_MEMORY_TIER=high OVERRIDE_THERMAL_CLASS=cooled scripts/generate-mlx-video.sh --dump-plan --prompt "a red fox running through snow"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=1 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled \
  scripts/generate-mlx-video.sh --dump-plan --prompt "plan"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=base OVERRIDE_THERMAL_CLASS=cooled \
  scripts/generate-mlx-video.sh --dump-plan --prompt "plan"
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro \
  OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  scripts/generate-mlx-video.sh --dump-plan --prompt "plan"
OVERRIDE_MEMORY_TIER=high OVERRIDE_CHIP_FAMILY=3 OVERRIDE_CHIP_SKU=pro \
  OVERRIDE_THERMAL_CLASS=cooled OVERRIDE_GPU_CORES=18 \
  scripts/generate-mlx-video.sh --dump-plan --prompt "plan"
```

`--dump-plan` uses detected RAM/chip when `sysctl` works, honors `OVERRIDE_*` when set, and falls back to constrained / RAM-only when detection is unavailable (Linux CI). Extra mlx-video flags go after `--` (e.g. `GENERATE_VIDEO_ARGS='-- --scheduler unipc'`). `GENERATE_VIDEO_ARGS` is split on whitespace and is not a shell command. Custom `--output` and `--image` paths must exist (for `--image`) and resolve under `MLX_WORKSPACE`. MP4s land in `outputs/videos/` (gitignored).

Wan generate fails until `models/video/wan21-t2v-1.3b-q4` contains `config.json`, `model.safetensors`, `t5_encoder.safetensors`, and `vae.safetensors`. Do not add `mlx-gen` to this venv (it is an mflux fork and fights pinned `mflux==0.19.1`).

`make clean` removes only `.venv`. Converted Wan weights under `models/video/` survive cleanup. To remove them: `rm -rf models/video` or `scripts/cleanup-mlx-native.sh --workspace-caches --force` (also drops other workspace caches such as `outputs/`).

---

## 8 GB machines

| Workload | Guidance |
| --- | --- |
| Speech (small models) | Possible with care; unload LLMs first |
| Image | Opt-in `mflux` only; constrained default is 4B 4-bit 512² with `--low-ram`. Expect swap. |
| Video | Refused by default on 8 GB, 16 GB slow/moderate base chips, and fanless Airs (generate wrapper exits unless `--force` / `MLX_VIDEO_FORCE=1`; UMT5 ~11 GB) |

---

## Policy

1. Scripts never install PyTorch as the LLM, image, or video **generation** backend.
2. Opt-in `mflux` currently pulls `torch` because its weight loader uses `safetensors.torch`. Denoising still runs on MLX. Do not add Diffusers+MPS stacks.
3. Opt-in `mlx-video` generation is MLX. Optional Wan conversion (`scripts/prepare-mlx-video-wan.sh`) needs `torch` to load original `.pth` T5/VAE files. Do not add `mlx-gen` to this venv.
4. README and docs must label Pure MLX vs MLX-first vs fallback clearly.
5. New media dependencies require an explicit rationale in the PR template checklist.
