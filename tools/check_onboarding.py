#!/usr/bin/env python3
"""Run only onboarding persistence/completion and yellow-theme contrast checks."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


def luminance(color):
    channels = [(color >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
              for channel in channels]
    return sum(channel * weight for channel, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(first, second):
    low, high = sorted((luminance(first), luminance(second)))
    return (high + 0.05) / (low + 0.05)


def check_contrast(root):
    assert abs(contrast(0x000000, 0xFFFFFF) - 21) < 0.0001
    assert contrast(0xF9E194, 0xF9E194) == 1
    source = (root / "apps/apple/iOS/Theme.swift").read_text()
    tokens = {name: (int(light, 16), int(dark, 16)) for name, light, dark in re.findall(
        r"static let (\w+) = adaptive\(0x([A-F0-9]+), 0x([A-F0-9]+)\)", source)}
    ratios = []
    for foreground, background in [
        ("repickInk", "repickCream"), ("repickInk", "repickSurface"),
        ("repickSecondaryText", "repickCream"), ("repickSecondaryText", "repickSurface"),
        ("repickGold", "repickCream"), ("repickGold", "repickSurface"),
        ("repickActionInk", "repickActionFill"), ("repickInk", "repickRewardSurface"),
    ]:
        for appearance in range(2):
            ratio = contrast(tokens[foreground][appearance], tokens[background][appearance])
            assert ratio >= 4.5, (foreground, background, appearance, ratio)
            ratios.append(ratio)
    source = (root / "apps/apple/iOS/OnboardingBackdrop.swift").read_text()
    palette = {name: (int(red) << 16) + (int(green) << 8) + int(blue)
               for name, red, green, blue in re.findall(
                   r"static let (\w+) = Color\(red: (\d+) / 255, green: (\d+) / 255, blue: (\d+) / 255\)", source)}
    for foreground in ["ink", "secondary", "accent", "error"]:
        for background in ["background", "cream", "control", "continueFill"]:
            ratio = contrast(palette[foreground], palette[background])
            assert ratio >= 4.5, (foreground, background, ratio)
            ratios.append(ratio)
    print(f"Theme: {len(ratios)} text/background pairs pass 4.5:1; minimum {min(ratios):.2f}:1.")


def main():
    root = Path(__file__).resolve().parents[1]
    check_contrast(root)
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="repick-onboarding-check-") as folder:
        directory = Path(folder)
        build = ["xcrun", "swift", "build", "--package-path", str(root / "packages/REPickShared"),
                 "--scratch-path", str(directory / "build"), "--build-system", "native"]
        subprocess.run(build, env=env, check=True)
        binary_directory = Path(subprocess.check_output(build + ["--show-bin-path"], env=env, text=True).strip())
        executable = directory / "check"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
            "-I", str(binary_directory / "Modules"),
            str(root / "apps/apple/iOS/OnboardingDraft.swift"), str(root / "tools/onboarding-check.swift"),
            *map(str, (binary_directory / "REPickShared.build").glob("*.o")), "-o", str(executable),
        ], env=env, check=True)
        subprocess.run([str(executable)], env=env, check=True)


if __name__ == "__main__":
    main()
