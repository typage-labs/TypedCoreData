import CoreData

public extension NSBatchDeleteRequest {
    /// Creates a native batch-delete request from typed managed object IDs.
    ///
    /// The underlying IDs are forwarded unchanged to Core Data's
    /// `init(objectIDs:)`. Its validation, result mode, and behavior are
    /// preserved, including any Objective-C exceptions for invalid input.
    ///
    /// Supply a nonempty array of permanent IDs for objects saved in a store
    /// supported by batch deletion and accessible to the executing context.
    /// Obtaining a permanent ID alone does not save an insertion. All IDs must satisfy
    /// Core Data's requirement that they belong to the same entity.
    ///
    /// A common Swift type does not prove a common Core Data entity: an array
    /// of superclass-typed IDs may contain different subentities, and multiple
    /// entities may share a Swift class. This initializer adds no validation
    /// beyond the native initializer and does not change context synchronization.
    ///
    /// - Parameter objectIDs: A nonempty array whose native IDs meet Core Data's
    ///   batch-delete requirements.
    convenience init<Entity: NSManagedObject>(objectIDs: [ManagedID<Entity>]) {
        self.init(objectIDs: objectIDs.map(\.objectID))
    }
}
