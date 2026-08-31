# Hardware tiers

Detection is dynamic (`scripts/detect-apple-silicon.sh`). The toolkit does **not** hard-code a single chip (for example M1/8 GB), though that configuration is an important minimum target.

## What is detected

| Signal | Use |
| --- | --- |
| `arm64` architecture | Hard requirement; Intel Macs are rejected |
| Apple chip / brand string | Reporting and support context |
| Unified memory (GiB) | Tier classification and defaults |
| CPU cores | Reporting |
| macOS version | Compatibility reporting |
| Disk available on workspace volume | Headroom for caches/models |
| Homebrew / Xcode CLT | Bootstrap prerequisites |
| Python version | Environment reporting |

## Memory tiers

| Physical unified memory | Tier id | Label | Default posture |
| --- | --- | --- | --- |
| ≤ 8 GB | `constrained` | 8 GB — constrained | 3B–4B **4-bit** models; short context; avoid image/video |
| ≤ 16 GB | `standard` | 16 GB — standard | 3B–8B 4-bit; careful 7B use |
| ≤ 32 GB | `high` | 24–32 GB — high | 7B–14B 4-bit; selected 8-bit |
| ≤ 64 GB | `workstation` | 36–64 GB — workstation | 14B–32B 4-bit; heavier media |
| > 64 GB | `large` | large-memory workstation | 30B+ quantized; multi-workload |

Tier classification **influences recommendations**. Advanced users can override defaults (`OVERRIDE_MEMORY_TIER`, `config/models.env`) without the toolkit blocking them.

## 8 GB guidance (minimum target)

On an 8 GB M1-class system:

- Prefer ~**3B–4B**, **4-bit** MLX Community models.
- Keep context conservative (roughly 1k–2k tokens unless measured otherwise).
- Prefer one persistent `mlx_lm.server` process over loading multiple models.
- Treat image and especially video generation as out of scope unless you accept heavy swap risk.
- Close memory-heavy apps (browsers with many tabs, IDEs with large indexes) before loading models.

## Overrides

```bash
# Force recommendation tier without lying about physical RAM in detect output
OVERRIDE_MEMORY_TIER=high make install

# Pin a specific model in local config (gitignored once copied)
cp config/models.example.env config/models.env
```

Physical detection always reports true hardware; overrides only change **policy**, not facts.
