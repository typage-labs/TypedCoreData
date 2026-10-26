import CoreData
import Testing
import TypedCoreData

@Suite("Validated managed identifier construction")
@MainActor
struct ManagedIDValidationTests {
    @Test func acceptsAnExplicitClassMappingWithACustomEntityName() throws {
        let stack = try ValidationStack()
        let object = stack.insertRecord()
        let id = try ManagedID<ValidationRecord>(validating: object.objectID)

        #expect(id.objectID === object.objectID)
        #expect(id == object.managedID)
        #expect(id.hashValue == object.managedID.hashValue)
        #expect(id.objectID.entity.name == "LibraryEntry")
        #expect(id.objectID.entity.managedObjectClassName == NSStringFromClass(ValidationRecord.self))
        #expect(id.objectID.entity.name != String(describing: ValidationRecord.self))
    }

    @Test func resolvesTheExactModuleQualifiedClassName() throws {
        let stack = try ValidationStack()
        let object = stack.insertModuleRecord()
        let runtimeName = NSStringFromClass(ModuleValidationRecord.self)
        #expect(runtimeName.contains("."))
        #expect(object.entity.managedObjectClassName == runtimeName)

        let id = try ManagedID<ModuleValidationRecord>(validating: object.objectID)
        #expect(id.objectID === object.objectID)
    }

    @Test func acceptsASubclassAsItsOwnTypeAndAsItsSuperclass() throws {
        let stack = try ValidationStack()
        let object = stack.insertSpecialRecord()

        let childID = try ManagedID<ValidationSpecialRecord>(validating: object.objectID)
        let baseID = try ManagedID<ValidationRecord>(validating: object.objectID)
        let erasedID = try ManagedID<NSManagedObject>(validating: object.objectID)
        #expect(childID.objectID == baseID.objectID)
        #expect(baseID.objectID == erasedID.objectID)
        #expect(childID.objectID.entity.superentity?.name == "LibraryEntry")
    }

    @Test func rejectsASuperclassIDAsASubclass() throws {
        let stack = try ValidationStack()
        let object = stack.insertRecord()

        #expect(throws: ManagedIDValidationError.incompatibleClass(
            expected: NSStringFromClass(ValidationSpecialRecord.self),
            actual: NSStringFromClass(ValidationRecord.self)
        )) {
            try ManagedID<ValidationSpecialRecord>(validating: object.objectID)
        }
    }

    @Test func rejectsAnUnrelatedMappedClass() throws {
        let stack = try ValidationStack()
        let object = stack.insertOtherRecord()

        #expect(throws: ManagedIDValidationError.incompatibleClass(
            expected: NSStringFromClass(ValidationRecord.self),
            actual: NSStringFromClass(ValidationOtherRecord.self)
        )) {
            try ManagedID<ValidationRecord>(validating: object.objectID)
        }
    }

    @Test func reportsAnEmptyDeclaredClassName() {
        // A detached, real Core Data object permits inspecting invalid metadata
        // without mutating a model that is already in use by a coordinator.
        // Assigning nil instead resets this native property to NSManagedObject.
        let entity = NSEntityDescription()
        entity.name = "MissingClassEntity"
        entity.managedObjectClassName = ""
        let object = NSManagedObject(entity: entity, insertInto: nil)
        #expect(object.objectID.isTemporaryID)

        #expect(throws: ManagedIDValidationError.missingClassName(entityName: "MissingClassEntity")) {
            try ManagedID<NSManagedObject>(validating: object.objectID)
        }
    }

    @Test func reportsAnUnresolvableDeclaredClassWithoutGuessing() {
        let entity = NSEntityDescription()
        entity.name = "UnresolvedClassEntity"
        entity.managedObjectClassName = "MissingValidationModule.Record"
        let object = NSManagedObject(entity: entity, insertInto: nil)

        #expect(throws: ManagedIDValidationError.unresolvableClassName("MissingValidationModule.Record")) {
            try ManagedID<NSManagedObject>(validating: object.objectID)
        }
    }

    @Test func acceptsDifferentEntitiesThatShareOneMappedClass() throws {
        let stack = try ValidationStack()
        let primary = stack.insertRecord()
        let archived = stack.insertArchivedRecord()
        let primaryID = try ManagedID<ValidationRecord>(validating: primary.objectID)
        let archivedID = try ManagedID<ValidationRecord>(validating: archived.objectID)

        #expect(primaryID.objectID.entity !== archivedID.objectID.entity)
        #expect(primaryID != archivedID)
        #expect(primaryID.objectID.entity.name == "LibraryEntry")
        #expect(archivedID.objectID.entity.name == "ArchivedLibraryEntry")
    }

    @Test func classValidationDoesNotImplyASpecificModelOrStore() throws {
        let first = try ValidationStack()
        let second = try ValidationStack()
        let firstObject = first.insertRecord()
        let secondObject = second.insertRecord()
        try first.context.save()
        try second.context.save()

        let firstID = try ManagedID<ValidationRecord>(validating: firstObject.objectID)
        let secondID = try ManagedID<ValidationRecord>(validating: secondObject.objectID)
        #expect(firstID.objectID.entity.managedObjectModel !== secondID.objectID.entity.managedObjectModel)
        #expect(firstID.objectID.persistentStore !== secondID.objectID.persistentStore)
        #expect(firstID != secondID)
    }

    @Test func validationDoesNotMaterializeObjects() throws {
        let stack = try ValidationStack()
        let object = stack.insertRecord()
        try stack.context.save()
        let rawID = object.objectID
        stack.context.reset()
        #expect(stack.context.registeredObjects.isEmpty)
        #expect(!stack.context.hasChanges)

        let id = try ManagedID<ValidationRecord>(validating: rawID)
        #expect(id.objectID === rawID)
        #expect(stack.context.registeredObjects.isEmpty)
        #expect(stack.context.registeredObject(for: rawID) == nil)
        #expect(!stack.context.hasChanges)
    }

    @Test func validationDoesNotPromoteOrSaveInsertedObjects() throws {
        let stack = try ValidationStack()
        let object = stack.insertRecord()
        let temporary = try ManagedID<ValidationRecord>(validating: object.objectID)
        #expect(temporary.objectID.isTemporaryID)
        #expect(object.objectID === temporary.objectID)
        #expect(object.isInserted)

        try stack.context.obtainPermanentIDs(for: [object])
        let permanent = try ManagedID<ValidationRecord>(validating: object.objectID)
        #expect(!permanent.objectID.isTemporaryID)
        #expect(temporary.objectID.isTemporaryID)
        #expect(temporary != permanent)
        #expect(object.isInserted)
        #expect(stack.context.hasChanges)
        let reader = stack.makeContext()
        #expect(throws: NSError.self) {
            try reader.existingObject(with: permanent.objectID)
        }
    }

    @Test func validatesADeletedIdentifierReconstructedFromItsURI() throws {
        let stack = try ValidationStack()
        let object = stack.insertRecord()
        try stack.context.save()
        let rawID = object.objectID
        let uri = rawID.uriRepresentation()
        stack.context.delete(object)
        try stack.context.save()
        stack.context.reset()
        let reconstructed = try #require(stack.coordinator.managedObjectID(forURIRepresentation: uri))

        let id = try ManagedID<ValidationRecord>(validating: reconstructed)
        #expect(id.objectID == rawID)
        #expect(stack.context.registeredObjects.isEmpty)
        let reader = stack.makeContext()
        let nativeError = try #require(captureValidationResolutionError {
            _ = try reader.existingObject(with: rawID)
        })
        let typedError = try #require(captureValidationResolutionError {
            _ = try stack.makeContext().existingObject(with: id)
        })
        #expect(typedError.domain == nativeError.domain)
        #expect(typedError.code == nativeError.code)
    }

    @Test func validationErrorsHaveValueEqualityAndAreSendable() {
        let missing = ManagedIDValidationError.missingClassName(entityName: nil)
        let unresolved = ManagedIDValidationError.unresolvableClassName("Missing.Record")
        let mismatch = ManagedIDValidationError.incompatibleClass(expected: "First", actual: "Second")
        requireValidationSendable(missing)
        requireValidationSendable(unresolved)
        requireValidationSendable(mismatch)
        #expect(missing == .missingClassName(entityName: nil))
        #expect(missing != .missingClassName(entityName: "Entry"))
        #expect(unresolved == .unresolvableClassName("Missing.Record"))
        #expect(mismatch == .incompatibleClass(expected: "First", actual: "Second"))
        #expect(mismatch != .incompatibleClass(expected: "Second", actual: "First"))
    }
}

private func requireValidationSendable<Value: Sendable>(_: Value) {}

private func captureValidationResolutionError(_ operation: () throws -> Void) -> NSError? {
    do {
        try operation()
        return nil
    } catch {
        return error as NSError
    }
}

@objc(TypedCoreDataValidationRecord)
private class ValidationRecord: NSManagedObject {
    @NSManaged var name: String?
}

@objc(TypedCoreDataValidationSpecialRecord)
private final class ValidationSpecialRecord: ValidationRecord {}

@objc(TypedCoreDataValidationOtherRecord)
private final class ValidationOtherRecord: NSManagedObject {}

// No @objc name: the model deliberately stores its module-qualified runtime name.
final class ModuleValidationRecord: NSManagedObject {}

@MainActor
private final class ValidationStack {
    let coordinator: NSPersistentStoreCoordinator
    let context: NSManagedObjectContext
    private let recordEntity: NSEntityDescription
    private let specialEntity: NSEntityDescription
    private let archivedEntity: NSEntityDescription
    private let otherEntity: NSEntityDescription
    private let moduleEntity: NSEntityDescription

    init() throws {
        func entity(_ name: String, _ objectClass: NSManagedObject.Type) -> NSEntityDescription {
            let entity = NSEntityDescription()
            entity.name = name
            entity.managedObjectClassName = NSStringFromClass(objectClass)
            return entity
        }
        func nameAttribute() -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = "name"
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = true
            return attribute
        }
        let record = entity("LibraryEntry", ValidationRecord.self)
        record.properties = [nameAttribute()]
        let special = entity("SpecialLibraryEntry", ValidationSpecialRecord.self)
        record.subentities = [special]
        let archived = entity("ArchivedLibraryEntry", ValidationRecord.self)
        archived.properties = [nameAttribute()]
        let other = entity("Company", ValidationOtherRecord.self)
        let module = entity("ModuleRecordEntity", ModuleValidationRecord.self)
        let model = NSManagedObjectModel()
        model.entities = [record, special, archived, other, module]
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        recordEntity = record
        specialEntity = special
        archivedEntity = archived
        otherEntity = other
        moduleEntity = module
    }

    func insertRecord() -> ValidationRecord {
        ValidationRecord(entity: recordEntity, insertInto: context)
    }

    func insertSpecialRecord() -> ValidationSpecialRecord {
        ValidationSpecialRecord(entity: specialEntity, insertInto: context)
    }

    func insertArchivedRecord() -> ValidationRecord {
        ValidationRecord(entity: archivedEntity, insertInto: context)
    }

    func insertOtherRecord() -> ValidationOtherRecord {
        ValidationOtherRecord(entity: otherEntity, insertInto: context)
    }

    func insertModuleRecord() -> ModuleValidationRecord {
        ModuleValidationRecord(entity: moduleEntity, insertInto: context)
    }

    func makeContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}
