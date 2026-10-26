import CoreData
import Testing
import TypedCoreData

private enum BatchPayload: CaseIterable, Sendable {
    case status, count, objectIDs

    var deleteResultType: NSBatchDeleteRequestResultType {
        switch self {
        case .status: .resultTypeStatusOnly
        case .count: .resultTypeCount
        case .objectIDs: .resultTypeObjectIDs
        }
    }

    var updateResultType: NSBatchUpdateRequestResultType {
        switch self {
        case .status: .statusOnlyResultType
        case .count: .updatedObjectsCountResultType
        case .objectIDs: .updatedObjectIDsResultType
        }
    }
}

@Suite("Typed batch operations on SQLite")
@MainActor
struct BatchOperationTests {
    @Test(arguments: BatchPayload.allCases)
    fileprivate func deletePayloadMatchesNativeExecution(_ payload: BatchPayload) throws {
        try withSQLiteTestStack { typedStack in
            try withSQLiteTestStack { nativeStack in
                let typedIDs = try seedItems(in: typedStack)
                let nativeIDs = try seedItems(in: nativeStack)
                let typedRequest = deleteRequest(resultType: payload.deleteResultType)
                let nativeRequest = deleteRequest(resultType: payload.deleteResultType)

                // These annotations verify overload inference without caller casts.
                let typedResult: NSBatchDeleteResult = try typedStack.context.execute(typedRequest)
                let nativeResult = try #require(
                    try nativeStack.context.execute(nativeRequest as NSPersistentStoreRequest)
                        as? NSBatchDeleteResult
                )
                #expect(typedResult.resultType == nativeResult.resultType)
                try assertPayload(typedResult.result, mode: payload, expectedIDs: typedIDs)
                try assertPayload(nativeResult.result, mode: payload, expectedIDs: nativeIDs)
                #expect(try persistedNames(in: typedStack) == ["keep"])
                #expect(try persistedNames(in: nativeStack) == ["keep"])
            }
        }
    }

    @Test(arguments: BatchPayload.allCases)
    fileprivate func updatePayloadMatchesNativeExecution(_ payload: BatchPayload) throws {
        try withSQLiteTestStack { typedStack in
            try withSQLiteTestStack { nativeStack in
                let typedIDs = try seedItems(in: typedStack)
                let nativeIDs = try seedItems(in: nativeStack)
                let typedRequest = updateRequest(resultType: payload.updateResultType)
                let nativeRequest = updateRequest(resultType: payload.updateResultType)

                let typedResult: NSBatchUpdateResult = try typedStack.context.execute(typedRequest)
                let nativeResult = try #require(
                    try nativeStack.context.execute(nativeRequest as NSPersistentStoreRequest)
                        as? NSBatchUpdateResult
                )
                #expect(typedResult.resultType == nativeResult.resultType)
                try assertPayload(typedResult.result, mode: payload, expectedIDs: typedIDs)
                try assertPayload(nativeResult.result, mode: payload, expectedIDs: nativeIDs)
                #expect(try persistedValues(in: typedStack) == ["first": 42, "second": 42, "keep": 1])
                #expect(try persistedValues(in: nativeStack) == ["first": 42, "second": 42, "keep": 1])
            }
        }
    }

    @Test func typedIdentifiersDeleteOnlyTheirSelectedObjects() throws {
        try withSQLiteTestStack { stack in
            let first = stack.insertItem(name: "first")
            let second = stack.insertItem(name: "second")
            _ = stack.insertItem(name: "keep")
            try stack.context.save()
            let ids: [ManagedID<SQLiteItem>] = [first.managedID, second.managedID]
            let request = NSBatchDeleteRequest(objectIDs: ids)
            request.resultType = .resultTypeObjectIDs

            let result: NSBatchDeleteResult = try stack.context.execute(request)
            let deletedIDs = try #require(result.result as? [NSManagedObjectID])
            #expect(Set(deletedIDs) == Set(ids.map(\.objectID)))
            #expect(try persistedNames(in: stack) == ["keep"])
        }
    }

    @Test func subclassIdentifiersKeepTheirEntityWhenViewedAsBaseIdentifiers() throws {
        try withSQLiteTestStack { stack in
            let first = stack.insertSpecialItem(name: "first")
            let second = stack.insertSpecialItem(name: "second")
            _ = stack.insertSpecialItem(name: "keep-child")
            _ = stack.insertItem(name: "keep-parent")
            try stack.context.save()
            let baseFirst: SQLiteItem = first
            let baseSecond: SQLiteItem = second
            let ids: [ManagedID<SQLiteItem>] = [baseFirst.managedID, baseSecond.managedID]
            #expect(ids.allSatisfy { $0.objectID.entity.name == "SpecialItem" })
            let request = NSBatchDeleteRequest(objectIDs: ids)
            request.resultType = .resultTypeObjectIDs

            let result: NSBatchDeleteResult = try stack.context.execute(request)
            let deletedIDs = try #require(result.result as? [NSManagedObjectID])
            #expect(Set(deletedIDs) == Set(ids.map(\.objectID)))
            #expect(try persistedNames(in: stack) == ["keep-child", "keep-parent"])
        }
    }

    @Test(arguments: [false, true])
    func deletePreservesIncludesSubentities(_ includesSubentities: Bool) throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertItem(name: "target")
            _ = stack.insertSpecialItem(name: "target")
            _ = stack.insertItem(name: "keep")
            try stack.context.save()
            let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: "Item")
            fetch.predicate = NSPredicate(format: "name == %@", "target")
            fetch.includesSubentities = includesSubentities
            let request = NSBatchDeleteRequest(fetchRequest: fetch)
            request.resultType = .resultTypeCount

            let result: NSBatchDeleteResult = try stack.context.execute(request)
            let count = try #require(result.result as? NSNumber)
            #expect(count.intValue == (includesSubentities ? 2 : 1))
            #expect(try persistedNames(in: stack) == (includesSubentities ? ["keep"] : ["keep", "target"]))
        }
    }

    @Test(arguments: [false, true])
    func updatePreservesIncludesSubentities(_ includesSubentities: Bool) throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertItem(name: "parent", value: 1)
            _ = stack.insertSpecialItem(name: "child", value: 1)
            try stack.context.save()
            let request = NSBatchUpdateRequest(entityName: "Item")
            request.includesSubentities = includesSubentities
            request.propertiesToUpdate = ["value": 42]
            request.resultType = .updatedObjectsCountResultType

            let result: NSBatchUpdateResult = try stack.context.execute(request)
            let count = try #require(result.result as? NSNumber)
            #expect(count.intValue == (includesSubentities ? 2 : 1))
            #expect(try persistedValues(in: stack) == ["parent": 42, "child": includesSubentities ? 42 : 1])
        }
    }

    @Test func deleteDoesNotMergeOrSavePendingContextChanges() throws {
        try withSQLiteTestStack { stack in
            let registered = stack.insertItem(name: "saved", value: 1)
            try stack.context.save()
            let id = registered.managedID
            registered.name = "local edit"
            let pending = stack.insertItem(name: "unsaved insertion", value: 5)
            let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: "Item")
            fetch.predicate = NSPredicate(format: "name == %@", "saved")
            let request = NSBatchDeleteRequest(fetchRequest: fetch)
            request.resultType = .resultTypeObjectIDs

            let result: NSBatchDeleteResult = try stack.context.execute(request)
            #expect(try #require(result.result as? [NSManagedObjectID]) == [id.objectID])
            #expect(try persistedNames(in: stack).isEmpty)
            #expect(stack.context.registeredObject(for: id) === registered)
            #expect(!registered.isDeleted)
            #expect(registered.name == "local edit")
            #expect(registered.isUpdated)
            #expect(pending.isInserted)
            #expect(stack.context.hasChanges)
            #expect(!stack.context.automaticallyMergesChangesFromParent)
        }
    }

    @Test func updateDoesNotMergeOrSavePendingContextChanges() throws {
        try withSQLiteTestStack { stack in
            let registered = stack.insertItem(name: "saved", value: 1)
            try stack.context.save()
            let id = registered.managedID
            registered.name = "local edit"
            let pending = stack.insertItem(name: "unsaved insertion", value: 5)
            let request = NSBatchUpdateRequest(entityName: "Item")
            request.predicate = NSPredicate(format: "name == %@", "saved")
            request.propertiesToUpdate = ["value": 42]
            request.resultType = .updatedObjectIDsResultType

            let result: NSBatchUpdateResult = try stack.context.execute(request)
            #expect(try #require(result.result as? [NSManagedObjectID]) == [id.objectID])
            #expect(try persistedValues(in: stack) == ["saved": 42])
            #expect(stack.context.registeredObject(for: id) === registered)
            #expect(registered.name == "local edit")
            #expect(registered.value == 1)
            #expect(registered.isUpdated)
            #expect(pending.isInserted)
            #expect(stack.context.hasChanges)
            #expect(!stack.context.automaticallyMergesChangesFromParent)
        }
    }

    private func seedItems(in stack: SQLiteTestStack) throws -> [NSManagedObjectID] {
        let first = stack.insertItem(name: "first", value: 1)
        let second = stack.insertItem(name: "second", value: 1)
        _ = stack.insertItem(name: "keep", value: 1)
        try stack.context.save()
        return [first.objectID, second.objectID]
    }

    private func deleteRequest(resultType: NSBatchDeleteRequestResultType) -> NSBatchDeleteRequest {
        let fetch = NSFetchRequest<any NSFetchRequestResult>(entityName: "Item")
        fetch.predicate = NSPredicate(format: "name != %@", "keep")
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        request.resultType = resultType
        return request
    }

    private func updateRequest(resultType: NSBatchUpdateRequestResultType) -> NSBatchUpdateRequest {
        let request = NSBatchUpdateRequest(entityName: "Item")
        request.predicate = NSPredicate(format: "name != %@", "keep")
        request.propertiesToUpdate = ["value": 42]
        request.resultType = resultType
        return request
    }

    private func persistedNames(in stack: SQLiteTestStack) throws -> [String] {
        try stack.makeContext().fetch(NSFetchRequest<SQLiteItem>(entityName: "Item"))
            .compactMap(\.name).sorted()
    }

    private func persistedValues(in stack: SQLiteTestStack) throws -> [String: Int64] {
        let objects = try stack.makeContext().fetch(NSFetchRequest<SQLiteItem>(entityName: "Item"))
        return try Dictionary(uniqueKeysWithValues: objects.map { item in
            (try #require(item.name), item.value)
        })
    }

    private func assertPayload(
        _ result: Any?,
        mode: BatchPayload,
        expectedIDs: [NSManagedObjectID]
    ) throws {
        switch mode {
        case .status:
            #expect(try #require(result as? NSNumber).boolValue)
        case .count:
            #expect(try #require(result as? NSNumber).intValue == expectedIDs.count)
        case .objectIDs:
            #expect(Set(try #require(result as? [NSManagedObjectID])) == Set(expectedIDs))
        }
    }
}
