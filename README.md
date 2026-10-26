# TypedCoreData

A lightweight, strongly typed extension layer for Apple's Core Data framework,
developed under **TypageLib**.

**If Core Data knows the type, Swift should know it too.**

TypedCoreData preserves managed object types in identifiers, object resolution,
ID fetching, fetched-results-controller sections, and native predicate attachment.
It also types batch-execution results and accepts typed IDs in batch-delete
requests. Your Core Data model, contexts, persistent stores, and queue discipline
remain the same.

## Requirements

- Xcode 26.6 or a later compatible release (officially supported toolchains).
- Swift 6 language mode with complete strict concurrency checking.
- iOS 13+ or macOS 10.15+.
- An Apple SDK that imports `NSManagedObjectID` as `Sendable`.
- Swift Package Manager; no external dependencies.

Native Swift predicate attachment requires **iOS 17+ / macOS 14+**. The other
APIs retain the package's iOS 13 / macOS 10.15 minimums.

The Xcode requirement is separate from these OS deployment targets. Older
toolchains, including Xcode 16.0, may still work but are not officially supported
or required CI checks. The manifest's `swift-tools-version: 6.0` remains unchanged;
it does not imply support for every Swift 6 toolchain.

The package uses checked `Sendable` conformance. It does not add
`@unchecked Sendable` or suppress concurrency diagnostics. Managed objects remain
confined to their contexts' queues.

## Installation

**0.1.0 is prepared for review, not published.** The repository URL and rights
clearance are still pending. Do not use the placeholder below as an actual URL.

After publication, in Xcode choose **File → Add Package Dependencies**, paste the
confirmed GitHub repository URL, select a version range from `0.1.0` up to (but
excluding) `0.2.0`, and add the **TypedCoreData** product to your target.

For a remote Swift Package Manager dependency, replace the placeholder with that
same confirmed repository URL:

```swift
dependencies: [
    .package(
        url: "<CONFIRMED_GITHUB_REPOSITORY_URL>",
        .upToNextMinor(from: "0.1.0")
    )
]
```

During local review, use this checkout instead:

```swift
dependencies: [
    .package(path: "../TypedCoreData")
]
```

Add `.product(name: "TypedCoreData", package: "TypedCoreData")` to your target's
dependencies, then `import TypedCoreData`.

During the `0.x` series, a minor release may introduce source changes; patch
releases are intended to remain source compatible. The next-minor dependency
range above makes upgrades across that boundary explicit. See [CHANGELOG.md](CHANGELOG.md).

## License preparation

The official [Apache License 2.0 text](LICENSE) is prepared as the proposed
license. Its presence does not establish ownership or clear prior Olvid SAS
rights. Copyright attribution and permission to publish remain subject to owner
review; see [the licensing review](docs/LICENSING_REVIEW.md). Nothing in this
checkout represents confirmation that those questions are resolved.

## Usage

Given a `Note: NSManagedObject` subclass configured in your existing Core Data
model, use the APIs on the context's queue:

```swift
import CoreData
import TypedCoreData

func createNote(in context: NSManagedObjectContext) {
    context.perform {
        do {
            let note = Note(context: context)
            try context.save()

            let id: ManagedID<Note> = note.managedID
            let existing: Note = try context.existingObject(with: id)
            let objectOrFault: Note = context.object(with: id)
            let registered: Note? = context.registeredObject(for: id)

            // Native Core Data APIs remain available.
            let nativeID: NSManagedObjectID = id.objectID
            print(existing, objectOrFault, registered as Any, nativeID)
        } catch {
            print("Core Data operation failed:", error)
        }
    }
}
```

Type inference also works: `let existing = try context.existingObject(with: id)`
infers `Note`. There is no caller-side cast. `ManagedID<Note>` cannot be used where
an unrelated managed object's identifier is required.

## API and native behavior

| API | Behavior |
| --- | --- |
| `object.managedID` | Captures the current native ID with the reference's static Swift type. |
| `id.objectID` | Exposes the native `NSManagedObjectID` for interoperability. |
| `try ManagedID<Note>(validating: rawID)` | Checks the entity's declared runtime class without fetching an object. |
| `try context.existingObject(with: id)` | Calls the native throwing resolver and propagates its errors unchanged. Core Data may perform I/O. |
| `context.object(with: id)` | Returns an existing registration or creates a fault without checking whether a stored object exists. |
| `context.registeredObject(for: id)` | Returns an existing registration, or `nil`; does not fetch or create a fault. |
| `try context.fetchObjectIDs(for: request)` | Copies a managed-object request, fetches native IDs, and validates every returned ID. |
| `objects(inSectionAt: index, of: controller)` | Returns a checked section array with the controller's result type. |
| `try setPredicate(predicate, on: request)` | Converts a native Swift predicate with the same root as the request; requires iOS 17 / macOS 14. |
| `try context.execute(batchDeleteRequest)` | Returns the native `NSBatchDeleteResult`, preserving errors and payloads. |
| `try context.execute(batchUpdateRequest)` | Returns the native `NSBatchUpdateResult`, preserving errors and payloads. |
| `NSBatchDeleteRequest(objectIDs: typedIDs)` | Forwards the underlying IDs to the native initializer, preserving its validation. |

The object-resolution and batch-execution overloads perform the native operation
followed by a checked cast. Core Data's
behavior for faults, pending deletions, and registrations is preserved. In
particular, `existingObject(with:)` is not a separate validation that a registered
object still has a row in the store. Accessing attributes of an inaccessible fault
returned by `object(with:)` retains Core Data's behavior, including possible
Objective-C exceptions; these are not converted into Swift errors.

## Validated identifier reconstruction

When a native API supplies an object ID, validate its declared class before
using it as a typed identifier:

```swift
// On the context's queue, with a raw ID obtained through a native Core Data API:
let id = try ManagedID<Note>(validating: rawID)
let note: Note = try context.existingObject(with: id)
```

Validation uses the exact `objectID.entity.managedObjectClassName` and Objective-C
runtime lookup. It accepts the requested class and subclasses, including exact
module-qualified mappings. Custom entity names and several entities using one
class are supported; names are never guessed from the Swift class.

`ManagedIDValidationError` distinguishes a missing/empty class name, an
unresolvable class name, and an incompatible class. The check does not fetch or
materialize an object. It proves **declared class compatibility**, not existence,
permanence, or compatibility with a particular context, model, or store. Deleted
and temporary IDs can pass. The trusted internal initializer remains
`fileprivate`; there is no public unchecked initializer.

## Fetch typed object IDs

Given a `Note` model entity with a `title` property, on the context's queue:

```swift
let request = NSFetchRequest<Note>(entityName: "Note") // Actual model entity name.
request.predicate = NSPredicate(format: "title != nil")
request.includesPendingChanges = false

let ids: [ManagedID<Note>] = try context.fetchObjectIDs(for: request)
// request.resultType is still .managedObjectResultType.
```

The method requires `.managedObjectResultType` on the source request, copies it,
and changes only the copy's mode to `.managedObjectIDResultType`. The original
request and its options remain unchanged. A different source mode throws
`FetchObjectIDsError.unsupportedResultType`. Native fetch errors propagate
unchanged; any invalid returned ID throws `ManagedIDValidationError`, and no
partial array is returned.

This is **per-result validation**. An empty result does not validate the request's
entity configuration. Native ID-mode semantics apply: pending changes can include
temporary or permanent-but-unsaved IDs, and ordering/pagination may differ from
an ordinary managed-object fetch. Property values may still be fetched when
`includesPropertyValues` is true. The helper does not save, promote IDs, materialize
objects for validation, or synchronize contexts. Do not mutate a request while
it is being used.

## Typed fetched-results-controller sections

```swift
// controller is NSFetchedResultsController<Note>, used on its context's queue.
try controller.performFetch()
if let sections = controller.sections, !sections.isEmpty {
    let notes: [Note]? = objects(inSectionAt: 0, of: controller)
    print(notes?.count as Any)
}
```

The controller determines the return type; there is no caller-selected cast.
The function preserves native order and object identity, returns `nil` when
sections or section objects are unavailable, and preserves an available empty
section as `[]`. Once section information exists, an invalid index fails a
descriptive precondition. Every element is checked; a runtime class mismatch also
fails a precondition instead of discarding objects or returning nil.

An empty grouped fetch may have no sections, so index zero is not always valid.
Whole-section conversion may allocate or materialize references; use the native
`controller.object(at:)` for a single row. Returned managed objects remain confined
to their context's queue.

## Native typed predicate attachment

On the context's queue, with a persisted `Note.title` property:

```swift
if #available(iOS 17, macOS 14, *) {
    let request = NSFetchRequest<Note>(entityName: "Note")
    let predicate = #Predicate<Note> { $0.title == "Draft" }
    try setPredicate(predicate, on: request)
    let notes: [Note] = try context.fetch(request)
}
```

One generic parameter ties `Predicate<Entity>` to `NSFetchRequest<Entity>`, so an
unrelated predicate root is rejected by the compiler. This uses Foundation's
native failable `NSPredicate` conversion. Failure throws
`PredicateConversionError.unsupportedPredicate` **before changing the request**;
the previous predicate remains intact. There is no unfiltered-query or in-memory
filtering fallback.

Successful conversion does not validate the model or guarantee SQLite translation.
A KVC-visible computed property can convert and then fail during fetch. Native
fetch errors and Objective-C exceptions retain their behavior. Optional
comparisons also preserve Core Data's semantics: on the tested SQLite runtime,
`nickname != "B"` and `!(nickname == "B")` excluded nil rows, while Swift predicate
evaluation included them. No expression rewriting promises Swift-equivalent nil
logic. Transformables, transient properties, and arbitrary expression forms are
not made SQL-compatible by this API.

### Why two free functions?

`objects(inSectionAt:of:)` and `setPredicate(_:on:)` use ordinary Swift generic
parameters that retain runtime type information. Swift 6 rejects the equivalent
generic Objective-C class extensions when their implementations need the class's
`ResultType` for a checked cast or generic predicate conversion. Moving the cast
into another helper does not fix that limitation. The free functions preserve
the controller/request relationships without an extra type argument, wrapper,
unchecked cast, custom predicate representation, or underscored KVC API.

Native properties remain mutable. The compiler checks the Swift types at these
call boundaries; it cannot stop callers from later changing a request's runtime
entity, result mode, or raw `NSPredicate`.

## Batch operations

Batch execution now infers the concrete result class. The result's **payload is
still `Any?`**, with its meaning determined by `resultType`:

| Operation | Result mode | Native payload interpretation |
| --- | --- | --- |
| Delete | `.resultTypeStatusOnly` | Boolean status (`NSNumber` / `Bool`). |
| Delete | `.resultTypeCount` | Deleted-object count (`NSNumber` / `Int`). |
| Delete | `.resultTypeObjectIDs` | `[NSManagedObjectID]`. |
| Update | `.statusOnlyResultType` | Boolean status (`NSNumber` / `Bool`). |
| Update | `.updatedObjectsCountResultType` | Updated-object count (`NSNumber` / `Int`). |
| Update | `.updatedObjectIDsResultType` | `[NSManagedObjectID]`. |

TypedCoreData returns the same result object and payload supplied by Core Data.
It does not convert payloads to typed IDs or change the selected result mode.

### Delete using typed IDs

Capture these IDs after saving the objects. The array must be nonempty, and all
IDs must satisfy Core Data's same-entity requirement and refer to a compatible
persistent store accessible to the executing context.

```swift
func deleteNotes(
    with ids: [ManagedID<Note>],
    in context: NSManagedObjectContext
) {
    guard !ids.isEmpty else { return }
    context.perform {
        do {
            let request = NSBatchDeleteRequest(objectIDs: ids)
            request.resultType = .resultTypeObjectIDs
            let result: NSBatchDeleteResult = try context.execute(request)

            if let deletedIDs = result.result as? [NSManagedObjectID] {
                print("Deleted stored objects:", deletedIDs.count)
                // Decide explicitly how to synchronize affected contexts.
            }
        } catch {
            print("Batch deletion failed:", error)
        }
    }
}
```

An array of `ManagedID<Note>` prevents mixing unrelated static Swift types. It
does **not** prove that every ID represents the same Core Data entity. IDs read
through a common superclass can represent different subentities, and several
entities can share one Swift class. The initializer forwards native IDs without
additional validation; invalid input retains Core Data's behavior, including
possible Objective-C exceptions. Temporary IDs are not appropriate for persisted
batch deletion, and obtaining permanent IDs alone does not save new objects.

### Update stored objects

For an actual model entity named `Note` with a `title` attribute:

```swift
func updateNoteTitles(in context: NSManagedObjectContext) {
    context.perform {
        do {
            let request = NSBatchUpdateRequest(entityName: "Note")
            request.propertiesToUpdate = ["title": "Updated"]
            request.resultType = .updatedObjectsCountResultType
            let result: NSBatchUpdateResult = try context.execute(request)

            if let count = result.result as? Int {
                print("Updated stored objects:", count)
            }
        } catch {
            print("Batch update failed:", error)
        }
    }
}
```

The update dictionary, entity name, and result payload retain their native types
and validation. The overload types the result class only.

When taking a reference to the overloaded method, supply the intended function
type. An unannotated `let execute = context.execute` is ambiguous after importing
TypedCoreData:

```swift
let execute: (NSPersistentStoreRequest) throws -> NSPersistentStoreResult =
    context.execute
```

### Store changes and context synchronization

Batch operations modify the persistent store directly. They do not behave like
calling `delete(_:)` or setting a property on each registered managed object.
Registered objects can retain stale values or remain registered after their
stored rows are deleted. Pending unsaved changes are not automatically saved.

The overloads do not save, merge, refresh, reset, or otherwise synchronize any
context. Choose a synchronization strategy appropriate for your application.
For example, after requesting object-ID results, you can explicitly call
`NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)` with
`NSDeletedObjectsKey` or `NSUpdatedObjectsKey` and the returned IDs for the
contexts you want to synchronize. Coordinate this with pending local edits and
normal Core Data queue rules.

Batch support and validation are store-dependent. These APIs are tested with
SQLite stores; they do not extend support to other store types. Batch operations
bypass ordinary managed-object lifecycle and validation behavior, so the same
application invariants may need to be enforced separately. See Apple's guides to
[batch deletes](https://developer.apple.com/library/archive/featuredarticles/CoreData_Batch_Guide/BatchDeletes/BatchDeletes.html)
and
[batch updates](https://developer.apple.com/library/archive/featuredarticles/CoreData_Batch_Guide/BatchUpdates/BatchUpdates.html).

## Guarantees and limitations

### Typed identity

`ManagedID<Entity>` is a `Hashable`, `Sendable` value. Equality and hashing forward
to the underlying `NSManagedObjectID`, so identifiers for the same object compare
equally across contexts when their generic types match. The identifier does not
retain a managed object or context and does not guarantee the object's existence.

Identifiers are created through `.managedID`, validated native-ID reconstruction,
or typed ID fetching. A URI-reconstructed ID can pass class validation without
having a row in the store. Raw IDs remain usable with native Core Data methods.

### Temporary and permanent IDs

New objects normally have temporary IDs. An identifier is a snapshot: capturing
`note.managedID` before saving does not make that value update when Core Data
assigns a permanent ID. Capture a new identifier after saving or calling
`obtainPermanentIDs(for:)`. Permanent-ID assignment alone does not save the object.

Temporary IDs can identify inserted objects in their owning context. They cannot
be used to resolve those unsaved objects in another context. For transfer to a
context connected to the same store, save the insertion and pass its permanent
typed ID. Parent/child contexts still require the normal saves through to the
persistent store when another store-connected context needs to read the object.

### Concurrency

The ID can cross concurrency boundaries; the managed object cannot. Read
`.managedID` on the owning context's queue and resolve it on the destination
context's queue using Core Data's `perform` or `performAndWait` APIs. These
overloads do not schedule work or change context isolation.

Swift 6 language mode enables complete strict concurrency checking for the library
and tests. The `Entity` parameter does not need to be `Sendable`: it supplies type
information and is not stored in the identifier. Checked conformance relies on
the Apple SDK's `NSManagedObjectID` concurrency annotation.

### Runtime models and inheritance

Swift's type system cannot validate a Core Data model. The identifier must be
valid for the destination context/store, and the model must resolve it to an
instance of `Entity` or a subclass. Resolution and section-access class mismatches
fail explicit preconditions. Validating reconstruction and ID fetching report
class-metadata failures through `ManagedIDValidationError`. Native errors are not
replaced with library errors, and no force casts are used.

Entity inheritance is supported. The generic parameter follows the reference's
static Swift type: a subclass reference produces `ManagedID<Subclass>`, while a
superclass reference to that same object produces `ManagedID<Superclass>`.
Generic IDs are invariant; `ManagedID<Subclass>` does not implicitly convert to
`ManagedID<Superclass>`.

## Testing

Run on macOS with Xcode 26.6 or a later compatible release selected:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
python3 Scripts/verify-advanced-apis.py
```

The tests build isolated, programmatic Core Data models backed by real in-memory
stores for identifier/resolution tests and disposable SQLite stores for batch
tests. They cover typed creation, equality and hashing, native resolution,
missing and deleted objects, registrations, lazy faults, temporary and permanent
IDs, entity inheritance, and transfer of a typed ID from a private context queue.
Batch tests cover native result classes and payload modes, errors, typed ID
inputs, inheritance, and registered-object synchronization behavior.
Additional tests cover class-metadata reconstruction, request copying and ID-mode
semantics, section arrays, and native predicate attachment executed on SQLite.
Private-context tests keep requests, controllers, and managed objects on their
context's queue and transfer only IDs and other Sendable values.
The verification script builds the production library and external clients for
macOS and iOS minimum targets, checks compiler-positive and compiler-negative
cases, and runs deliberate section and resolver precondition failures in separate
processes. Its self-tests reject unrelated compiler failures, including the
missing-symbol false positive found during review. Probe execution selects the
host's Intel or Apple Silicon architecture; cross-compilation is reported separately.
Fatal probes are outside the package test target. Research-only unsupported SQL
and crash probes under `Experiments/` are not run by the package suite.
A small Objective-C helper is linked only to the tests so they can observe native
validation exceptions without terminating the test process. The library target
has no dependency on that helper.
The asynchronous context test requires macOS 12 / iOS 15 or later; the library
does not require those newer context APIs. Native predicate tests require
macOS 14 / iOS 17. Cross-compilation does not certify older OS or iOS runtime
behavior. The required [CI workflow](.github/workflows/ci.yml) uses Xcode 26.6 on
`macos-26` for Debug/Release tests and the verifier, plus a separate required iOS
simulator job using the same Xcode version. Strict concurrency and warnings as
errors remain enabled. Intel minimum-target cross-compilation remains in the
verifier; there is no required Intel host job.
Run `python3 Scripts/test-ios-simulator.py` locally to use an installed compatible
simulator; a skip is reported when one is unavailable.

Positive compiler checks verify the ID and section APIs' inferred result types.
Separate negative functions attempt incompatible assignments using explicitly
typed parameters and local variables. The verifier requires the concrete types
in a mismatch diagnostic; generic ambiguity is not accepted. See the
[compiler verification follow-up](docs/IMPLEMENTATION_VERIFICATION.md#swift-60-negative-compiler-verification-follow-up)
for local results and historical older-toolchain findings. Xcode 16.0 verification
is no longer a release requirement.

See [release preparation results](docs/RELEASE_PREPARATION.md) for the current
toolchain, counts, commands, and platform gaps. Historical results remain in
[implementation verification](docs/IMPLEMENTATION_VERIFICATION.md).

## Design

The public surface consists of typed identifiers, validating reconstruction,
object resolution, ID fetching, section access, native predicate attachment,
batch overloads, and small validation/configuration error types. The trusted
identifier initializer stays `fileprivate` beside the protocol extension.
Checked casts enforce runtime object/result-class assumptions. Batch execution explicitly upcasts
the request to `NSPersistentStoreRequest` to select Core Data's native method
without recursive overload resolution.

There are no repositories, persistence abstractions, library-defined macros,
alternative models, query DSLs, or external dependencies. Predicate attachment
uses Apple's existing `Predicate` and conversion. Core Data remains responsible
for persistence and object lifecycle.

## Roadmap and remaining limits

**0.1.0 candidate:** typed identifiers and resolution, typed batch operations,
validated ID reconstruction, typed ID fetches, typed section access, and native
predicate attachment are all implemented. This is the intended first-release
scope; the earlier 0.2 allocation has been superseded. Publication awaits the
licensing, Git candidate, and platform verification decisions recorded in
[release preparation](docs/RELEASE_PREPARATION.md).

**0.2:** compatibility fixes and evidence from additional Swift 6 toolchains and
Apple OS runtimes take priority. A model-scoped fetch factory remains a design
candidate, with no committed API or delivery promise.

Future work remains separate: model-scoped fetch factories/templates, typed
relationships and batch payloads, and richer query validation. A custom predicate
DSL, underscored KVC conversion, concurrency scheduler, and public unchecked ID
initializer are not planned. The implementation preserves native nil, store,
pending-change and queue behavior rather than claiming to validate every runtime
configuration. See the [API audit](docs/API_AUDIT.md) and
[advanced study](docs/ADVANCED_TYPE_SAFETY_STUDY.md) for the design history and the
generic Objective-C extension limitation discovered during implementation.

See Apple's documentation for
[`NSManagedObjectID`](https://developer.apple.com/documentation/coredata/nsmanagedobjectid)
and
[`NSManagedObjectContext`](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext)
for the underlying APIs.
