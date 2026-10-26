import CoreData

public extension NSManagedObjectContext {
    /// Resolves an identifier using Core Data's `existingObject(with:)`.
    ///
    /// Core Data may perform I/O. Its errors propagate unchanged, and its
    /// handling of already registered objects, faults, and pending deletions
    /// is preserved. This method is not an independent store-existence check.
    ///
    /// Call on this context's queue, using an ID valid for the context's store.
    /// The model's class mapping must produce an instance of `Entity` or a
    /// subclass; a mismatch is a programmer error and fails a precondition.
    ///
    /// - Parameter id: The typed identifier to resolve.
    /// - Returns: The managed object in this context.
    /// - Throws: The error thrown by Core Data's native method.
    func existingObject<Entity: NSManagedObject>(
        with id: ManagedID<Entity>
    ) throws -> Entity {
        checkedManagedObject(try existingObject(with: id.objectID), as: Entity.self)
    }

    /// Returns a registered object or creates a fault using Core Data's
    /// `object(with:)`.
    ///
    /// This method does not perform I/O or verify that an object exists in the
    /// store. Accessing a fault for a missing object retains Core Data's native
    /// inaccessible-fault behavior, which may raise an Objective-C exception.
    ///
    /// Call on this context's queue, using an ID valid for the context's store.
    /// The model's class mapping must produce an instance of `Entity` or a
    /// subclass; a mismatch is a programmer error and fails a precondition.
    ///
    /// - Parameter id: The typed identifier to resolve.
    /// - Returns: The managed object or fault in this context.
    func object<Entity: NSManagedObject>(
        with id: ManagedID<Entity>
    ) -> Entity {
        checkedManagedObject(object(with: id.objectID), as: Entity.self)
    }

    /// Returns an already registered object using Core Data's
    /// `registeredObject(for:)`, without fetching or creating a fault.
    ///
    /// Call on this context's queue. The model's class mapping must produce an
    /// instance of `Entity` or a subclass; a mismatch is a programmer error and
    /// fails a precondition rather than being reported as an unregistered ID.
    /// Pending deletions retain Core Data's native registration behavior.
    ///
    /// - Parameter id: The typed identifier to look up.
    /// - Returns: The registered managed object, or `nil` if none is registered.
    func registeredObject<Entity: NSManagedObject>(
        for id: ManagedID<Entity>
    ) -> Entity? {
        guard let object = registeredObject(for: id.objectID) else {
            return nil
        }
        return checkedManagedObject(object, as: Entity.self)
    }
}

// Core Data's runtime model is outside Swift's type system. Check the class
// invariant without masking native errors or turning a mismatch into nil.
private func checkedManagedObject<Entity: NSManagedObject>(
    _ object: NSManagedObject,
    as entityType: Entity.Type
) -> Entity {
    guard let entity = object as? Entity else {
        preconditionFailure(
            "Core Data resolved \(type(of: object)); expected \(entityType). "
                + "Check the model's managed object classes and context/store compatibility."
        )
    }
    return entity
}
