# 0.1.0 release preparation

**26 October 2026 — ready for human review; NO-GO for publication yet.**
The proposed licensing and source inventory require owner approval, Git index
cleanup is blocked by this session's filesystem permissions, the remote URL is
unknown, and the prepared hosted CI has not run. No commit, push, tag or
publication was performed.

## Changes prepared

- Official Apache 2.0 terms in `LICENSE`, with a separate attribution proposal and
  provenance inventory in [LICENSING_REVIEW.md](LICENSING_REVIEW.md). These do not
  establish ownership or Olvid SAS rights clearance.
- T1: negative compiler checks now require exit 1 and the intended diagnostic
  category/types from diagnostic headers, excluding echoed source and notes.
  Additional unrelated errors cause failure. An actual mutated Swift fixture
  confirms that the missing-symbol false positive fails the intended ID check.
- T2: native crash probes select ARM64 or x86_64 according to the verification
  process architecture. Both macOS architectures and the iOS minimum targets
  remain cross-compiled. Twelve Python self-tests exercise matcher and host
  selection behavior and run automatically before the compiler checks.
- T3: three real SQLite tests exercise typed ID fetches, predicates and sections
  on private context queues. Only Sendable snapshots return across the async
  boundary; context reset completes before store cleanup. Three new subprocess
  probes exercise the existing/object/registered resolver mismatch preconditions.
- Read-only CI, remote-installation preparation, 0.1.0 changelog, updated roadmap,
  and ignored Python bytecode caches. The positive client now covers the explicit
  function type that disambiguates `context.execute` (A1).

**All seven production sources and Package.swift are byte-for-byte unchanged**
from the beginning of this preparation. No public API or deployment target changed.
No existing source/comment copyright notice was removed.

## Git index — unresolved filesystem blocker

Inspected HEAD, index blobs, staged diff, unstaged diff and every untracked path.
HEAD remains `ccc8a44` (Initial Commit), with no remotes or tags. The index is not
the release candidate: it contains early versions of `ManagedID.swift` and the
context extension, the old manifest/test template, and absent source files.

The authorized cleanup command was attempted:

```sh
git rm --cached -- Sources/TypedCoreData/TypeSafeCoreData.swift
```

It failed with exit 128:

```text
fatal: Unable to create '/Users/sylvainheraud/Dev/TypedCoreData/.git/index.lock': Operation not permitted
```

This session grants read-only access to `.git` and cannot request elevated access.
The index was not changed or bypassed. Its SHA-256 remains
`925a7a1bc8c49ac16d5f5b31931a2514473c798ee1c3b8e1237408efcef6bb76`.
The obsolete file is **absent from the working tree and the intended release
inventory, but remains in the current index**. It is not correct to say that R1
is resolved.

On a normal writable checkout, the owner can run the command above, then verify:

```sh
git ls-files -- Sources/TypedCoreData/TypeSafeCoreData.swift
git diff --cached --stat
git status --short --untracked-files=all
```

The first command should produce no output after cleanup. The old template
`Sources/TypedCoreData/TypedCoreData.swift` is also absent from the working tree
but tracked in HEAD/index; its existing deletion must be staged during final
candidate reconciliation. No unrelated file was deleted or staged here.
Reconcile all intended additions, modifications and these deletions against the
inventory before inspecting the complete staged diff and testing that exact
candidate. Do not commit the present stale index.

Working-tree `git diff --check` passes. `git diff --cached --check` still fails
on five trailing-whitespace lines in the obsolete staged `TypeSafeCoreData.swift`;
this is part of the unresolved index cleanup, not a new source warning.

## Exact intended release inventory

[RELEASE_FILES.txt](RELEASE_FILES.txt) is the explicit, sorted **48-file** inventory
of this proposed source release, including itself and this report. It lists paths
relative to the repository root. This is a review manifest, not a claim that the
files are staged, legally cleared, committed or published.

It includes the seven production files, manifest, normal and isolated tests,
verification/CI tools, documentation and nine historical research files.
Research files are retained for the study's reproducibility and provenance; they
are outside the package targets and are not run by normal tests or CI. Their
dangerous native-exception probes remain isolated and were not rerun here.

Excluded: both absent obsolete/template Swift files, `.git`, `.build`, Xcode
derived data, `.DS_Store`, Python caches, temporary logs and generated binaries.
Test-only Objective-C exception support is not part of the library product.
The review snapshot is a file-based candidate, not a Git export, because the
index cannot be reconciled in this session.

The 48-file allowlist was compared with every existing tracked/untracked,
non-ignored file and copied to `.build/release-preparation/candidate/TypedCoreData/`.
Both obsolete Swift paths are absent there. An external SwiftPM consumer built
the copied package using the README's local dependency and product spelling;
the library and client compiled with complete concurrency and warnings as errors.
No test-only Objective-C helper was built or linked. This validates local package
consumption and the intended source inventory, not a remote Git tag.

## Verification

Local environment: Xcode 27.1 (`27A9275`), Apple Swift 6.4
(`swiftlang-6.4.0.34.1`), macOS 27.0.1 ARM64; macOS SDK 27.0 and iOS SDK 27.1.
All Swift compiler verification uses Swift 6 language mode, complete concurrency
checking and warnings as errors.

| Check | Result | Evidence / limit |
| --- | --- | --- |
| Complete debug suite | **63 tests / 73 cases / 8 suites passed** | `.build/release-preparation/debug-tests.log`; zero compiler warnings |
| Complete optimized release suite | **63 tests / 73 cases / 8 suites passed** | `.build/release-preparation/release-tests.log`; zero compiler warnings; debug-symbol generation disabled as described below |
| Updated compiler/verifier run | **Passed: 12 Python self-tests; 4 library/client targets; 14 expected compiler rejections; 1 actual mutation check; 7 isolated traps** | `.build/advanced-verification/results.json` and per-check logs; native traps executed on ARM64, signal 5 with expected production diagnostics |
| Clean file-based candidate / external SwiftPM consumer | **Built successfully; zero compiler warnings** | `.build/release-preparation/candidate-consumer.log`; copied manifest and production files match the reviewed working tree |
| iOS simulator execution | **Skipped locally; no iOS runtime tests executed** | CoreSimulator service inventory fails, not evidence that no runtime is installed; required mode fails instead of passing |
| Hosted CI / oldest Swift 6 toolchain / Intel host execution | **Not executed here** | Workflow prepared; pending actual runner results |

The test totals comprise the previous 60 tests / 70 cases plus three private-queue
tests. Parameterized invocations account for the additional cases. Swift Testing
reports 63 declarations in its final summary. Expected native Core Data logs from
read-only stores and deliberate missing-table tests are not compiler warnings.

Full-suite commands used writable caches and the established nested compiler
plugin sandbox accommodation, preserving strict checking and the outer sandbox:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-module-cache" \
swift test --disable-sandbox \
  --cache-path .build/cache --config-path .build/config \
  --security-path .build/security --scratch-path .build/advanced-package \
  -Xswiftc -disable-sandbox \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The release run adds `-c release -debug-info-format none`. The previous review
reproduced a host permission failure during dSYM generation; this run deliberately
uses the documented accommodation. Optimization is retained. CI runs ordinary
debug and release commands with debug-symbol generation enabled.

```sh
python3 Scripts/verify-advanced-apis.py
python3 Scripts/test-ios-simulator.py
python3 Scripts/test-ios-simulator.py --require-runtime
```

The simulator helper was executed in both modes. Logs and JSON reports are in
`.build/ios-simulator/run-p5qy2aou/` (optional) and
`.build/ios-simulator/run-qhhxixbg/` (required). It reports unavailable
service/runtime execution as `SKIPPED`
with exit 77 locally, or exit 1 in required mode. Build/test failures always fail.
It chooses an available iOS 17+ device compatible with the selected SDK to include
predicate tests, and schedules no runtime downloads or device creation.

The resolver probes intentionally inject a class/model mismatch through the native
designated initializer. They first verify the actual native returned class and
raw resolver behavior, then require the production precondition diagnostic and
process termination. This tests guards under an invalid configuration; it does
not present that configuration as supported application usage. No public unchecked
ID initializer, mocked ID, or mutation of a model attached to a store was added.

## CI and support limits

[ci.yml](../.github/workflows/ci.yml) has read-only `contents` permission, checkout
credentials disabled, timeouts, and no release/publication job. It prepares:

- Intel `macos-15-intel` / Xcode 16.0 for the Swift 6.0 compiler floor.
- ARM64 `macos-26` / Xcode 26.6 for another Swift 6 toolchain.
- Debug and optimized release tests, strict concurrency and warnings as errors,
  minimum-target library/client builds and negative/crash verification on both.
- A required iOS simulator test job on the latter runner.

Runner/Xcode choices were checked against the
[official Intel image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
and [Apple Silicon image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
Hosted availability can change; CI records the selected compiler/SDK versions
and fails if selection or a required simulator fails. No remote exists here, so
this workflow has not executed on GitHub. Local YAML/Python syntax and synthetic
simulator-selection checks do not substitute for that execution.

Current cross-build evidence verifies macOS 10.15 Intel, macOS 11 ARM64, iOS 13
device and iOS 13 Intel simulator compilation. It does not certify those old OS
runtimes, Intel execution, or iOS execution. Native predicate APIs still require
iOS 17 / macOS 14. The new async private-context tests require iOS 15 / macOS 12;
the library does not acquire that requirement. Native SQLite/nil semantics,
queue confinement, batch synchronization and runtime metadata limitations remain
as documented in README.

## Remaining human decisions

1. Confirm provenance, legal copyright holder(s), attribution and authority to
   apply Apache 2.0, including any Olvid SAS permission or material replacement.
   See [LICENSING_REVIEW.md](LICENSING_REVIEW.md); no rights clearance is asserted.
2. Remove obsolete index entries and reconcile the full candidate on a writable
   checkout. Review the staged diff against the explicit inventory.
3. Confirm the actual GitHub repository URL; replace the README placeholder only
   then. Versioned remote installation cannot be verified before the actual
   repository/tag exists. The `.upToNextMinor(from: "0.1.0")` policy is prepared.
4. Obtain successful hosted CI and iOS runtime results, review any oldest-toolchain
   differences, and explicitly accept remaining old-runtime coverage limits.

**Stop for final human review.** Passing local tests and preparing license text
do not authorize publication or turn these unresolved items into completed work.

## Final Git status

Snapshot after preparation, before any human staging. `AM` means an older staged
addition also has working-tree edits; `AD` is the obsolete staged addition absent
from disk; `??` files are still untracked. No new files were staged in this run.

```text
 M .gitignore
 M Package.swift
AM Sources/TypedCoreData/ManagedID.swift
AM Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift
AD Sources/TypedCoreData/TypeSafeCoreData.swift
 D Sources/TypedCoreData/TypedCoreData.swift
 M Tests/TypedCoreDataTests/TypedCoreDataTests.swift
?? .github/workflows/ci.yml
?? CHANGELOG.md
?? Experiments/AdvancedTypeSafety/GeneratedModel.xcdatamodel/contents
?? Experiments/AdvancedTypeSafety/GeneratedSubclassPredicate.swift
?? Experiments/AdvancedTypeSafety/IdentityAndSections.swift
?? Experiments/AdvancedTypeSafety/NativePredicateBridge.swift
?? Experiments/AdvancedTypeSafety/PredicatePrototype.swift
?? Experiments/AdvancedTypeSafety/PredicateTypeSafety.swift
?? Experiments/AdvancedTypeSafety/SQLitePredicates.swift
?? Experiments/AdvancedTypeSafety/Support/module.modulemap
?? Experiments/AdvancedTypeSafety/run.py
?? LICENSE
?? README.md
?? Scripts/test-ios-simulator.py
?? Scripts/test_verify_advanced_apis.py
?? Scripts/verify-advanced-apis.py
?? Sources/TypedCoreData/FetchedResultsSections.swift
?? Sources/TypedCoreData/NSBatchDeleteRequest+ManagedID.swift
?? Sources/TypedCoreData/NSManagedObjectContext+BatchOperations.swift
?? Sources/TypedCoreData/NSManagedObjectContext+FetchObjectIDs.swift
?? Sources/TypedCoreData/PredicateAttachment.swift
?? Tests/CompileChecks/AdvancedAPIs.swift
?? Tests/CompileChecks/GenericObjectiveCBoundary.swift
?? Tests/CoreDataExceptionSupport/CoreDataExceptionSupport.m
?? Tests/CoreDataExceptionSupport/include/CoreDataExceptionSupport.h
?? Tests/IsolatedProbes/FetchedResultsSectionPreconditions.swift
?? Tests/IsolatedProbes/ManagedObjectResolutionPreconditions.swift
?? Tests/TypedCoreDataTests/BatchFailureTests.swift
?? Tests/TypedCoreDataTests/BatchOperationTests.swift
?? Tests/TypedCoreDataTests/FetchObjectIDTests.swift
?? Tests/TypedCoreDataTests/FetchedResultsSectionTests.swift
?? Tests/TypedCoreDataTests/ManagedIDValidationTests.swift
?? Tests/TypedCoreDataTests/PredicateAttachmentTests.swift
?? Tests/TypedCoreDataTests/PrivateContextAPITests.swift
?? Tests/TypedCoreDataTests/SQLiteTestStack.swift
?? Tests/TypedCoreDataTests/TestStack.swift
?? docs/ADVANCED_TYPE_SAFETY_STUDY.md
?? docs/API_AUDIT.md
?? docs/IMPLEMENTATION_VERIFICATION.md
?? docs/LICENSING_REVIEW.md
?? docs/PRE_RELEASE_REVIEW.md
?? docs/RELEASE_FILES.txt
?? docs/RELEASE_PREPARATION.md
```
