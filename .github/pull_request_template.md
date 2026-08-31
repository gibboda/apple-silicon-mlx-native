## Summary

<!-- What does this PR change and why? -->

## Checklist

- [ ] Commit subjects follow [Conventional Commits](../README.md#conventional-commits-policy)
- [ ] `make lint` (ShellCheck) passes for touched shell scripts
- [ ] `make validate` passes when MLX environment changes apply
- [ ] Documentation updated (`README.md` and/or `docs/`) when behavior changes
- [ ] `CHANGELOG.md` `[Unreleased]` updated for user-visible changes
- [ ] Apple Silicon (`arm64`) compatibility considered; no Rosetta-only/x86 deps on the normal path
- [ ] Memory implications documented (weights ≠ total unified-memory use)
- [ ] New dependencies are necessary, MLX-native when possible, and do not silently pull PyTorch/MPS as a core runtime

## Memory / hardware notes

<!-- e.g. tested on M-series / N GB; default model tier impact -->

## Test plan

- [ ] `make detect`
- [ ] `make audit`
- [ ] `make lint`
- [ ] `make validate` (when applicable)
