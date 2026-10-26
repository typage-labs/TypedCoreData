import CoreData

/// A source-request configuration that cannot be used for typed ID fetching.
public enum FetchObjectIDsError: Error, Equatable, Sendable {
    /// The source request is not configured to return managed objects.
    ///
    /// A request's generic parameter does not prevent callers from changing its
    /// native result mode. Only `.managedObjectResultType` is accepted.
    case unsupportedResultType(NSFetchRequestResultType)
}

public extension NSManagedObjectContext {
    /// Fetches and validates typed IDs using a copy of a managed-object request.
    ///
    /// The source must use `.managedObjectResultType`. This method copies the
    /// native request, changes only the copy's result mode to
    /// `.managedObjectIDResultType`, and executes it with Core Data. The source
    /// request is not modified. Native fetch errors propagate unchanged.
    ///
    /// Every returned ID is checked with ``ManagedID/init(validating:)`` before
    /// the array is returned. This is a guarantee about returned IDs, not a
    /// validation of the request's entity binding: an empty result may succeed
    /// even when the configured entity is incompatible with `Entity`.
    ///
    /// Native ID-result semantics apply to preserved options, including pending
    /// changes, sorting, pagination, and property values. Results may contain
    /// temporary IDs and need not have the ordering of a managed-object fetch.
    /// This method does not save, obtain permanent IDs, or resolve objects.
    ///
    /// Call on this context's queue and do not mutate the request concurrently.
    ///
    /// - Parameter request: A native request configured to return managed objects.
    /// - Returns: IDs whose declared entity classes are compatible with `Entity`.
    /// - Throws: ``FetchObjectIDsError/unsupportedResultType(_:)`` for another
    ///   source result mode, Core Data's fetch error, or a
    ///   ``ManagedIDValidationError`` if any returned ID is incompatible.
    /// - Precondition: Native copying must return an `NSFetchRequest`. A different
    ///   result class is a runtime invariant violation and fails a precondition.
    func fetchObjectIDs<Entity: NSManagedObject>(
        for request: NSFetchRequest<Entity>
    ) throws -> [ManagedID<Entity>] {
        guard request.resultType == .managedObjectResultType else {
            throw FetchObjectIDsError.unsupportedResultType(request.resultType)
        }
        // Objective-C erases the generic argument. The cast only checks the
        // request class; the result mode and each returned ID are checked below.
        guard let copiedRequest = request.copy() as? NSFetchRequest<NSManagedObjectID> else {
            preconditionFailure("Core Data did not copy the request as an NSFetchRequest.")
        }
        copiedRequest.resultType = .managedObjectIDResultType
        return try fetch(copiedRequest).map { try ManagedID<Entity>(validating: $0) }
    }
}
