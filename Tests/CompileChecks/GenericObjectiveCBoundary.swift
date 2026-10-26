// Compiler probe, outside the package test target. No production API here.
import CoreData
import Foundation

#if EXACT_SECTION_METHOD
extension NSFetchedResultsController {
    func proposedObjects(inSectionAt index: Int) -> [ResultType]? {
        sections?[index].objects as? [ResultType]
    }
}
#endif

#if EXACT_PREDICATE_METHOD
extension NSFetchRequest where ResultType: NSManagedObject {
    @available(iOS 17, macOS 14, *)
    func proposedSetPredicate(_ predicate: Predicate<ResultType>) {
        self.predicate = NSPredicate(predicate)
    }
}
#endif

// These standalone functions retain a reified Swift generic parameter.
func proposedObjects<Result: NSFetchRequestResult>(
    inSectionAt index: Int, of controller: NSFetchedResultsController<Result>
) -> [Result]? {
    guard let sections = controller.sections else { return nil }
    precondition(sections.indices.contains(index))
    guard let objects = sections[index].objects else { return nil }
    guard let typed = objects as? [Result] else { preconditionFailure("Type mismatch") }
    return typed
}

private enum ProposalError: Error { case unsupportedPredicate }

@available(iOS 17, macOS 14, *)
func proposedSetPredicate<Entity: NSManagedObject>(
    _ predicate: Predicate<Entity>, on request: NSFetchRequest<Entity>
) throws {
    guard let native = NSPredicate(predicate) else { throw ProposalError.unsupportedPredicate }
    request.predicate = native
}
