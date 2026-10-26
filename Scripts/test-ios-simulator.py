#!/usr/bin/env python3
"""Run the native Swift package scheme on an installed iOS 17+ simulator.

No runtime is downloaded or device created. Uses the selected Xcode on Intel or
Apple Silicon. An unavailable simulator is explicitly SKIPPED (exit 77), or a
failure with --require-runtime. Build/test failures always fail. Logs and a JSON
status report are retained under .build/ios-simulator/ for every attempt.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def version(value):
    numbers = tuple(int(part) for part in re.findall(r"\d+", value))
    return (numbers + (0, 0, 0))[:3]


def select_device(inventory, sdk_version):
    candidates = []
    for runtime in inventory.get("runtimes", []):
        identifier = runtime.get("identifier", "")
        runtime_version = version(runtime.get("version", "0"))
        if (not identifier.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                or not runtime.get("isAvailable", False)
                or not (version("17") <= runtime_version <= sdk_version)):
            continue
        for device in inventory.get("devices", {}).get(identifier, []):
            if device.get("isAvailable", False) and device.get("udid"):
                candidates.append((runtime_version, device, runtime))
    if not candidates:
        return None
    return max(candidates, key=lambda item: (
        item[0], item[1].get("state") == "Booted",
        item[1].get("name", "").startswith("iPhone"), item[1]["udid"]
    ))[1:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-runtime", action="store_true",
                        help="fail instead of skipping when simulator execution is unavailable")
    args = parser.parse_args()
    base = ROOT / ".build" / "ios-simulator"
    base.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="run-", dir=base))

    def finish(status, reason, code, **details):
        report = {"status": status, "reason": reason, "required": args.require_runtime,
                  "exit_code": code, **details}
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"{status.upper()}: {reason}\nResults: {output}", flush=True)
        return code

    def unavailable(reason):
        return finish("skipped", reason, 1 if args.require_runtime else 77)

    try:
        inventory = subprocess.run(["xcrun", "simctl", "list", "--json"], cwd=ROOT,
                                   text=True, capture_output=True)
        (output / "simctl.log").write_text(inventory.stderr + inventory.stdout)
        if inventory.returncode:
            return unavailable("CoreSimulator inventory failed; service/tool access is unavailable. "
                               "See simctl.log. This is not proof that no runtime is installed.")
        sdk = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
                             cwd=ROOT, text=True, capture_output=True)
        (output / "sdk.log").write_text(sdk.stderr + sdk.stdout)
        if sdk.returncode:
            return unavailable("The selected Xcode's iOS simulator SDK could not be read.")
        selected = select_device(json.loads(inventory.stdout), version(sdk.stdout.strip()))
        if selected is None:
            return unavailable("No available iOS 17+ simulator device within the selected SDK's "
                               "version was found. No tests executed.")
        device, runtime = selected
        destination = f"platform=iOS Simulator,id={device['udid']}"
        command = [
            "xcodebuild", "test", "-scheme", "TypedCoreData",
            "-destination", destination, "-destination-timeout", "120",
            "-derivedDataPath", str(output / "DerivedData"),
            "-resultBundlePath", str(output / "Tests.xcresult"),
            "-parallel-testing-enabled", "NO", "-skipPackageUpdates",
            "SWIFT_VERSION=6", "SWIFT_STRICT_CONCURRENCY=complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES", "GCC_TREAT_WARNINGS_AS_ERRORS=YES",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        print(f"Testing {device['name']} / iOS {runtime['version']}\nLogs: {output}", flush=True)
        with (output / "xcodebuild.log").open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT)
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
            code = process.wait()
        return finish("passed" if code == 0 else "failed", "Native xcodebuild test completed.",
                      0 if code == 0 else 1, xcodebuild_exit_code=code,
                      destination=destination, runtime=runtime["version"])
    except (OSError, ValueError) as error:
        return finish("failed", str(error), 1)


if __name__ == "__main__":
    raise SystemExit(main())
