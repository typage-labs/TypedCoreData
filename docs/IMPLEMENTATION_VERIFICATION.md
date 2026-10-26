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
