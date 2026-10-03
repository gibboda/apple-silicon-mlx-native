#!/usr/bin/env python3
# Emit detect-apple-silicon.sh --json payload from DETECT_* environment variables.
# Copyright (C) 2026 Dona Gibbons (gibboda)
# SPDX-License-Identifier: GPL-3.0-only

import json
import os
import sys


def maybe_int(key: str):
    v = os.environ.get(key, "")
    if v == "":
        return None
    try:
        return int(v)
    except ValueError:
        return None


def maybe_str(key: str):
    v = os.environ.get(key, "")
    return v if v != "" else None


def main() -> int:
    required = (
        "DETECT_ARCH",
        "DETECT_CHIP",
        "DETECT_MEM_BYTES",
        "DETECT_MEM_GIB",
        "DETECT_TIER_ID",
        "DETECT_TIER_LABEL",
        "DETECT_TIER_HINT",
        "DETECT_CORES",
        "DETECT_MACOS",
        "DETECT_PY",
        "DETECT_BREW_OK",
        "DETECT_XCODE",
        "DETECT_MODEL",
        "DETECT_WORKSPACE",
    )
    missing = [key for key in required if os.environ.get(key, "") == ""]
    if missing:
        print("detect JSON missing env: " + ", ".join(missing), file=sys.stderr)
        return 1

    payload = {
        "architecture": os.environ["DETECT_ARCH"],
        "apple_chip": os.environ["DETECT_CHIP"],
        "chip_family": maybe_int("DETECT_CHIP_FAMILY"),
        "chip_sku": maybe_str("DETECT_CHIP_SKU"),
        "gpu_cores": maybe_int("DETECT_GPU_CORES"),
        "p_cores": maybe_int("DETECT_P_CORES"),
        "e_cores": maybe_int("DETECT_E_CORES"),
        "hw_model": maybe_str("DETECT_HW_MODEL"),
        "thermal_class": maybe_str("DETECT_THERMAL"),
        "bandwidth_gbs": maybe_int("DETECT_BANDWIDTH"),
        "throughput_class": maybe_str("DETECT_THROUGHPUT"),
        "memory_bytes": int(os.environ["DETECT_MEM_BYTES"]),
        "memory_gib": int(os.environ["DETECT_MEM_GIB"]),
        "memory_tier_id": os.environ["DETECT_TIER_ID"],
        "memory_tier_label": os.environ["DETECT_TIER_LABEL"],
        "physical_memory_tier_id": maybe_str("DETECT_PHYSICAL_TIER_ID"),
        "physical_memory_tier_label": maybe_str("DETECT_PHYSICAL_TIER_LABEL"),
        "memory_tier_hint": os.environ["DETECT_TIER_HINT"],
        "cpu_cores": int(os.environ["DETECT_CORES"]),
        "macos_version": os.environ["DETECT_MACOS"],
        "disk_available_gib": int(float(os.environ.get("DETECT_DISK") or 0)),
        "python_version": os.environ["DETECT_PY"],
        "homebrew": os.environ["DETECT_BREW_OK"] == "true",
        "homebrew_prefix": os.environ.get("DETECT_BREW_PREFIX", ""),
        "xcode_clt": os.environ["DETECT_XCODE"] == "true",
        "recommended_model": os.environ["DETECT_MODEL"],
        "recommended_context": maybe_int("DETECT_CONTEXT"),
        "recommended_image_profile": os.environ.get("DETECT_IMAGE_PROFILE") or None,
        "recommended_video_profile": os.environ.get("DETECT_VIDEO_PROFILE") or None,
        "video_force_required": os.environ.get("DETECT_VIDEO_FORCE", "0") == "1",
        "workspace": os.environ["DETECT_WORKSPACE"],
    }
    ws = maybe_int("DETECT_WORKING_SET")
    if ws is not None:
        payload["working_set_bytes"] = ws
    arch = maybe_str("DETECT_GPU_ARCH")
    if arch is not None:
        payload["gpu_arch"] = arch
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
