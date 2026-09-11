## Summary

<!-- What does this PR change and why? -->

## Checklist

- [ ] Commit subjects follow [Conventional Commits](README.md#conventional-commits-policy)
- [ ] `make lint` (ShellCheck) passes for touched shell scripts
- [ ] `make test` passes when shell self-tests apply
- [ ] `make validate` passes when MLX environment changes apply
- [ ] Documentation updated (`README.md` and/or `docs/`) when behavior changes
- [ ] `CHANGELOG.md` `[Unreleased]` updated for user-visible changes
- [ ] Apple Silicon (`arm64`) compatibility considered; no Rosetta-only/x86 deps on the normal path
- [ ] Memory implications documented (weights ≠ total unified-memory use)
- [ ] New dependencies are necessary and MLX-native when possible. Do not add PyTorch/MPS or Diffusers+MPS as an LLM/image **generation** backend; documented transitive deps (e.g. opt-in `mflux` → `torch` for weight loading) are OK

## Memory / hardware notes

<!-- e.g. tested on M-series / N GB; default model tier impact -->

## Test plan

- [ ] `make detect`
- [ ] `make audit`
- [ ] `make lint`
- [ ] `make test` (when applicable)
- [ ] `make validate` (when applicable)
