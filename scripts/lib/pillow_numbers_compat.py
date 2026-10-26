# Pillow 13.0.0 loads PIL._typing, which does `from numbers import _IntegralLike`.
# That name exists in typeshed stubs but not in CPython 3.12–3.14 stdlib numbers.
# mflux imports PIL._typing (StrOrBytesPath) for image I/O.
#
# Installed into the project venv via install_pillow_numbers_compat() (.pth auto-import).
# Remove when upstream Pillow no longer needs this (or stdlib exposes _IntegralLike).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

from __future__ import annotations


def apply() -> None:
    import numbers

    if hasattr(numbers, "_IntegralLike"):
        return

    import typing

    class _IntegralLike(typing.Protocol):
        def __index__(self) -> int: ...

    numbers._IntegralLike = _IntegralLike  # type: ignore[attr-defined]


apply()
