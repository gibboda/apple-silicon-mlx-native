# common-golden fixtures

Byte-stable expected output for `tests/common-golden.test.sh` (detect `--env` / `--json`, `--list*`, and wrapper `--dump-plan`).

## Regenerate

From the repository root:

```bash
./tests/regen-common-golden.sh
```

Use `LC_ALL=C` (the regen script sets it). Volatile fields (`MLX_WORKSPACE`, `python_version`, Homebrew/Xcode CLT presence, video `model_dir`) are normalized in the test and regen script so Linux stub CI and macOS runners match.

## Profiles

| Slug | Intent |
| --- | --- |
| `constrained_fanless` | 8 GB policy tier, fanless thermal |
| `standard_fast_cooled` | 16 GB standard, M5-class fast throughput |
| `high_fast_cooled` | High tier, fast throughput (M5 base bandwidth) |
| `high_very_fast_cooled` | High tier, very_fast policy throughput (M5 Pro) → Qwen2.5-14B branch |
| `very_fast` | Standard tier, very_fast policy throughput → 7B default |
| `unknown` | Unknown policy chip → unknown bandwidth / RAM-only text default |
| `fanless_high` | High tier, fanless |
| `large_cooled` | Large tier, cooled, very_fast bandwidth |
| `workstation_cooled` | Workstation tier, cooled |

## Provenance

Fixtures last regenerated to match toolkit behavior at git commit **`4ffafec8746cabee6931756bdbcdcbffd85751cf`** on `main` (baseline cited in PR #100 review). Re-run regen after intentional output changes and update this SHA.
