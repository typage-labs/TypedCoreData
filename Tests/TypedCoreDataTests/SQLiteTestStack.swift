import CoreData
import Foundation
import Testing

@objc(TypedCoreDataSQLiteItem)
class SQLiteItem: NSManagedObject {
    @NSManaged var name: String?
    @NSManaged var value: Int64
}

@objc(TypedCoreDataSQLiteSpecialItem)
final class SQLiteSpecialItem: SQLiteItem {
    @NSManaged var detail: String?
}

@objc(TypedCoreDataSQLiteOther)
final class SQLiteOther: NSManagedObject {
    @NSManaged var name: String?
}

/// A real SQLite store in an isolated directory, removed after each test.
@MainActor
final class SQLiteTestStack {
    let coordinator: NSPersistentStoreCoordinator
    let context: NSManagedObjectContext
    let storeURL: URL
    private let directoryURL: URL
    private let itemEntity: NSEntityDescription
    private let specialItemEntity: NSEntityDescription
    private let otherEntity: NSEntityDescription
    private var contexts: [NSManagedObjectContext]
    private var cleanedUp = false

    init() throws {
        let item = NSEntityDescription()
        item.name = "Item"
        item.managedObjectClassName = NSStringFromClass(SQLiteItem.self)
        let value = NSAttributeDescription()
        value.name = "value"
        value.attributeType = .integer64AttributeType
        value.defaultValue = 0
        item.properties = [Self.stringAttribute(named: "name"), value]

        let special = NSEntityDescription()
        special.name = "SpecialItem"
        special.managedObjectClassName = NSStringFromClass(SQLiteSpecialItem.self)
        special.properties = [Self.stringAttribute(named: "detail")]
        item.subentities = [special]

        let other = NSEntityDescription()
        other.name = "Other"
        other.managedObjectClassName = NSStringFromClass(SQLiteOther.self)
        other.properties = [Self.stringAttribute(named: "name")]

        let model = NSManagedObjectModel()
        model.entities = [item, special, other]
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypedCoreData-SQLite-\(UUID().uuidString)", isDirectory: true)
        storeURL = directoryURL.appendingPathComponent("Store.sqlite")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        do {
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL
            )
        } catch {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                Issue.record(error, "Failed to remove a SQLite fixture directory after initialization failed")
            }
            throw error
        }
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        contexts = [context]
        itemEntity = item
        specialItemEntity = special
        otherEntity = other
    }

    func makeContext() -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        contexts.append(context)
        return context
    }

    func insertItem(name: String = "", value: Int64 = 0) -> SQLiteItem {
        let item = SQLiteItem(entity: itemEntity, insertInto: context)
        item.name = name
        item.value = value
        return item
    }

    func insertSpecialItem(name: String = "", value: Int64 = 0) -> SQLiteSpecialItem {
        let item = SQLiteSpecialItem(entity: specialItemEntity, insertInto: context)
        item.name = name
        item.value = value
        return item
    }

    func insertOther(name: String = "") -> SQLiteOther {
        let other = SQLiteOther(entity: otherEntity, insertInto: context)
        other.name = name
        return other
    }

    func cleanup() throws {
        guard !cleanedUp else { return }
        for context in contexts {
            context.reset()
        }
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
        try FileManager.default.removeItem(at: directoryURL)
        cleanedUp = true
    }

    private static func stringAttribute(named name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true
        return attribute
    }
}

/// Cleanup runs even when an assertion throws; cleanup errors fail the test.
@MainActor
func withSQLiteTestStack<Result>(
    _ operation: (SQLiteTestStack) throws -> Result
) throws -> Result {
    let stack = try SQLiteTestStack()
    defer {
        do {
            try stack.cleanup()
        } catch {
            Issue.record(error, "Failed to clean up the SQLite Core Data test store")
        }
    }
    return try operation(stack)
}
