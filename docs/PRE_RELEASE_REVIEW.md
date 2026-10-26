# Pre-release critical review — 0.1.0

Historical review snapshot: findings and references below describe the checkout
at review time. Current toolchain support starts at **Xcode 26.6**, with later
compatible releases supported; Xcode 16.0 is no longer a required CI check.
See [current requirements](../README.md#requirements) and
[CI support policy](RELEASE_PREPARATION.md#ci-and-support-limits).

**Review date:** 26 October 2026. **Recommendation: NO-GO for publication.**

The review found no confirmed runtime correctness defect in the current
production sources. It did find an unresolved licensing/provenance release gate,
a Git index that does not represent the reviewed implementation, missing release
verification/installation preparation, and reproducible weaknesses in the
verification tooling. Passing tests do not resolve those findings.

This report is the only source/documentation file added by the review. Production
code, public APIs, tests, manifest, existing documentation and Git index were not
changed. No license was added; nothing was committed, pushed, tagged or published.

## Scope, evidence and severity

Reviewed all seven production source files, Package.swift, README, package tests,
compiler and isolated probes, verification scripts, API_AUDIT.md,
ADVANCED_TYPE_SAFETY_STUDY.md and IMPLEMENTATION_VERIFICATION.md. Also inspected
the working-tree inventory, ignored files, HEAD, staged blobs, tags and remotes.

- **P0:** blocks this release, including an unresolved right to publish under the
  proposed open-source terms. This does not necessarily mean a code exploit.
- **P1:** important to correct before release.
- **P2:** optional improvement or bounded compatibility/test-hardening concern.
- **No issue:** no actionable defect found within the evidence examined; not a
  universal correctness or legal-clearance certificate.

Each finding distinguishes a confirmed observation from an unverified risk.
References identify the working-tree file and line at review time. References
prefixed **Git index** identify a staged blob, not a currently existing file.
Absent files have no line number; their absence is tied to the inventory command
and the affected documentation or manifest.

| ID | Priority | Finding | Evidence status |
| --- | --- | --- | --- |
| L1 | **P0** | Authorized licensing/provenance decision is missing | Missing license/clearance evidence confirmed; infringement or ownership conclusions unresolved |
| R1 | **P1** | HEAD/index are not the reviewed release candidate | Confirmed |
| R2 | **P1** | No CI, oldest-toolchain verification, or iOS runtime evidence | Confirmed coverage/release-process gap; no demonstrated incompatibility |
| R3 | **P1** | Remote package installation and 0.1.0 release contract are not ready | Confirmed documentation/preparation gap |
| T1 | **P2** | Compiler-negative verifier accepts an unrelated error | Reproduced with a disposable fixture |
| T2 | **P2** | Verification runner assumes an Apple Silicon host | Confirmed implementation limitation; Intel execution not performed here |
| A1 | **P2** | Batch overloads make an untyped native method reference ambiguous | Reproduced with strict compiler probes |
| T3 | **P2** | A few invariant/concurrency branches lack direct runtime regression tests | Confirmed coverage gap, not a confirmed implementation defect |

## Licensing and provenance — separate from technical findings

### L1 — P0: no authorized licensing/provenance decision is available

**References:** [ManagedID.swift:14](../Sources/TypedCoreData/ManagedID.swift#L14),
[ManagedID.swift:76](../Sources/TypedCoreData/ManagedID.swift#L76),
[NSManagedObjectContext+ManagedID.swift:17](../Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift#L17),
[advanced study:680](ADVANCED_TYPE_SAFETY_STUDY.md#L680),
[implementation verification:184](IMPLEMENTATION_VERIFICATION.md#L184), and
**Git index** `Sources/TypedCoreData/TypeSafeCoreData.swift:1–54`.

**Evidence / reproduction:**

```sh
rg --files --hidden -g '!**/.git/**' -g '!**/.build/**'
git show :Sources/TypedCoreData/TypeSafeCoreData.swift
git show :Sources/TypedCoreData/ManagedID.swift
```

The repository inventory has no `LICENSE`, `COPYING`, `NOTICE`, or provenance/
permission record. The user explicitly identified an earlier Olvid SAS
implementation distributed under AGPLv3. The staged predecessor contains a typed
ID wrapper, a protocol exposing a typed ID from `Self`, and a context resolver.
Those are the first areas whose development history should be traced. A personal
“Created by” header in that predecessor establishes neither ownership nor a
permission to relicense it.

The study's “no external code was copied” statement and the implementation
report's similar statement describe the recent work. They do not establish the
origin of earlier supplied code, rights assignments, or contractual clearance.
This review did not inspect or copy Olvid implementation code, perform a legal
similarity analysis, or examine employment/assignment agreements. Absence of a
record in the repository is not proof that no permission exists elsewhere.

**User impact:** prospective users cannot identify the authorized redistribution
terms, and publishing now could make an unsupported licensing/ownership claim.
An unlicensed public repository is not the intended open-source release.
[GitHub's licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
distinguishes public visibility from an open-source license grant.

**Minimal correction:** before publication, have the project owner/rightsholder
and appropriately qualified counsel establish the provenance of the supplied,
staged and current code and relevant contractual rights. Record the conclusion
and any written permissions, then add only the authorized license and required
notices. Review documentation, comments and examples as well as Swift files.
Do not add MIT merely because this implementation was rewritten.

The generic-ID idea alone does not establish copyright derivation. Conversely,
a rewrite alone does not decide whether protected expression or employer rights
are involved. The distinction between ideas and expression, and the separate
question of employee-created software, appear in
[Directive 2009/24/EC, Articles 1–2](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32009L0024).
The [GNU copyright FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#HowIGetCopyright)
also identifies employment circumstances, contracts and applicable law as
relevant. If protected AGPL-covered implementation was incorporated, distribution
obligations must be assessed under the applicable license or separate permission;
see [AGPLv3, especially section 5](https://www.gnu.org/licenses/agpl-3.0-body.html).
These sources explain the questions to resolve; they do not determine this
project's jurisdiction, ownership or license outcome.

**Disposition:** release gate, not a finding of confirmed AGPL infringement.
No ownership clearance or license choice is asserted by this review.

## Technical and release findings

### R1 — P1: the index can restore an obsolete unsafe API and omit the reviewed code

**References:** **Git index**
`Sources/TypedCoreData/TypeSafeCoreData.swift:10–15,46–53`;
**Git index** `Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift:10–11`;
current [Package.swift:17](../Package.swift#L17) and
[README.md:406](../README.md#L406).

**Evidence / reproduction:**

```sh
git status --short
git ls-tree -r --name-only HEAD
git ls-files --stage
git show :Sources/TypedCoreData/TypeSafeCoreData.swift
git show :Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift
git ls-files --others --exclude-standard
```

HEAD is the initial template commit `ccc8a44`. The index still contains
`TypeSafeCoreData.swift`, although it is deleted in the working tree (`AD`). Its
staged version exposes `TypeSafeManagedObjectID<T>.init(objectID:)` without
validation and a resolver using `as! T`. The staged context extension for the
current ID type is empty. Most current production additions, tests, README,
scripts and docs are untracked. The manifest also differs between HEAD/index and
the reviewed working copy. There is no release tag or configured remote.

**User impact:** committing/tagging the existing index or publishing HEAD would
not distribute the package that passed review. In particular, the obsolete
unchecked API could reappear while approved APIs and tests disappear.

**Minimal correction:** at a later authorized release-preparation step, reconcile
the index with the intended files and deletions, inspect the complete staged
diff, then verify a clean checkout/archive of that exact candidate. Tag only the
verified commit. Do not use a blind staging operation that might include unrelated
files. The dirty state is understandable under the no-commit instructions; it is
a release-preparation finding, not a defect in the current production sources.

### R2 — P1: advertised compatibility lacks a maintained release verification matrix

**References:** [Package.swift:1](../Package.swift#L1),
[Package.swift:7](../Package.swift#L7), [README.md:16](../README.md#L16),
[implementation verification:3](IMPLEMENTATION_VERIFICATION.md#L3),
[implementation verification:168](IMPLEMENTATION_VERIFICATION.md#L168), and
[verification script:61](../Scripts/verify-advanced-apis.py#L61).
`.github/workflows/` is absent from the full hidden-file inventory.

**Evidence:** the manifest accepts tools 6.0 and the README advertises Swift 6 or
later, iOS 13 and macOS 10.15. Reproduced builds use Swift 6.4/current SDKs. The
iOS checks compile and link code; they do not execute Core Data on iOS. No earlier
Swift 6 toolchain or older OS runtime was available in this review. This limitation
is disclosed, but no CI job currently prevents the support claim from drifting.

**User impact:** a clean local macOS result can miss an older compiler/SDK import
difference or an iOS Core Data runtime difference. No incompatibility is confirmed,
but the public support range is broader than the runtime evidence.

**Minimal correction:** establish a small macOS-hosted CI matrix before release:

1. Select and record the oldest supported Swift 6/Xcode SDK combination and a
   current one; run the package with complete concurrency checking and warnings
   as errors. If the older combination fails, correct the code or explicitly
   narrow the supported toolchain claim.
2. Build the library and external clients at iOS 13/macOS 10.15 deployment targets.
3. Execute the Core Data tests on an available iOS simulator, including SQLite
   predicate and batch behavior. This still does not certify iOS 13 runtime behavior.
4. Run compiler-negative and isolated precondition probes on a compatible host;
   keep expected crashes out of the main test process.
5. Test the exact release candidate, retaining logs and the selected SDK/runtime
   versions. Use read-only workflow permissions and do not run publication from
   ordinary PR/test jobs.

If actual oldest-runtime testing is unavailable, retain that limitation in the
release notes. Do not count a deployment-target build as an old-runtime test.

### R3 — P1: public installation and the 0.1.0 release contract are incomplete

**References:** [README.md:28](../README.md#L28),
[README.md:419](../README.md#L419),
[API_AUDIT.md:696](API_AUDIT.md#L696). `git remote -v` and `git tag --list`
both return no entries.

**Evidence:** installation only shows `.package(path: "../TypedCoreData")`.
That is correct for the current local checkout but not remote GitHub consumption.
There is no confirmed repository URL, versioned install example or release note
identifying what 0.1.0 contains. The historical roadmap still groups several
already implemented additions under 0.2, whereas the proposed first public release
is now 0.1.0.

**User impact:** a new user cannot follow a versioned remote installation path or
tell which of the documented APIs belongs to the first release.

**Minimal correction:** after L1 and candidate preparation, confirm the actual
repository URL, document Xcode and manifest installation for the actual 0.1.0 tag,
and verify it from a clean consumer. Do not invent a GitHub organization/URL.
State the 0.x compatibility policy and choose an explicit dependency range; a
next-minor range is appropriate if minor 0.x releases may break source compatibility.
Publish a short initial API/requirements/limitations release note and reconcile
the roadmap's release labels. Package.swift does not need a package version field:
the remote version belongs to the Git release/tag.

### T1 — P2: an unrelated compiler error can satisfy a negative test

**References:** [verify-advanced-apis.py:36](../Scripts/verify-advanced-apis.py#L36),
[verify-advanced-apis.py:80](../Scripts/verify-advanced-apis.py#L80),
[AdvancedAPIs.swift:28](../Tests/CompileChecks/AdvancedAPIs.swift#L28), and
[implementation verification:143](IMPLEMENTATION_VERIFICATION.md#L143).

**Confirmed reproduction:** in a disposable copy of `AdvancedAPIs.swift`, replace
the `WRONG_ID_RESULT` expression with:

```swift
let _: [ManagedID<CompileCompany>] = unrelatedMissingSymbol()
```

Compile with the same imports, strict flags and `-D WRONG_ID_RESULT`. The only
error is `cannot find 'unrelatedMissingSymbol' in scope`. Nevertheless, the current
acceptance expression is true: exit status is nonzero, `error:` is present, and
`CompileCompany` occurs in the compiler's echoed source line. No type relationship
was tested by that failure. Evidence was retained in
`/tmp/tcd-review-negative-falsepositive.swift` and its `.log` during this review.

**User impact:** a future fixture failure can be reported as proof that an unsafe
API is rejected. The current 14 original negative cases were also inspected and
failed for their intended reasons; this finding does not invalidate every current
negative result. It does invalidate the report's blanket claim that unrelated
compiler failures cannot count.

**Minimal correction:** require an ordinary compiler error exit and match the
expected diagnostic category and relevant types in diagnostic messages, excluding
echoed source. Keep the positive control and compile one negative case at a time.
Add a verifier self-check showing that the missing-symbol fixture is rejected by
the harness rather than accepted as a successful negative test.

### T2 — P2: the documented verification runner cannot execute its probes on Intel

**References:** [verify-advanced-apis.py:63](../Scripts/verify-advanced-apis.py#L63),
[verify-advanced-apis.py:94](../Scripts/verify-advanced-apis.py#L94),
[verify-advanced-apis.py:100](../Scripts/verify-advanced-apis.py#L100),
[README.md:375](../README.md#L375).

**Evidence:** the runner unconditionally selects the `macos-arm64` library and
compiles/runs an ARM64 executable. README requires only macOS plus an Apple Swift
6 toolchain. An Intel host cannot execute this ARM64 binary. The architecture
selection is confirmed in the source; an Intel machine was not available to
reproduce the launch error.

**User impact:** the recommended verification command fails on a supported
development architecture and can fail when copied into an Intel CI job, despite
the library itself compiling for Intel.

**Minimal correction:** select the runnable probe target from the host
architecture while retaining cross-compilation checks. Alternatively document
the script's Apple Silicon-only host requirement and select matching CI runners.
Do not report cross-compilation as successful execution on the other architecture.

### A1 — P2: concrete batch overloads make an untyped method reference ambiguous

**References:** [NSManagedObjectContext+BatchOperations.swift:20](../Sources/TypedCoreData/NSManagedObjectContext+BatchOperations.swift#L20)
and [line 48](../Sources/TypedCoreData/NSManagedObjectContext+BatchOperations.swift#L48).

**Confirmed reproduction:** an external Swift 6 client containing
`let execute = context.execute` compiles with Core Data alone and fails with an
ambiguous-use error after importing TypedCoreData. The two concrete request
overloads add equally available choices when no contextual function type is given.
Ordinary calls with a request argument and raw empty-array batch construction
were not ambiguous in the probes.

**User impact:** some existing client code needs a type annotation when the library
is first imported. This is a bounded source-compatibility effect, not incorrect
batch execution or recursive overload resolution.

**Minimal correction:** document the disambiguation and add a client regression
case. Renaming the approved native-style overloads is not justified by this case:

```swift
let execute: (NSPersistentStoreRequest) throws -> NSPersistentStoreResult =
    context.execute
```

### T3 — P2: some advertised invariants have source review but no direct runtime test

**References:** [typed resolver check:64](../Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift#L64),
[batch result checks:23](../Sources/TypedCoreData/NSManagedObjectContext+BatchOperations.swift#L23),
[section object availability:37](../Sources/TypedCoreData/FetchedResultsSections.swift#L37),
[FRC tests:72](../Tests/TypedCoreDataTests/FetchedResultsSectionTests.swift#L72),
[private-queue test:304](../Tests/TypedCoreDataTests/TypedCoreDataTests.swift#L304).

**Evidence:** four isolated traps test section bounds and element mismatch.
They do not test the typed resolver's class-mismatch precondition or the batch
result-class invariant. Real FRC tests cover absent `sections`, empty sections and
populated sections, but do not observe a nonnil section whose `objects` is nil.
The private-queue transfer test exercises existing ID creation/resolution; new
fetch, predicate and section tests use main-queue contexts.

**User impact:** a few error branches or an accidental future main-queue dependency
could regress without current tests identifying it. No wrong queue access or
broken invariant check was found in the implementation.

**Minimal correction:** when hardening tests, prioritize one private-queue SQLite
scenario using the new APIs and returning only Sendable values, plus an isolated
resolver-mismatch probe. Exercise impossible/native-invariant branches only with
clearly labeled injection tests; do not describe mocks as real Core Data behavior
or manufacture unsafe store use just to raise a coverage number.

## Public declaration review — No issue unless linked above

| Declaration / exact reference | Assessment and evidence | Minimal correction |
| --- | --- | --- |
| [ManagedID:14](../Sources/TypedCoreData/ManagedID.swift#L14), `objectID:16`, trusted initializer `:18` | Stored native ID supplies equality/hash behavior. Generic parameter is invariant and not stored as an object. Public raw ID interop is intentional; unchecked construction remains fileprivate. Checked Sendable compiles with the examined SDK. | None; retain the SDK/toolchain qualification in R2. |
| [Validating initializer:39](../Sources/TypedCoreData/ManagedID.swift#L39) | Uses exact declared class lookup, accepts subclasses, rejects reverse/unrelated mapping, does not fetch. Deleted and temporary IDs passing is documented behavior, not an existence claim. | None. |
| [ManagedIDValidationError:62](../Sources/TypedCoreData/ManagedID.swift#L62), all three cases | Small value-only public error surface; strings avoid retaining a model/object and satisfy Sendable. Missing-name, lookup and incompatibility failures are distinct. | None. |
| [ManagedIdentifiable:76](../Sources/TypedCoreData/ManagedID.swift#L76), `objectID:78`, `managedID:92`, conformance `:97` | The protocol-based `Self` relationship preserves the static subclass type. The inherited property requirement is redundant as a member, but no incorrect access or necessary redesign was found. Broad references produce broad IDs as documented. | None for 0.1.0. |
| [existingObject:17](../Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift#L17), [object:36](../Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift#L36), [registeredObject:52](../Sources/TypedCoreData/NSManagedObjectContext+ManagedID.swift#L52) | Native ID argument selects the native overload; checked result conversion does not mask native errors or report mismatch as nil. Context/store/lifecycle rules remain native. | None; T3 identifies an optional invariant-test gap. |
| [Batch execute:20 and :48](../Sources/TypedCoreData/NSManagedObjectContext+BatchOperations.swift#L20) | Explicit upcast prevents recursion. Concrete results, native errors and untyped payloads are preserved; no save/merge occurs. | Document method-reference ambiguity in A1. |
| [Batch-delete initializer:22](../Sources/TypedCoreData/NSBatchDeleteRequest+ManagedID.swift#L22) | Maps only native IDs. Shared Swift class is explicitly not a same-entity proof. Native validation/exception behavior remains visible. Empty raw literals still select the native constructor. | None. |
| [FetchObjectIDsError:4](../Sources/TypedCoreData/NSManagedObjectContext+FetchObjectIDs.swift#L4), `unsupportedResultType:9`, [fetchObjectIDs:39](../Sources/TypedCoreData/NSManagedObjectContext+FetchObjectIDs.swift#L39) | Mode checked before native copy; only copy mode changes; every ID validates before return. Empty mismatch is deliberately not preflight validation. Real SQLite error parity and no-save/promotion behavior are covered. | None. |
| [objects(inSectionAt:of:):28](../Sources/TypedCoreData/FetchedResultsSections.swift#L28) | One generic parameter binds the native controller to the result. Checked whole-array conversion rejects a later incompatible element. Nil, empty and invalid-index contracts are explicit. No wrapper/cache or redundant cast type. | None beyond T2/T3 tooling/coverage concerns. |
| [PredicateConversionError:9](../Sources/TypedCoreData/PredicateAttachment.swift#L9), `unsupportedPredicate:11`, [setPredicate(_:on:):39](../Sources/TypedCoreData/PredicateAttachment.swift#L39) | One invariant `Predicate<Entity>` root is tied to the request. Conversion completes before mutation; failure preserves the exact previous predicate. Availability and native SQL/nil limitations are documented. | None. |

The free functions are a smaller supported surface than a controller/request
wrapper or custom predicate representation with equivalent guarantees. An
extension that needs the Objective-C class's generic metadata is rejected by the
compiler; the standalone function parameters retain the required Swift type
information. Independent probes rejected unrelated roots and hierarchy narrowing.
No caller-selected generic cast or silent type erasure escape was found.

Naming follows native terms closely enough for 0.1.0. The free names can be
module-qualified (`TypedCoreData.objects`, `TypedCoreData.setPredicate`) if another
module supplies a colliding name. No unnecessary public scheduling abstraction,
model wrapper, generic result caster or public unchecked initializer was found.

## Correctness, security and lifecycle assessment

- **No confirmed unsafe cast or concurrency escape in production.** No `as!`,
  `unsafeBitCast`, `@unchecked Sendable`, underscored KVC conversion or new
  scheduling layer is present. The obsolete staged predecessor is a separate
  R1 concern. Strict Swift compilation does not replace Core Data queue discipline.
- **Queue usage:** production functions execute synchronously on the caller's
  context queue. Tests use main-queue contexts on `@MainActor`, with an existing
  private-context test returning only an ID. No reviewed test passed a managed
  object between queues. Missing private-queue coverage is T3, not a proven race.
- **Temporary/deleted IDs:** lifecycle restrictions and snapshot behavior are
  documented and exercised. Metadata validation is deliberately weaker than
  object existence or destination-store validation. No automatic ID promotion,
  saving or synchronization was found.
- **Native exceptions:** invalid batch inputs and unsupported store predicates
  may still produce Objective-C exceptions. This is documented native behavior,
  not a promise that Swift `throws` catches every failure. The small test-only
  exception bridge is not linked into the library product. Dangerous SQL research
  and intentional Swift traps remain outside ordinary package tests.
- **Predicate semantics:** supported SQLite execution and filter preservation
  are exercised. Successful Foundation conversion is not a SQL validator. The
  observed optional inequality/NOT divergence is documented and intentionally
  not rewritten. No string interpolation query API or new injection surface is
  introduced by these helpers.
- **Memory/performance:** ID validation is linear in result count and performs
  class lookup per ID. Section conversion can materialize references and allocate.
  No benchmark or zero-copy claim is made. No retained cache, context/object cycle,
  leak, or unintended lifecycle action was demonstrated. Optimize only after
  measurement rather than broadening this release.

## Test quality and verification performed

The package tests use real in-memory and disposable SQLite stores. They assert
actual returned identities, values, class metadata, source request options,
registration state and native error parity. These are runtime checks. External
client typechecking and linked cross-platform libraries are compiler/build checks
only; they are not runtime verification of iOS or older macOS.

| Review command/check | Result | Limit |
| --- | --- | --- |
| Complete debug suite, Swift 6 + complete concurrency + warnings as errors | **60 tests / 70 cases, 7 suites passed; zero compiler warnings** | macOS 27.0.1, Swift 6.4/current SDK only |
| First optimized release-suite attempt | **Failed** at `GenerateDSYMFile`: `Operation not permitted` | Host build-tool permission failure; tests did not run in this attempt |
| Optimized release suite with `-debug-info-format none`, same strict flags | **60 tests / 70 cases, 7 suites passed; zero compiler warnings** | Debug-symbol generation excluded; optimization and strict checks retained |
| `python3 Scripts/verify-advanced-apis.py` | Four library/client targets built; 14 expected compiler failures; four isolated precondition traps | Current compiler; traps executed on ARM64 macOS only; T1/T2 qualify verifier strength/portability |
| Independent inference probes | Intended unrelated roots, ID mixtures and narrowing rejected; native empty batch arrays accepted | Compiler evidence only |
| Disposable external SwiftPM consumer using README dependency/product declarations | **Built with strict concurrency and warnings as errors; zero warnings/errors; test helper neither built nor linked** | Local package dependency, not remote GitHub installation or runtime execution |
| Negative-verifier mutation probe | Unrelated missing-symbol error incorrectly accepted by the verifier rule | Confirmed tooling defect T1; repository fixture unchanged |
| Git inventory and ignored build artifacts | `.build`, `.DS_Store`, common Xcode output ignored; no generated binaries tracked | Does not repair the stale index or establish legal provenance |

The successful negative cases were inspected for their actual mismatch/availability
diagnostics rather than relying exclusively on the script's broad token test.
Core Data's expected read-only and missing-table diagnostics are logged by error
propagation tests; they are not compiler warnings or unexpected suite failures.
No dangerous transformable crash probe was rerun.

The consumer was built under `/tmp/tcd-packaging-review-client` using
`swift build --product TypedCoreDataPackagingClient` with the same strict Swift
flags and writable caches. Its log is `/tmp/tcd-packaging-review-build.log`.
It compiles all public API signatures from outside the library. This verifies
the real SPM product boundary rather than only direct `swiftc` compilation.

Commands used writable cache/scratch paths and the previously documented
compiler-plugin sandbox accommodation, without weakening concurrency checking:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-module-cache" \
swift test --disable-sandbox \
  --cache-path .build/cache --config-path .build/config \
  --security-path .build/security --scratch-path .build/advanced-package \
  -Xswiftc -disable-sandbox \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

For the successful release run, the same command included
`-c release -debug-info-format none`. Logs are in `.build/pre-release-review/`;
the compiler/probe runner also writes `.build/advanced-verification/`. The latter
script contains its exact target triples and flags. These outputs are ignored.

Package structure itself has no identified defect: one library product, no
external dependencies, separate test support, and experimental/fatal probes
outside the package test target. Every current public declaration has API comments.
The historical audit/study explicitly point to the current API guide. A standalone
DocC site, issue templates or a code-of-conduct file are not prerequisites for
correctness and are not promoted to release blockers here.

## Release decision

**NO-GO for 0.1.0 publication on the evidence currently available.** This is not a
claim of a discovered exploitable defect or a confirmed copyright violation.

Before a GO decision, resolve L1 with the responsible humans, prepare and verify
the exact release candidate in R1, establish the support/CI evidence in R2, and
finish real remote/versioned installation and release documentation in R3.
P2 items may be explicitly accepted for a small first release, but the verifier
false-positive should preferably be corrected before it is used as a CI gate.

No API redesign or feature expansion is recommended. Stop for human review;
this report does not authorize licensing, committing, tagging or publication.
