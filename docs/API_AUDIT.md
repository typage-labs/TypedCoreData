# Core Data API Coverage and Type Safety Audit

**Project:** TypedCoreData / TypageLib
**Audit date:** 2026-10-25
**Status:** Historical audit; roadmap updated after the approved implementation.

The original findings below describe the audit-time package. Batch APIs and the
approved advanced additions have since been implemented locally. See the
[README](../README.md) for current APIs and
[implementation verification](IMPLEMENTATION_VERIFICATION.md) for results.

> If Core Data knows the type, Swift should know it too.

## Findings and scope

The existing `ManagedID<Entity>` and three context resolution overloads address a
real loss of type information. No correctness issue requiring their redesign was
found. Their checked casts correctly accommodate subclass instances and detect
inconsistent runtime model mappings.

The most useful next opportunities are:

1. Associate concrete batch request classes with their concrete result classes in
   `NSManagedObjectContext.execute` overloads.
2. Accept existing typed identifiers when constructing a batch-delete request.
3. Evaluate one model-scoped, validated fetch-request factory for generic code
   that cannot use a concrete generated `fetchRequest()` method. This is a
   conditional opportunity: its additional model checks are runtime validation.

Most ordinary fetch, insertion, fetched-results-controller, and concurrency APIs
already have suitable typed functionality. They do not need wrappers.

Two limits apply throughout this audit:

- Core Data's runtime entity model is not a Swift generic constraint. A class
  may represent multiple entities, and entity inheritance does not itself prove
  compatible Swift class inheritance.
- Native fetch requests remain mutable. Their generic result parameter does not
  constrain their `entity` or `resultType`. A factory can validate construction;
  it cannot prevent later contradictory configuration.

### Evidence and interpretation

The audit inspected the installed Apple SDK, rather than assuming online
documentation exactly matches it:

| Item | Examined version |
| --- | --- |
| Compiler | Apple Swift 6.4, `swiftlang-6.4.0.34.1` |
| Language/checking mode | Swift 6; complete strict concurrency; warnings as errors |
| macOS SDK | 27.0 |
| iOS SDK | 27.1 |
| Runtime used for standalone Core Data probes | macOS 27.0.1 |
| Current package deployment targets | macOS 10.15 / iOS 13 |

Signatures below use their Swift spelling and omit irrelevant access modifiers.
`E` means `E: NSManagedObject`; `R` means `R: NSFetchRequestResult`. Proposed
signatures are design sketches, not declarations added to the package.

**Implement** means recommended for a future implementation pass, **defer** means
the benefit needs additional design or evidence, and **reject** means no addition
under the current lightweight scope. Complexity includes semantic validation and
tests, not just the number of forwarding lines.

## 1. API candidate inventory

### A1. Managed object identifiers and context resolution

- **Native:** `NSManagedObject.objectID: NSManagedObjectID`;
  `existingObject(with: NSManagedObjectID) throws -> NSManagedObject`;
  `object(with: NSManagedObjectID) -> NSManagedObject`;
  `registeredObject(for: NSManagedObjectID) -> NSManagedObject?`.
- **Typed proposal:** The existing `.managedID: ManagedID<Self>` and overloads
  accepting `ManagedID<E>` and returning `E` / `E?`.
- **Compile-time gain:** The identifier's entity type determines the resolution
  result. Unrelated typed IDs cannot be substituted for one another.
- **Runtime assumptions:** Correct model/class mapping, compatible store and
  context, native ID lifecycle, and context queue confinement. An identifier is
  not proof that a stored object exists.
- **Native equivalent:** No entity-parameterized native object-ID API.
- **Complexity:** Low; already implemented and covered by real Core Data tests.
- **Recommendation:** **Implement — retain the existing implementation for 0.1.**
  No new public initializer and no `@unchecked Sendable` are needed.

### A2. Managed object construction and context mutation

- **Native:** `NSManagedObject.init(context: NSManagedObjectContext)`;
  `init(entity: NSEntityDescription, insertInto: NSManagedObjectContext?)`;
  `NSEntityDescription.insertNewObject(forEntityName: String, into:
  NSManagedObjectContext) -> NSManagedObject`; context `insert(_:)`, `delete(_:)`,
  and `refresh(_:mergeChanges:)` accept `NSManagedObject`;
  `obtainPermanentIDs(for: [NSManagedObject]) throws`.
- **Typed proposal considered:** `context.insert<E>(_: E.Type) -> E`, or generic
  versions of the mutation methods.
- **Compile-time gain:** Typed insertion duplicates `Person(context:)` or
  `Person(entity:insertInto:)`. Generic `Void`-returning mutation methods add no
  relationship between input and output types.
- **Runtime assumptions:** Class/entity association, abstract-entity rules,
  context/store membership, and queue confinement remain unchanged.
- **Native equivalent:** Yes, subclass initializers return the subclass type;
  native mutation methods already accept managed-object subclasses.
- **Complexity:** Low forwarding cost; unnecessary mapping policy for insertion.
- **Recommendation:** **Reject.** Document the native typed initializers instead.

### A3. Ordinary KVC and primitive accessors

- **Native:** `value(forKey: String) -> Any?`, `setValue(_: Any?, forKey: String)`,
  `primitiveValue(forKey: String) -> Any?`, and
  `setPrimitiveValue(_: Any?, forKey: String)` on `NSManagedObject`.
- **Typed proposal considered:** Accessors tying a `KeyPath<Owner, Value>` or
  `ReferenceWritableKeyPath<Owner, Value>` to a returned/assigned `Value`.
- **Compile-time gain:** Can relate a property root and value type. A generic
  `value<T>(forKey: String) -> T` does not establish that relationship and merely
  moves the cast. Normal generated Swift properties already provide it.
- **Runtime assumptions:** A Swift key path must represent the intended KVC key.
  Primitive storage may bridge values differently from a custom public accessor;
  optional values, `NSNull`, transformables, and KVO/fault notifications matter.
- **Native equivalent:** Yes for ordinary typed property access; no general
  typed primitive-storage contract.
- **Complexity:** Low for redundant ordinary access; high for a correct primitive
  accessor design.
- **Recommendation:** **Reject** ordinary KVC wrappers; **defer** primitive access
  to separate design driven by an actual custom-accessor use case.

### A4. Relationship object IDs

- **Native:** `NSManagedObject.objectIDs(forRelationshipNamed: String)
  -> [NSManagedObjectID]`.
- **Typed proposal:** Relationship-key-path overloads returning
  `[ManagedID<Destination>]`, with distinct signatures for to-one and to-many
  relationship property types.
- **Compile-time gain:** The relationship property's destination type determines
  the ID type, without loading destination objects just to obtain `.managedID`.
- **Runtime assumptions:** Validate the key as a relationship and its destination
  entity/class hierarchy. Preserve native cardinality/order behavior. Generated
  `NSSet?` / `NSOrderedSet?` properties do not encode an element type in Swift.
- **Native equivalent:** No typed-ID equivalent; generated relationship accessors
  often already type individual managed objects.
- **Complexity:** High: key-path representation, optional/to-many variants,
  destination validation, and an internal trusted ID-construction path.
- **Recommendation:** **Defer.** Do not accept an unrelated caller-chosen generic
  type alongside a string and describe that as compile-time validation.

### A5. Context fetching and counting

- **Native:** `fetch<R>(_ request: NSFetchRequest<R>) throws -> [R]` and
  `count<R>(for request: NSFetchRequest<R>) throws -> Int`.
- **Typed proposal considered:** Additional `fetch<E>` / `count<E>` overloads
  restricted to managed objects.
- **Compile-time gain:** None beyond the existing generic request/result link.
- **Runtime assumptions:** The request must select a compatible entity and result
  mode; native predicates, store capabilities, and queue confinement still apply.
- **Native equivalent:** Yes, including generic `count(for:)` in the installed
  Swift overlay. Fetching IDs, dictionaries, and counts need not be excluded.
- **Complexity:** Low.
- **Recommendation:** **Reject.** Reuse native generic fetch/count.

### A6. Context registration and change collections

- **Native:** `registeredObjects`, `insertedObjects`, `updatedObjects`, and
  `deletedObjects` are `Set<NSManagedObject>`.
- **Typed proposal considered:** `registeredObjects<E>(of: E.Type) -> Set<E>` and
  corresponding change-set filters.
- **Compile-time gain:** Produces a typed subset, but Core Data's full collection
  is genuinely heterogeneous; it has not lost one known entity type.
- **Runtime assumptions:** Runtime subtype filtering, context queue access, and
  explicit subset semantics. A cast of the entire set is not generally valid.
- **Native equivalent:** Standard Swift collection filtering and conditional
  casts provide the operation; no homogeneous native collection is implied.
- **Complexity:** Low.
- **Recommendation:** **Reject** as a convenience-only addition at this stage.

### A7. Validated entity-to-fetch-request binding

- **Native:** `NSManagedObject.entity() -> NSEntityDescription`;
  `NSEntityDescription.entity(forEntityName: String, in:
  NSManagedObjectContext) -> NSEntityDescription?`;
  `NSManagedObjectModel.entitiesByName: [String: NSEntityDescription]`;
  `NSFetchRequest<R>.init()`, `init(entityName: String)`, and
  `entity: NSEntityDescription?`.
- **Typed proposal:**

  ```swift
  // On NSManagedObjectModel; proposed only.
  func fetchRequest<E: NSManagedObject>(
      for type: E.Type,
      entityName: String? = nil
  ) throws -> NSFetchRequest<E>
  ```

- **Compile-time gain:** The class argument determines the request and eventual
  fetch result type, including in generic code. The extra protection over native
  `NSFetchRequest<E>` is runtime validation of the model binding, not compiler
  knowledge of the model. It must do that validation to justify its existence.
- **Runtime assumptions:** Resolve within this model, reject missing/ambiguous
  mappings, validate the selected class and included subentities, and execute in
  a context using that model. Later request mutation can invalidate the binding.
- **Native equivalent:** Partial. Concrete generated `Person.fetchRequest()` is
  normally sufficient. Neither the base generic call nor an arbitrary
  `NSFetchRequest<Person>(entityName: ...)` validates the model/class association.
- **Complexity:** Medium. See the exact proposed contract in section 2.
- **Recommendation:** **Defer; conditional 0.2 candidate.** Implement only if
  validated runtime model binding is accepted within scope and a generic
  construction use case justifies it. Under a strict requirement for additional
  compile-time guarantees, retain native requests. If adopted, prefer this single
  factory over separate object, entity, context, and container factories.

### A8. Generic entity-description wrappers

- **Native:** `NSEntityDescription.managedObjectClassName: String!`,
  `name: String?`, `superentity: NSEntityDescription?`,
  `subentities: [NSEntityDescription]`, and
  `isKindOf(entity: NSEntityDescription) -> Bool`.
- **Typed proposal considered:** A new `ManagedEntity<E>` wrapper, or a typed
  entity lookup returning only an unparameterized `NSEntityDescription`.
- **Compile-time gain:** A wrapper could retain a class association. Returning the
  native descriptor alone cannot retain it for subsequent operations.
- **Runtime assumptions:** Entity inheritance and Swift class inheritance are
  distinct; class-name resolution and model membership require validation.
- **Native equivalent:** Native metadata is already typed as metadata, but has no
  generic connection to a managed-object class.
- **Complexity:** Medium/high once a useful wrapper API is designed.
- **Recommendation:** **Reject for 0.1/0.2.** A new descriptor abstraction is not
  necessary for A7 and would enlarge the library's model surface.

### A9. Model fetch templates

- **Native:** `fetchRequestTemplate(forName: String)
  -> NSFetchRequest<any NSFetchRequestResult>?`;
  `fetchRequestFromTemplate(withName: String, substitutionVariables:
  [String: Any]) -> NSFetchRequest<any NSFetchRequestResult>?`;
  `fetchRequestTemplatesByName: [String: NSFetchRequest<any NSFetchRequestResult>]`.
- **Typed proposal:** A substitution overload with an additional `as: E.Type`,
  returning `NSFetchRequest<E>?` and throwing on an incompatible binding.
- **Compile-time gain:** Carries a checked template's result type into native
  fetch. The model's template name and substitution-variable types remain dynamic.
- **Runtime assumptions:** Validate result mode, entity mapping and descendants;
  use a request copy and preserve native missing-template behavior. An
  `as? NSFetchRequest<E>` cast alone cannot validate erased Objective-C generics.
- **Native equivalent:** No equivalent checked typed template retrieval.
- **Complexity:** Medium/high, building on A7 and defining validation errors.
- **Recommendation:** **Defer** until a concrete template use case justifies it.
  Never mutate a template owned by an in-use model. [Apple template API][templates]

### A10. Fetch execution, result modes, and typed ID results

- **Native:** `NSFetchRequest<R>.execute() throws -> [R]`;
  `resultType: NSFetchRequestResultType`; context generic `fetch(_:)`;
  ID-mode requests return `[NSManagedObjectID]`.
- **Typed proposal:** A future context operation such as
  `fetchObjectIDs<E>(for request: NSFetchRequest<E>) throws -> [ManagedID<E>]`.
- **Compile-time gain:** Preserves the source entity type through an ID-only
  fetch. Generic `execute` wrappers themselves add nothing.
- **Runtime assumptions:** Validate the source entity/hierarchy, use a copy rather
  than changing the caller's result mode, preserve request options and native
  pending-change/store behavior, and establish trusted ID provenance. Swift's
  `R` and the mutable result mode are not linked by the native type system.
- **Native equivalent:** Generic fetch/execute and raw ID fetch exist; preserving
  `E` in an ID result does not.
- **Complexity:** Medium/high. Copying and retargeting an Objective-C generic
  request is not a proof of its runtime entity type.
- **Recommendation:** **Defer** typed ID fetch to a separate request/result design;
  **reject** duplicate generic `execute` and caller-selected `result<T>()` casts.

### A11. Request predicates, sorting, projections, and prefetch paths

- **Native:** `predicate: NSPredicate?`, `sortDescriptors: [NSSortDescriptor]?`,
  `propertiesToFetch: [Any]?`, `propertiesToGroupBy: [Any]?`, and
  `relationshipKeyPathsForPrefetching: [String]?` on `NSFetchRequest<R>`.
- **Typed proposal considered:** Root-bound key-path configuration, for example
  prefetch paths accepted as `[PartialKeyPath<E>]`, or sort paths rooted in `E`.
- **Compile-time gain:** Can reject misspelled Swift properties and unrelated
  roots. It cannot prove that a property is persistent, a relationship, or
  translatable into the store's query language.
- **Runtime assumptions:** KVC representation, relationship/attribute validation,
  permitted expressions, optional values and store-supported operations. A
  `PartialKeyPath` alone also permits scalar properties for relationship prefetch.
- **Native equivalent:** Partial: Foundation already offers
  `NSSortDescriptor(keyPath:ascending:)`; the fetch request's erased descriptor
  array does not retain that root constraint. Ordinary generated properties are
  already typed. Arbitrary Swift predicates are not automatically Core Data SQL.
- **Complexity:** Medium for a narrow validated key-path setter; high for a query
  language or typed projection system.
- **Recommendation:** **Defer** narrow root-bound configuration; **reject** a
  general predicate/query DSL within this roadmap.

### A12. Fetched-results-controller core access

- **Native:** `NSFetchedResultsController<R>`;
  `init(fetchRequest: NSFetchRequest<R>, managedObjectContext:
  NSManagedObjectContext, sectionNameKeyPath: String?, cacheName: String?)`;
  `fetchRequest: NSFetchRequest<R>`, `fetchedObjects: [R]?`,
  `object(at: IndexPath) -> R`, and `indexPath(forObject: R) -> IndexPath?`.
- **Typed proposal considered:** Generic forwarding controller/object accessors.
- **Compile-time gain:** None: the request and result APIs already share `R`.
- **Runtime assumptions:** Correct request configuration, sort order, caching,
  and context queue access.
- **Native equivalent:** Yes.
- **Complexity:** Low.
- **Recommendation:** **Reject.** Use the native generic controller.

### A13. Fetched-results-controller section contents and section key

- **Native:** `sections: [any NSFetchedResultsSectionInfo]?` and section-info
  `objects: [Any]?`; initializer `sectionNameKeyPath: String?`.
- **Typed proposal:** Controller-owned
  `objects(inSectionAt: Int) -> [R]?`; separately, an initializer accepting a
  section `KeyPath<R, SectionValue>`.
- **Compile-time gain:** The controller knows the section objects' type. A
  key-path initializer can associate the section property's root with `R`.
- **Runtime assumptions:** Only use sections obtained from this controller; define
  nil/index semantics and check casts. A key path must be KVC-representable and
  satisfy native sectioning/sort requirements. Array conversion may allocate.
- **Native equivalent:** Partial: `object(at:)` already provides typed individual
  access. Section arrays and the section-name string remain erased.
- **Complexity:** Low/medium for section contents; medium for the key-path contract.
- **Recommendation:** **Defer**, behind the higher-value request/result boundaries.

### A14. Fetched-results-controller delegate callbacks

- **Native:** `controller(_: NSFetchedResultsController<any NSFetchRequestResult>,
  didChange: Any, at: IndexPath?, for: NSFetchedResultsChangeType,
  newIndexPath: IndexPath?)`; the difference callback accepts
  `CollectionDifference<NSManagedObjectID>`.
- **Typed proposal:** A controller-bound delegate adapter with `E` object callbacks
  and, if validated, `ManagedID<E>` changes.
- **Compile-time gain:** Restores the controller's known type across the erased
  Objective-C delegate boundary.
- **Runtime assumptions:** Adapter lifetime, forwarding/replacement, notification
  mode precedence, queue confinement, and ID provenance. Deleted IDs cannot be
  typed by fetching deleted objects afterward.
- **Native equivalent:** No fully generic delegate protocol. Extensions cannot
  make Apple's existing protocol generic.
- **Complexity:** High.
- **Recommendation:** **Defer** to separate adapter design; no controller wrapper
  or observation subsystem in 0.1/0.2.

### A15. Batch-delete and batch-update execution result classes

- **Native:** `NSManagedObjectContext.execute(_ request:
  NSPersistentStoreRequest) throws -> NSPersistentStoreResult`.
- **Typed proposal:**

  ```swift
  func execute(_ request: NSBatchDeleteRequest) throws -> NSBatchDeleteResult
  func execute(_ request: NSBatchUpdateRequest) throws -> NSBatchUpdateResult
  ```

- **Compile-time gain:** Each concrete request selects its documented concrete
  result class. No caller cast or unrelated generic output-type choice is needed.
  These specific overloads are preferable to an unconstrained generic `execute`.
- **Runtime assumptions:** Core Data returns the documented result subclass.
  Propagate native errors unchanged; check that invariant without swallowing a
  mismatch. Native store support, validation and synchronization semantics remain.
- **Native equivalent:** No equivalent concrete-result overload in the installed SDK.
- **Complexity:** Low. Result **payloads** remain `Any?`; see A18.
- **Recommendation:** **Implement first in 0.2.** These are small, substantive
  improvements and need no new persistence abstraction.

### A16. Batch-delete input identifiers

- **Native:** `NSBatchDeleteRequest.init(objectIDs: [NSManagedObjectID])`.
- **Typed proposal:** `convenience init<E: NSManagedObject>(objectIDs:
  [ManagedID<E>])`.
- **Compile-time gain:** Rejects a typed array mixing unrelated managed-object
  classes and accepts the existing identifier type without erasing it at call sites.
- **Runtime assumptions:** Static class equality does **not** prove the native
  same-entity requirement: superclass-typed IDs may represent multiple subentities,
  and several entities may use one Swift class. IDs must be appropriate permanent
  IDs for the executing store. The native request does not retain `E` as a generic.
- **Native equivalent:** No typed-ID overload.
- **Complexity:** Low; document native validation rather than promise homogeneous
  Core Data entities. [Apple's same-entity requirement][batch-ids]
- **Recommendation:** **Implement in 0.2 at lower priority**, with inheritance,
  invalid-input, and store-compatibility tests.

### A17. Batch-delete generic fetch input

- **Native:** `NSBatchDeleteRequest.init(fetchRequest:
  NSFetchRequest<any NSFetchRequestResult>)`.
- **Typed proposal considered:** `init<E: NSManagedObject>(fetchRequest:
  NSFetchRequest<E>)`.
- **Compile-time gain:** Primarily removes an erasure step for an already typed
  request. It does not carry `E` into the batch request or its output.
- **Runtime assumptions:** Entity/result-mode consistency and batch-store support.
  A typed request is not implicitly convertible to the erased generic request in
  the tested Swift compiler, despite the Objective-C covariance annotation.
- **Native equivalent:** The erased initializer already performs the operation.
- **Complexity:** Low/medium, including careful request copying/erasure semantics.
- **Recommendation:** **Reject** as a convenience-only overload in this scope.

### A18. Batch result payloads

- **Native:** `NSBatchDeleteResult.result: Any?` with
  `resultType: NSBatchDeleteRequestResultType`; `NSBatchUpdateResult.result: Any?`
  with `resultType: NSBatchUpdateRequestResultType`. Requests select status, count,
  or object-ID results through mutable `resultType` properties.
- **Typed proposal:** A future statically selected result-mode operation returning
  status, count or IDs; possibly a checked payload enum.
- **Compile-time gain:** Could prevent interpreting a count as IDs. Entity-typed
  ID output additionally requires entity provenance through the request.
- **Runtime assumptions:** Validate mode and payload, handle NSNumber bridging and
  nil, and account for inherited entities. Resolving deleted objects afterward
  cannot establish their types. The current `fileprivate` ID initializer requires
  a deliberate internal creation design, not a public unchecked initializer.
- **Native equivalent:** No coupling between a request's mode and a Swift payload
  type. Concrete result-class overloads in A15 do not solve this separate problem.
- **Complexity:** Medium/high.
- **Recommendation:** **Defer**. Reject arbitrary generic `result<T>()` cast helpers.

### A19. Batch-update entity and property values

- **Native:** `NSBatchUpdateRequest.init(entityName: String)`,
  `init(entity: NSEntityDescription)`, `entity: NSEntityDescription`,
  `includesSubentities: Bool`, and `propertiesToUpdate: [AnyHashable: Any]?`.
- **Typed proposal:** An entity-bound update operation associating
  `ReferenceWritableKeyPath<E, Value>` with a `Value` assignment.
- **Compile-time gain:** Could constrain both property root and assigned value.
  Simply adding `init<E>(_: E.Type)` does not make the update dictionary typed.
- **Runtime assumptions:** The native request has no `E` parameter, so an isolated
  key-path setter cannot prove its entity matches the key-path root. Persistent
  attributes, expressions, nulls, bridging, relationships, and batch validation
  differ from ordinary Swift property assignment.
- **Native equivalent:** No entity/value-bound generic update API.
- **Complexity:** High; a larger operation representation would be required.
- **Recommendation:** **Defer** to separate design. Do not add an update DSL or
  entity-name convenience initializer in 0.1/0.2.

### A20. Context and container concurrency

- **Native:** Generic `perform`, `performAndWait` and
  `NSPersistentContainer.performBackgroundTask` already return `T` and rethrow;
  section 3 records their full concurrency-sensitive signatures.
- **Typed proposal considered:** Async/throwing wrappers; alternatively a
  distinctly named operation requiring `T: Sendable`.
- **Compile-time gain:** None for generic async wrappers. A distinct constrained
  method could reject non-Sendable results, but cannot enforce every context-queue
  access. A same-name constrained overload leaves the native fallback available.
- **Runtime assumptions:** Context queue confinement still applies to captures,
  returned objects, faulting collections and object graphs.
- **Native equivalent:** Yes for scheduling, errors and generic return values;
  no native `T: Sendable` result constraint in this SDK.
- **Complexity:** Low for duplicates; medium to design a useful narrower contract.
- **Recommendation:** **Reject** duplicates and same-name safety claims; **defer**
  any distinct Sendable-result operation. Add guidance, not helpers, in 0.1/0.2.

### A21. Persistent-container stack properties

- **Native:** `viewContext: NSManagedObjectContext`,
  `newBackgroundContext() -> NSManagedObjectContext`,
  `managedObjectModel: NSManagedObjectModel`, and
  `init(name: String, managedObjectModel: NSManagedObjectModel)`.
- **Typed proposal considered:** `TypedPersistentContainer<E>` or entity-specific
  context properties/factories.
- **Compile-time gain:** None justified: a native container/context normally
  manages several entity types. A single `E` would impose a new limitation.
- **Runtime assumptions:** Store loading, model selection, configurations, and
  queue ownership remain native responsibilities.
- **Native equivalent:** Existing properties already provide their concrete types;
  explicit model injection already supports multiple models.
- **Complexity:** Medium/high if made into a useful container abstraction.
- **Recommendation:** **Reject.** No container, repository, or persistence wrapper.

## 2. Typed fetch requests without entity-name guesses

### Options evaluated

| Approach | Assessment |
| --- | --- |
| `String(describing: E.self)` / splitting a module-qualified name | Reject. A Swift class name is not a Core Data entity name. |
| `E.entity()` followed by assigning `request.entity` | Works for a correctly configured, unambiguous single mapping, including a custom entity name. It has no explicit model argument and is not robust across multiple live models or shared class mappings. |
| `NSFetchRequest<E>(entityName: knownModelEntityName)` | Native and adequate when the application already owns that mapping. It does not validate that the named entity produces `E`. |
| Concrete generated `Person.fetchRequest()` | Preferred native API for ordinary concrete code. Generated code records the model's entity name; it does not need to infer it from the Swift class. |
| Generic `E.fetchRequest()` where `E: NSManagedObject` | Resolves through the base declaration returning `NSFetchRequest<any NSFetchRequestResult>`. It does not statically use every concrete subclass's generated typed overload. |
| Explicit descriptor from a selected model | Avoids name guessing and global class-to-entity lookup. Class compatibility still needs checking before binding it to `NSFetchRequest<E>`. |
| Class lookup within an explicit model | Can infer a unique entity mapping, with an explicit entity-name escape hatch for legitimately ambiguous models. Smallest candidate if generic code needs validated binding. |

The installed base `fetchRequest()` is an Objective-C dynamic,
`@_disfavoredOverload` Swift overlay method. Generated concrete typed overloads
are separate; generic algorithms must not assume they satisfy a universal
`NSFetchRequest<Self>` contract. [Apple generated-code example][codegen]

### Smallest additive API, if validated binding is in scope

If adopting A7, use **one factory on `NSManagedObjectModel`**. A typical call
would be `try model.fetchRequest(for: Person.self)`; a shared-class model could
disambiguate with `entityName: "ArchivedPersonRecord"`.

The model is an explicit input through the receiver. This avoids a global cache,
process-wide class-to-entity lookup, context scheduling policy, a registration protocol,
and a new typed entity wrapper. Applications can supply
`container.managedObjectModel`. Concrete generated fetch methods remain the
default for applications that do not need generic construction.

This recommendation admits a checked construction boundary as a type-safety
improvement. If the acceptance criterion is strictly a new compile-time guarantee
beyond native `NSFetchRequest<E>`, add no factory: use generated requests or
explicit descriptors. The factory's model-validation benefit is runtime-based
and must not be advertised as a compiler-verified schema.

Proposed factory contract:

1. **Resolve in this model only.** Without an explicit name, find exactly one
   entity whose configured managed-object class resolves to `E` by class identity.
   Do not choose the first match. With a name, use `entitiesByName` and validate it.
2. **Resolve Objective-C runtime class identities.** Respect module-qualified
   names and explicit `@objc` names using the model's class metadata. Use
   `NSClassFromString`/class identity, not shortened-name comparisons. Fail
   explicitly when a class name cannot be resolved; do not silently substitute
   `NSManagedObject`.
3. **Validate compatibility.** A named entity mapped to an `E` subclass is
   compatible with an `NSFetchRequest<E>`. A superclass or unrelated class is not.
   The automatic search uses exact class identity to avoid selecting arbitrary
   descendants as the intended root entity. This conservative contract also
   checks an abstract root's mapped class. If that root is mapped more broadly
   than `E`, request the broader Swift type or select a concrete entity; do not
   infer a narrower root type from its current concrete descendants.
4. **Validate included descendants.** Native `includesSubentities` defaults to
   true. All descendants that can produce results must also map to classes
   compatible with `E`. Do not silently disable subentity fetching. Abstract
   roots may be fetched; they must not be treated as insertable objects.
5. **Construct a native request.** Use `NSFetchRequest<E>()`, assign the selected
   descriptor, and retain native managed-object result mode and other defaults.
   No class-derived entity-name string is needed.
6. **Fail recoverably.** Missing, ambiguous, unresolved or incompatible mappings
   are construction failures. Define their error representation during
   implementation; never pick a model/entity silently.
7. **State the boundary.** The request must execute against a context using the
   selected model. A mutable request can later be changed into an incompatible
   request. This factory establishes a validated initial binding, not a permanent
   proof enforced by Swift.

An explicit `NSEntityDescription` already identifies the model entity, so native
construction with `request.entity = descriptor` remains an adequate escape hatch
for callers that own the validation. Adding a second public factory for it is not
necessary in the initial design. A context-scoped variant is also unnecessary;
the model-scoped version avoids model-discovery and queue-ownership policy.

### Runtime and compiler findings

Standalone programmatic-model probes established the following on the examined SDK:

| Case | Observation and consequence |
| --- | --- |
| Class `Person` mapped to custom entity name | `Person.entity()` found the custom name when the mapping was unambiguous. Class-name equality is unnecessary. |
| Two live models mapping `Person` | Class-only `entity()` lookup logged ambiguity and returned a descriptor with no name, belonging to neither expected model. Model-scoped lookup selected the intended descriptor. Do not depend on that particular failure representation. |
| Two entities in one model mapped to `Person` | Class-only selection was ambiguous. An explicit model alone is insufficient without either a uniqueness check or an explicit entity name. |
| Module-qualified managed-object class | `NSStringFromClass` / `NSClassFromString` preserved and resolved its runtime identity. |
| Matching entity and Swift subclass inheritance | A base-class fetch could return the compatible subclass. Exact-class validation of every result would incorrectly reject valid inheritance. |
| Entity subentity mapped to an unrelated Swift managed-object class | Core Data accepted the model and save; a base typed fetch contained the unrelated instance. Validate descendant class compatibility, not just `isKindOf(entity:)`. |
| Change `NSFetchRequest<Person>.resultType` to object-ID mode | Compiled; runtime inspection of erased results showed object IDs. The generic argument does not select/validate result mode. |
| Assign an unrelated descriptor to `NSFetchRequest<Person>.entity` | Compiled and produced objects of that unrelated class. A native generic request is not immutable type evidence. |
| Read `.entity` on an unresolved name-only request before contextual use | Raised `NSObjectInaccessibleException` in the probe. Do not blindly inspect this getter as a supposedly safe validation step; resolve the known name in the explicit model. |
| Return generic `E.fetchRequest()` as `NSFetchRequest<E>` | Compilation failed because the base method returns the erased request type. |

These observations motivate validation; they do not authorize changing Core Data's
native defaults. Entity name, class name, and module are distinct model settings.
[Apple entity configuration][entities]

## 3. Swift concurrency audit

### Native signatures and availability

On `NSManagedObjectContext`, the callback forms are available since
macOS 10.7 / iOS 5:

```swift
func perform(_ block: @escaping @Sendable () -> Void)
func performAndWait(_ block: @Sendable () -> Void)
```

The installed Swift overlay supplies the generic forms since macOS 12 / iOS 15:

```swift
@preconcurrency nonisolated
func performAndWait<T>(_ block: @Sendable () throws -> T) rethrows -> T

@preconcurrency nonisolated
func perform<T>(
    schedule: ScheduledTaskType = .immediate,
    _ block: @escaping @Sendable () throws -> T
) async rethrows -> T
```

`.immediate` permits immediate execution when already on the context queue;
`.enqueued` requests enqueuing. `performAndWait` is synchronous and supports
reentrant use. Preserve these choices rather than introducing different task
scheduling behavior under a similar name. [Apple's async Core Data session][wwdc]

On `NSPersistentContainer`, the callback API is available since macOS 10.12 / iOS 10:

```swift
func performBackgroundTask(
    _ block: @escaping @Sendable (NSManagedObjectContext) -> Void
)
```

Its generic async overload is already present since macOS 12 / iOS 15:

```swift
func performBackgroundTask<T>(
    _ block: @escaping (NSManagedObjectContext) throws -> T
) async rethrows -> T
```

The missing `@Sendable` in this last declaration is present in the inspected SDK;
it is not an omission in this audit. None of these generic return types has a
`T: Sendable` constraint or a `sending` result annotation.

### Sendability is not queue confinement

The inspected headers explicitly annotate `NSManagedObjectID`,
`NSManagedObjectContext`, and `NSPersistentContainer` as `NS_SWIFT_SENDABLE`.
`NSManagedObject` is explicitly `NS_SWIFT_NONSENDABLE`. The package's checked
`ManagedID<E>: Sendable` conformance compiles without requiring `E: Sendable`,
because it stores an ID rather than an instance of `E`.

Being able to transfer a context reference does not make all context methods or
registered objects safe on any queue. Read `.managedID` on the object's context
queue; transfer the ID; resolve and use the object on the destination context's
queue. Permanent-ID allocation alone does not save an insertion. Native batch
fetching can also return a lazily faulting array owned by the context, so a
collection result needs the same care as its managed objects.

Returning a managed object from `performAndWait` can be legitimate when the caller
will continue using it on its owning queue. It does not authorize accessing a
private-queue object on the calling thread. Likewise, returning one from an async
operation does not transfer Core Data ownership or detach it from its graph.
[Apple background guidance][background]

### What Swift 6 actually diagnosed

Compile-only probes used Swift 6.4, `-swift-version 6`,
`-strict-concurrency=complete`, and `-warnings-as-errors`. Unsafe managed-object
transfer examples were **not executed**.

| Probe | Observed result |
| --- | --- |
| Native async context `perform` returns `NSManagedObject`, including from `@MainActor` | Compiled without diagnostics. |
| Native async context `perform` returns `ManagedID<E>` | Compiled without diagnostics. |
| Native `performAndWait` returns `NSManagedObject` | Compiled without diagnostics. |
| Main-actor caller uses inferred closure with async container `performBackgroundTask` | Failed with an actor-isolated closure transfer diagnostic, including when returning an ID. |
| Same container call uses explicit `{ @Sendable context in ... }` | Compiled. |
| Existing managed object captured in context `perform` | Produced a warning but exit status 0, even with warnings-as-errors, under this SDK's compatibility annotations. |
| Pass managed object to an explicit `T: Sendable` requirement | Failed: managed-object Sendable conformance is unavailable. |
| Add same-name `perform<T: Sendable>` overload, then return a managed object | Still compiled by selecting the native unconstrained overload. |

The async object-return, ID-return, and container inference cases were also checked
against the iOS SDK. Diagnostics are compiler/SDK-specific observations, not a
promise about every Swift 6 release. `@preconcurrency` compatibility and imported
API signatures mean complete strict checking is not a Core Data queue-safety
proof. [Swift incremental concurrency migration][se0337]

A minimal accepted-but-unsafe-to-consume-off-queue example is:

```swift
import CoreData

@available(macOS 12.0, iOS 15.0, *)
@MainActor
func nativeBoundary(
    _ context: NSManagedObjectContext,
    id: NSManagedObjectID
) async throws -> NSManagedObject {
    try await context.perform {
        try context.existingObject(with: id)
    }
}
```

For a private context, do not access the returned object's properties on the main
actor. Return a `ManagedID`, scalar, or independently Sendable value snapshot
instead. A `sending` annotation would describe Swift region transfer, not remove
Core Data's queue requirements. A detached task or unchecked conformance cannot
repair this mismatch.

### Decision on helpers

No new concurrency helper is needed for 0.1 or 0.2. Native APIs already handle
generic results, throwing work, scheduling, and background contexts. Supporting
older deployment targets through a shim would be compatibility work rather than
new type safety, and is not part of this roadmap.

A distinctly named `T: Sendable` operation could enforce a narrower **result**
contract, but would not make captures or arbitrary context calls safe. Defer it
until a concrete use case justifies the extra API. Do not claim that a constrained
overload of the native name prevents callers from selecting the unconstrained
native operation.

## 4. Prioritized roadmap

Release preparation update (26 October 2026): all implemented additions below
belong to the proposed **0.1.0** release. This supersedes their earlier allocation
to 0.2. No version has been published. See [CHANGELOG.md](../CHANGELOG.md) and
[release preparation](RELEASE_PREPARATION.md) for the candidate and remaining gates.

| Release / priority | Work | Rationale and acceptance criteria |
| --- | --- | --- |
| **0.1 — implemented locally** | Typed IDs and three resolution overloads. | Essential loss-of-type-information fix; native semantics, checked Sendable, trusted fileprivate construction, and runtime preconditions retained. |
| **0.1 — P0** | Document native generic fetch/count/FRC and context APIs, ID lifecycle, and compiler limitations. | Prevent unnecessary wrappers and false queue-safety claims. Keep Swift 6 checking and dependency-free SPM support. |
| **0.1 — implemented locally** | Concrete `execute` overloads for batch delete/update (A15). | Native errors, concrete result classes and payload modes tested with SQLite; payloads remain untyped. |
| **0.1 — implemented locally** | Typed batch-delete ID initializer (A16). | Preserves native same-entity validation, ID-lifecycle behavior, store requirements and synchronization behavior. |
| **0.1 — implemented locally** | Validated ID reconstruction and copied-request typed ID fetching (A10). | Per-result declared-class validation; no existence, empty-request binding, saving or promotion guarantee. |
| **0.1 — implemented locally** | Typed FRC section access (A13). | `objects(inSectionAt:of:)` preserves the controller's type; checked elements and explicit index preconditions. A generic free function is required by Swift's Objective-C generic limitation. |
| **0.1 — implemented locally, newer OS only** | Native typed predicate attachment (A11). | `setPredicate(_:on:)` ties one root to the native request, reports bridge failure before mutation, and retains Core Data semantics. Requires iOS 17 / macOS 14; no DSL or underscored KVC dependency. |
| **0.2 — priority** | Broaden compiler/SDK/runtime evidence and address compatibility findings. | Current deployment-target compilation does not certify execution on old OS versions or other hosts. |
| **0.2 — P2, conditional** | Evaluate one validated model-scoped fetch factory (A7). | Defer implementation until runtime model binding is accepted as an in-scope benefit and a generic use case justifies it. If accepted, test missing/ambiguous mappings, explicit names, qualified/Objective-C class names, abstract roots, and compatible/incompatible descendants. |
| **Future** | Checked model templates (A9). | Separate model-binding and ambiguity contract still required. |
| **Future** | Relationship IDs, FRC section key paths/delegates, and typed batch payloads (A4/A13/A14/A18). | Useful erased boundaries, but each needs a separate ownership, validation or representation design. |
| **Future, only with demonstrated demand** | Primitive property access and entity-bound batch-update assignments (A3/A19). | Bridging, nullability, persistent-property and expression semantics make these more than forwarding overloads. |
| **Not planned** | Duplicate generic fetch/count/FRC/perform APIs; repositories, macros, container wrappers, alternate models or a query DSL. | No corresponding lightweight type-safety gain, or substantial departure from the project's scope. |

Batch APIs now have tests using disposable **SQLite stores**. In-memory tests
alone do not establish store-level batch support, validation or synchronization
behavior. Native batch
changes do not automatically synchronize every registered object; wrappers must
not introduce automatic merging or saving as an undocumented side effect.
[Apple batch deletes][batch-delete-guide] [Apple batch updates][batch-update-guide]

The validating initializer delegates to the trusted `fileprivate` initializer;
ID fetching reuses validation. No public unchecked initializer was introduced.
These roadmap entries report implementation state, not a published release.

## 5. Verification, limits, and reproducibility

This audit used header/overlay inspection, compiler probes, and standalone real
Core Data programmatic models backed by in-memory stores. It did not implement
any proposed API in the package. Existing package source, tests, manifest and
public APIs were left unchanged; the existing test suite was not rerun for this documentation-only
change. No commit, push or publication was performed.

Compiler probes used the following pattern (`-emit-sil` for concurrency probes,
`-typecheck` for signature/overload probes):

```sh
xcrun swiftc -emit-sil -parse-as-library -swift-version 6 \
  -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path /tmp/typedcoredata-audit-cache \
  Probe.swift -o /tmp/Probe.sil
```

For iOS checks, add `-target arm64-apple-ios15.0` and the SDK path reported by
`xcrun --sdk iphoneos --show-sdk-path`. Runtime observations above are macOS
observations, not iOS runtime test results. Older Swift 6 toolchains and older OS
runtimes were not exercised in this audit. No unsafe queue-transfer example was
run, and no store-level batch behavior was claimed from an in-memory test.

Remaining design issues are the fetch factory's validation-error representation,
request mutation after validation, trusted creation of typed IDs from non-object
results, and the designs explicitly deferred in the roadmap. There is no newly
identified correctness defect in the current public APIs.

### Installed SDK source map

Resolve the SDK root with `xcrun --sdk macosx --show-sdk-path`. Paths below are
relative to `System/Library/Frameworks/CoreData.framework/` in that SDK:

| File | Evidence inspected |
| --- | --- |
| `Headers/NSManagedObject.h` | Class-only `entity` contract; typed initializers; non-Sendable annotation; KVC and relationship ID access. |
| `Headers/NSManagedObjectID.h` | Native ID Sendable annotation and temporary-ID metadata. |
| `Headers/NSManagedObjectContext.h` | Native resolution, callback scheduling, heterogeneous sets, erased store-request execution, Sendable annotation. |
| `Headers/NSManagedObjectModel.h` | Entity lookup, model/template mutability and erased template APIs. |
| `Headers/NSEntityDescription.h` | Entity names, runtime class names, entity inheritance and metadata. |
| `Headers/NSFetchRequest.h` | Generic result parameter, mutable entity/result mode, projection/prefetch fields, context-owned batch-fetch array warning. |
| `Headers/NSFetchedResultsController.h` | Generic core APIs, erased section contents and delegate modes. |
| `Headers/NSBatchDeleteRequest.h` / `NSBatchUpdateRequest.h` | Constructors, mutable result modes, store-support/validation limits and untyped updates. |
| `Headers/NSPersistentStoreResult.h` | Batch result classes, runtime result modes and erased payloads. |
| `Headers/NSPersistentContainer.h` | Explicit model injection, typed stack properties, Sendable annotation and background callback. |
| `Modules/CoreData.swiftmodule/arm64e-apple-macos.swiftinterface` | Base `fetchRequest` (line 23), async container task (995–998), generic fetch/count (1059–1066), generic context scheduling (1120–1141). |

The matching iOS headers and `arm64e-apple-ios.swiftinterface` were also inspected
for Sendable annotations and concurrency signatures. Line references describe
this installed SDK snapshot and may move in later releases.

[entities]: https://developer.apple.com/documentation/coredata/configuring-entities
[codegen]: https://developer.apple.com/documentation/coredata/generating-code
[templates]: https://developer.apple.com/documentation/coredata/nsmanagedobjectmodel/fetchrequestfromtemplate%28withname%3Asubstitutionvariables%3A%29
[batch-ids]: https://developer.apple.com/documentation/coredata/nsbatchdeleterequest/init%28objectids%3A%29
[batch-delete-guide]: https://developer.apple.com/library/archive/featuredarticles/CoreData_Batch_Guide/BatchDeletes/BatchDeletes.html
[batch-update-guide]: https://developer.apple.com/library/archive/featuredarticles/CoreData_Batch_Guide/BatchUpdates/BatchUpdates.html
[wwdc]: https://developer.apple.com/videos/play/wwdc2021/10017/
[background]: https://developer.apple.com/documentation/coredata/using-core-data-in-the-background
[se0337]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md
