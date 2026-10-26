import CoreData

@objc(TypedCoreDataTestItem)
class TestItem: NSManagedObject {
    @NSManaged var name: String?
}

/// Test-only, nonisolated entry point: the context is created here rather than
/// transferred from MainActor. Only the native Sendable coordinator, the
/// Sendable operation, and its Sendable result cross that actor boundary.
@available(macOS 12, iOS 15, *)
func withPrivateTestContext<Snapshot: Sendable>(
    coordinator: NSPersistentStoreCoordinator,
    _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Snapshot
) async throws -> Snapshot {
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    // Do not require context captures to be Sendable. Older SDKs accept an
    // ordinary closure here; this function gives it no actor isolation to inherit.
    return try await context.perform {
        // Complete private-queue cleanup before the fixture owner resumes.
        defer { context.reset() }
        return try operation(context)
    }
}

@objc(TypedCoreDataTestSpecialItem)
final class TestSpecialItem: TestItem {
    @NSManaged var detail: String?
}

/// Each test owns a real, isolated in-memory Core Data store.
@MainActor
final class TestStack {
    let coordinator: NSPersistentStoreCoordinator
    let context: NSManagedObjectContext
    private let itemEntity: NSEntityDescription
    private let specialItemEntity: NSEntityDescription

    init() throws {
        let item = NSEntityDescription()
        item.name = "Item"
        item.managedObjectClassName = NSStringFromClass(TestItem.self)
        item.properties = [Self.stringAttribute(named: "name")]

        let special = NSEntityDescription()
        special.name = "SpecialItem"
        special.managedObjectClassName = NSStringFromClass(TestSpecialItem.self)
        special.properties = [Self.stringAttribute(named: "detail")]
        item.subentities = [special]

        let model = NSManagedObjectModel()
        model.entities = [item, special]
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil
        )
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        itemEntity = item
        specialItemEntity = special
    }

    func makeContext(
        concurrencyType: NSManagedObjectContextConcurrencyType = .mainQueueConcurrencyType
    ) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: concurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    func insertItem(name: String? = nil) -> TestItem {
        let item = TestItem(entity: itemEntity, insertInto: context)
        item.name = name
        return item
    }

    func insertSpecialItem() -> TestSpecialItem {
        TestSpecialItem(entity: specialItemEntity, insertInto: context)
    }

    private static func stringAttribute(named name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true
        return attribute
    }
}
