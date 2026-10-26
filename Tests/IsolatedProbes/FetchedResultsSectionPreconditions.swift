// Standalone subprocess probe. Intentionally failing preconditions must never
// run inside the package's test process. The verification harness compiles this
// executable against the production TypedCoreData module.
import CoreData
import TypedCoreData

@objc(TypedCoreDataSectionProbeItem)
private class SectionProbeItem: NSManagedObject {
    @NSManaged var category: String
    @NSManaged var position: Int64
}

@objc(TypedCoreDataSectionProbeChild)
private final class SectionProbeChild: SectionProbeItem {}

@main
private enum FetchedResultsSectionPreconditionProbe {
    @MainActor
    static func main() throws {
        guard let scenario = CommandLine.arguments.dropFirst().first else {
            fatalError("Pass negative-index, out-of-range, empty-grouped, or wrong-runtime-type")
        }
        let category = NSAttributeDescription()
        category.name = "category"
        category.attributeType = .stringAttributeType
        let position = NSAttributeDescription()
        position.name = "position"
        position.attributeType = .integer64AttributeType
        let parent = NSEntityDescription()
        parent.name = "ProbeParentRecord"
        parent.managedObjectClassName = NSStringFromClass(SectionProbeItem.self)
        parent.properties = [category, position]
        let child = NSEntityDescription()
        child.name = "ProbeChildRecord"
        child.managedObjectClassName = NSStringFromClass(SectionProbeChild.self)
        parent.subentities = [child]
        let model = NSManagedObjectModel()
        model.entities = [parent, child]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType,
            configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        if scenario != "empty-grouped" {
            let first = SectionProbeChild(entity: child, insertInto: context)
            first.category = "A"
            first.position = 0
            let second = SectionProbeItem(entity: parent, insertInto: context)
            second.category = "A"
            second.position = 1
            try context.save()
        }

        if scenario == "wrong-runtime-type" {
            // The mutable native request can fetch the parent entity even though
            // its Swift generic type claims every object is a child. The first
            // object is compatible; the second proves the entire array is checked.
            let request = NSFetchRequest<SectionProbeChild>(entityName: "ProbeChildRecord")
            request.entity = parent
            request.sortDescriptors = sortDescriptors
            let controller = NSFetchedResultsController(fetchRequest: request,
                managedObjectContext: context, sectionNameKeyPath: "category", cacheName: nil)
            try controller.performFetch()
            guard let native = controller.sections?.first?.objects,
                  native.count == 2,
                  native[0] is SectionProbeChild,
                  !(native[1] is SectionProbeChild) else {
                fatalError("Probe setup did not create mixed runtime section classes")
            }
            _ = objects(inSectionAt: 0, of: controller)
        } else {
            let request = NSFetchRequest<SectionProbeItem>(entityName: "ProbeParentRecord")
            request.sortDescriptors = sortDescriptors
            let controller = NSFetchedResultsController(fetchRequest: request,
                managedObjectContext: context, sectionNameKeyPath: "category", cacheName: nil)
            try controller.performFetch()
            guard let sections = controller.sections else {
                fatalError("Probe setup did not produce section information")
            }
            switch scenario {
            case "negative-index":
                _ = objects(inSectionAt: -1, of: controller)
            case "out-of-range":
                _ = objects(inSectionAt: sections.count, of: controller)
            case "empty-grouped":
                precondition(sections.isEmpty, "Probe expected an empty grouped fetch")
                _ = objects(inSectionAt: 0, of: controller)
            default:
                fatalError("Unknown section probe scenario: \(scenario)")
            }
        }
        fatalError("Expected the production section accessor's precondition to fail")
    }

    private static var sortDescriptors: [NSSortDescriptor] {
        [
            NSSortDescriptor(keyPath: \SectionProbeItem.category, ascending: true),
            NSSortDescriptor(keyPath: \SectionProbeItem.position, ascending: true),
        ]
    }
}
