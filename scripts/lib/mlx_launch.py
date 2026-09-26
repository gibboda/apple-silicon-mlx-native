#!/usr/bin/env python3
# Apply Apple Silicon MLX limits, then run mlx_lm generate or server.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
"""Launch mlx_lm in this process so memory limits apply to model load.

The shell wrapper exports MLX_APPLY_WORKING_SET_LIMITS=1 and
MLX_CACHE_LIMIT_BYTES only for the constrained (≤8 GB) tier. Other tiers
keep MLX defaults. Image and video wrappers do not call this module.
"""

from __future__ import annotations

import os
import sys


def _positive_int(name: str) -> int:
    raw = os.environ.get(name, "")
    if not raw.isdigit() or int(raw) <= 0:
        raise SystemExit(f"mlx_runtime: {name} must be a positive integer")
    return int(raw)


def apply_runtime_limits() -> None:
    """Pin GPU and, on the constrained tier, cap memory, cache, and wired limits.

    Called before importing mlx_lm so the generation stream is created on GPU.
    """
    if os.environ.get("MLX_APPLY_WORKING_SET_LIMITS") != "1":
        return

    import mlx.core as mx

    if not mx.metal.is_available():
        sys.stderr.write("mlx_runtime=metal_unavailable\n")
        return

    mx.set_default_device(mx.gpu)
    info = mx.device_info()
    working_set = int(info.get("max_recommended_working_set_size") or 0)
    memory_size = int(info.get("memory_size") or 0)
    if working_set <= 0:
        sys.stderr.write("mlx_runtime=no_working_set\n")
        return

    memory_limit = working_set
    wired_limit = working_set
    # set_wired_limit must stay strictly below total unified memory.
    if memory_size > 0 and wired_limit >= memory_size:
        wired_limit = memory_size - 1
    cache_limit = _positive_int("MLX_CACHE_LIMIT_BYTES")

    mx.set_memory_limit(memory_limit)
    mx.set_cache_limit(cache_limit)
    wired_error = ""
    try:
        mx.set_wired_limit(wired_limit)
    except Exception as exc:  # noqa: BLE001 — surface Metal/wired failures and continue
        wired_error = str(exc)
        wired_limit = 0

    sys.stderr.write(
        "mlx_runtime device=gpu memory_limit_bytes=%s cache_limit_bytes=%s wired_limit_bytes=%s\n"
        % (memory_limit, cache_limit, wired_limit)
    )
    if wired_error:
        sys.stderr.write("wired_limit_error=%s\n" % (wired_error,))


def main(argv: list[str] | None = None) -> None:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] not in ("generate", "server"):
        raise SystemExit("usage: mlx_launch.py generate|server [mlx_lm args...]")
    command = args[0]
    sys.argv = [f"mlx_lm.{command}", *args[1:]]
    apply_runtime_limits()
    if command == "generate":
        from mlx_lm.generate import main as run
    else:
        from mlx_lm.server import main as run
    run()


if __name__ == "__main__":
    main()
