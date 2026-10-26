# Advanced Type Safety Study

**Status: historical design study, followed by approved implementation.**

The study below records the original proposals and research evidence. The
implementation keeps ID reconstruction and ID-fetch signatures, but uses
`objects(inSectionAt:of:)` and `setPredicate(_:on:)` as generic free functions,
as approved after a compiler limitation was discovered. See the
[implementation correction](#implementation-correction) and
[verification results](IMPLEMENTATION_VERIFICATION.md). The [README](../README.md)
is the current API guide.

All approved implemented additions are included in the proposed **0.1.0** scope.
See [the updated roadmap](API_AUDIT.md#4-prioritized-roadmap) and
[release preparation](RELEASE_PREPARATION.md) for the current evidence and
unresolved publication gates. The proposals below remain historical design work.

Study date: 25 October 2026. Read alongside [API_AUDIT.md](API_AUDIT.md).
The audit's A15/A16 batch proposals are now implemented in the existing package;
this study does not change them, `ManagedID`, or any other public API.

## Findings and proposed direction

There are useful, small additions available, but none can make a runtime Core
Data model a compile-time Swift fact:

1. **Predicates:** Foundation already converts `Predicate<Entity>` to
   `NSPredicate` on macOS 14 / iOS 17. Conversion is failable, and successful
   conversion does not establish SQLite support or Swift-equivalent nil
   semantics. Prefer a small, availability-gated typed attachment to a native
   fetch request before designing another predicate language.
2. **Baseline predicate support:** Key-path factories can reject wrong values
   and retain the root across composition on macOS 10.15 / iOS 13. A small typed
   representation would be justified only if supporting these older systems is
   an explicit requirement for the new predicate feature. Its first version
   should cover persisted scalar properties, nil checks, and composition.
3. **Sections:** A checked `[ResultType]?` section accessor fills a real hole in
   the generic fetched-results controller. It should remain an extension.
4. **Reconstruction:** A validating `ManagedID` initializer can check the class
   declared by an ID's entity. It cannot establish store existence or prove
   compatibility with a particular destination context.
5. **ID fetching:** Copying a native request and validating every returned ID
   offers a useful result guarantee without a new request abstraction. It must
   document ID-mode semantics, temporary IDs, and potentially different ordering.

The most consequential experiment was a successfully bridged native
`#Predicate` whose Swift and `NSPredicate` in-memory evaluations included nil
rows, while SQLite excluded them. A promise of “Swift expressions with identical
database semantics” would be incorrect for the tested optional comparisons.

## 1. Evidence and scope

The study inspected the current sources, tests, README, API audit, installed SDK
headers and Swift interfaces, and the primary sources linked below. Executable
experiments are in [Experiments/AdvancedTypeSafety](../Experiments/AdvancedTypeSafety).
They are outside all Swift package targets and use no external dependencies.

| Environment | Examined configuration |
| --- | --- |
| Compiler | Apple Swift 6.4, `swiftlang-6.4.0.34.1` |
| Language and checks | Swift 6, complete strict concurrency, warnings as errors |
| SDKs | macOS 27.0; iOS 27.1 |
| Runtime used for experiments | macOS 27.0.1, Apple Silicon |
| Existing package minimums | macOS 10.15; iOS 13 |

Evidence is distinguished throughout:

- **Executed:** behavior reproduced by the included compiler or SQLite probes.
- **SDK/documented:** declarations or contracts inspected in Apple sources.
- **Source-reviewed:** external library code inspected, without installing or
  running that library.
- **Proposed:** an architecture or contract to review, not an implemented feature.

Runtime observations apply to this SDK/runtime and these models. They are not a
certification of all supported operating systems, stores, transformations, or
expressions. There are no timing or allocation benchmarks. This is a study of
Core Data interoperability; SwiftData's acceptance of an expression is not used
as evidence that Core Data accepts it.

## 2. Native API inventory

Signatures are abbreviated to their relevant Swift surface. `E` denotes an
`NSManagedObject` subclass and `R` an `NSFetchRequestResult` type.

| API / relevant signature | What is already typed | Remaining boundary |
| --- | --- | --- |
| `NSPredicate(format:argumentArray:)`, `init(block:)`, `evaluate(with:)` | No entity/property relationship; evaluation accepts `Any?`. | Format strings, argument types and model keys are unchecked. A block is not a SQLite predicate. |
| `NSExpression(forKeyPath: String)`, `init(forConstantValue: Any?)` | No root/value relation. | Key and operand compatibility are runtime concerns. |
| `NSExpression.init<Root, Value>(forKeyPath: KeyPath<Root, Value>)` | Checks that the property exists on `Root`. | Returns an erased expression; does not tie a comparison constant to `Value`. Nonfailable conversion requires a KVC-representable key path. |
| `NSComparisonPredicate(leftExpression:rightExpression:modifier:type:options:)` | Native operator/modifier enums. | Expressions need not have compatible values or roots; an enum case does not imply SQL support. |
| `NSCompoundPredicate(andPredicateWithSubpredicates:)`, `orPredicateWithSubpredicates:`, `notPredicateWithSubpredicate:` | Native logical composition. | Components have no retained generic root. |
| `Predicate<each Input>`, `#Predicate<E> { ... }` | Root and expression values are checked; the standard expression tree is `Sendable`. | Only supported Swift expression forms expand; compiled expressions need not convert or execute in Core Data. |
| `PredicateExpressions`, `StandardPredicateExpression<Output>` | Expression input/output types, operator constraints, and standard expression requirements. | Hand-building a tree does not add a model or persistent-store proof. |
| `NSPredicate.init?<Input>(_ predicate: Predicate<Input>) where Input: NSObject` | Converts a typed, single-input Swift predicate. | Failable; the returned `NSPredicate` erases `Input`. |
| `Expression<each Input, Output>`, `#Expression`, `NSExpression.init?<Input, Output>(_ expression: Expression<Input, Output>) where Input: NSObject` | Typed expression construction and a failable native bridge. | Same conversion/model/SQL boundaries; newer availability than `Predicate`. |
| `NSFetchRequest<R>`, `context.fetch<R>(_:) throws -> [R]` | Request result type determines returned Swift array type. | Mutable `entity`, `entityName` construction, `resultType`, `predicate: NSPredicate?`, and `sortDescriptors: [NSSortDescriptor]?` are not dependent on `R`. |
| `NSSortDescriptor.init<Root, Value>(keyPath: KeyPath<Root, Value>, ascending: Bool)` | Property selection is typed at construction. | The descriptor loses its root and is not proof of a persisted/sortable model property. |
| `SortDescriptor<Compared>` and `NSSortDescriptor.init<Compared>(_: SortDescriptor<Compared>) where Compared: NSObject` | Swift sorting retains the compared root; a native bridge already exists. | Request assignment still accepts erased descriptors; SQL supports only its own ordering operations. |
| `NSFetchedResultsController<R>.fetchedObjects: [R]?`, `object(at: IndexPath) -> R` | All fetched objects and one indexed object are already typed. | `sections: [any NSFetchedResultsSectionInfo]?`; section `objects: [Any]?` loses `R`. |
| `NSManagedObjectID.entity: NSEntityDescription`, `isTemporaryID: Bool`, `NSEntityDescription.managedObjectClassName: String!` | Native entity metadata and lifecycle information. | No generic class parameter; model mapping is runtime data. |

The installed Foundation interface declares the key-path `NSExpression`
initializer from macOS 10.10 / iOS 8, native `SortDescriptor` and its bridge from
macOS 12 / iOS 15, the `Predicate` bridge from macOS 14 / iOS 17, and the
`Expression` bridge from macOS 15 / iOS 18. Swift 6 can use the older APIs without
raising the deployment targets. Availability guards do not backport new runtime
features.

Primary references: Apple's [Predicate bridge](https://developer.apple.com/documentation/foundation/nspredicate/init(_:)),
[fetch request predicate](https://developer.apple.com/documentation/coredata/nsfetchrequest/predicate),
[key-path sort descriptor](https://developer.apple.com/documentation/foundation/nssortdescriptor/init(keypath:ascending:)),
and [block predicate](https://developer.apple.com/documentation/foundation/nspredicate/init(block:)).
The installed `Foundation.swiftinterface` supplies the exact generic signatures
and availability; `NSPredicate.h` explicitly excludes block predicates from the
SQLite store. `NSExpression.h` cautions that many expression forms are not
supported by Core Data SQL stores.

### Native Swift predicate interoperability

This already works on the newer systems, without a library predicate DSL:

```swift
// Example only: Contact is a correctly configured managed-object subclass.
if #available(macOS 14, iOS 17, *) {
    let predicate = #Predicate<Contact> { $0.age > 18 }
    guard let native = NSPredicate(predicate) else {
        // Report unsupported conversion; do not execute an unfiltered fetch.
        return
    }
    let request = NSFetchRequest<Contact>(entityName: "AddressBookEntry")
    request.predicate = native
    // Execute on the context's queue and handle native fetch failures.
}
```

Assigning `request.predicate = NSPredicate(predicate)` directly is dangerous:
a failed conversion assigns `nil`, which removes the filter. Neither a silent
unfiltered fetch nor filtering fetched objects in memory is an acceptable
fallback. In-memory filtering changes limits, pagination, memory use, and store
semantics.

## 3. Compiler and runtime experiments

### Reproduction

From the repository root on macOS with the installed Xcode toolchain:

```sh
python3 Experiments/AdvancedTypeSafety/run.py
```

The standard-library-only runner writes executables, compiler logs, runtime logs,
and `results.json` under `.build/advanced-study/`. It compiles Swift with:

```text
-swift-version 6 -strict-concurrency=complete -warnings-as-errors
```

It also uses `-disable-sandbox` for the compiler's nested macro-plugin sandbox,
which cannot initialize inside this host's restricted sandbox. The outer process
sandbox and strict concurrency checks remain in force. No `@unchecked Sendable`,
`@preconcurrency` workaround, dependency, or package-target change was introduced.

The existing test-only Objective-C exception observer is linked into research
executables to observe native exceptions. This is not a proposed library error
handling mechanism. Risky SQL cases run in separate processes. The runner owns
their temporary directories and removes them even when the child terminates;
core dumps are disabled. Normal fixtures detach their stores and remove SQLite
files after execution.

| Executable | Purpose and observed result |
| --- | --- |
| [PredicateTypeSafety.swift](../Experiments/AdvancedTypeSafety/PredicateTypeSafety.swift), using [PredicatePrototype.swift](../Experiments/AdvancedTypeSafety/PredicatePrototype.swift) | Typed root/value equality, numeric comparison, nil and same-root composition compile. A Swift-only computed path is rejected before native expression creation. Erasing to `NSPredicate` permits assignment to an unrelated request. |
| [SQLitePredicates.swift](../Experiments/AdvancedTypeSafety/SQLitePredicates.swift) | Real SQLite queries for scalar/date/string operations, nil, composition, relationships, renamed attributes and transformables. Separate unsupported probes expose native failures and semantic limits. |
| [NativePredicateBridge.swift](../Experiments/AdvancedTypeSafety/NativePredicateBridge.swift) | Native macro construction, failable conversion, real SQLite execution, nil semantics, optional relationships, unsupported properties, and the newer expression bridge. |
| [GeneratedSubclassPredicate.swift](../Experiments/AdvancedTypeSafety/GeneratedSubclassPredicate.swift) | `momc` generates actual Swift subclasses from [GeneratedModel.xcdatamodel](../Experiments/AdvancedTypeSafety/GeneratedModel.xcdatamodel/contents). Generated key paths and the generated fetch request execute a SQLite comparison correctly after save/reset. |
| [IdentityAndSections.swift](../Experiments/AdvancedTypeSafety/IdentityAndSections.swift) | Checked raw-ID reconstruction, request copying/ID mode, pending changes, inheritance/model mismatches, and typed section-array access. |

These include four executable predicate studies, exceeding the requested three.
The helper is a deliberately incomplete research wrapper; it is not a production
implementation of a general predicate representation.

### Compiler-negative cases

The runner compiles each flag separately and requires a compiler error:

| Flag | Rejected construct |
| --- | --- |
| `MISMATCHED_VALUE` | Comparing an `Int64` key path with `"Alice"`. |
| `WRONG_ROOT` | Assigning a company predicate to a contact predicate variable. |
| `WRONG_COMPOSITION` | Composing predicates with unrelated root types. |
| `NATIVE_WRONG_VALUE` | `#Predicate` comparing `Int64` with `String`. |
| `NATIVE_UNSUPPORTED_FUNCTION` | Calling `trimmingCharacters(in:)` in the tested native macro expression. |
| `NATIVE_CAPTURE_OBJECT` | Capturing a managed object in the tested standard predicate expression; the expression does not meet the required standard-expression conformances. |
| `NATIVE_ERASED_KEYPATH_SENDABILITY` | Passing a key path erased to plain `KeyPath<Root, Value>` to the current sendable native expression builder. |

The last case matters for generic helpers: the inspected
`PredicateExpressions.KeyPath` initializer accepts
`KeyPath<Root.Output, Output> & Sendable`. A key-path literal may preserve this
information while an unconstrained parameter does not. Do not suppress the
diagnostic or assume every captured value/key path is transferable.

### Detailed SQLite findings

| Case | Executed observation | Consequence |
| --- | --- | --- |
| Persisted `@NSManaged` scalar | Typed string equality, `Int64` and `Date` comparison selected expected rows. | Suitable initial factory candidates. Swift `Equatable`/`Comparable` alone is still too broad a SQL contract. |
| Custom entity name | Swift `SQLContact` mapped to `AddressBookEntry`. Queries succeeded with the actual entity name. | Do not derive entity names from Swift class names. |
| Custom attribute name | Swift `firstName`, declared `@objc(given_name)`, bridged to model key `given_name`; query and sort succeeded. | Use Objective-C key-path bridging, not Swift property spelling or key-path descriptions. |
| Generated subclass | `momc` generated `TCDGeneratedPerson` for entity `AddressBookRecord`; generated request and key-path comparison worked. | This actual generated subclass and scalar query worked on the tested SDK/runtime; arbitrary dynamic subclass behavior was not examined. |
| Nil comparison | `nickname == nil` and `nickname != nil` worked in native and typed-construction probes. | Explicit nil checks are useful initial operations. |
| Nonoptional inequality and logic | String inequality, AND, OR and NOT returned expected rows. | Same-root composition is feasible. Nil-bearing leaves need a separate semantic contract. |
| String operations | `contains`, `beginsWith`, `endsWith` worked for a persisted string attribute with default options. | Locale, diacritics, case options, and all Unicode edge cases were not certified. |
| To-one relationship | Object identity equality and `company.name` selected expected rows. | Context/store membership still matters; a relationship object is not a sendable query constant. |
| Optional relationship traversal | `\SQLContact.company?.name` bridged to `company.name`. Native `#Predicate` converted an optional traversal into a `TERNARY` expression and executed correctly. | This particular optional path works; arbitrary Swift optional transformations are not established as SQL-compatible. |
| To-many `ANY` | Native `ANY tags.label == "swift"` selected Alice. | Native capability demonstrated; the `NSSet?` property does not encode a typed element for a generic Swift factory. |
| To-many `ALL` | `ALL tags.label == "ios"` raised `NSInvalidArgumentException`. | Do not expose generic `ALL` as universally supported SQL behavior. |
| Swift-only computed property | Factory rejected its missing KVC representation; native Swift-predicate conversion returned `nil`. | Swift type correctness is only the first gate. |
| KVC-visible computed property absent from model | Native bridge succeeded, then SQLite raised `NSInvalidArgumentException`. | KVC representability is not persistence validation. |
| Transient model attribute | Equality returned an empty array despite assigned in-memory values. | Model membership alone is insufficient; transient values do not have ordinary persisted-column semantics. |
| Transformable `NSString?` | Nil comparison worked; equality to `"alpha"` returned Alice in this fixture. | Do not generalize from a specific transformer/representation. |
| Transformable string operation | `payload BEGINSWITH "al"` terminated its isolated process with SIGSEGV (`-11`). | A Swift string-like value does not make a transformable attribute a SQL string column. No safe support claim follows. |
| Block predicate | SQLite raised `NSInvalidArgumentException`. | Never substitute block predicates when conversion fails. |
| Custom function | `uppercaseString` function expression was rejected by SQLite. | Arbitrary Foundation expressions cannot be advertised as SQL-translatable. |

#### Nil semantics are an architecture decision

In the native-bridge fixture, Alice and Carol have nil nicknames, and Bob's
nickname is `"B"`. Both expressions below compiled and converted successfully:

```swift
#Predicate<BridgeRecord> { $0.nickname != "B" }
#Predicate<BridgeRecord> { !($0.nickname == "B") }
```

| Evaluation | Both expressions selected |
| --- | --- |
| Swift `Predicate.evaluate` | Alice, Carol |
| Bridged `NSPredicate.evaluate(with:)` | Alice, Carol |
| SQLite-backed Core Data fetch | No rows |

The factory probe independently observed that `nickname != "Bobby"` excluded a
nil nickname. This is evidence of a backend semantic difference, not a failed
generic constraint. It also affects NOT applied to optional equality and paths
that encounter missing relationships.

**Proposed policy:** preserve native Core Data semantics and state that contract
explicitly. A small factory surface should initially support nil equality/nil
inequality and nonoptional scalar comparisons. Defer an optional-nonnil inequality
API or automatic rewrites until its intended truth table is agreed and tested.
An explicit `isNil OR differsFromValue` expression is a possible caller-selected
policy; do not silently rewrite all predicates to promise Swift optional logic.
Native `Predicate` attachment must disclose the same limitation.

### Verification outcome

The final runner completed all five normal executables with exit status 0. All
seven negative compiler probes failed as intended. Successful Swift compilations
emitted no warnings under warnings-as-errors. Six unsupported-expression probes
were recorded separately: four observed native exceptions, one returned an empty
result for a transient property, and one terminated with SIGSEGV. Core Data's
expected runtime error logging is not a compiler warning or an unexpected failure
of a supported-case assertion.

The availability-guarded native predicate source also typechecked for macOS 10.15
and iOS 13 deployment targets using the installed SDKs. No old-OS or iOS runtime
execution was performed. The existing package suite was not changed or rerun for
this research-only task; its preceding implementation verification remains
separate from these executable studies.

## 4. Predicate API designs

### What a meaningful guarantee requires

`KeyPath<Root, Value>` ties a selected property to both its root and value type.
Taking the comparison constant as that same `Value` rejects an age/string
comparison. A `TypedPredicate<Root>` result can then retain the root while
heterogeneous property value types compose into a Boolean predicate.

Returning `NSPredicate` immediately would lose that second benefit. The root
must survive construction, composition, and the typed request attachment point.
Even then the native request remains mutable: callers can later replace its
entity, predicate, or result mode. The guarantee is local to the typed operation,
not a permanent invariant of every `NSFetchRequest<Root>`.

Illustrative signatures, **not additions to the public API**:

```swift
// Factory shape demonstrated by the experiment. Production support must be
// narrower than all Equatable/Comparable values (see below).
struct TypedPredicate<Root: NSManagedObject> {
    static func equals<Value: Equatable>(
        _ keyPath: KeyPath<Root, Value>, _ value: Value
    ) throws -> Self

    static func greaterThan<Value: Comparable>(
        _ keyPath: KeyPath<Root, Value>, _ value: Value
    ) throws -> Self

    func and(_ other: Self) -> Self
    func or(_ other: Self) -> Self
    func negated() -> Self
}

extension NSFetchRequest where ResultType: NSManagedObject {
    func setPredicate(_ predicate: TypedPredicate<ResultType>) throws
}
```

The `throws` boundary would report conversion/model-validation failures only to
the extent the chosen implementation actually validates them. A request without
resolved entity metadata cannot support an unconditional model-validation promise.

The requested `Contact.predicate(\.age, greaterThan: 18)` spelling can be layered
over this root/value relationship using a protocol with `Self`, analogous to the
existing `ManagedIdentifiable` pattern. It is syntax, not an additional safety
mechanism. Prefer deciding the representation and contracts before adding another
public protocol or several equivalent construction spellings.

For a production scalar subset, use explicit supported scalar/optional overloads
or a carefully bounded operand contract. `Equatable` includes arbitrary user
structs and transformables; `Comparable` does not imply SQL ordering support. Even
`KeyPath<Contact, String>` needs model inspection to distinguish a string attribute
from a computed, transient, or transformable property. An open protocol that any
type can adopt must not be described as a closed SQL-supported type set.

### A. KeyPath-based factories

Factories can build native `NSExpression`/`NSComparisonPredicate` objects with
typed operands. Returning a root-retaining representation enables same-root AND,
OR and NOT. Returning raw `NSPredicate` offers only construction-time value safety.

The native key-path expression initializer is nonfailable. The experiment uses
`_kvcKeyPathString` to reject unrepresentable paths before calling it. This is an
accessible but underscored Swift implementation-detail API, not a documented,
stable checked Core Data conversion contract. Its presence is verified in the
[Swift key-path implementation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/KeyPath.swift).
Force-unwrapping it, using `String(describing: keyPath)`, or turning an invalid path
into an empty key is unacceptable. Whether to accept this underscored dependency
is an explicit architecture decision for baseline support.

### B. Native Swift predicates

Use Apple's typed expression system and failable bridge. The smallest additive
surface with a real gain is a typed attachment operation:

```swift
@available(macOS 14, iOS 17, *)
extension NSFetchRequest where ResultType: NSManagedObject {
    func setPredicate(_ predicate: Predicate<ResultType>) throws
}
```

Its proposed contract is narrowly defined: require the same root as the request,
convert successfully before assigning, leave the previous predicate unchanged on
conversion failure, and report that failure explicitly. It does not guarantee
model compatibility, SQL translation, or Swift-equivalent evaluation. It does not
create requests or guess entity names. No new macro is needed.

This adds value beyond a generic `asNSPredicate()` shortcut: the latter already
duplicates Apple's initializer and loses the root before assignment. Native
composition and the compiler's expression support should be reused wherever
possible. A promise to validate every native expression node against every model
would be a much larger, separately designed feature.

### C. A small typed predicate representation

A private, limited expression tree behind `TypedPredicate<Root>` could retain the
operation, key path, constant, and same-root composition until conversion. This
would allow validation of persisted attribute kinds and explicit nil semantics
without reconstructing them from an arbitrary `NSPredicate`.

The public representation should expose operations, not public untyped enum cases
that let callers extract a comparison from one root and rewrap it as another.
An internal heterogeneous representation is reasonable only if construction is
controlled and preserves its invariants. This design has the greatest validation
potential but also creates a conversion layer that needs maintenance.

It is not demonstrated as necessary for the modern-only bridge. If baseline
predicate support is required, choose a tiny scalar subset first. Do not add
joins, aggregates, subqueries, projections, custom functions, or a replacement
fetch-request abstraction as part of the same change.

### D. Typed wrappers around NSPredicate

A wrapper is the lightest way to retain a root after checked factory construction.
The PoC uses this design. It can support typed composition and request attachment
without an AST. However, erasure makes later semantic/model validation harder.

`TypedPredicate<Contact>(someArbitraryNSPredicate)` cannot establish that a key
exists on `Contact`, that a comparison value is appropriate, or that SQL supports
it. A public initializer with this signature would be an unchecked assertion,
not a validation. Native `request.predicate` already supplies the escape hatch;
there is no need to brand arbitrary input as safe.

### Comparison

| Dimension | A: key-path factories | B: native Swift predicate | C: small typed representation | D: native-predicate wrapper |
| --- | --- | --- | --- | --- |
| Compile-time guarantees | Root/value relation at construction; root persists only if return type retains it. | Strong expression typing; typed attachment can preserve root until assignment. | Root/value construction, same-root composition, controlled operator set. | Root retention only as trustworthy as its constructors. |
| Runtime limits | KVC, model mapping, attribute kind, nil and SQL support. | Macro subset, failable bridge, model and SQL support, nil divergence. | Can reject more known invalid cases; cannot certify arbitrary stores/models. | Cannot infer a lost root/value proof from arbitrary native input. |
| Ergonomics | Familiar small factory calls; throwing conversion. | Native Swift syntax; explicit conversion failure/availability handling. | More types and operator policy; potentially predictable diagnostics. | Small surface, familiar native interoperability. |
| Performance | Small expression allocations; normally native SQL after lowering. | Macro work at compile time; runtime bridge traversal then native SQL. | Extra nodes/validation traversal before native SQL. | One container plus native expression/composition costs. |
| Availability | Existing minimums, subject to chosen bridging mechanism. | macOS 14 / iOS 17 for the bridge. | Existing minimums if built on old Foundation APIs. | Existing minimums for native predicates. |
| Implementation complexity | Medium for a bounded subset; high for relationships/validation. | Low for typed attachment; much higher for a SQL validator. | Medium–high even with a narrow operator set. | Low for a wrapper; validation requirements determine real complexity. |
| Maintenance | Scalar and key-path compatibility matrix, underscored bridge risk. | Apple owns expression syntax/conversion; integration still needs regression tests. | Library owns representation, semantics and lowering matrix. | Small unless marketed as a validator, which it cannot inherently be. |
| Native request compatibility | Direct after lowering; raw assignment erases root. | Direct after bridge; same-root attachment is useful. | Direct after lowering; no request wrapper needed. | Direct extraction; mutation remains native. |

These approaches are partly composable: A may construct C or D. Choosing A alone
does not settle how roots survive composition. The recommendation is B plus typed
attachment first if modern-only availability is acceptable; otherwise evaluate
A+C against A+D for a deliberately small baseline feature. Do not ship parallel
full predicate systems merely to offer multiple syntaxes.

### Operator scope recommendation

| Operation | Initial recommendation | Unresolved boundary |
| --- | --- | --- |
| Equality | Persisted supported scalars and explicit nil checks. | Swift type does not establish the model's storage kind. |
| Inequality | Nonoptional supported scalars; explicit `!= nil`. | Optional-to-value inequality and negated equality differ from Swift evaluation. |
| Numeric/date ordering | Narrow known numeric/date types after model compatibility checks. | Arbitrary `Comparable`, numeric width conversions, and optional operands need policy. |
| String contains/prefix/suffix | Small explicit set for persisted string attributes. | Comparison options, locale and transformables need separate testing. |
| AND/OR/NOT | Same-root composition with native Core Data truth semantics. | NOT does not remove nil/SQL semantic differences. |
| To-one identity | Defer until operand lifetime, store and optional contracts are explicit. | Managed-object constants require queue confinement; ID-based constants need separate validation. |
| Nested to-one path | Candidate second step; validate each relationship and final property. | Missing relationships and inherited model variants. |
| To-many ANY | Defer a typed API despite the successful native SQL example. | `NSSet`/`NSOrderedSet` erase destination type; typed Swift collections need their own bridging proof. |
| ALL, subqueries, functions | Defer; do not advertise blanket SQL support. | Observed rejection of ALL and custom functions; no full translation study. |
| Transformables/transient/computed | Exclude from the first SQL factory contract. | Observed empty results, failures and a crash; a Swift value type is insufficient. |

## 5. Typed object-ID fetching

Proposed signature:

```swift
extension NSManagedObjectContext {
    func fetchObjectIDs<Entity: NSManagedObject>(
        for request: NSFetchRequest<Entity>
    ) throws -> [ManagedID<Entity>]
}
```

**Meaningful guarantee:** returned IDs have entity class metadata compatible with
`Entity`. No caller-chosen cast is required, and incompatible IDs cannot escape
through a partially validated returned array. This does not establish that the
original request was consistently configured when an empty result is returned.

### Proposed execution contract

1. Run on the context's queue; the caller must not mutate the request concurrently.
2. Require the source request's `resultType` to be `.managedObjectResultType`.
   A generic `NSFetchRequest<Entity>` can still be mutated to dictionary/count
   mode; silently repurposing such a request would obscure a configuration error.
3. Copy the native request. Preserve its entity binding and options; change only
   the copy's result mode to `.managedObjectIDResultType`.
4. Execute the copy with the native generic fetch. Preserve native fetch errors.
5. Check every returned ID's declared class before trusted typed construction.
   A mismatch is an explicit validation error, not an omitted row or an unchecked
   brand. Do not save, promote temporary IDs, or materialize objects to validate.

The experiment checks the copied class with
`as? NSFetchRequest<NSManagedObjectID>`. Objective-C generic erasure means this cast
does not validate entity or result-element compatibility. Setting the result
mode and validating the actual results are the relevant checks.

### Copying and mutable configuration

Executed: the copy was a distinct request, the source result mode stayed unchanged,
and inspected options were retained: entity, predicate, sort descriptors, fetch
limit/offset/batch size, pending-change and subentity flags, property-values/fault
flags, `propertiesToFetch`, and affected stores. This is not a deep freeze of all
objects reachable through a request. Core Data defines which options have meaning
in ID mode; preserving an option does not preserve managed-object-mode behavior.

Do not resolve an ambiguous model by calling global `Entity.entity()`, guess a
name from the class, or silently substitute an entity from another coordinator.
An entity descriptor from the request remains authoritative. For an unresolved
entity-name request, native execution can resolve it in the context. The earlier
audit found that inspecting an unresolved `request.entity` can itself raise an
Objective-C exception; eager validation must not add that failure accidentally.

Two possible contracts must not be conflated:

- **Per-result validation**, recommended minimum: catches incompatible returned
  entities, including incompatible descendants. An empty mismatched fetch may
  succeed with `[]`; this is a result guarantee, not request validation.
- **Preflight request validation**, optional separate work: resolves model-bound
  entity configuration and checks all possible subentities even for empty results.
  This needs explicit rules for unresolved names, multiple models and stores.

### Inheritance, models and ID lifecycle

Executed: compatible subclass IDs were accepted as base IDs; an incompatible
descendant in an entity hierarchy was rejected. Changing the request to another
entity produced rejected IDs. An empty mismatched request returned `[]` under the
per-result contract. Core Data entity ancestry and Swift class inheritance must
be checked separately; the former does not prove the latter.

With `includesPendingChanges = false`, the fixture's object and ID fetches had
the same membership and ordering. With pending changes included, ID fetches
included an unsaved temporary ID, an unsaved permanent ID, and an object moved
into the predicate, while excluding a pending deletion. Membership matched the
ordinary object fetch in that fixture, but ordering differed. The temporary ID
remained temporary and the context remained dirty after fetching.

Therefore, never promise permanent IDs, saved rows, cross-context resolvability,
or identical pagination to an ordinary object fetch. Multiple models or entities
can use the same Swift class; accepting their class compatibility does not make
their stores interchangeable.

### Performance and option semantics

The fresh reader in the ID experiment had zero registered objects after fetching
IDs. This supports avoiding managed-object registration in that case, not a
universal speedup or an absence of database/property work. Validation and wrapping
add O(n) work and an output array; cache class resolution only if model lifetime
and cache ownership are correctly defined.

Apple documents that `includesPropertyValues` can still fetch property data in
ID mode and defaults to true. Preserve it rather than silently changing the query;
callers can explicitly choose false. Apple's `resultType` documentation also
describes sorting as best-effort when ID results are requested without property
values. This reinforces the ordering caveat rather than supporting a claim that
an ID fetch is just an ordinary fetch with a cheaper result cast.
See [includesPropertyValues](https://developer.apple.com/documentation/coredata/nsfetchrequest/includespropertyvalues),
[resultType](https://developer.apple.com/documentation/coredata/nsfetchrequest/resulttype),
and [returnsObjectsAsFaults](https://developer.apple.com/documentation/coredata/nsfetchrequest/returnsobjectsasfaults).

**Recommendation:** implement after the class-validation contract is settled.
Keep the existing request abstraction. Complexity: **medium**, chiefly semantic
tests and diagnostics rather than forwarding code.

## 6. Typed fetched-results-controller sections

Proposed signature:

```swift
extension NSFetchedResultsController {
    func objects(inSectionAt index: Int) -> [ResultType]?
}
```

`fetchedObjects` and `object(at:)` already return the generic type. The useful
addition is checking the otherwise erased `section.objects` array on access and
preserving its relationship to the controller's `ResultType`.

**Proposed contract:** return nil when native section information or the selected
section's objects is unavailable; return `[]` for an available empty section.
Check bounds explicitly when section information exists. Treat an invalid index
or element-class mismatch as a precondition failure with a diagnostic, consistent
with the existing library's invariant handling and indexed collection access.
Do not return nil for a class mismatch or drop elements with `compactMap`.
The experiment uses thrown errors to observe these cases without terminating;
that testing choice is not the proposed public signature.

Executed observations:

- Before `performFetch`, `sections` was nil.
- Populated sections contained four objects each; checked typed arrays preserved
  the identities and order returned by native `object(at:)`.
- Negative and upper-bound indices were explicitly rejected by the prototype.
- An empty unsectioned fetch had one section with `[]`; an empty grouped fetch
  had no sections. Nil, empty content and an invalid index are distinct states.
- Mutating a typed request to an incompatible entity led to a failed checked
  section-array cast. The generic controller alone did not prevent this.

A checked array conversion may traverse elements, bridge storage or allocate a
new reference array; it does not copy the managed objects themselves. No zero-copy
promise is justified. With `fetchBatchSize = 1`, registrations were observed as
0 after fetching, 8 after one native `object(at:)`, and 8 after the section cast.
This particular run cannot isolate allocation cost or prove batch-preserving
behavior of whole-section access. Prefer the existing native accessor for a
single row; measure large sections before promising performance properties.

Read on the owning context's queue; the returned managed objects remain confined
to that context. **Recommendation: implement; low complexity.** No controller
wrapper, cache, scheduling helper or duplicate whole-result accessor is needed.

## 7. Validated ManagedID reconstruction

Proposed signature:

```swift
extension ManagedID {
    init(validating objectID: NSManagedObjectID) throws
}
```

The existing `fileprivate init(_:)` should remain in the same file as trusted
construction. A future validating initializer can live there and delegate to it
after checking metadata. No initializer is added by this study; its prototype
uses a separate experiment-only identifier type.

### What can be checked

Read `objectID.entity.managedObjectClassName`, resolve that exact Objective-C
runtime name with `NSClassFromString`, and verify that the resulting class is
`Entity` or a subclass (`runtimeClass is Entity.Type` in the executed prototype).
Missing or unresolvable names and incompatible classes are validation errors.

Do not synthesize module prefixes, strip them, compare only simple class names,
or require the Core Data entity name to equal the Swift name. The configured
runtime name is the evidence. An `@objc` class name and a module-qualified Swift
runtime name both worked in the experiment. Custom module settings work only
insofar as the model contains a name the runtime actually resolves.

| Situation | Executed result / proposed interpretation |
| --- | --- |
| Exact mapped class | Accept. |
| Subclass ID as a base-class ID | Accept; class covariance is checked during construction. The existing generic identifier type itself remains invariant. |
| Base ID as a subclass ID | Reject. |
| Unrelated Swift class | Reject, including when entity inheritance says it is a descendant. |
| Several entities use one Swift class | Accept their class compatibility; do not claim one specific entity. |
| Same class across different models/stores | Accept class compatibility; no store/model guarantee. |
| Module-qualified runtime class | Accept when exact lookup succeeds. |
| Missing configured runtime class | Reject. Core Data fell back to an `NSManagedObject` instance in the probe; that fallback is not proof of the configured subclass. |
| Temporary or permanent-unsaved ID | Class checking does not promote or persist it. Lifecycle restrictions remain native. |
| Deleted object's ID | Class validation still succeeded; a fresh context's `existingObject` failed with `NSCocoaErrorDomain` 133000. |
| ID reconstructed from a URI | URI reconstruction returned the same deleted identity; class compatibility does not establish existence. |

**The check establishes declared class compatibility, not stored-object existence.**
It does not fetch an object, verify a row, check a particular coordinator, prove a
model is immutable, or make a faulty model reliable. Subsequent resolution keeps
the current library's actual-object class check and native errors. Metadata work
should follow Core Data's model/context ownership rules; ID sendability alone is
not a reason to inspect mutable models concurrently.

### Is a public unchecked initializer useful?

It could let callers brand an ID when they have an external proof unavailable to
runtime class lookup, such as unusual dynamic mapping. That is a possible escape
hatch, but this study established no concrete need for it. It introduces a caller
assertion at the core type-safety boundary.
It is unnecessary for ordinary URI reconstruction, subclass IDs, shared classes,
or raw API interoperability. The public `objectID` property and native Core Data
methods already support untyped use.

**Recommendation:** implement validated reconstruction first; **defer/reject a
public unchecked initializer for the current scope** until a concrete supported
mapping cannot use the checked path. Never call an arbitrary raw-ID cast
“validated,” and do not infer existence from a permanent identifier.
Complexity: **low–medium**, with most work in error contracts and model fixtures.

## 8. Compatibility and concurrency

| Feature | macOS 10.15 / iOS 13 | macOS 12 / iOS 15 | macOS 14 / iOS 17 | macOS 15 / iOS 18+ |
| --- | --- | --- | --- | --- |
| Native expression/comparison/compound factories | Available | Available | Available | Available |
| Native key-path `NSExpression` / `NSSortDescriptor` | Available | Available | Available | Available |
| `SortDescriptor<Root>` and native descriptor bridge | Unavailable | Available | Available | Available |
| `Predicate<Root>`, `#Predicate`, `NSPredicate(Predicate)` | Unavailable | Unavailable | Available | Available |
| `Expression`, `#Expression`, native expression bridge | Unavailable | Unavailable | Unavailable | Available |
| Proposed typed section access / ID validation / ID fetch | No inherent target increase identified | Same | Same | Same |
| Proposed baseline factory/representation | Possible using older Foundation APIs; KVC conversion policy unresolved | Same | Same | Same |

This matrix describes SDK availability, not tests on each runtime. The package
can keep its minimum targets and gate only newer overloads. Older SDK/toolchain
combinations need separate build validation, especially for imported concurrency
annotations and macro-builder signatures.

`Predicate` being `Sendable` does not make a managed object an acceptable captured
value or make evaluating it on the wrong queue safe. Read scalar query parameters
on their owning queue, then capture transferable values. The current builder's
sendable key-path requirements must be retained in generic APIs. Do not add
`@unchecked Sendable` to a custom representation merely to match native syntax.

The existing `ManagedID` checked conformance relies on the installed SDK's
sendable `NSManagedObjectID`. Its generic class is metadata, not a stored managed
object. Reconstructed or fetched IDs retain the same lifecycle restrictions.
Resolved objects and section arrays containing objects do not become transferable.

The experiments use main-queue contexts from `@MainActor` functions. That is a
fixture choice, not a proposal to make the library main-actor-only. Actual APIs
must work on the owning context's queue, including private queues. The prior
audit established that native `perform` overloads already supply generic results
and that compatibility annotations can allow unsafe object transfers to compile.
No new `perform` wrapper is warranted here; strict compilation is necessary but
does not replace Core Data queue discipline.

## 9. Competitive research

The following are **primary-source and documentation reviews**, not claims that
these packages were compiled with Swift 6 or tested on the current SDK. The
RCDataKit row explicitly identifies its more limited README/manifest evidence.
Pinned versions are used where available; an unpinned branch is identified as
such. No external code was copied into TypedCoreData, and no dependency was added.

| Project / inspected revision | Verified relevant design | Limits and relevance to TypedCoreData |
| --- | --- | --- |
| CoreStore 9.3.0, commit `5a0d27cf343c6e341b0ef3c8d36104770b27a839` | `Where<O>` retains the object type during normal construction/composition; typed fetching lives in a broader stack/model system. | Source uses force-unwrapped `_kvcKeyPathString` and offers raw string/predicate paths. `DynamicObject.ObjectID` aliases raw `NSManagedObjectID`, rather than providing an entity-branded identifier. Its inspected manifest uses Swift 5 language mode and iOS 16 / macOS 13 minimums. |
| QueryKit 0.14.1 | Key-path operators produce `Predicate<R>`; `QuerySet<R>` retains a result root. | Basic comparison overloads leave `Value` unconstrained by `Equatable`/`Comparable`; same-value typing alone does not establish SQL operator support. Raw `NSPredicate` overloads erase the root; forced KVC conversion can trap. Query-set entity names remain separately supplied strings. Tagged packaging targets old Swift/platform versions; do not infer current Swift 6 compatibility. |
| PredicateKit 1.10.0, commit `8e3c45cb580baceb70384572d0aa38002b972bfc` | Root-typed predicate representation; equality/ordering constrain primitive operands; optional, string and collection operations exist. | Some lowering paths use `fatalError`. Public untyped comparison payloads can be rewrapped under another generic root. Fetch creation uses `Entity.entity().name` with a class-description fallback, raising the same ambiguity/naming issues as the earlier audit. Inspected manifest uses Swift 5 and iOS 11 / macOS 10.15. |
| CoreDataQueryInterface, unpinned `master` snapshot | `QueryBuilder<M, R>` supplies typed query structure and uses PredicateQI. | A broader query-builder/dependency design; native predicate storage remains erased. Inspected manifest uses Swift 5, iOS 15 / macOS 13. This is context, not a dependency recommendation. |
| RCDataKit 1.0.2, release commit `9a1e868f327794cf8693532ef49bca233097135e` | Its tagged README documents a `Sendable` `TypedObjectID` wrapper created from a managed object and accepted by a typed `existingObject(with:)`. Its manifest enables experimental strict concurrency with tools 5.10 and iOS 15 / macOS 12 minimums. | **Documentation/manifest evidence only:** implementation retrieval was unavailable. Exact generic declaration, raw-ID initializer access, validation and cast strategy were not verified. It is documented typed-ID prior art, not evidence of a checked Swift 6 build. |

Sources reviewed:

- CoreStore: [Where.swift](https://github.com/JohnEstropia/CoreStore/blob/5a0d27cf343c6e341b0ef3c8d36104770b27a839/Sources/Where.swift),
  [DynamicObject.swift](https://github.com/JohnEstropia/CoreStore/blob/5a0d27cf343c6e341b0ef3c8d36104770b27a839/Sources/DynamicObject.swift),
  [Package.swift](https://github.com/JohnEstropia/CoreStore/blob/5a0d27cf343c6e341b0ef3c8d36104770b27a839/Package.swift).
- QueryKit: [KeyPath.swift](https://github.com/QueryKit/QueryKit/blob/0.14.1/Sources/QueryKit/KeyPath.swift),
  [QuerySet.swift](https://github.com/QueryKit/QueryKit/blob/0.14.1/Sources/QueryKit/QuerySet.swift),
  [podspec](https://github.com/QueryKit/QueryKit/blob/0.14.1/QueryKit.podspec),
  [Package.swift](https://github.com/QueryKit/QueryKit/blob/0.14.1/Package.swift).
  Its [key-path failure issue](https://github.com/QueryKit/QueryKit/issues/61) is
  a primary user report, not a reproduction by this study.
- PredicateKit: [Predicate.swift](https://github.com/ftchirou/PredicateKit/blob/1.10.0/PredicateKit/Predicate.swift),
  [NSFetchRequestBuilder.swift](https://github.com/ftchirou/PredicateKit/blob/1.10.0/PredicateKit/CoreData/NSFetchRequestBuilder.swift),
  [NSManagedObjectContextExtensions.swift](https://github.com/ftchirou/PredicateKit/blob/1.10.0/PredicateKit/CoreData/NSManagedObjectContextExtensions.swift),
  [Package.swift](https://github.com/ftchirou/PredicateKit/blob/1.10.0/Package.swift).
- CoreDataQueryInterface: [QueryBuilder.swift](https://github.com/Prosumma/CoreDataQueryInterface/blob/master/Sources/CoreDataQueryInterface/QueryBuilder.swift),
  [Package.swift](https://github.com/Prosumma/CoreDataQueryInterface/blob/master/Package.swift),
  [PredicateQI](https://github.com/Prosumma/PredicateQI/blob/master/README.md).
- RCDataKit: [tagged README](https://github.com/RCCoop/RCDataKit/blob/1.0.2/README.md#typed-nsmanagedobjectid),
  [Package.swift](https://github.com/RCCoop/RCDataKit/blob/1.0.2/Package.swift),
  [release commit](https://github.com/RCCoop/RCDataKit/commit/9a1e868f327794cf8693532ef49bca233097135e).

The useful contribution is not claiming invention of typed predicates or IDs. It is a
small integration surface over native Core Data, precise construction/assignment
guarantees, explicit model/SQL limitations, and Swift 6 regression evidence.
Existing solutions demonstrate why unchecked escape hatches, forced KVC
conversion, and class-name-derived entities deserve scrutiny.

## 10. Risks, implementation order and review decisions

### Principal risks

| Risk | Required response |
| --- | --- |
| Swift type and runtime model disagree | State metadata checks precisely; validate returned values/IDs; do not invent a static model proof. |
| Failable predicate conversion becomes nil | Fail before mutating the request; never remove filtering silently. |
| Typed or KVC-valid expression is unsupported in SQL | Bound the advertised subset and test real stores. Do not promise all native failures become Swift errors. |
| Nil and pending-change semantics differ by evaluator | Preserve/document native behavior; specify truth tables before adding rewrites or Swift-equivalence claims. |
| Underscored KVC bridge changes | Decide whether baseline factories accept that maintenance risk; avoid forced conversion. |
| Model inheritance, shared classes, or multiple stores | Validate Swift class compatibility separately from entity identity and store compatibility. |
| ID fetch mutates source or promotes IDs | Copy before changing mode; preserve flags; no saves, promotions or context synchronization. |
| Whole-section access defeats lazy access | Retain native single-object access; no zero-copy or batch-efficiency claim without measurements. |
| Strict compilation mistaken for queue safety | Keep execution on context queues and do not transfer managed objects as identifiers. |

### Recommended order and effort

These are relative engineering estimates for implementation, tests and docs, not
delivery commitments. Runtime/SDK matrix expansion can dominate the code size.

| Priority / sequence | Proposal | Complexity / expected effort | Gate |
| --- | --- | --- | --- |
| Architecture decision first | Choose modern-only native predicate integration or an additional baseline scalar factory feature. | Small decision, large effect on scope. | Agree on root retention, conversion errors, nil semantics and model-validation claims. |
| 1 | Typed FRC section accessor. | Low; roughly 1–2 engineering days. | Agree on nil, index preconditions and mismatch policy. |
| 2 | Validated `ManagedID` reconstruction and shared internal class-validation logic. | Low–medium; roughly 2–4 days. | Accept class-metadata compatibility as the contract; specify validation errors. |
| 3 | Typed object-ID fetch using copied native requests. | Medium; roughly 3–5 days. | Choose per-result validation, mode rejection, ordering and pending-change documentation. |
| 4, first predicate implementation | Typed `Predicate<ResultType>` request attachment on macOS 14 / iOS 17+. | Low–medium; roughly 2–4 days for a narrowly stated contract. | No SQL-completeness claim; explicit bridge failure and nil semantics. |
| 5, only if requested | Baseline scalar key-path factories with one root-retaining representation. | Medium–high; about 1–2 weeks for a small tested subset. | Decide underscored KVC policy, supported operands, and validation timing. |
| Separate future design | Typed relationships/ANY, optional semantic rewrites, richer model validation, projections/subqueries. | High; not estimated without narrower requirements. | Additional runtime and API studies. |

Predicate architecture is the priority decision even though independent, smaller
API additions can be implemented first. It is reasonable to document Apple's
native bridge without adding a library predicate API if typed attachment is not
valuable enough to justify a new public method.

### Explicitly rejected approaches

- A generic cast from arbitrary `NSPredicate` or raw IDs presented as compile-time
  validation.
- A public raw-predicate constructor that grants a trusted generic root without
  evidence; public untyped AST cases that bypass constructor checks.
- A complete query DSL, repository, controller wrapper, persistence abstraction,
  alternative model, macro implementation, or external dependency for this scope.
- Deriving entity/model names from `String(describing: Entity.self)`, stripping
  modules, or relying on global class-to-entity lookup across multiple models.
- Assuming Core Data entity inheritance proves Swift class inheritance, or a
  shared Swift superclass proves all IDs represent one entity.
- Force-unwrapping key-path conversion or relying on key-path debug strings.
- Treating all `Equatable`, `Comparable`, transformable, transient, or KVC-visible
  properties as SQL-supported columns.
- Silently dropping mismatched results with `compactMap`, returning nil for an
  invariant mismatch, or filtering all objects in memory after bridge failure.
- Claiming a permanent/URI-reconstructed ID proves store existence, or promoting
  and saving objects inside an ID-fetch helper.
- Advertising all `#Predicate` expressions as Core Data-compatible because
  SwiftData supports native predicates.
- Returning section objects across concurrency boundaries, duplicating native
  `perform`, weakening strict concurrency, or adding `@unchecked Sendable`.

### Architecture review checklist

Before production implementation, settle four decisions: whether newer-only
predicate availability is acceptable; whether any baseline factory may depend on
underscored KVC conversion; whether the library promises native Core Data nil
semantics; and whether ID fetching validates returned IDs only or also preflights
the entire request. Then approve the exact error and bounds contracts.

The study stops here. Existing public APIs, package configuration, production
sources and tests remain unchanged. No commit, push, tag or publication is part
of this work.

## Implementation correction

The later implementation exposed a gap in the proposed extension signatures:
the standalone experiment functions had reified Swift generic parameters, but
did not prove that an extension of a generic Objective-C class could access its
`ResultType` at runtime. Swift 6 rejects both the checked section-array cast and
the native predicate conversion inside those proposed class extensions.
Delegation to a generic helper does not restore that missing type information.

The approved implementation therefore uses:

```swift
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

Each function has one generic parameter linking the relevant input and output;
neither accepts a caller-selected cast type. Compiler-positive and negative
external-client tests verify these relationships and the rejected original
extension forms. The other approved signatures remain unchanged.

Architecture decisions are now settled: existing package minimums are retained;
only native predicate attachment is availability-gated; Core Data nil semantics
are preserved; ID fetching validates returned IDs only. No custom predicate
representation, underscored KVC dependency, concurrency abstraction, dependency,
or unchecked initializer was introduced. The baseline factory/DSL alternatives
in this historical study are not part of the implementation roadmap.
