# Models

Prefer models from the [`mlx-community`](https://huggingface.co/mlx-community) Hugging Face organization.

## Memory identity

```text
model weights
+ KV cache
+ runtime allocations
+ macOS / system memory
= real unified-memory requirement
```

**Do not** treat the on-disk model file size as total RAM consumption. KV-cache cost grows with context length and batch size; runtime scratch and macOS baseline often consume multiple gigabytes before your prompt starts.

**RAM is the OOM fence; chip class is the performance fence.** See [hardware-tiers.md](hardware-tiers.md). Chip throughput must never raise a default past unified memory (Wan UMT5 ~11 GB still cannot run on 8 GB).

## CLI and server

```bash
source .venv/bin/activate
source config/models.env  # if present; provides MLX_DEFAULT_MODEL and MLX_RECOMMENDED_CONTEXT
# Generate wrappers parse MLX_* assignments from this file (they do not source/execute it).

# One-shot generation
mlx_lm.generate \
  --model "${MLX_DEFAULT_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}" \
  --prompt "Explain unified memory in one paragraph." \
  --max-tokens 128 \
  --max-kv-size "${MLX_RECOMMENDED_CONTEXT:-2048}"

# Persistent OpenAI-compatible server (preferred)
mlx_lm.server \
  --model "${MLX_DEFAULT_MODEL:-mlx-community/Llama-3.2-3B-Instruct-4bit}" \
  --host 127.0.0.1 \
  --port 8080
  # Add --max-kv-size "${MLX_RECOMMENDED_CONTEXT}" when mlx_lm.server supports that flag.
```

Example client call:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community/Llama-3.2-3B-Instruct-4bit",
    "messages": [{"role": "user", "content": "Hello from MLX"}],
    "max_tokens": 64
  }'
```

Keeping one model resident in `mlx_lm.server` avoids repeated weight load latency and reduces churn on unified memory. Cap client-side context to `MLX_RECOMMENDED_CONTEXT` when the server has no context flag.

## Recommended matrix

Figures are **approximate** and intended for planning. Measure on your machine before raising context or quantization.

| Model ID | Quantization | Approx. weights memory | Expected KV-cache impact | Recommended RAM tier | Context recommendation | Swap risk | Expected use |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | 4-bit | ~2.0–2.5 GB | Low–moderate; grows with context | constrained+ | 1k–2k on 8 GB / fanless; 4k+ on fast 16 GB+ | Low on 8 GB if context stays short | Default chat on 8 GB and 16 GB slow/moderate (M1–M4 base) |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | 4-bit | ~0.8–1.2 GB | Low | constrained+ | 2k–4k | Very low | Ultra-light prompts, classification |
| `mlx-community/Phi-3.5-mini-instruct-4bit` | 4-bit | ~2.2–2.8 GB | Low–moderate | constrained+ | 1k–2k on 8 GB | Low–moderate | Compact instruct / coding assist |
| `mlx-community/Qwen2.5-3B-Instruct-4bit` | 4-bit | ~2.0–2.6 GB | Low–moderate | constrained+ | 1k–2k on 8 GB | Low | Multilingual / general chat |
| `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | 4-bit | ~4.0–5.0 GB | Moderate | standard+ on **fast cooled** chips (tight on 8 GB / 16 GB slow/moderate) | ≤1k on 8 GB only if measured; 2k–4k on 16 GB+ | **High on 8 GB**; tight on 16 GB M1–M4 base | Default on 16 GB M5-class; optional on 16 GB slow/moderate |
| `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit` | 4-bit | ~4.5–5.5 GB | Moderate | standard+ fast cooled | 2k–4k on 16 GB+ | High on 8 GB; moderate on 16 GB | General 8B workloads |
| `mlx-community/Qwen2.5-14B-Instruct-4bit` | 4-bit | ~8–10 GB | Moderate–high | high+ **very_fast** (Max 32 GB) | 2k–8k | High below 24 GB | Heavier reasoning / coding |
| `mlx-community/Qwen2.5-32B-Instruct-4bit` | 4-bit | ~18–20 GB | High | workstation+ / large | 2k–8k | Severe below 36 GB | Large single-model server |

### Defaults by composed profile

| Memory tier | Chip class | Default model | `MLX_RECOMMENDED_CONTEXT` |
| --- | --- | --- | --- |
| constrained (≤8 GB) | any, including this M1 | `mlx-community/Llama-3.2-3B-Instruct-4bit` | 2048 |
| standard (≤18 GB / `< 24` GB) | slow / moderate (16 GB M1, M2/M3/M4 base) | `mlx-community/Llama-3.2-3B-Instruct-4bit` | 2048 |
| standard (≤18 GB / `< 24` GB) | fast+ cooled (16 GB M5, 18 GB Pro) | `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | 4096 |
| high (24–32 GB) | not very_fast | `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | 4096 |
| high (24–32 GB) | very_fast (Max) | `mlx-community/Qwen2.5-14B-Instruct-4bit` | 8192 |
| workstation (≤64 GB) | any | `mlx-community/Qwen2.5-14B-Instruct-4bit` | 8192 |
| large (>64 GB) | extreme / RAM-only | `mlx-community/Qwen2.5-32B-Instruct-4bit` | 8192 |
| unknown chip | RAM-only fallback | Same as that memory tier without a fast+ upgrade (standard = 3B / 2048) | Same as slow/moderate at that RAM |

Fanless Airs keep the RAM-only default model and context at 2048 even when RAM/throughput would otherwise raise them.

Print a fresh profile without writing `models.env`:

```bash
make recommend
scripts/detect-apple-silicon.sh --json
```

## 8 GB limitations

- Prefer **3B–4B 4-bit** unless your own measurements support something larger.
- A 7B 4-bit weight footprint alone can leave almost no room for KV cache + macOS.
- Avoid concurrent large apps, multiple loaded models, or long contexts.
- Image/video generation is generally impractical; see [media.md](media.md). Video’s UMT5 encoder is ~11 GB even for Wan 1.3B 4-bit.

## Updating local defaults

```bash
make recommend                          # composed profile for *this* Mac
cp config/models.example.env config/models.env
# edit MLX_DEFAULT_MODEL / MLX_RECOMMENDED_CONTEXT
```

`config/models.env` is preserved on `make rebuild`. After moving a clone to another Mac, re-run `make recommend` so you do not keep a stale `MLX_DEFAULT_MODEL`.
