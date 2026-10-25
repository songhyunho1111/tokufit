import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("create_simulator", Path(__file__).parents[1] / "create_simulator.py")
script = importlib.util.module_from_spec(spec)
spec.loader.exec_module(script)

PHONE = "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"
UDID = "11111111-2222-4333-8444-555555555555"
INVENTORY = {
    "devicetypes": [{"name": "iPhone 18 Pro", "identifier": PHONE, "productFamily": "iPhone"}],
    "runtimes": [
        {"name": "iOS 27.0", "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
         "version": "27.0", "isAvailable": True, "supportedDeviceTypes": [{"identifier": PHONE}]},
        {"name": "iOS 27.1", "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
         "version": "27.1", "isAvailable": True, "supportedDeviceTypes": [{"identifier": "iphone-duo"}]},
    ],
}


class DestinationTests(unittest.TestCase):
    def test_newest_compatible_instead_of_newest_installed(self):
        _, runtime = script.destination(INVENTORY, "iPhone 18 Pro", None)
        self.assertEqual(runtime["version"], "27.0")

    def test_explicit_identifiers(self):
        device, runtime = script.destination(INVENTORY, PHONE, INVENTORY["runtimes"][0]["identifier"])
        self.assertEqual(device["identifier"], PHONE)
        self.assertEqual(runtime["version"], "27.0")

    def test_incompatible_explicit_runtime_fails(self):
        with self.assertRaisesRegex(ValueError, "Compatible runtimes: iOS 27.0"):
            script.destination(INVENTORY, "iPhone 18 Pro", "27.1")

    def test_unavailable_runtime_is_not_selected(self):
        inventory = copy.deepcopy(INVENTORY)
        inventory["runtimes"][0]["isAvailable"] = False
        with self.assertRaisesRegex(ValueError, "Compatible runtimes: none"):
            script.destination(inventory, "iPhone 18 Pro", None)

    def test_old_inventory_uses_version_bounds(self):
        inventory = copy.deepcopy(INVENTORY)
        for runtime in inventory["runtimes"]:
            del runtime["supportedDeviceTypes"]
        inventory["devicetypes"][0].update(minRuntimeVersion=27 << 16, maxRuntimeVersion=27 << 16)
        self.assertEqual(script.destination(inventory, PHONE, None)[1]["version"], "27.0")

    def test_unknown_device_fails(self):
        with self.assertRaisesRegex(ValueError, "Unknown iPhone"):
            script.destination(INVENTORY, "not a device", None)


class WorkflowTests(unittest.TestCase):
    def workflow(self, fail_build):
        with tempfile.TemporaryDirectory(prefix="repick script test ") as temporary:
            root = Path(temporary)
            project = root / "REPick.xcodeproj"
            project.mkdir()
            calls = []

            def fake_run(command, env, log, *, capture=False, timeout=120):
                calls.append(command)
                self.assertIsInstance(command, list)
                log.write_text("test command\n")
                if command[:4] == ["xcrun", "simctl", "list", "--json"]:
                    return json.dumps(INVENTORY)
                if command[:3] == ["xcrun", "simctl", "create"]:
                    return UDID
                if command[:2] == ["xcodebuild", "build"]:
                    if fail_build:
                        raise RuntimeError("Build failed in test")
                    app = root / "build/simulator/DerivedData/Build/Products/Debug-iphonesimulator/REPick.app"
                    app.mkdir(parents=True)
                    (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "dev.repick.app"}))
                return "" if capture else None

            output, errors = io.StringIO(), io.StringIO()
            with patch.object(script, "ROOT", root), patch.object(script, "PROJECT", project), \
                 patch.object(script, "developer_directory", return_value=root / "Xcode with spaces/Contents/Developer"), \
                 patch.object(script.sys, "platform", "darwin"), patch.object(script, "run", side_effect=fake_run), \
                 contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                code = script.main(["--name", "QA ; $literal"])

            create = next(c for c in calls if c[:3] == ["xcrun", "simctl", "create"])
            self.assertEqual(create[3], "QA ; $literal")
            self.assertFalse(any(c[2] in ("erase", "delete", "shutdown") for c in calls if c[0] == "xcrun"))
            summaries = list(root.glob("build/simulator/runs/*/result.json"))
            if fail_build:
                self.assertEqual(code, 1)
                self.assertIn(UDID, errors.getvalue())
                self.assertFalse(any(c[:3] == ["xcrun", "simctl", "install"] for c in calls))
                self.assertFalse(summaries)
            else:
                self.assertEqual(code, 0)
                self.assertEqual(calls[-1], ["xcrun", "simctl", "launch", UDID, "dev.repick.app"])
                self.assertIn("headlessly", errors.getvalue())
                self.assertEqual(len(summaries), 1)
                summary = json.loads(summaries[0].read_text())
                self.assertEqual(summary["udid"], UDID)
                self.assertFalse(summary["guiOpened"])

    def test_missing_gui_does_not_fail_install_and_launch(self):
        self.workflow(fail_build=False)

    def test_failed_build_preserves_created_device_and_never_installs(self):
        self.workflow(fail_build=True)


if __name__ == "__main__":
    unittest.main()
