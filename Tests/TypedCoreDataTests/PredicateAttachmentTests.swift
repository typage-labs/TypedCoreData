import CoreData
import Foundation
import Testing
import TypedCoreData

// A Swift property can be type-correct without having a KVC/model representation.
private extension SQLiteItem {
    var swiftOnlyIsPositive: Bool { value > 0 }
}

@Suite("Native typed predicate attachment")
@MainActor
struct PredicateAttachmentTests {
    @available(macOS 14, iOS 17, *)
    @Test func scalarPredicateExecutesOnSQLiteAndReplacesPreviousPredicate() throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertItem(name: "Alice", value: 30)
            _ = stack.insertItem(name: "Bob", value: 17)
            _ = stack.insertItem(name: "Carol", value: 24)
            try stack.context.save()
            let reader = stack.makeContext()
            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            request.predicate = NSPredicate(value: false)
            request.fetchLimit = 10
            request.includesPendingChanges = false
            request.sortDescriptors = [NSSortDescriptor(key: "value", ascending: true)]
            let predicate = #Predicate<SQLiteItem> { $0.value >= 18 && $0.name != "Carol" }

            try setPredicate(predicate, on: request)

            #expect(try reader.fetch(request).map(\.name) == ["Alice"])
            #expect(request.fetchLimit == 10)
            #expect(!request.includesPendingChanges)
            #expect(request.sortDescriptors?.first?.key == "value")
            #expect(request.resultType == .managedObjectResultType)

            let native = NSFetchRequest<SQLiteItem>(entityName: "Item")
            guard let converted = NSPredicate(predicate) else {
                Issue.record("Expected the supported native predicate to convert")
                return
            }
            native.predicate = converted
            #expect(try reader.fetch(request).map(\.objectID) == reader.fetch(native).map(\.objectID))
        }
    }

    @available(macOS 14, iOS 17, *)
    @Test func failedConversionPreservesPreviousPredicateAndItsFiltering() throws {
        try withSQLiteTestStack { stack in
            _ = stack.insertItem(name: "Alice", value: 30)
            _ = stack.insertItem(name: "Bob", value: 17)
            try stack.context.save()
            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            let previous = NSPredicate(format: "name == %@", "Bob")
            request.predicate = previous
            let unsupported = #Predicate<SQLiteItem> { $0.swiftOnlyIsPositive }
            #expect(NSPredicate(unsupported) == nil)

            #expect(throws: PredicateConversionError.unsupportedPredicate) {
                try setPredicate(unsupported, on: request)
            }

            #expect(request.predicate === previous)
            #expect(try stack.makeContext().fetch(request).map(\.name) == ["Bob"])
        }
    }

    @available(macOS 14, iOS 17, *)
    @Test func failedConversionPreservesAnAbsentPredicate() {
        let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
        let unsupported = #Predicate<SQLiteItem> { $0.swiftOnlyIsPositive }

        #expect(throws: PredicateConversionError.unsupportedPredicate) {
            try setPredicate(unsupported, on: request)
        }
        #expect(request.predicate == nil)
    }

    @available(macOS 14, iOS 17, *)
    @Test func explicitNilComparisonsExecuteOnSQLite() throws {
        try withSQLiteTestStack { stack in
            let unnamed = stack.insertItem(value: 1)
            unnamed.name = nil
            let named = stack.insertItem(name: "B", value: 2)
            try stack.context.save()
            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            let reader = stack.makeContext()

            try setPredicate(#Predicate<SQLiteItem> { $0.name == nil }, on: request)
            #expect(try reader.fetch(request).map(\.objectID) == [unnamed.objectID])
            try setPredicate(#Predicate<SQLiteItem> { $0.name != nil }, on: request)
            #expect(try reader.fetch(request).map(\.objectID) == [named.objectID])
        }
    }

    @available(macOS 14, iOS 17, *)
    @Test(arguments: [false, true])
    func optionalComparisonsPreserveNativeSQLiteSemantics(_ negateEquality: Bool) throws {
        try withSQLiteTestStack { stack in
            let first = stack.insertItem(value: 1)
            first.name = nil
            _ = stack.insertItem(name: "B", value: 2)
            let third = stack.insertItem(value: 3)
            third.name = nil
            try stack.context.save()
            let predicate: Predicate<SQLiteItem>
            if negateEquality {
                predicate = #Predicate<SQLiteItem> { !($0.name == "B") }
            } else {
                predicate = #Predicate<SQLiteItem> { $0.name != "B" }
            }
            let reader = stack.makeContext()
            let all = try reader.fetch(NSFetchRequest<SQLiteItem>(entityName: "Item"))
            let swiftIDs = try all.filter { try predicate.evaluate($0) }.map(\.objectID)
            #expect(Set(swiftIDs) == Set([first.objectID, third.objectID]))

            let native = NSFetchRequest<SQLiteItem>(entityName: "Item")
            guard let converted = NSPredicate(predicate) else {
                Issue.record("Expected the supported native predicate to convert")
                return
            }
            native.predicate = converted
            let request = NSFetchRequest<SQLiteItem>(entityName: "Item")
            try setPredicate(predicate, on: request)
            let typedIDs = try reader.fetch(request).map(\.objectID)
            let nativeIDs = try reader.fetch(native).map(\.objectID)

            // No rewriting to Swift Optional semantics: SQLite excludes nil
            // rows in these comparisons on the tested Apple runtime.
            #expect(typedIDs == nativeIDs)
            #expect(typedIDs.isEmpty)
            #expect(Set(typedIDs) != Set(swiftIDs))
        }
    }
}
