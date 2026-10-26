import CoreData

/// Returns the selected section's objects with this controller's result type.
///
/// Preserves the native section's order and object identities. Returns `nil`
/// when section information or the selected section's objects is unavailable,
/// and an empty array when an available section has no objects.
///
/// When section information is available, `index` must be a valid section
/// index. Every object must be compatible with `ResultType`; an invalid index
/// or runtime type mismatch fails a precondition instead of returning `nil`
/// or omitting objects. Swift's generic type cannot validate the fetch
/// request's mutable entity configuration or the Core Data model.
///
/// Call on the managed object context's queue. The returned objects remain
/// confined to that context. Checking and converting a whole section may
/// materialize references or allocate an array; use native `object(at:)`
/// when only a single object is needed.
///
/// A free function preserves the controller's generic result type for the
/// runtime check; Objective-C generic class extensions cannot access that
/// type parameter at runtime.
///
/// - Parameters:
///   - index: The zero-based section index.
///   - controller: The controller whose section contents to read.
/// - Returns: The typed section contents, or `nil` if unavailable.
public func objects<ResultType: NSFetchRequestResult>(
    inSectionAt index: Int,
    of controller: NSFetchedResultsController<ResultType>
) -> [ResultType]? {
    guard let sections = controller.sections else { return nil }
    precondition(
        sections.indices.contains(index),
        "Fetched-results section index \(index) is out of bounds for \(sections.count) sections."
    )
    guard let objects = sections[index].objects else { return nil }
    guard let typedObjects = objects as? [ResultType] else {
        preconditionFailure(
            "Core Data section \(index) contains objects incompatible with \(ResultType.self). "
                + "Check the fetch request's entity and the model's managed object classes."
        )
    }
    return typedObjects
}
