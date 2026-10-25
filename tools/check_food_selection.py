#!/usr/bin/env python3
"""Check the production food model using isolated picker, API and persistence doubles."""

import os
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="repick-food-selection-check-") as folder:
        directory = Path(folder)
        build = [
            "xcrun", "swift", "build", "--package-path", str(root / "packages/REPickShared"),
            "--scratch-path", str(directory / "build"), "--build-system", "native",
        ]
        subprocess.run(build, env=env, check=True)
        binary_directory = Path(subprocess.check_output(build + ["--show-bin-path"], env=env, text=True).strip())
        model = directory / "FoodCaloriesModel.swift"
        source = (root / "apps/apple/iOS/FoodCaloriesModel.swift").read_text()
        # Only framework imports change; the complete production model executes unchanged.
        model.write_text("import Foundation\n" + "\n".join(
            line for line in source.splitlines() if line not in {"import PhotosUI", "import SwiftUI"}
        ) + "\n")
        nutrient_input = directory / "MealNutrientInput.swift"
        meal = (root / "apps/apple/iOS/MealView.swift").read_text()
        marker = "enum MealNutrientInput {"
        if meal.count(marker) != 1:
            raise RuntimeError("Expected the production MealNutrientInput parser once")
        nutrient_input.write_text("import Foundation\nimport REPickShared\n" + marker + meal.split(marker, 1)[1])
        executable = directory / "check"
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
            "-I", str(binary_directory / "Modules"),
            str(model), str(nutrient_input), str(root / "apps/apple/iOS/FoodPhotoPreparation.swift"),
            str(root / "tools/food-selection-check.swift"),
            *map(str, (binary_directory / "REPickShared.build").glob("*.o")),
            "-o", str(executable),
        ], env=env, check=True)
        subprocess.run([str(executable)], env=env, check=True)


if __name__ == "__main__":
    main()
