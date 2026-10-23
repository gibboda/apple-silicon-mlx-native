#!/usr/bin/env python3
# Re-exec scripts/release.sh under bash (python3 entry for tests and tooling).
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only
"""Delegate to the bash release driver."""

from __future__ import annotations

import os
import sys


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    release_sh = os.path.join(os.path.dirname(script_dir), "release.sh")
    os.execvp("bash", ["bash", release_sh, *sys.argv[1:]])


if __name__ == "__main__":
    main()
