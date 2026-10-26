import CoreData

/// A Core Data object identifier that preserves its managed object's Swift type.
///
/// Obtain an identifier from ``ManagedIdentifiable/managedID`` or validate a
/// native ID with ``init(validating:)``. The identifier stores the current
/// `NSManagedObjectID`; it does not retain the managed object
/// or its context, verify that a stored object exists, or make the object safe
/// to access from another queue.
///
/// Equality and hashing use the underlying object ID. A temporary identifier is
/// a snapshot: it does not change when the object later obtains a permanent ID.
/// Obtain a fresh identifier after saving or obtaining permanent IDs.
public struct ManagedID<Entity: NSManagedObject>: Hashable, Sendable {
    /// The native identifier, available for interoperability with Core Data.
    public let objectID: NSManagedObjectID

    fileprivate init(_ objectID: NSManagedObjectID) {
        self.objectID = objectID
    }

    /// Creates a typed identifier after checking its entity's declared class.
    ///
    /// The entity's configured Objective-C runtime class must resolve to
    /// `Entity` or a subclass. Entity names are not inferred from Swift class
    /// names, and multiple entities may share one compatible class.
    ///
    /// This check reads model metadata without fetching or materializing an
    /// object. It does not verify existence, permanence, or compatibility with
    /// a destination context or store. Deleted and temporary IDs can pass this
    /// check; their native lifecycle restrictions still apply.
    ///
    /// Follow Core Data's model and context access rules when reading metadata.
    /// ID sendability does not authorize concurrent mutation of its model.
    ///
    /// - Parameter objectID: The native identifier whose declared class to check.
    /// - Throws: ``ManagedIDValidationError`` if the class name is missing,
    ///   cannot be resolved, or is incompatible with `Entity`.
    public init(validating objectID: NSManagedObjectID) throws {
        guard let className = objectID.entity.managedObjectClassName,
              !className.isEmpty else {
            throw ManagedIDValidationError.missingClassName(entityName: objectID.entity.name)
        }
        guard let runtimeClass = NSClassFromString(className) else {
            throw ManagedIDValidationError.unresolvableClassName(className)
        }
        guard runtimeClass is Entity.Type else {
            throw ManagedIDValidationError.incompatibleClass(
                expected: NSStringFromClass(Entity.self),
                actual: NSStringFromClass(runtimeClass)
            )
        }
        self.init(objectID)
    }
}

/// A failure to validate an object's declared class for a typed identifier.
///
/// These errors describe model metadata, not object existence or store access.
/// Names are stored as strings so the error can cross concurrency boundaries
/// without retaining a model, entity description, or managed object.
public enum ManagedIDValidationError: Error, Equatable, Sendable {
    /// The entity has no configured class name, or its class name is empty.
    case missingClassName(entityName: String?)

    /// The configured Objective-C runtime class name could not be resolved.
    case unresolvableClassName(String)

    /// The resolved class is neither the expected class nor a subclass of it.
    case incompatibleClass(expected: String, actual: String)
}

/// A managed object that can expose an identifier preserving its Swift type.
///
/// `NSManagedObject` conforms, so its subclasses need no additional conformance.
public protocol ManagedIdentifiable: NSManagedObject {
    /// The object's current native Core Data identifier.
    var objectID: NSManagedObjectID { get }
}

public extension ManagedIdentifiable {
    /// A typed snapshot of the object's current identifier.
    ///
    /// Read this property on the object's context queue. The resulting value is
    /// sendable, but temporary IDs cannot resolve unsaved objects in another
    /// context. Obtain permanent IDs and save before resolving newly inserted
    /// objects in another context connected to the same persistent store.
    ///
    /// The generic type follows the reference's static Swift type. Reading this
    /// property through an `NSManagedObject` reference produces
    /// `ManagedID<NSManagedObject>`.
    var managedID: ManagedID<Self> {
        ManagedID(objectID)
    }
}

extension NSManagedObject: ManagedIdentifiable {}
