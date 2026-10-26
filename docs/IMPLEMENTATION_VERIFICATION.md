# Advanced API implementation and verification

Historical implementation record. The later [pre-release review](PRE_RELEASE_REVIEW.md)
found that this version of the compiler-negative verifier could accept an unrelated
error despite the diagnostic claim below (T1). Release preparation fixes the
harness and adds self-tests; see [current verification](RELEASE_PREPARATION.md)
for the new results, platform gaps and release status.

Verified on 25 October 2026 with Apple Swift 6.4 (`swiftlang-6.4.0.34.1`),
macOS SDK 27.0, iOS SDK 27.1, and macOS 27.0.1 on Apple Silicon.

## Implemented public APIs

```swift
extension ManagedID {
    public init(validating objectID: NSManagedObjectID) throws
}

public extension NSManagedObjectContext {
    func fetchObjectIDs<Entity: NSManagedObject>(
        for request: NSFetchRequest<Entity>
    ) throws -> [ManagedID<Entity>]
}

public func objects<ResultType: NSFetchRequestResult>(
    inSectionAt index: Int,
    of controller: NSFetchedResultsController<ResultType>
) -> [ResultType]?

@available(iOS 17, macOS 14, *)
public func setPredicate<Entity: NSManagedObject>(
    _ predicate: Predicate<Entity>,
    on request: NSFetchRequest<Entity>
) throws
```

The two free functions are the approved replacement for the originally proposed
generic Objective-C extensions. Swift rejects runtime use of those classes'
`ResultType` in the extension bodies. A standalone Swift generic parameter
retains the type information needed for validation and conversion. Each function
uses exactly one generic parameter to bind the controller/result or
predicate/request, with no caller-selected metatype or unchecked cast.

Three small public errors describe library checks:

- `ManagedIDValidationError`: missing, unresolvable, or incompatible declared
  runtime class; no object existence claim.
- `FetchObjectIDsError.unsupportedResultType`: the source request is not in
  managed-object mode.
- `PredicateConversionError.unsupportedPredicate`: Foundation's conversion
  returned nil, and the previous request predicate was preserved.

Native Core Data fetch errors propagate without replacement. No API saves,
promotes IDs, merges changes, or schedules context work. The existing trusted
initializer remains `fileprivate`. Package.swift is unchanged from the preceding
implementation: iOS 13, macOS 10.15, Swift 6, no external dependencies.

## Complete package suite

**Passed: 60 test declarations, 70 executed cases, 7 suites, 0 failures.**
The case count includes parameterized test invocations. The Swift Testing runner
reports the 60 declarations in its final summary.

| Suite | Tests | Cases |
| --- | ---: | ---: |
| Existing managed identifiers and native resolution | 17 | 17 |
| Existing batch operations on SQLite | 8 | 14 |
| Existing batch failures and native input behavior | 4 | 4 |
| Validated identifier construction | 13 | 13 |
| Typed object-ID fetching | 8 | 11 |
| Typed FRC sections | 5 | 5 |
| Native typed predicate attachment | 5 | 6 |
| **Total** | **60** | **70** |

All Swift code compiled in Swift 6 mode with complete strict concurrency and
warnings as errors. **Final compiler warnings: zero.** Expected native Core Data
logging occurs in read-only batch tests and the genuine SQLite fetch-error test;
it is not a compiler warning or an unexpected test failure. The fetch-error test
removes a table only in its disposable SQLite store and verifies that native and
typed fetches return matching NSError domain, code, and userInfo.

The predicate tests execute real SQLite fetches, check conversion failure and
previous-filter preservation, and compare native and typed results for optional
inequality and negation. Swift evaluation includes the fixture's nil rows while
SQLite excludes them. No rewrite or in-memory fallback is introduced.

Normal reproduction:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The restricted host used writable module caches and disabled the compiler's
nested macro-plugin sandbox. These settings do not weaken Swift checking or the
outer host sandbox:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-module-cache" \
swift test --disable-sandbox \
  --cache-path .build/cache --config-path .build/config \
  --security-path .build/security --scratch-path .build/advanced-package \
  -Xswiftc -disable-sandbox \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The selected toolchain built the Swift Testing host at macOS 14. The standalone
production-library checks below separately verify the package's older minimums.

## Deployment targets and compiler contracts

Run:

```sh
python3 Scripts/verify-advanced-apis.py
```

The script uses only the Python standard library and installed Apple toolchain.
It builds and links the actual production sources, then typechecks an external
client importing the resulting module with Swift 6 strict checking and warnings
as errors.

| Target | Production library | Positive external client |
| --- | --- | --- |
| Intel macOS 10.15 | Passed | Passed |
| ARM64 macOS 11.0, native probe host | Passed | Passed |
| ARM64 iOS 13.0 device | Passed | Passed |
| x86_64 iOS 13.0 simulator | Passed | Passed |

Apple Silicon macOS begins at 11.0; the Intel build verifies the package's 10.15
minimum. Mach-O load commands independently confirmed minimum versions 10.15,
13.0 and 13.0 for the macOS, iOS-device and simulator minimum-target libraries.
The manifest's deployment targets were not raised.

**14 expected compiler-negative results passed:** six external-client cases on
each of macOS 10.15 and iOS 13, plus two rejected original extension forms.

| Negative case | Guarantee exercised |
| --- | --- |
| Unrelated requested ID-array type | Request entity type determines `ManagedID<Entity>`. |
| Unrelated requested section-array type | Controller result type determines the section element type. |
| Unlabeled raw-ID initializer | Trusted unchecked construction remains inaccessible. |
| Unrelated native predicate root | Predicate root and request result share one generic type. |
| Comparing numeric property to String in `#Predicate` | Native expression value checking remains active. |
| Unguarded `setPredicate` reference on the minimum targets | The function itself requires macOS 14 / iOS 17. |
| Original section extension | Swift rejects runtime access to the Objective-C generic parameter. |
| Original predicate extension | Swift rejects the generic native conversion in that extension. |

Positive cases verify exact typed results, guarded native predicate use, and
availability-annotated clients. Expected failures must contain the relevant
diagnostic; an unrelated compiler failure does not count as a passing check.

## Isolated failure probes

**Four section probes passed** against the compiled production library. Each
terminated its own child process with the expected Swift precondition diagnostic:
negative index, index at the upper bound, index zero in an empty grouped result,
and a mixed section whose second object has an incompatible runtime class.
The latter confirms that a valid first element does not allow a later mismatch
to escape. Core dumps are disabled by the parent runner.

The fatal probes live outside the package test target. Existing batch-constructor
exception comparisons use the established test-only Objective-C boundary; they
do not add that dependency to the library. Dangerous unsupported-SQL research
probes, including the study's transformable crash, remain outside the ordinary
suite and were not rerun as part of this implementation verification.

Local logs are under `.build/advanced-implementation/` and
`.build/advanced-verification/`; the latter contains `results.json` and individual
compiler/probe logs. Build products and logs are ignored by Git.

## Remaining limitations

- Cross-compilation is not runtime testing on iOS or old macOS versions. Only the
  current macOS runtime was exercised; older Swift 6 toolchains were not tested.
- Native predicate attachment is unavailable before iOS 17 / macOS 14. Successful
  conversion still does not guarantee model validity, SQL translation, or
  Swift-equivalent nil behavior. Unsupported expressions may raise native
  Objective-C exceptions rather than Swift errors.
- Identifier validation proves declared class compatibility only. Temporary,
  deleted, unsaved, or wrong-store identifiers retain native lifecycle rules.
- ID fetching validates each returned ID, not an empty request's entity binding.
  Native pending-change, ordering and pagination differences remain visible.
- A request's generic type cannot prevent later incompatible runtime mutation.
  Section mismatches and invalid indices are explicit programmer preconditions.
- Managed objects and returned section arrays retain context queue confinement.
  Whole-section conversion may allocate or materialize references; no performance
  benchmark or zero-copy guarantee is claimed.

No custom predicate representation, underscored KVC use, unchecked Sendable
conformance, concurrency abstraction, dependency, or third-party implementation
was added. No commit, push, tag, or publication was performed.

## Xcode 16.0 CI compatibility follow-up

**Historical first attempt:** its explicit `@Sendable` closure change was
insufficient. A subsequent hosted failure confirmed that Xcode 16.0 imports
`NSManagedObjectContext` as non-Sendable. The corrected test design and current
verification status are recorded in the next section. The two identity-assertion
changes below remain in place.

**26 October 2026.** The first hosted run was
[40307190448](https://github.com/typage-labs/TypedCoreData/actions/runs/40307190448),
with failed job
[121519102492 — macOS / Xcode 16.0](https://github.com/typage-labs/TypedCoreData/actions/runs/40307190448/job/121519102492).
GitHub CLI was installed but could not connect to `api.github.com` from the
restricted session. Diagnosis uses the job excerpt supplied by the maintainer;
the complete hosted log was not retrieved.

### First failure and classification

The exact failing step was **Debug tests**, running:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

All seven production files compiled before the test target failed. The first
meaningful error was at the original `PrivateContextAPITests.swift:23`, the
`context.perform` call inside a `@MainActor` helper:

```text
sending main actor-isolated value of type '() throws -> Snapshot' with later accesses to nonisolated context risks causing data races
```

The closure was inferred as main-actor-isolated at the older toolchain's async
call boundary. The fix explicitly declares the closure `@Sendable`, preventing
that inherited isolation and checking its captures. The operation parameter and
returned snapshot were already constrained to be Sendable. Core Data still
schedules the work; reset remains inside the private-queue closure before the
main-actor fixture cleans up the store. The same annotation is applied to the
existing `writer.perform` test, which has the same inference-sensitive pattern.
That second call was not separately diagnosed in the supplied log.

The log also reports two older Swift Testing macro expansion errors at the
original `TypedCoreDataTests.swift:60` and `:77`:

```text
call can throw, but it is executed in a non-throwing autoclosure
```

Both assertions had the form `#expect(object === (try nativeLookup()))`. The
generated binary-operation checker could not handle the nested throwing operand.
Evaluating each native lookup into a local `let` first preserves call order,
throwing behavior and the identity comparison, without that macro expansion.

**Classification:** test-source compatibility with Swift 6.0's closure-isolation
checking and its bundled Swift Testing macro. This log does not show a production
`ManagedID` Sendable failure or a CI runner/configuration failure. The exact older
Core Data SDK declaration was not independently inspected, so the closure issue
is not attributed to a specific SDK annotation change or compiler bug as a
verified fact.

### Scope and verification after the fix

Only the two test files above and compatibility documentation changed. Production
sources, public APIs, Package.swift, iOS 13/macOS 10.15 deployment targets, CI
matrix, strict concurrency flags and warnings-as-errors are unchanged. No test
was removed, skipped or weakened; no unchecked conformance or diagnostic
suppression was introduced.

| Check | Result and limits |
| --- | --- |
| Complete debug suite | **63 tests / 73 cases / 8 suites passed**, zero compiler warnings |
| Complete optimized release suite | **63 tests / 73 cases / 8 suites passed**, zero compiler warnings; `-debug-info-format none` retains the previously documented host dSYM workaround |
| Full API verifier | **12 Python self-tests, four minimum-target library/client builds, 14 intended compiler rejections, one mutation check and seven isolated traps passed** |
| Focused closure compiler probe | A compile-only async signature accepting an unannotated escaping closure reproduces actor-transfer rejection; explicit `@Sendable` passes strict SIL compilation. This models inference, not Core Data runtime scheduling or the actual Xcode 16 SDK. |
| Earlier local iOS run | Existing `.build/ios-simulator/run-ksvkj3r3/` logs confirm **63 tests / 8 suites passed** on iOS 27.1 before this patch; this is not a patched-code rerun |
| Patched iOS runtime / Xcode 16.0 | **Not verified in this session**: CoreSimulator service access is unavailable, and Xcode 16.0 is not installed locally |

Local post-fix verification used Xcode 27.1 / Apple Swift 6.4 on ARM64 macOS
27.0.1. Logs are in `.build/xcode16-ci-fix/` (`debug-tests.log`,
`release-tests.log`, `verifier.log`); individual compiler/probe logs remain in
`.build/advanced-verification/`. Swift compilation retained complete strict
concurrency and warnings-as-errors, using the writable caches and nested-sandbox
accommodation documented earlier in this file.

The maintainer reports the first hosted Xcode 26.6 macOS and iOS simulator jobs
passed. The corrected Xcode 16.0 **debug, release and verifier steps still need a
hosted rerun**; the original job stopped during debug test compilation, so it
provides no result for the later steps. Current local success does not establish
that all remaining old-toolchain checks will pass. No commit, push, tag or
publication was performed during this fix.

## Corrected private-context tests for older SDK sendability

The next hosted **Debug tests** failure identified a non-Sendable context capture
in `PrivateContextAPITests.swift:26` and a context capture in the `#require`
expansion at `TypedCoreDataTests.swift:313` (line numbers before this correction).
These are the maintainer's confirmed diagnostics. No new log attachment was
available in this session, so this record does not claim an independent read of
the complete second failure log. Production compilation succeeds according to
that report; the correction remains confined to tests, diagnostics and docs.

### Why the first attempt was insufficient

An explicit `@Sendable` closure avoids inherited main-actor isolation, but also
requires Sendable captures. The earlier probe used the newer SDK's native context
type, so it failed to model the older SDK's non-Sendable context. It therefore
could not establish compatibility with Xcode 16.0.

This distinction is supported by Apple's
[June 2024 DTS guidance](https://developer.apple.com/forums/thread/756807), which
identifies the context as non-Sendable and recommends a nonisolated entry point,
and its [SDK 26 release notes](https://developer.apple.com/go/?id=ipados-26-rn),
which describe the later context and `perform`-family Sendable annotation changes.
Those sources explain the mismatch; current documentation is not a substitute
for inspecting Xcode 16.0's exact final SDK interface.

### Current design and preserved guarantees

- `withPrivateTestContext` in `Tests/TypedCoreDataTests/TestStack.swift` is a
  test-only global async function outside all actor-isolated types. The package
  does not opt into default MainActor isolation. It receives the native
  coordinator and a Sendable operation, creates the context locally, and calls
  native async `perform` with an ordinary closure. It does not capture a context
  from an actor into an explicitly Sendable closure or return a context.
- `Snapshot: Sendable` is still required. Requests, controllers, managed objects
  and attribute reads stay within Core Data's private queue. The existing
  assertions still verify that execution is off the main thread and check native
  results, source-request preservation, identity, ordering and inheritance.
- The SQLite fixture remains owned by MainActor. The private closure's `defer`
  resets the context on success or error, before its async operation completes.
  Only then can the wrapper's `defer` remove the store and directory. The
  identifier-transfer test reuses the same helper and still saves on the private
  queue before resolving the Sendable identifier on the main queue.
- All six private-context entity lookups are evaluated into local optionals
  before `#require`. The macro unwraps the same value and retains its failure
  assertion without embedding a context lookup in its generated closure.

There is no new production scheduling API, unsafe pointer/box, detached task,
unchecked conformance, `nonisolated(unsafe)`, `@preconcurrency import`, lowered
diagnostic setting, removed test or reduced assertion. The coordinator and
operation crossing the actor boundary remain subject to normal Sendable checking.

### SDK signature verification: completed and pending

Only Xcode 27.1 / Swift 6.4 is installed locally. Its macOS 27 SDK was inspected:
the context has `NS_SWIFT_NONISOLATED NS_SWIFT_SENDABLE`, the coordinator has
`NS_SWIFT_SENDABLE`, and the async method is imported as:

```swift
@preconcurrency nonisolated
public func perform<T>(
    schedule: NSManagedObjectContext.ScheduledTaskType = .immediate,
    _ block: @escaping @Sendable () throws -> T
) async rethrows -> T
```

The conservative compile probe uses a **plain non-Sendable mutable class** and
this older-form signature:

```swift
func perform<T>(_ block: @escaping () throws -> T) async rethrows -> T
```

This is an explicitly labeled model of the annotation boundary, not an assertion
that the complete final Xcode 16.0 interface was retrieved. The new helper shape
passes strict SIL compilation with this model and real Testing macros. Three
negative controls reject an explicit Sendable context capture, an actor-inherited
closure transfer, and a non-Sendable coordinator transfer. Thus the probe no
longer accidentally benefits from the current SDK's context conformance.

**Exact Xcode 16.0 SDK verification remains pending.** Attempts to retrieve its
final interface were unsuccessful. Historical SDK header evidence supports the
coordinator's native Sendable conformance, but the final SDK must confirm it.
The CI matrix still includes Xcode 16.0 and now prints the selected SDK path,
context/coordinator Objective-C declarations, native block methods, Swift
interface compiler metadata and every `perform` declaration **before Debug
tests**. This makes the actual signatures available even if test compilation
fails. The read-only inspection runs successfully with the installed SDK;
no compiler flags or CI test gates were weakened.

### Verification of this correction

| Check | Result |
| --- | --- |
| Debug suite, Swift 6 complete concurrency / warnings as errors | **63 tests / 73 cases / 8 suites passed**, zero compiler warnings |
| Optimized release suite, same checks | **63 tests / 73 cases / 8 suites passed**, zero compiler warnings; existing host dSYM accommodation `-debug-info-format none` retained |
| API verifier | Four minimum-target library/client builds, 12 harness self-tests, 14 intended compiler rejections, one mutation check and seven isolated traps; see current local logs |
| Conservative non-Sendable-context probe | Positive compilation and three intended negative controls; compiler evidence only, not Core Data runtime evidence |
| Exact Xcode 16.0 / patched iOS runtime execution | Hosted verification required; local Xcode 16.0 is absent and this session cannot access CoreSimulator |

Logs and probe evidence for this correction are in
`.build/coredata-sendability-fix/`; the API verifier's individual logs are in
`.build/advanced-verification/`. Production sources, public APIs and iOS 13 /
macOS 10.15 deployment targets are unchanged. The earlier passing hosted Xcode
26.6 jobs and local iOS 27.1 run predate this correction and are not counted as
post-change verification. Nothing was committed, pushed, tagged or published.
