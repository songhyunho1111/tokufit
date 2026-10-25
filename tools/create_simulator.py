#!/usr/bin/env python3
"""Create a fresh iPhone simulator, build RE:PICK, install it, and launch it."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from datetime import datetime
from uuid import UUID, uuid4


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "apps/apple/REPick.xcodeproj"
SCHEME = "REPick"


def developer_directory():
    explicit = os.environ.get("DEVELOPER_DIR")
    if explicit:
        candidates = [Path(explicit).expanduser()]
    else:
        selected = subprocess.run(
            ["xcode-select", "-p"], capture_output=True, text=True, check=False
        )
        candidates = []
        if selected.returncode == 0:
            candidates.append(Path(selected.stdout.strip()))
        candidates.append(Path("/Applications/Xcode.app/Contents/Developer"))
    for candidate in candidates:
        if candidate.suffix == ".app":
            candidate = candidate / "Contents/Developer"
        if (candidate / "usr/bin/xcodebuild").is_file():
            return candidate
    raise RuntimeError(
        "Xcode build tools were not found. Set DEVELOPER_DIR to "
        "your Xcode.app/Contents/Developer directory."
    )


def destination(inventory, device_name, ios):
    phones = [d for d in inventory["devicetypes"] if d.get("productFamily") == "iPhone"]
    device = next(
        (d for d in phones if device_name in (d["name"], d["identifier"])), None
    )
    if device is None:
        raise ValueError("Unknown iPhone. Installed types: " + ", ".join(d["name"] for d in phones))

    compatible = []
    for runtime in inventory["runtimes"]:
        if not runtime.get("isAvailable") or not runtime["identifier"].startswith(
            "com.apple.CoreSimulator.SimRuntime.iOS-"
        ):
            continue
        supported = runtime.get("supportedDeviceTypes")
        if supported is not None:
            if not any(d["identifier"] == device["identifier"] for d in supported):
                continue
        else:
            # Older inventories expose version bounds instead of a supported-device list.
            parts = [int(p) for p in runtime["version"].split(".")]
            major, minor, patch = (parts + [0, 0])[:3]
            version = (major << 16) | (minor << 8) | patch
            if not device.get("minRuntimeVersion", 0) <= version <= device.get("maxRuntimeVersion", 0xFFFFFFFF):
                continue
        compatible.append(runtime)

    choices = [r for r in compatible if ios is None or ios in (r["version"], r["name"], r["identifier"])]
    if not choices:
        installed = ", ".join(r["name"] for r in compatible) or "none"
        raise ValueError(
            f"No compatible installed iOS runtime for {device['name']}"
            f"{f' / {ios}' if ios else ''}. Compatible runtimes: {installed}."
        )
    runtime = max(choices, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
    return device, runtime


def run(command, env, log, *, capture=False, timeout=120):
    with log.open("w") as output:
        result = subprocess.run(
            command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT,
            timeout=timeout, check=False,
        )
    if result.returncode:
        raise RuntimeError(f"{command[0]} failed (exit {result.returncode}). See {log}")
    return log.read_text().strip() if capture else None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", help="New simulator name (default: REPick + device + timestamp)")
    parser.add_argument("--device", default="iPhone 18 Pro", help="Installed iPhone name or device-type ID")
    parser.add_argument("--ios", help="Installed iOS version or runtime ID (default: newest compatible)")
    parser.add_argument("--no-open", action="store_true", help="Skip the optional Simulator window")
    args = parser.parse_args(argv)
    udid = None
    logs = None
    try:
        if sys.platform != "darwin":
            raise RuntimeError("This script requires macOS and Xcode simulator tools.")
        if not PROJECT.is_dir():
            raise RuntimeError(f"Project not found: {PROJECT}")
        if args.name is not None and (not args.name.strip() or any(ord(c) < 32 for c in args.name)):
            raise ValueError("Simulator name must be nonempty and contain no control characters.")
        developer = developer_directory()
        env = {**os.environ, "DEVELOPER_DIR": str(developer)}
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        work = ROOT / "build/simulator"
        logs = work / "runs" / f"{stamp}-{uuid4().hex[:8]}"
        logs.mkdir(parents=True)
        # shortcut: share the build cache for sequential runs; add locking for concurrent use.
        derived = work / "DerivedData"
        run(["xcodebuild", "-version"], env, logs / "xcode.log")
        inventory = json.loads(run(
            ["xcrun", "simctl", "list", "--json"], env, logs / "inventory.json", capture=True
        ))
        device, runtime = destination(inventory, args.device, args.ios)
        name = args.name or f"REPick - {device['name']} - {stamp}"
        print(f"Creating {name} ({runtime['name']})", flush=True)
        created = run(
            ["xcrun", "simctl", "create", name, device["identifier"], runtime["identifier"]],
            env, logs / "create.log", capture=True,
        )
        udid = str(UUID(created)).upper()
        print(f"Simulator ID: {udid}\nBooting...", flush=True)
        run(["xcrun", "simctl", "boot", udid], env, logs / "boot.log")
        run(["xcrun", "simctl", "bootstatus", udid, "-b"], env, logs / "boot-status.log", timeout=300)
        print(f"Building {SCHEME}... Log: {logs / 'build.log'}", flush=True)
        run([
            "xcodebuild", "build", "-project", str(PROJECT), "-scheme", SCHEME,
            "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={udid}",
            "-derivedDataPath", str(derived),
        ], env, logs / "build.log", timeout=1800)
        app = derived / "Build/Products/Debug-iphonesimulator/REPick.app"
        with (app / "Info.plist").open("rb") as file:
            bundle_id = plistlib.load(file)["CFBundleIdentifier"]
        if not isinstance(bundle_id, str) or not bundle_id:
            raise ValueError("Built app has no valid bundle identifier.")
        print("Installing and launching...", flush=True)
        run(["xcrun", "simctl", "install", udid, str(app)], env, logs / "install.log")
        run(["xcrun", "simctl", "launch", udid, bundle_id], env, logs / "launch.log")
        gui_opened = False
        if not args.no_open:
            simulator = developer / "Applications/Simulator.app"
            if simulator.is_dir():
                try:
                    run(["open", "-a", str(simulator), "--args", "-CurrentDeviceUDID", udid], env, logs / "open.log")
                    gui_opened = True
                except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    print(f"Warning: window could not open: {error}", file=sys.stderr)
            else:
                print("Warning: Simulator.app is missing under this Xcode; the device and app are running headlessly.", file=sys.stderr)
        summary = {
            "udid": udid, "name": name, "device": device["name"], "runtime": runtime["name"],
            "bundleIdentifier": bundle_id, "appPath": str(app), "guiOpened": gui_opened,
        }
        (logs / "result.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
        print(f"Ready: {name}\nApp: {bundle_id}\nSimulator ID: {udid}\nLogs and result: {logs}", flush=True)
        return 0
    except KeyboardInterrupt:
        print("Cancelled.", file=sys.stderr)
        code = 130
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"Error: {error}", file=sys.stderr)
        code = 1
    if udid:
        print(f"Created simulator preserved for inspection: {udid}", file=sys.stderr)
    if logs:
        print(f"Logs: {logs}", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
