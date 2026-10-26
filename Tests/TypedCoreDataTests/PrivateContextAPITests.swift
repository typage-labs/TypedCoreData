import CoreData
import Foundation
import Testing
import TypedCoreData

/// The context, requests, controllers, and managed objects stay on the private
/// context's queue. Only a checked-Sendable snapshot crosses back to the test.
@available(macOS 12, iOS 15, *)
@MainActor
private func withPrivateSQLiteContext<Snapshot: Sendable>(
    _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Snapshot
) async throws -> Snapshot {
    let stack = try SQLiteTestStack()
    defer {
        do {
            try stack.cleanup()
        } catch {
            Issue.record(error, "Failed to clean up the private-context SQLite test store")
        }
    }
    return try await withPrivateTestContext(coordinator: stack.coordinator, operation)
}

private struct PrivateIDSnapshot: Sendable {
    let ids: [ManagedID<SQLiteItem>]
    let nativeIDs: [NSManagedObjectID]
    let expectedIDs: [NSManagedObjectID]
    let pendingID: ManagedID<SQLiteItem>
    let hasUnsavedChanges: Bool
    let sourceRequestUnchanged: Bool
    let executedOffMainThread: Bool
}

private struct PrivatePredicateSnapshot: Sendable {
    let ids: [ManagedID<SQLiteItem>]
    let nativeIDs: [NSManagedObjectID]
    let expectedID: ManagedID<SQLiteItem>
    let names: [String?]
    let sourceOptionsPreserved: Bool
    let executedOffMainThread: Bool
}

private struct PrivateSectionSnapshot: Sendable {
    let names: [String]
    let values: [[Int64]]
    let ids: [[ManagedID<SQLiteItem>]]
    let nativeIDs: [[NSManagedObjectID]]
    let expectedIDs: [[NSManagedObjectID]]
    let nativeIdentityPreserved: Bool
    let includesSubclass: Bool
    let wasUnavailableBeforeFetch: Bool
    let executedOffMainThread: Bool
}

@Suite("Typed APIs on private SQLite contexts")
@MainActor
struct PrivateContextAPITests {
    @available(macOS 12, iOS 15, *)
    @Test func objectIDFetchPreservesPendingChangesAndNativeResultsOnPrivateQueue() async throws {
        let snapshot = try await withPrivateSQLiteContext { context in
            let itemDescription = NSEntityDescription.entity(forEntityName: "Item", in: context)
            let childDescription = NSEntityDescription.entity(forEntityName: "SpecialItem", in: context)
            let entity = try #require(itemDescription)
            let childEntity = try #require(childDescription)
            let excluded = SQLiteItem(entity: entity, insertInto: context)
            excluded.value = 10
            let saved = SQLiteItem(entity: entity, insertInto: context)
            saved.value = 20
            let child = SQLiteSpecialItem(entity: childEntity, insertInto: context)
            child.value = 30
            try context.save()
            let pending = SQLiteItem(entity: entity, insertInto: context)
            pending.value = 40
            let pendingID = pending.managedID

            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            let predicate = NSPredicate(format: "value >= 20")
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: "value", ascending: true)]
            request.includesPendingChanges = true
            let ids = try context.fetchObjectIDs(for: request)

            let native = try #require(request.copy() as? NSFetchRequest<NSManagedObjectID>)
            native.resultType = .managedObjectIDResultType
            return PrivateIDSnapshot(
                ids: ids,
                nativeIDs: try context.fetch(native),
                expectedIDs: [saved.objectID, child.objectID, pending.objectID],
                pendingID: pendingID,
                hasUnsavedChanges: context.hasChanges,
                sourceRequestUnchanged: request.resultType == .managedObjectResultType
                    && request.predicate === predicate
                    && request.includesPendingChanges
                    && request.sortDescriptors?.first?.key == "value",
                executedOffMainThread: !Thread.isMainThread
            )
        }

        // Core Data's ID-result pending merge does not promise object-fetch order.
        #expect(Set(snapshot.ids.map(\.objectID)) == Set(snapshot.nativeIDs))
        #expect(Set(snapshot.ids.map(\.objectID)) == Set(snapshot.expectedIDs))
        #expect(snapshot.ids.contains(snapshot.pendingID))
        #expect(snapshot.pendingID.objectID.isTemporaryID)
        #expect(snapshot.hasUnsavedChanges)
        #expect(snapshot.sourceRequestUnchanged)
        #expect(snapshot.executedOffMainThread)
    }

    @available(macOS 14, iOS 17, *)
    @Test func predicateAttachmentAndExecutionStayOnPrivateQueue() async throws {
        let snapshot = try await withPrivateSQLiteContext { context in
            let itemDescription = NSEntityDescription.entity(forEntityName: "Item", in: context)
            let entity = try #require(itemDescription)
            let alice = SQLiteItem(entity: entity, insertInto: context)
            alice.name = "Alice"
            alice.value = 30
            let bob = SQLiteItem(entity: entity, insertInto: context)
            bob.name = "Bob"
            bob.value = 17
            let carol = SQLiteItem(entity: entity, insertInto: context)
            carol.name = "Carol"
            carol.value = 24
            try context.save()

            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            request.predicate = NSPredicate(value: false)
            request.fetchLimit = 5
            request.includesPendingChanges = false
            request.sortDescriptors = [NSSortDescriptor(key: "value", ascending: true)]
            let predicate = #Predicate<SQLiteItem> { $0.value >= 18 && $0.name != "Carol" }
            try setPredicate(predicate, on: request)
            let fetched = try context.fetch(request)
            let native = NSFetchRequest<SQLiteItem>(entityName: "Item")
            guard let converted = NSPredicate(predicate) else {
                throw PredicateConversionError.unsupportedPredicate
            }
            native.predicate = converted

            return PrivatePredicateSnapshot(
                ids: fetched.map(\.managedID),
                nativeIDs: try context.fetch(native).map(\.objectID),
                expectedID: alice.managedID,
                names: fetched.map(\.name),
                sourceOptionsPreserved: request.fetchLimit == 5
                    && !request.includesPendingChanges
                    && request.sortDescriptors?.first?.key == "value"
                    && request.resultType == .managedObjectResultType,
                executedOffMainThread: !Thread.isMainThread
            )
        }

        #expect(snapshot.ids == [snapshot.expectedID])
        #expect(snapshot.ids.map(\.objectID) == snapshot.nativeIDs)
        #expect(snapshot.names == ["Alice"])
        #expect(snapshot.sourceOptionsPreserved)
        #expect(snapshot.executedOffMainThread)
    }

    @available(macOS 12, iOS 15, *)
    @Test func sectionAccessPreservesIdentityOrderAndSubclassesOnPrivateQueue() async throws {
        let snapshot = try await withPrivateSQLiteContext { context in
            let itemDescription = NSEntityDescription.entity(forEntityName: "Item", in: context)
            let childDescription = NSEntityDescription.entity(forEntityName: "SpecialItem", in: context)
            let entity = try #require(itemDescription)
            let childEntity = try #require(childDescription)
            let second = SQLiteItem(entity: entity, insertInto: context)
            second.name = "A"
            second.value = 2
            let first = SQLiteSpecialItem(entity: childEntity, insertInto: context)
            first.name = "A"
            first.value = 1
            let third = SQLiteItem(entity: entity, insertInto: context)
            third.name = "B"
            third.value = 3
            try context.save()

            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            request.sortDescriptors = [
                NSSortDescriptor(key: "name", ascending: true),
                NSSortDescriptor(key: "value", ascending: true),
            ]
            let controller = NSFetchedResultsController(fetchRequest: request,
                managedObjectContext: context, sectionNameKeyPath: "name", cacheName: nil)
            let wasUnavailable = controller.sections == nil
                && objects(inSectionAt: 0, of: controller) == nil
            try controller.performFetch()
            let sections = try #require(controller.sections)
            var values: [[Int64]] = []
            var ids: [[ManagedID<SQLiteItem>]] = []
            var nativeIDs: [[NSManagedObjectID]] = []
            var identityPreserved = true
            var includesSubclass = false
            for sectionIndex in sections.indices {
                let typed = try #require(objects(inSectionAt: sectionIndex, of: controller))
                let native = try #require(sections[sectionIndex].objects as? [NSManagedObject])
                values.append(typed.map(\.value))
                ids.append(typed.map(\.managedID))
                nativeIDs.append(native.map(\.objectID))
                includesSubclass = includesSubclass || typed.contains { $0 is SQLiteSpecialItem }
                identityPreserved = identityPreserved && typed.count == native.count
                for row in typed.indices {
                    identityPreserved = identityPreserved && native.indices.contains(row)
                        && typed[row] === native[row]
                        && typed[row] === controller.object(at: IndexPath(indexes: [sectionIndex, row]))
                }
            }
            return PrivateSectionSnapshot(
                names: sections.map(\.name), values: values, ids: ids, nativeIDs: nativeIDs,
                expectedIDs: [[first.objectID, second.objectID], [third.objectID]],
                nativeIdentityPreserved: identityPreserved,
                includesSubclass: includesSubclass,
                wasUnavailableBeforeFetch: wasUnavailable,
                executedOffMainThread: !Thread.isMainThread
            )
        }

        #expect(snapshot.names == ["A", "B"])
        #expect(snapshot.values == [[1, 2], [3]])
        #expect(snapshot.ids.map { $0.map(\.objectID) } == snapshot.expectedIDs)
        #expect(snapshot.ids.map { $0.map(\.objectID) } == snapshot.nativeIDs)
        #expect(snapshot.nativeIdentityPreserved)
        #expect(snapshot.includesSubclass)
        #expect(snapshot.wasUnavailableBeforeFetch)
        #expect(snapshot.executedOffMainThread)
    }
}
