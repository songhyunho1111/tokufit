#!/usr/bin/env python3
"""Check the real food camera controller with a deterministic capture-service double."""

import os
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="repick-food-camera-check-") as folder:
        executable = Path(folder) / "check"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
            "-parse-as-library",
            str(root / "apps/apple/iOS/FoodCameraController.swift"),
            str(root / "tools/food-camera-lifecycle-check.swift"),
            "-o", str(executable),
        ], env=env, check=True)
        subprocess.run([str(executable)], env=env, check=True, timeout=30)


if __name__ == "__main__":
    main()
