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

## CLI and server

```bash
source .venv/bin/activate

# One-shot generation
mlx_lm.generate \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit \
  --prompt "Explain unified memory in one paragraph." \
  --max-tokens 128

# Persistent OpenAI-compatible server (preferred)
mlx_lm.server \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit \
  --host 127.0.0.1 \
  --port 8080
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

Keeping one model resident in `mlx_lm.server` avoids repeated weight load latency and reduces churn on unified memory.

## Recommended matrix

Figures are **approximate** and intended for planning. Measure on your machine before raising context or quantization.

| Model ID | Quantization | Approx. weights memory | Expected KV-cache impact | Recommended RAM tier | Context recommendation | Swap risk | Expected use |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | 4-bit | ~2.0–2.5 GB | Low–moderate; grows with context | constrained+ | 1k–2k on 8 GB; 4k+ on 16 GB+ | Low on 8 GB if context stays short | Default chat / tooling on 8–16 GB |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | 4-bit | ~0.8–1.2 GB | Low | constrained+ | 2k–4k | Very low | Ultra-light prompts, classification |
| `mlx-community/Phi-3.5-mini-instruct-4bit` | 4-bit | ~2.2–2.8 GB | Low–moderate | constrained+ | 1k–2k on 8 GB | Low–moderate | Compact instruct / coding assist |
| `mlx-community/Qwen2.5-3B-Instruct-4bit` | 4-bit | ~2.0–2.6 GB | Low–moderate | constrained+ | 1k–2k on 8 GB | Low | Multilingual / general chat |
| `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | 4-bit | ~4.0–5.0 GB | Moderate | standard+ (tight on 8 GB) | ≤1k on 8 GB only if measured; 2k–4k on 16 GB+ | **High on 8 GB** | Stronger instruct on 16 GB+ |
| `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit` | 4-bit | ~4.5–5.5 GB | Moderate | standard+ | 2k–4k on 16 GB+ | High on 8 GB; moderate on 16 GB | General 8B workloads |
| `mlx-community/Qwen2.5-14B-Instruct-4bit` | 4-bit | ~8–10 GB | Moderate–high | high+ | 2k–4k | High below 24 GB | Heavier reasoning / coding |
| `mlx-community/Qwen2.5-32B-Instruct-4bit` | 4-bit | ~18–20 GB | High | workstation+ | 2k–4k | Severe below 36 GB | Large single-model server |

### Defaults by tier

| Tier | Default model |
| --- | --- |
| constrained (≤8 GB) | `mlx-community/Llama-3.2-3B-Instruct-4bit` |
| standard (≤16 GB) | `mlx-community/Llama-3.2-3B-Instruct-4bit` (try 7B–8B 4-bit carefully) |
| high (≤32 GB) | `mlx-community/Mistral-7B-Instruct-v0.3-4bit` |
| workstation (≤64 GB) | `mlx-community/Qwen2.5-14B-Instruct-4bit` |
| large (>64 GB) | `mlx-community/Qwen2.5-32B-Instruct-4bit` |

## 8 GB limitations

- Prefer **3B–4B 4-bit** unless your own measurements support something larger.
- A 7B 4-bit weight footprint alone can leave almost no room for KV cache + macOS.
- Avoid concurrent large apps, multiple loaded models, or long contexts.
- Image/video generation is generally impractical; see [media.md](media.md).

## Updating local defaults

```bash
cp config/models.example.env config/models.env
# edit MLX_DEFAULT_MODEL / context guidance
```
