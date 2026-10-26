#!/usr/bin/env python3
"""Compile public API clients and run fatal probes in isolated child processes.

Uses Python's standard library and Apple's installed toolchain only. Run the
Swift package suite separately with strict concurrency and warnings as errors.
No simulator/device runtime is required for these cross-compilation checks.
Parser and host-selection self-tests: python3 Scripts/test_verify_advanced_apis.py
"""

from dataclasses import dataclass
from pathlib import Path
import json
import os
import platform
import re
import resource
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build" / "advanced-verification"
RESULTS = []
ENVIRONMENT = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(BUILD / "module-cache"))

# Match diagnostic headers only. Swift echoes source and notes below them;
# neither is evidence that the intended compiler error occurred. Source gutters
# contain '|', which is deliberately excluded from the location prefix.
ERROR_HEADER = re.compile(r"^(?:[^|\r\n]+:\d+(?::\d+)?: )?error: (.+)$")


def compiler_error_messages(output):
    return [match.group(1) for line in output.splitlines()
            if (match := ERROR_HEADER.fullmatch(line))]


@dataclass(frozen=True)
class CompilerRejection:
    """Require intended errors and reject any unrelated diagnostic or crash."""

    required: tuple[str, ...]
    allowed_companions: tuple[str, ...] = ()

    def matches(self, returncode, output):
        messages = compiler_error_messages(output)
        patterns = self.required + self.allowed_companions
        return (
            returncode == 1
            and bool(messages)
            and all(any(re.match(pattern, message) for message in messages)
                    for pattern in self.required)
            and all(any(re.match(pattern, message) for pattern in patterns)
                    for message in messages)
        )


NEGATIVE_CASES = {
    "WRONG_ID_RESULT": CompilerRejection((
        r"cannot (?:assign|convert) value of type '\[ManagedID<CompileContact>\]' "
        r"to (?:type|specified type) '\[ManagedID<CompileCompany>\]'",
    )),
    "WRONG_SECTION_RESULT": CompilerRejection((
        r"cannot (?:assign|convert) value of type '\[CompileContact\]\?' "
        r"to (?:type|specified type) '\[CompileCompany\]\?'",
    )),
    "UNCHECKED_ID_INITIALIZER": CompilerRejection((
        r"missing argument label 'validating:' in call",
    )),
    "WRONG_PREDICATE_ROOT": CompilerRejection((
        r"cannot convert value of type 'NSFetchRequest<CompileContact>' "
        r"to expected argument type 'NSFetchRequest<CompileCompany>'"
        r"|cannot convert value of type 'Predicate<CompileCompany>' "
        r"to expected argument type 'Predicate<CompileContact>'",
    )),
    "WRONG_PREDICATE_VALUE": CompilerRejection((
        r"binary operator '==' cannot be applied to operands of type 'Int64' and 'String'",
    )),
    "UNGUARDED_PREDICATE_API": CompilerRejection((
        r"'setPredicate\(_:on:\)' is only available in (?:macOS 14|iOS 17)(?:\.0)? or newer",
    ), allowed_companions=(
        r"'Predicate' is only available in (?:macOS 14|iOS 17)(?:\.0)? or newer",
    )),
}
OBJC_GENERIC_REJECTION = CompilerRejection((
    r"extension of a generic Objective-C class cannot access the class's generic parameters at runtime",
))
MISSING_SYMBOL_REJECTION = CompilerRejection((
    r"cannot find 'unrelatedMissingSymbol' in scope",
))


def native_target_label(machine):
    """Select a runnable macOS binary without dropping cross-target builds."""
    labels = {"arm64": "macos-arm64", "x86_64": "macos-minimum"}
    try:
        return labels[machine]
    except KeyError:
        raise ValueError(f"Unsupported native probe architecture: {machine!r}") from None


def run(arguments, label, *, rejection=None, trap=None):
    environment = dict(ENVIRONMENT)
    if "-sdk" in arguments:
        # xcrun's host SDK environment otherwise reaches the linker's clang
        # driver even when swiftc's frontend receives a cross-platform -sdk.
        environment["SDKROOT"] = arguments[arguments.index("-sdk") + 1]
    result = subprocess.run(arguments, cwd=ROOT, env=environment, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (BUILD / f"{label}.log").write_text(result.stdout)
    RESULTS.append({"label": label, "exit_code": result.returncode,
                    "log": f"{label}.log"})
    print(f"{label}: exit {result.returncode}", flush=True)
    if rejection is not None:
        success = rejection.matches(result.returncode, result.stdout)
    elif trap is not None:
        success = result.returncode < 0 and trap in result.stdout
    else:
        success = result.returncode == 0 and "warning:" not in result.stdout
    if not success:
        print(result.stdout)
        raise SystemExit(f"Unexpected result: {label}")
    return result


def sdk(name):
    return subprocess.check_output(["xcrun", "--sdk", name, "--show-sdk-path"],
                                   cwd=ROOT, env=ENVIRONMENT, text=True).strip()


def verify_missing_symbol_mutation(compiler, flags, destination, client):
    """The pre-release review's unrelated-error mutation must not pass T1."""
    source = client.read_text()
    original = "let _: [ManagedID<CompileCompany>] = try context.fetchObjectIDs(for: request)"
    mutated = "let _: [ManagedID<CompileCompany>] = unrelatedMissingSymbol()"
    if source.count(original) != 1:
        raise SystemExit("Cannot locate the unique WRONG_ID_RESULT mutation site")
    fixture = BUILD / "UnrelatedErrorMutation.swift"
    fixture.write_text(source.replace(original, mutated))
    result = run([*compiler, *flags, "-I", str(destination), "-typecheck",
                  "-D", "WRONG_ID_RESULT", str(fixture)],
                 "selfcheck-unrelated-error-mutation", rejection=MISSING_SYMBOL_REJECTION)
    if NEGATIVE_CASES["WRONG_ID_RESULT"].matches(result.returncode, result.stdout):
        raise SystemExit("Unrelated missing-symbol error incorrectly passed the ID-type check")
    print("Verifier mutation self-check: unrelated error correctly rejected", flush=True)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    RESULTS.clear()
    # Do not leave a prior successful summary behind after a failed verification.
    (BUILD / "results.json").unlink(missing_ok=True)
    host_label = native_target_label(platform.machine())
    print(f"Native executable probes use {host_label} ({platform.machine()})", flush=True)
    run([sys.executable, str(ROOT / "Scripts/test_verify_advanced_apis.py")], "verifier-self-tests")
    compiler = ["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                "-warnings-as-errors", "-no-color-diagnostics",
                "-module-cache-path", str(BUILD / "module-cache"),
                # Allows macro subprocesses within restricted hosts, preserving
                # Swift checking and the outer process sandbox.
                "-disable-sandbox"]
    sources = list(map(str, sorted((ROOT / "Sources/TypedCoreData").glob("*.swift"))))
    client = ROOT / "Tests/CompileChecks/AdvancedAPIs.swift"
    boundary = str(ROOT / "Tests/CompileChecks/GenericObjectiveCBoundary.swift")
    targets = [
        # Apple Silicon macOS starts at 11. Intel checks the package's 10.15 minimum.
        ("macos-arm64", "macosx", "arm64-apple-macosx11.0"),
        ("macos-minimum", "macosx", "x86_64-apple-macosx10.15"),
        ("ios-minimum", "iphoneos", "arm64-apple-ios13.0"),
        ("ios-simulator-minimum", "iphonesimulator", "x86_64-apple-ios13.0-simulator"),
    ]
    settings = {}
    for label, sdk_name, target in targets:
        destination = BUILD / label
        destination.mkdir(exist_ok=True)
        flags = ["-sdk", sdk(sdk_name), "-target", target]
        settings[label] = (destination, flags)
        run([*compiler, *flags, "-parse-as-library", "-module-name", "TypedCoreData",
             "-emit-library", "-emit-module", "-emit-module-path", str(destination / "TypedCoreData.swiftmodule"),
             *sources, "-o", str(destination / "libTypedCoreData.dylib")], f"build-{label}")
        run([*compiler, *flags, "-I", str(destination), "-typecheck", str(client)],
            f"client-positive-{label}")

    for label in ["macos-minimum", "ios-minimum"]:
        destination, flags = settings[label]
        for flag, diagnostic in NEGATIVE_CASES.items():
            run([*compiler, *flags, "-I", str(destination), "-typecheck", "-D", flag, str(client)],
                f"reject-{label}-{flag}", rejection=diagnostic)

    host, host_flags = settings[host_label]
    verify_missing_symbol_mutation(compiler, host_flags, host, client)
    run([*compiler, *host_flags, "-typecheck", boundary], "generic-function-boundary-positive")
    for flag in ["EXACT_SECTION_METHOD", "EXACT_PREDICATE_METHOD"]:
        run([*compiler, *host_flags, "-typecheck", "-D", flag, boundary],
            f"reject-{flag}", rejection=OBJC_GENERIC_REJECTION)

    probe = BUILD / "section-preconditions"
    run([*compiler, *host_flags, "-parse-as-library", "-I", str(host), "-L", str(host),
         "-lTypedCoreData", "-Xlinker", "-rpath", "-Xlinker", str(host),
         str(ROOT / "Tests/IsolatedProbes/FetchedResultsSectionPreconditions.swift"),
         "-o", str(probe)], "compile-section-preconditions")
    for scenario in ["negative-index", "out-of-range", "empty-grouped", "wrong-runtime-type"]:
        diagnostic = ("contains objects incompatible with SectionProbeChild"
                      if scenario == "wrong-runtime-type" else "out of bounds for")
        run([str(probe), scenario], f"trap-{scenario}", trap=diagnostic)

    resolution_probe = BUILD / "resolver-preconditions"
    run([*compiler, *host_flags, "-parse-as-library", "-I", str(host), "-L", str(host),
         "-lTypedCoreData", "-Xlinker", "-rpath", "-Xlinker", str(host),
         str(ROOT / "Tests/IsolatedProbes/ManagedObjectResolutionPreconditions.swift"),
         "-o", str(resolution_probe)], "compile-resolver-preconditions")
    for scenario in ["existing-object", "object", "registered-object"]:
        run([str(resolution_probe), scenario], f"trap-resolution-{scenario}",
            trap="Core Data resolved ResolutionProbeExpected; expected ResolutionProbeActual.")

    (BUILD / "results.json").write_text(json.dumps(RESULTS, indent=2) + "\n")
    print("Verified 4 library/client targets, 14 expected compiler rejections, "
          "1 compiler-backed verifier self-check, and 7 isolated traps.")
    print(f"Logs: {BUILD}")


if __name__ == "__main__":
    main()
