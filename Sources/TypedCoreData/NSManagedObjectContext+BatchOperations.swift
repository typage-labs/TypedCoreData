import CoreData

public extension NSManagedObjectContext {
    /// Executes a batch-delete request and returns its native concrete result.
    ///
    /// This overload forwards to Core Data's `execute(_:)`, preserving its
    /// errors, result object, and payload. `NSBatchDeleteResult.result` remains
    /// `Any?`; interpret it according to the result's `resultType`.
    ///
    /// Call on this context's queue. Batch deletion operates on the persistent
    /// store and retains Core Data's store-support and validation requirements.
    /// This overload does not save pending context changes or merge the deletion
    /// into registered objects. Coordinate affected contexts using native APIs.
    ///
    /// - Parameter request: The batch-delete request to execute.
    /// - Returns: The result returned by Core Data, without payload conversion.
    /// - Throws: The error thrown by Core Data's native method.
    /// - Precondition: Core Data must return an `NSBatchDeleteResult`. A different
    ///   result class is a runtime invariant violation and fails a precondition.
    func execute(_ request: NSBatchDeleteRequest) throws -> NSBatchDeleteResult {
        // The upcast selects the native overload rather than recursing here.
        let result = try execute(request as NSPersistentStoreRequest)
        guard let deleteResult = result as? NSBatchDeleteResult else {
            preconditionFailure(
                "Core Data returned \(type(of: result)) for NSBatchDeleteRequest; "
                    + "expected NSBatchDeleteResult."
            )
        }
        return deleteResult
    }

    /// Executes a batch-update request and returns its native concrete result.
    ///
    /// This overload forwards to Core Data's `execute(_:)`, preserving its
    /// errors, result object, and payload. `NSBatchUpdateResult.result` remains
    /// `Any?`; interpret it according to the result's `resultType`.
    ///
    /// Call on this context's queue. Batch updates operate on the persistent
    /// store and retain Core Data's store-support and validation requirements.
    /// This overload does not save pending context changes or merge the update
    /// into registered objects. Coordinate affected contexts using native APIs.
    ///
    /// - Parameter request: The batch-update request to execute.
    /// - Returns: The result returned by Core Data, without payload conversion.
    /// - Throws: The error thrown by Core Data's native method.
    /// - Precondition: Core Data must return an `NSBatchUpdateResult`. A different
    ///   result class is a runtime invariant violation and fails a precondition.
    func execute(_ request: NSBatchUpdateRequest) throws -> NSBatchUpdateResult {
        // The upcast selects the native overload rather than recursing here.
        let result = try execute(request as NSPersistentStoreRequest)
        guard let updateResult = result as? NSBatchUpdateResult else {
            preconditionFailure(
                "Core Data returned \(type(of: result)) for NSBatchUpdateRequest; "
                    + "expected NSBatchUpdateResult."
            )
        }
        return updateResult
    }
}
