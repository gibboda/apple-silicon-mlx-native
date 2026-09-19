# Hardware tiers

Detection is dynamic (`scripts/detect-apple-silicon.sh`). The toolkit does **not** hard-code a single chip (for example M1/8 GB), though that configuration is the **floor**: defaults must not become more aggressive than they are on an 8 GB fanless M1 Air.

## Two axes

| Axis | Role |
| --- | --- |
| **RAM / memory tier** | **OOM fence.** What can fit in unified memory. Chip class must never raise a model past this. |
| **Chip class (throughput + thermal)** | **Performance fence.** How hard to push at that RAM. Bandwidth, not generation number. |

An 8 GB M1, a 16 GB M1, and a 16 GB M5 therefore do **not** share one policy. Wan’s UMT5 encoder (~11 GB) still cannot run on 8 GB, including 8 GB M5.

Unknown chips (unrecognized brand string, or a family with no bandwidth row such as M7 / M10) **warn and fall back to RAM-only defaults**. Install does not fail.

## What is detected

| Signal | Use |
| --- | --- |
| `arm64` architecture | Hard requirement; Intel Macs are rejected |
| Apple chip / brand string | Parsed with longest-match regex (Ultra, then Max, then Pro, then base). `Apple M1 Pro` is Pro, not base; `Apple M10` is family 10, not 1 |
| Chip family / SKU | Bandwidth lookup and throughput class |
| GPU cores (`ioreg` `gpu-core-count`) | Max GPU-bin footnotes; modest video frame scaling when RAM already allows Wan |
| P/E cores (`hw.perflevel0/1.physicalcpu`) | Reporting |
| `hw.model` | Thermal class: `MacBookAir*` is **fanless**, otherwise **cooled** |
| Unified memory (GiB) | Memory tier (OOM fence) |
| `mx.device_info()` working set / GPU arch | When mlx is importable; omitted otherwise. Uses `mx.device_info`, not deprecated `mx.metal.device_info` |
| CPU cores / macOS / disk / Homebrew / Xcode CLT / Python | Reporting and bootstrap |

Bandwidth is **not** measurable via sysctl. The toolkit looks it up from family+SKU (small table, not a per-retail-SKU encyclopedia). Max variants that differ by GPU bin (for example M3 Max 30- vs 40-core) use `gpu-core-count` when present; unknown Max bins use the conservative (lower) figure.

## Memory tiers (OOM fence)

| Physical unified memory | Tier id | Label | Default posture |
| --- | --- | --- | --- |
| ≤ 8 GB | `constrained` | 8 GB — constrained | 3B–4B **4-bit** models; short context; avoid image/video (video UMT5 ~11 GB) |
| ≤ 18 GB (`< 24` GB) | `standard` | 16–18 GB — standard | 3B default on slow chips; 7B–8B 4-bit on fast cooled chips. 18 GB Pro SKUs stay here so image/video do not use the 24 GB profile |
| 24–32 GB | `high` | 24–32 GB — high | 7B–14B 4-bit; selected 8-bit |
| ≤ 64 GB | `workstation` | 36–64 GB — workstation | 14B–32B 4-bit; heavier media |
| > 64 GB | `large` | large-memory workstation | 30B+ quantized; multi-workload |

## Throughput class (performance fence)

Class comes from looked-up bandwidth, **not** generation number. M3 Pro (~150 GB/s) is slower at decode than M2 Pro (~200 GB/s); both land in `fast`.

| Class | Bandwidth | Typical chips |
| --- | --- | --- |
| `slow` | < 100 GB/s | Base M1 (~68) |
| `moderate` | 100 ≤ bw < 150 GB/s | Base M2 / M3 / M4 |
| `fast` | 150 ≤ bw < 300 GB/s | Base M5, M3 Pro (~150), most Pro |
| `very_fast` | 300–600 GB/s | Max |
| `extreme` | > 600 GB/s | Ultra |

M5+ GPU Neural Accelerators (generation ≥ 5) do **not** change image defaults (those follow `fast` throughput on cooled RAM). They only affect video: on the `high` tier, Wan frames go from 33 to 49 when throughput is known, GPU cores ≥ 24, **and** (throughput is `very_fast` **or** the chip has NAX). Unknown chips stay on the tier-only 33-frame profile. They do not help decode, and this stack never routes through ANE — MLX/Metal GPU only.

Fanless (`MacBookAir*`) derates: throughput_class must **not** raise the default model, image, video, or context above the conservative Air profile, even on later Airs.

## Composed LLM defaults

| Memory tier | Throughput / thermal | Default model | Context |
| --- | --- | --- | --- |
| constrained | any (this 8 GB M1) | Llama 3.2 3B Instruct 4-bit | 2048 |
| standard | slow / moderate (16 GB M1, M2/M3/M4 base) | Llama 3.2 3B Instruct 4-bit | 2048 |
| standard | fast+, cooled (16 GB M5, 18 GB Pro) | Mistral 7B Instruct 4-bit | 4096 |
| high | very_fast (Max 32 GB) | Qwen2.5 14B Instruct 4-bit | 8192 |
| large | extreme | Qwen2.5 32B Instruct 4-bit | 8192 |
| unknown chip | RAM-only | Conservative table (standard = 3B / 2048 / 4-bit image, not the M5 path) | Conservative table |

Fanless keeps the RAM-only default model and context at 2048.

`MLX_RECOMMENDED_CONTEXT` is a real exported default (`scripts/detect-apple-silicon.sh --json` / `--env`, `config/models.env`). Pass it to `mlx_lm.generate --max-kv-size`. Pass `--max-kv-size` to `mlx_lm.server` when that flag exists (mlx-lm 0.31.3 server does not; generate does).

## MLX runtime limits

On constrained machines, `make validate` probes `mx.set_wired_limit` / `set_memory_limit` / `set_cache_limit` from `max_recommended_working_set_size` and does **not** exceed that Metal recommended working set in the probe process (this M1: ~5.33 GB). Those limits are process-local and are **not** inherited by generate wrappers (`mflux-generate`, `mlx-video`). `make detect` prints the working set when mlx is importable.

## 8 GB guidance (minimum target)

On an 8 GB M1-class fanless system:

- Prefer ~**3B–4B**, **4-bit** MLX Community models.
- Keep context conservative (2048 tokens unless measured otherwise).
- Prefer one persistent `mlx_lm.server` process over loading multiple models.
- Treat image generation as opt-in (`make install-image`) with the constrained 4B 4-bit 512² `--low-ram` profile; expect heavy swap. Treat video as opt-in (`make install-video`) only with `--force`: Wan 1.3B still needs ~11 GB for UMT5.
- Close memory-heavy apps (browsers with many tabs, IDEs with large indexes) before loading models.

## Overrides

Overrides change **recommendations**, not reported facts. Physical detect output stays truthful. `scripts/detect-apple-silicon.sh --env` prints `MLX_PHYSICAL_TIER_ID` (detected RAM) and `MLX_TIER_ID` (policy, including `OVERRIDE_MEMORY_TIER`). `--json` uses `physical_memory_tier_id` and `memory_tier_id` the same way.

```bash
# Force recommendation tier without lying about physical RAM in detect output
OVERRIDE_MEMORY_TIER=high make install

# CI / manual chip policy (no Mac hardware required for dump-plan)
OVERRIDE_MEMORY_TIER=standard OVERRIDE_CHIP_FAMILY=5 OVERRIDE_CHIP_SKU=base \
  OVERRIDE_THERMAL_CLASS=cooled scripts/generate-mlx-image.sh --dump-plan --prompt "plan"

# Pin a specific model in local config (gitignored once copied)
cp config/models.example.env config/models.env
```

Also: `OVERRIDE_CHIP_FAMILY`, `OVERRIDE_CHIP_SKU`, `OVERRIDE_GPU_CORES`, `OVERRIDE_THERMAL_CLASS`. Unknown `OVERRIDE_MEMORY_TIER` / `OVERRIDE_CHIP_SKU` / `OVERRIDE_THERMAL_CLASS` values, or a non-numeric `OVERRIDE_CHIP_FAMILY`, fail instead of silently mapping to the 8 GB path.

`config/models.env` is created once from the composed profile and **preserved on rebuild**. After moving a clone to another Mac, run `make recommend` and update `MLX_DEFAULT_MODEL` / `MLX_RECOMMENDED_CONTEXT` if the composed profile changed — rebuild will not refresh a stale file.
