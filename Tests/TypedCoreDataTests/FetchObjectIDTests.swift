import CoreData
import SQLite3
import Testing
import TypedCoreData

@Suite("Typed object-ID fetching")
@MainActor
struct FetchObjectIDTests {
    @Test(arguments: [true, false])
    func copiedSQLiteRequestPreservesOptionsAndLeavesSourceUnchanged(
        includesPropertyValues: Bool
    ) throws {
        try withSQLiteTestStack { stack in
            let primaryStore = try #require(stack.coordinator.persistentStores.first)
            let secondStore = try stack.coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: stack.storeURL.deletingLastPathComponent().appendingPathComponent("Second.sqlite")
            )
            var items: [SQLiteItem] = []
            for value in [Int64(0), 10, 20, 30, 40] {
                let item = stack.insertItem(name: "Item-\(value)", value: value)
                stack.context.assign(item, to: primaryStore)
                items.append(item)
            }
            let special = stack.insertSpecialItem(name: "Excluded subentity", value: 100)
            stack.context.assign(special, to: primaryStore)
            let otherStoreItem = stack.insertItem(name: "Excluded store", value: 200)
            stack.context.assign(otherStoreItem, to: secondStore)
            try stack.context.save()
            let savedIDs = Dictionary(uniqueKeysWithValues: items.map { ($0.value, $0.objectID) })
            let pending = stack.insertItem(name: "Excluded pending insertion", value: 99)
            stack.context.assign(pending, to: primaryStore)

            let source = NSFetchRequest<SQLiteItem>()
            source.entity = stack.coordinator.managedObjectModel.entitiesByName["Item"]
            let predicate = NSPredicate(format: "value >= 10")
            let sort = NSSortDescriptor(key: "value", ascending: false)
            source.predicate = predicate
            source.sortDescriptors = [sort]
            source.fetchLimit = 2
            source.fetchOffset = 1
            source.fetchBatchSize = 1
            source.includesPendingChanges = false
            source.includesSubentities = false
            source.includesPropertyValues = includesPropertyValues
            source.returnsObjectsAsFaults = false
            source.shouldRefreshRefetchedObjects = true
            source.returnsDistinctResults = true
            source.propertiesToFetch = ["name", "value"]
            source.relationshipKeyPathsForPrefetching = []
            source.affectedStores = [primaryStore]

            let native = try nativeIDRequest(copying: source)
            let reader = stack.makeContext()
            let expected = try reader.fetch(native)
            let typed: [ManagedID<SQLiteItem>] = try reader.fetchObjectIDs(for: source)

            #expect(typed.map(\.objectID) == expected)
            #expect(typed.count == 2)
            if includesPropertyValues {
                #expect(typed.map(\.objectID) == [savedIDs[30], savedIDs[20]].compactMap { $0 })
            }
            #expect(reader.registeredObjects.isEmpty)
            #expect(source.resultType == .managedObjectResultType)
            #expect(source.entity === stack.coordinator.managedObjectModel.entitiesByName["Item"])
            #expect(source.predicate === predicate)
            #expect(source.sortDescriptors == [sort])
            #expect(source.fetchLimit == 2)
            #expect(source.fetchOffset == 1)
            #expect(source.fetchBatchSize == 1)
            #expect(!source.includesPendingChanges)
            #expect(!source.includesSubentities)
            #expect(source.includesPropertyValues == includesPropertyValues)
            #expect(!source.returnsObjectsAsFaults)
            #expect(source.shouldRefreshRefetchedObjects)
            #expect(source.returnsDistinctResults)
            // Core Data may normalize property-name strings to model descriptors.
            #expect(source.propertiesToFetch?.compactMap {
                ($0 as? NSPropertyDescription)?.name ?? ($0 as? String)
            } == ["name", "value"])
            #expect(source.relationshipKeyPathsForPrefetching == [])
            #expect(source.affectedStores == [primaryStore])
            #expect(pending.objectID.isTemporaryID)
            #expect(stack.context.hasChanges)
        }
    }

    @Test func SQLitePendingChangesRetainNativeIDSemanticsWithoutSavingOrPromotion() throws {
        try withSQLiteTestStack { stack in
            let removed = stack.insertItem(name: "Removed", value: 1)
            let movedIn = stack.insertItem(name: "Moved in", value: -1)
            let movedOut = stack.insertItem(name: "Moved out", value: 2)
            let unchanged = stack.insertItem(name: "Unchanged", value: 3)
            try stack.context.save()
            let storedIDs = [removed.objectID, movedOut.objectID, unchanged.objectID]

            stack.context.delete(removed)
            movedIn.value = 4
            movedOut.value = -2
            let temporary = stack.insertItem(name: "Temporary", value: 5)
            let permanent = stack.insertItem(name: "Unsaved permanent", value: 6)
            try stack.context.obtainPermanentIDs(for: [permanent])
            let capturedTemporaryID = temporary.objectID
            let capturedPermanentID = permanent.objectID
            stack.context.processPendingChanges()

            let source = NSFetchRequest<SQLiteItem>(entityName: "Item")
            source.predicate = NSPredicate(format: "value >= 0")
            source.sortDescriptors = [NSSortDescriptor(key: "value", ascending: true)]
            for includesPendingChanges in [false, true] {
                source.includesPendingChanges = includesPendingChanges
                let native = try nativeIDRequest(copying: source)
                let expected = try stack.context.fetch(native)
                let typed = try stack.context.fetchObjectIDs(for: source)
                // Compare membership with native ID mode. The pending-object
                // merge does not promise stable ordering between executions.
                #expect(Set(typed.map(\.objectID)) == Set(expected))
                if !includesPendingChanges {
                    #expect(typed.map(\.objectID) == expected)
                }
                let expectedMembership = includesPendingChanges
                    ? [movedIn.objectID, unchanged.objectID, capturedTemporaryID, capturedPermanentID]
                    : storedIDs
                #expect(Set(typed.map(\.objectID)) == Set(expectedMembership))
                #expect(source.resultType == .managedObjectResultType)
            }
            #expect(temporary.objectID == capturedTemporaryID)
            #expect(temporary.objectID.isTemporaryID)
            #expect(permanent.objectID == capturedPermanentID)
            #expect(!permanent.objectID.isTemporaryID)
            #expect(stack.context.insertedObjects.contains(temporary))
            #expect(stack.context.insertedObjects.contains(permanent))
            #expect(stack.context.deletedObjects.contains(removed))
            #expect(stack.context.hasChanges)
            let reader = stack.makeContext()
            #expect(try reader.count(for: NSFetchRequest<SQLiteItem>(entityName: "Item")) == 4)
        }
    }

    @Test func inMemoryFetchAcceptsCompatibleInheritanceAndTemporaryIDs() throws {
        let stack = try TestStack()
        let base = stack.insertItem(name: "Base")
        let special = stack.insertSpecialItem()
        special.name = "Special"
        try stack.context.save()
        let pending = stack.insertItem(name: "Pending")
        stack.context.processPendingChanges()

        // An unresolved entity-name request is resolved natively in the context.
        let source = NSFetchRequest<TestItem>(entityName: "Item")
        source.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let expected = try stack.context.fetch(nativeIDRequest(copying: source))
        let typed: [ManagedID<TestItem>] = try stack.context.fetchObjectIDs(for: source)
        #expect(Set(typed.map(\.objectID)) == Set(expected))
        #expect(Set(typed.map(\.objectID)) == Set([base.objectID, special.objectID, pending.objectID]))
        #expect(pending.objectID.isTemporaryID)
        #expect(stack.context.hasChanges)

        source.includesSubentities = false
        let baseOnly = try stack.context.fetchObjectIDs(for: source)
        #expect(Set(baseOnly.map(\.objectID)) == Set([base.objectID, pending.objectID]))
        let childRequest = NSFetchRequest<TestSpecialItem>(entityName: "SpecialItem")
        let children: [ManagedID<TestSpecialItem>] = try stack.context.fetchObjectIDs(for: childRequest)
        #expect(children == [special.managedID])
    }

    @Test(arguments: [
        NSFetchRequestResultType.managedObjectIDResultType,
        .dictionaryResultType,
        .countResultType,
    ])
    func rejectsMutatedSourceResultModes(_ mode: NSFetchRequestResultType) throws {
        let stack = try TestStack()
        let request = NSFetchRequest<TestItem>(entityName: "Item")
        request.resultType = mode

        #expect(throws: FetchObjectIDsError.unsupportedResultType(mode)) {
            try stack.context.fetchObjectIDs(for: request)
        }
        #expect(request.resultType == mode)
        #expect(stack.context.registeredObjects.isEmpty)
    }

    @Test func rejectsIDsFromAnUnrelatedRuntimeEntity() throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertOther(name: "Other")
            try stack.context.save()
            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            request.entity = stack.coordinator.managedObjectModel.entitiesByName["Other"]
            let reader = stack.makeContext()

            #expect(throws: ManagedIDValidationError.incompatibleClass(
                expected: NSStringFromClass(SQLiteItem.self),
                actual: NSStringFromClass(SQLiteOther.self)
            )) {
                try reader.fetchObjectIDs(for: request)
            }
            #expect(request.resultType == .managedObjectResultType)
            #expect(request.entity?.name == "Other")
            #expect(reader.registeredObjects.isEmpty)
        }
    }

    @Test func emptyMismatchedRequestDoesNotClaimBindingValidation() throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertOther(name: "Filtered out")
            try stack.context.save()
            let request = NSFetchRequest<SQLiteItem>(entityName: "Other")
            request.predicate = NSPredicate(value: false)

            let ids: [ManagedID<SQLiteItem>] = try stack.context.fetchObjectIDs(for: request)
            #expect(ids.isEmpty)
            #expect(request.resultType == .managedObjectResultType)
        }
    }

    @Test func incompatibleDescendantRejectsTheEntireResultArray() throws {
        try withIncompatibleIDDescendant { context, root, child in
            let valid = SQLiteItem(entity: root, insertInto: context)
            valid.name = "A valid first result"
            let incompatible = SQLiteOther(entity: child, insertInto: context)
            incompatible.name = "Z incompatible descendant"
            try context.save()
            let source = NSFetchRequest<SQLiteItem>()
            source.entity = root
            source.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            let native = try context.fetch(nativeIDRequest(copying: source))
            #expect(native == [valid.objectID, incompatible.objectID])

            var returned: [ManagedID<SQLiteItem>]?
            #expect(throws: ManagedIDValidationError.incompatibleClass(
                expected: NSStringFromClass(SQLiteItem.self),
                actual: NSStringFromClass(SQLiteOther.self)
            )) {
                returned = try context.fetchObjectIDs(for: source)
            }
            #expect(returned == nil)
            #expect(source.resultType == .managedObjectResultType)

            source.includesSubentities = false
            #expect(try context.fetchObjectIDs(for: source) == [valid.managedID])
        }
    }

    @Test func propagatesANativeSQLiteFetchErrorUnchanged() throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertItem(name: "Disposable fixture")
            try stack.context.save()
            stack.context.reset()
            // Corrupt only this test's disposable store to cause a real native
            // read error. No application database or shared fixture is touched.
            try removeFixtureItemTable(at: stack.storeURL)
            let source = NSFetchRequest<SQLiteItem>(entityName: "Item")
            source.includesPendingChanges = false
            let native = try nativeIDRequest(copying: source)
            let nativeContext = stack.makeContext()
            let typedContext = stack.makeContext()
            let nativeError = try #require(fetchError {
                _ = try nativeContext.fetch(native)
            })
            let typedError = try #require(fetchError {
                _ = try typedContext.fetchObjectIDs(for: source)
            })

            #expect(nativeError.domain == NSCocoaErrorDomain)
            #expect(nativeError.userInfo[NSSQLiteErrorDomain] as? Int == Int(SQLITE_ERROR))
            #expect(typedError.domain == nativeError.domain)
            #expect(typedError.code == nativeError.code)
            #expect(NSDictionary(dictionary: typedError.userInfo).isEqual(to: nativeError.userInfo))
            #expect(source.resultType == .managedObjectResultType)
        }
    }
}

private func nativeIDRequest<Entity: NSManagedObject>(
    copying source: NSFetchRequest<Entity>
) throws -> NSFetchRequest<NSManagedObjectID> {
    let copy = try #require(source.copy() as? NSFetchRequest<NSManagedObjectID>)
    copy.resultType = .managedObjectIDResultType
    return copy
}

private func fetchError(_ operation: () throws -> Void) -> NSError? {
    do {
        try operation()
        return nil
    } catch {
        return error as NSError
    }
}

private func removeFixtureItemTable(at url: URL) throws {
    var database: OpaquePointer?
    let opened = sqlite3_open(url.path, &database)
    defer {
        if let database { #expect(sqlite3_close(database) == SQLITE_OK) }
    }
    try #require(opened == SQLITE_OK)
    let connection = try #require(database)
    // ZITEM is the table in this explicit programmatic SQLite fixture. A schema
    // change must fail fixture preparation rather than skip the error assertion.
    let result = sqlite3_exec(connection, "DROP TABLE ZITEM", nil, nil, nil)
    try #require(result == SQLITE_OK)
}

@MainActor
private func withIncompatibleIDDescendant(
    _ operation: (NSManagedObjectContext, NSEntityDescription, NSEntityDescription) throws -> Void
) throws {
    let name = NSAttributeDescription()
    name.name = "name"
    name.attributeType = .stringAttributeType
    name.isOptional = true
    let value = NSAttributeDescription()
    value.name = "value"
    value.attributeType = .integer64AttributeType
    value.defaultValue = 0
    let root = NSEntityDescription()
    root.name = "FetchIDRoot"
    root.managedObjectClassName = NSStringFromClass(SQLiteItem.self)
    root.properties = [name, value]
    let child = NSEntityDescription()
    child.name = "FetchIDUnrelatedChild"
    child.managedObjectClassName = NSStringFromClass(SQLiteOther.self)
    root.subentities = [child]
    let model = NSManagedObjectModel()
    model.entities = [root, child]
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    let store = try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    defer {
        context.reset()
        do { try coordinator.remove(store) }
        catch { Issue.record(error, "Failed to remove the incompatible-inheritance test store") }
    }
    try operation(context, root, child)
}
