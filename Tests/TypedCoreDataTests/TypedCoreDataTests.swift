import CoreData
import Testing
import TypedCoreData

@Suite("Managed identifiers and native Core Data behavior")
@MainActor
struct TypedCoreDataTests {
    @Test func identifierPreservesObjectIDAndStaticType() throws {
        let stack = try TestStack()
        let item = stack.insertItem()

        // The explicit annotation verifies the public generic API at compile time.
        let id: ManagedID<TestItem> = item.managedID
        #expect(id.objectID === item.objectID)
        #expect(id.objectID.isTemporaryID)
        #expect(id.objectID.entity.name == "Item")
    }

    @Test func equalIdentifiersHaveEqualHashes() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        let other = stack.insertItem()
        let first = item.managedID
        let repeated = item.managedID

        #expect(first == repeated)
        #expect(first.hashValue == repeated.hashValue)
        #expect(first != other.managedID)
        #expect(Set([first, repeated, other.managedID]).count == 2)
        #expect([first: "value"][repeated] == "value")
    }

    @Test func permanentIdentifiersCompareAcrossContexts() throws {
        let stack = try TestStack()
        let item = stack.insertItem(name: "Shared identity")
        try stack.context.save()
        let id = item.managedID
        let reader = stack.makeContext()
        let resolved: TestItem = try reader.existingObject(with: id)

        #expect(resolved !== item)
        #expect(resolved.managedObjectContext === reader)
        #expect(resolved.managedID == id)
        #expect(resolved.managedID.hashValue == id.hashValue)
        #expect(Set([id, resolved.managedID]).count == 1)
        #expect(resolved.name == "Shared identity")
    }

    @Test func allOverloadsResolveAnInsertedTemporaryObject() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        let id = item.managedID

        let existing: TestItem = try stack.context.existingObject(with: id)
        let object: TestItem = stack.context.object(with: id)
        let registered: TestItem? = stack.context.registeredObject(for: id)
        #expect(existing === item)
        #expect(object === item)
        #expect(registered === item)
        let nativeExisting = try stack.context.existingObject(with: id.objectID)
        #expect(existing === nativeExisting)
        #expect(object === stack.context.object(with: id.objectID))
        #expect(registered === stack.context.registeredObject(for: id.objectID))
    }

    @Test func existingObjectLoadsASavedObject() throws {
        let stack = try TestStack()
        let item = stack.insertItem(name: "Saved value")
        try stack.context.save()
        let id = item.managedID
        let reader = stack.makeContext()
        #expect(reader.registeredObject(for: id) == nil)

        let resolved: TestItem = try reader.existingObject(with: id)
        #expect(resolved.objectID == id.objectID)
        #expect(resolved.name == "Saved value")
        #expect(reader.registeredObject(for: id) === resolved)
        let nativeResolved = try reader.existingObject(with: id.objectID)
        #expect(resolved === nativeResolved)
    }

    @Test func registeredObjectDoesNotFetchAnUnregisteredObject() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        try stack.context.save()
        let id = item.managedID
        let reader = stack.makeContext()

        #expect(reader.registeredObject(for: id.objectID) == nil)
        #expect(reader.registeredObject(for: id) == nil)
        #expect(reader.registeredObjects.isEmpty)

        let fault: TestItem = reader.object(with: id)
        #expect(fault.isFault)
        #expect(reader.registeredObject(for: id) === fault)
        #expect(reader.registeredObject(for: id.objectID) === fault)

        reader.reset()
        #expect(reader.registeredObject(for: id) == nil)
        #expect(reader.registeredObject(for: id.objectID) == nil)
        #expect(reader.registeredObjects.isEmpty)
    }

    @Test func objectReturnsAFaultWithoutFetching() throws {
        let stack = try TestStack()
        let item = stack.insertItem(name: "Loaded on access")
        try stack.context.save()
        let id = item.managedID
        let typedReader = stack.makeContext()
        let nativeReader = stack.makeContext()

        let typed: TestItem = typedReader.object(with: id)
        let native = nativeReader.object(with: id.objectID)
        #expect(typed.isFault)
        #expect(native.isFault)
        #expect(typed.objectID == native.objectID)
        #expect(typed.name == "Loaded on access")
        #expect(!typed.isFault)
    }

    @Test func existingObjectMatchesNativeBehaviorForARegisteredFault() throws {
        let stack = try TestStack()
        let item = stack.insertItem(name: "Initially faulted")
        try stack.context.save()
        let id = item.managedID
        let typedReader = stack.makeContext()
        let nativeReader = stack.makeContext()
        let typedFault: TestItem = typedReader.object(with: id)
        let nativeFault = nativeReader.object(with: id.objectID)
        #expect(typedFault.isFault)
        #expect(nativeFault.isFault)

        let typedExisting: TestItem = try typedReader.existingObject(with: id)
        let nativeExisting = try nativeReader.existingObject(with: id.objectID)
        #expect(typedExisting === typedFault)
        #expect(nativeExisting === nativeFault)
        // Core Data decides whether an already registered fault is realized.
        // The overload must preserve that behavior without fetching itself.
        #expect(typedExisting.isFault == nativeExisting.isFault)
        #expect(typedExisting.name == "Initially faulted")
        #expect(nativeExisting.value(forKey: "name") as? String == "Initially faulted")
    }

    @Test func anUnsavedPermanentIDDoesNotMakeAnObjectAvailableInAnotherContext() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        try stack.context.obtainPermanentIDs(for: [item])
        let id = item.managedID
        #expect(!id.objectID.isTemporaryID)
        #expect(item.isInserted)

        let nativeReader = stack.makeContext()
        let typedReader = stack.makeContext()
        let nativeError = try #require(captureError {
            _ = try nativeReader.existingObject(with: id.objectID)
        })
        let typedError = try #require(captureError {
            _ = try typedReader.existingObject(with: id)
        })
        #expect(typedError.domain == nativeError.domain)
        #expect(typedError.code == nativeError.code)
    }

    @Test func aTemporaryIDCannotResolveAnInsertedObjectInAnotherContext() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        let id = item.managedID
        #expect(id.objectID.isTemporaryID)

        let nativeReader = stack.makeContext()
        let typedReader = stack.makeContext()
        #expect(typedReader.registeredObject(for: id) == nil)
        let nativeError = try #require(captureError {
            _ = try nativeReader.existingObject(with: id.objectID)
        })
        let typedError = try #require(captureError {
            _ = try typedReader.existingObject(with: id)
        })
        #expect(typedError.domain == nativeError.domain)
        #expect(typedError.code == nativeError.code)
    }

    @Test func pendingDeletionMatchesNativeResolution() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        try stack.context.save()
        let id = item.managedID
        stack.context.delete(item)
        #expect(item.isDeleted)

        #expect(stack.context.object(with: id) === stack.context.object(with: id.objectID))
        #expect(stack.context.registeredObject(for: id) === stack.context.registeredObject(for: id.objectID))
        #expect(try stack.context.existingObject(with: id) === stack.context.existingObject(with: id.objectID))
        #expect(stack.context.object(with: id) === item)
    }

    @Test func savedDeletionMakesExistingObjectThrowTheNativeError() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        try stack.context.save()
        let id = item.managedID
        stack.context.delete(item)
        try stack.context.save()

        // Separate contexts prevent one lookup from influencing the other.
        let nativeReader = stack.makeContext()
        let typedReader = stack.makeContext()
        let nativeError = try #require(captureError {
            _ = try nativeReader.existingObject(with: id.objectID)
        })
        let typedError = try #require(captureError {
            _ = try typedReader.existingObject(with: id)
        })
        #expect(typedError.domain == nativeError.domain)
        #expect(typedError.code == nativeError.code)
    }

    @Test func missingObjectCanStillProduceAnUnfiredFault() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        try stack.context.save()
        let id = item.managedID
        stack.context.delete(item)
        try stack.context.save()
        let typedReader = stack.makeContext()
        let nativeReader = stack.makeContext()

        #expect(typedReader.registeredObject(for: id) == nil)
        let typed: TestItem = typedReader.object(with: id)
        let native = nativeReader.object(with: id.objectID)
        #expect(typed.isFault)
        #expect(native.isFault)
        #expect(typed.objectID == native.objectID)
        #expect(typedReader.registeredObject(for: id) === typed)
        // Accessing persistent attributes would fire a missing-object fault and
        // may raise an Objective-C exception, just as the native API does.
    }

    @Test func obtainingPermanentIDsDoesNotMutateAnExistingIdentifier() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        let temporary = item.managedID
        let temporarySet = Set([temporary])
        try stack.context.obtainPermanentIDs(for: [item])
        let permanent = item.managedID

        #expect(temporary.objectID.isTemporaryID)
        #expect(!permanent.objectID.isTemporaryID)
        #expect(temporary != permanent)
        #expect(temporarySet.contains(temporary))
        #expect(!temporarySet.contains(permanent))
        #expect(stack.context.object(with: permanent) === item)
        #expect(try stack.context.existingObject(with: permanent) === item)
        #expect(stack.context.registeredObject(for: permanent) === item)

        try stack.context.save()
        #expect(item.managedID == permanent)
        let reader = stack.makeContext()
        #expect(try reader.existingObject(with: permanent).managedID == permanent)
    }

    @Test func savingPromotesATemporaryID() throws {
        let stack = try TestStack()
        let item = stack.insertItem()
        let temporary = item.managedID
        try stack.context.save()
        let permanent = item.managedID

        #expect(temporary.objectID.isTemporaryID)
        #expect(!permanent.objectID.isTemporaryID)
        #expect(temporary != permanent)
        #expect(permanent.objectID == item.objectID)
    }

    @Test func entityInheritancePreservesConcreteAndBaseStaticTypes() throws {
        let stack = try TestStack()
        let special = stack.insertSpecialItem()
        special.name = "Inherited name"
        special.detail = "Subclass value"
        try stack.context.save()

        let concreteID: ManagedID<TestSpecialItem> = special.managedID
        let base: TestItem = special
        let baseID: ManagedID<TestItem> = base.managedID
        let erased: NSManagedObject = special
        let erasedID: ManagedID<NSManagedObject> = erased.managedID
        #expect(concreteID.objectID == baseID.objectID)
        #expect(baseID.objectID == erasedID.objectID)
        #expect(concreteID.objectID.entity.superentity?.name == "Item")

        let reader = stack.makeContext()
        let concrete: TestSpecialItem = try reader.existingObject(with: concreteID)
        let resolvedBase: TestItem = try reader.existingObject(with: baseID)
        let resolvedErased: NSManagedObject = try reader.existingObject(with: erasedID)
        #expect(concrete === resolvedBase)
        #expect(concrete === resolvedErased)
        #expect(concrete.name == "Inherited name")
        #expect(concrete.detail == "Subclass value")
        #expect(reader.object(with: concreteID) === concrete)
        #expect(reader.object(with: baseID) === concrete)
        #expect(reader.registeredObject(for: concreteID) === concrete)
        #expect(reader.registeredObject(for: baseID) === concrete)
    }

    @available(macOS 12, iOS 15, *)
    @Test func identifierCrossesAContextQueueUnderStrictConcurrency() async throws {
        let stack = try TestStack()
        let writer = stack.makeContext(concurrencyType: .privateQueueConcurrencyType)

        // Only the Sendable identifier leaves the private queue. The managed
        // object remains confined to the context that created it.
        let id: ManagedID<TestItem> = try await writer.perform { @Sendable in
            let entity = try #require(NSEntityDescription.entity(forEntityName: "Item", in: writer))
            let item = TestItem(entity: entity, insertInto: writer)
            item.name = "Written on a private queue"
            try writer.save()
            return item.managedID
        }
        requireSendable(id)
        #expect(!id.objectID.isTemporaryID)
        let resolved: TestItem = try stack.context.existingObject(with: id)
        #expect(resolved.name == "Written on a private queue")
        #expect(resolved.managedObjectContext === stack.context)
    }
}

private func requireSendable<Value: Sendable>(_: Value) {}

private func captureError(_ operation: () throws -> Void) -> NSError? {
    do {
        try operation()
        return nil
    } catch {
        return error as NSError
    }
}
