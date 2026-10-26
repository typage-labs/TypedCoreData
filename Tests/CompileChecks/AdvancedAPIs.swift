// External-client compiler checks; intentionally outside the package test target.
import CoreData
import Foundation
import TypedCoreData

@objc(TCDCompileContact)
class CompileContact: NSManagedObject {
    @NSManaged var age: Int64
}

@objc(TCDCompileCompany)
final class CompileCompany: NSManagedObject {
    @NSManaged var employeeCount: Int64
}

func baselineAPIClient(
    context: NSManagedObjectContext,
    request: NSFetchRequest<CompileContact>,
    controller: NSFetchedResultsController<CompileContact>,
    rawID: NSManagedObjectID
) throws {
    let _: ManagedID<CompileContact> = try ManagedID(validating: rawID)
    // Infer from the request/controller alone, then verify the inferred types.
    // A conflicting result annotation on the call can produce only an
    // ambiguity diagnostic on Swift 6.0 instead of the intended type mismatch.
    let ids = try context.fetchObjectIDs(for: request)
    let _: [ManagedID<CompileContact>] = ids
    let section = objects(inSectionAt: 0, of: controller)
    let _: [CompileContact]? = section
    // The concrete batch overloads require a type when storing the native method.
    let nativeExecute: (NSPersistentStoreRequest) throws -> NSPersistentStoreResult = context.execute
    _ = nativeExecute

    #if WRONG_ID_RESULT
    let _: [ManagedID<CompileCompany>] = ids
    #endif
    #if WRONG_SECTION_RESULT
    let _: [CompileCompany]? = section
    #endif
    #if UNCHECKED_ID_INITIALIZER
    _ = ManagedID<CompileContact>(rawID)
    #endif
}

@available(iOS 17, macOS 14, *)
func modernAPIClient(request: NSFetchRequest<CompileContact>) throws {
    let predicate = #Predicate<CompileContact> { $0.age >= 18 }
    try setPredicate(predicate, on: request)

    #if WRONG_PREDICATE_ROOT
    let companyPredicate = #Predicate<CompileCompany> { $0.employeeCount > 0 }
    try setPredicate(companyPredicate, on: request)
    #endif
    #if WRONG_PREDICATE_VALUE
    _ = #Predicate<CompileContact> { $0.age == "Alice" }
    #endif
}

// A baseline client can use the new API only inside an availability guard.
func guardedModernAPIClient(request: NSFetchRequest<CompileContact>) throws {
    if #available(iOS 17, macOS 14, *) {
        try setPredicate(#Predicate<CompileContact> { $0.age >= 18 }, on: request)
    }
}

#if UNGUARDED_PREDICATE_API
func unguardedModernAPIClient(request: NSFetchRequest<CompileContact>) throws {
    // The older Predicate type is also unavailable, so a separate fixture below
    // explicitly checks the public function's own availability diagnostic.
    let attach = setPredicate as (Predicate<CompileContact>, NSFetchRequest<CompileContact>) throws -> Void
    _ = attach
}
#endif
