#!/usr/bin/env python3
"""Run the production Watch receiver/publisher with isolated macOS transport/UI doubles."""

import os
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="repick-watch-companion-check-") as folder:
        directory = Path(folder)
        build = [
            "xcrun", "swift", "build", "--package-path", str(root / "packages/REPickShared"),
            "--scratch-path", str(directory / "build"), "--build-system", "native",
        ]
        subprocess.run(build, env=env, check=True)
        binary_directory = Path(subprocess.check_output(build + ["--show-bin-path"], env=env, text=True).strip())
        sources = []
        for filename in ["WatchCompanion.swift", "WatchComplicationPublisher.swift", "WatchConnectivityBackground.swift"]:
            source = root / "apps/apple/watchOS" / filename
            output = directory / filename
            # Only platform imports change; the receiver, image validation and publisher execute unchanged.
            output.write_text("\n".join(line for line in source.read_text().splitlines()
                                        if line not in {"import UIKit", "import WatchConnectivity", "import WidgetKit"}) + "\n")
            sources.append(str(output))
        executable = directory / "check"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
            "-I", str(binary_directory / "Modules"),
            *sources, str(root / "tools/watch-companion-check.swift"),
            *map(str, (binary_directory / "REPickShared.build").glob("*.o")),
            "-o", str(executable),
        ], env=env, check=True)
        subprocess.run([str(executable)], env=env, check=True)


if __name__ == "__main__":
    main()
