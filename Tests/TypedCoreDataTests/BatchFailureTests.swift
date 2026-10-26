import CoreData
import CoreDataExceptionSupport
import Testing
import TypedCoreData

@Suite("Batch failures and native input behavior")
@MainActor
struct BatchFailureTests {
    @Test func deletePropagatesTheNativeReadOnlyStoreError() throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertItem(name: "Unchanged", value: 7)
            try stack.context.save()
            try reopenReadOnly(stack)
            let nativeContext = stack.makeContext()
            let typedContext = stack.makeContext()
            let nativeRequest = NSBatchDeleteRequest(
                fetchRequest: NSFetchRequest<any NSFetchRequestResult>(entityName: "Item")
            )
            let typedRequest = NSBatchDeleteRequest(
                fetchRequest: NSFetchRequest<any NSFetchRequestResult>(entityName: "Item")
            )

            // Upcasting the request selects Apple's original execute overload.
            // SQLite intentionally logs read-only-database errors for these calls.
            let nativeError = try #require(captureBatchError {
                _ = try nativeContext.execute(nativeRequest as NSPersistentStoreRequest)
            })
            let typedError = try #require(captureBatchError {
                let _: NSBatchDeleteResult = try typedContext.execute(typedRequest)
            })
            expectMatchingErrors(typedError, nativeError)

            let reader = stack.makeContext()
            let remaining = try reader.fetch(NSFetchRequest<SQLiteItem>(entityName: "Item"))
            #expect(remaining.count == 1)
            #expect(remaining.first?.name == "Unchanged")
            #expect(remaining.first?.value == 7)
        }
    }

    @Test func updatePropagatesTheNativeReadOnlyStoreError() throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertItem(name: "Unchanged", value: 7)
            try stack.context.save()
            try reopenReadOnly(stack)
            let nativeContext = stack.makeContext()
            let typedContext = stack.makeContext()
            let nativeRequest = NSBatchUpdateRequest(entityName: "Item")
            nativeRequest.propertiesToUpdate = ["value": 99]
            let typedRequest = NSBatchUpdateRequest(entityName: "Item")
            typedRequest.propertiesToUpdate = ["value": 99]

            let nativeError = try #require(captureBatchError {
                _ = try nativeContext.execute(nativeRequest as NSPersistentStoreRequest)
            })
            let typedError = try #require(captureBatchError {
                let _: NSBatchUpdateResult = try typedContext.execute(typedRequest)
            })
            expectMatchingErrors(typedError, nativeError)

            let reader = stack.makeContext()
            let remaining = try reader.fetch(NSFetchRequest<SQLiteItem>(entityName: "Item"))
            #expect(remaining.count == 1)
            #expect(remaining.first?.value == 7)
        }
    }

    @Test func emptyTypedIDsPreserveTheNativeInitializerException() throws {
        let nativeIDs: [NSManagedObjectID] = []
        let typedIDs: [ManagedID<SQLiteItem>] = []
        let nativeException = try #require(TCDCaptureException {
            _ = NSBatchDeleteRequest(objectIDs: nativeIDs)
        })
        let typedException = try #require(TCDCaptureException {
            _ = NSBatchDeleteRequest(objectIDs: typedIDs)
        })

        #expect(nativeException.name == .invalidArgumentException)
        #expect(typedException.name == nativeException.name)
        #expect(typedException.reason == nativeException.reason)
    }

    @Test func commonSwiftTypeDoesNotMakeUnrelatedEntitiesCompatible() throws {
        try withSQLiteTestStack { stack in
            // Erasing both references to NSManagedObject produces the same
            // generic ID type, despite their unrelated Core Data entity roots.
            let first: NSManagedObject = stack.insertItem()
            let second: NSManagedObject = stack.insertOther()
            try stack.context.save()
            let nativeIDs = [first.objectID, second.objectID]
            let typedIDs: [ManagedID<NSManagedObject>] = [first.managedID, second.managedID]
            #expect(first.entity !== second.entity)

            let nativeException = try #require(TCDCaptureException {
                _ = NSBatchDeleteRequest(objectIDs: nativeIDs)
            })
            let typedException = try #require(TCDCaptureException {
                _ = NSBatchDeleteRequest(objectIDs: typedIDs)
            })
            #expect(nativeException.name == .invalidArgumentException)
            #expect(typedException.name == nativeException.name)
            #expect(typedException.reason == nativeException.reason)

            let reader = stack.makeContext()
            #expect(try reader.count(for: NSFetchRequest<SQLiteItem>(entityName: "Item")) == 1)
            #expect(try reader.count(for: NSFetchRequest<SQLiteOther>(entityName: "Other")) == 1)
        }
    }

}

@MainActor
private func reopenReadOnly(_ stack: SQLiteTestStack) throws {
    stack.context.reset()
    let store = try #require(stack.coordinator.persistentStores.first)
    try stack.coordinator.remove(store)
    try stack.coordinator.addPersistentStore(
        ofType: NSSQLiteStoreType,
        configurationName: nil,
        at: stack.storeURL,
        options: [NSReadOnlyPersistentStoreOption: true]
    )
}

private func captureBatchError(_ operation: () throws -> Void) -> NSError? {
    do {
        try operation()
        return nil
    } catch {
        return error as NSError
    }
}

private func expectMatchingErrors(_ typed: NSError, _ native: NSError) {
    #expect(typed.domain == native.domain)
    #expect(typed.code == native.code)
    #expect(NSDictionary(dictionary: typed.userInfo).isEqual(to: native.userInfo))
}
