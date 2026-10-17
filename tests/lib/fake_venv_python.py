#!/usr/bin/env python3
# Fake .venv/bin/python3 for wrapper argv tests (Linux CI + macOS).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
"""Record argv for mlx_launch.py or python -m invocations; delegate otherwise."""

from __future__ import annotations

import os
import sys


def _write_rec(argv: list[str]) -> None:
    path = os.environ.get("MLX_TEST_RECORD_ARGV", "")
    if not path:
        return
    with open(path, "wb") as handle:
        for arg in argv:
            handle.write(arg.encode("utf-8") + b"\0")


def _python_argv0() -> str:
    venv = os.environ.get("MLX_VENV", "")
    if venv:
        return os.path.join(venv, "bin", "python3")
    return sys.argv[0]


def main() -> None:
    args = sys.argv[1:]
    if len(args) >= 2 and args[0] == "-c" and args[1] == "import mlx_video":
        raise SystemExit(0)
    if len(args) >= 2 and args[0] == "-m":
        _write_rec([_python_argv0(), *args])
        raise SystemExit(0)
    for index, arg in enumerate(args):
        if arg.endswith("mlx_launch.py") and index + 1 < len(args):
            _write_rec([args[index + 1], *args[index + 2 :]])
            raise SystemExit(0)
    os.execvp("python3", ["python3", *args])


if __name__ == "__main__":
    main()
