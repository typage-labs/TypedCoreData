# Changelog

## 0.1.0 — Unreleased

Initial release candidate, pending rights clearance and final human review. No
release date, Git tag, or remote package URL has been assigned.

### Included

- `ManagedID<Entity>` with checked `Sendable`, native equality/hashing, raw-ID
  interoperability, and `ManagedIdentifiable.managedID`.
- Typed native object resolution: `existingObject(with:)`, `object(with:)`, and
  `registeredObject(for:)`.
- Validated reconstruction from native IDs and copied-request `fetchObjectIDs(for:)`.
- `objects(inSectionAt:of:)`, preserving the fetched-results controller's type
  and checking every section element.
- Native `setPredicate(_:on:)`, tying the predicate root to the request and
  preserving the previous predicate when Foundation conversion fails.
- Concrete batch-delete/update execution results and a typed batch-delete ID
  initializer. Payloads and context synchronization remain native.
- SQLite and in-memory tests, private-context coverage, positive/negative
  compiler checks, isolated precondition probes, and prepared read-only CI.

### Requirements and limitations

- Swift 6 language mode, iOS 13 / macOS 10.15 deployment targets, no external
  dependencies. Native predicate attachment requires iOS 17 / macOS 14.
- Generic free functions are used where Swift cannot access an Objective-C
  generic class's type parameter from an extension implementation.
- Metadata checks do not establish store existence. Empty ID fetches do not
  validate a request's entity mapping. Native queue and ID lifecycle rules apply.
- Predicate conversion does not prove SQLite compatibility or Swift-equivalent
  nil semantics. Batch operations do not save or synchronize registered objects.
- Taking `context.execute` as an untyped method reference becomes ambiguous;
  supply its intended function type. Ordinary calls retain native spelling.
- Oldest OS runtimes and an Intel verification host have not been exercised
  locally. iOS compilation is distinct from simulator execution. See the exact
  evidence and outstanding CI/runtime checks in
  [release preparation](docs/RELEASE_PREPARATION.md).

The proposed Apache 2.0 licensing and attribution remain under review; see
[licensing review](docs/LICENSING_REVIEW.md). A rewrite alone does not establish
ownership or permission to publish.

During 0.x, minor versions may change source compatibility; patch versions are
intended to remain source compatible. No future feature is promised by this file.
