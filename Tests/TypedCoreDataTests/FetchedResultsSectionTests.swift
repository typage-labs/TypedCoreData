import CoreData
import Testing
import TypedCoreData

@objc(TypedCoreDataSectionItem)
private class SectionItem: NSManagedObject {
    @NSManaged var category: String
    @NSManaged var position: Int64
}

@objc(TypedCoreDataSpecialSectionItem)
private final class SpecialSectionItem: SectionItem {}

@MainActor
private final class SectionTestStack {
    let context: NSManagedObjectContext
    private let coordinator: NSPersistentStoreCoordinator
    private let itemEntity: NSEntityDescription
    private let specialEntity: NSEntityDescription

    init() throws {
        let category = NSAttributeDescription()
        category.name = "category"
        category.attributeType = .stringAttributeType
        let position = NSAttributeDescription()
        position.name = "position"
        position.attributeType = .integer64AttributeType

        let item = NSEntityDescription()
        item.name = "SectionRecord"
        item.managedObjectClassName = NSStringFromClass(SectionItem.self)
        item.properties = [category, position]
        let special = NSEntityDescription()
        special.name = "SpecialSectionRecord"
        special.managedObjectClassName = NSStringFromClass(SpecialSectionItem.self)
        item.subentities = [special]
        let model = NSManagedObjectModel()
        model.entities = [item, special]
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType,
            configurationName: nil, at: nil)
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        itemEntity = item
        specialEntity = special
    }

    func insert(category: String, position: Int64, special: Bool = false) -> SectionItem {
        let item = special
            ? SpecialSectionItem(entity: specialEntity, insertInto: context)
            : SectionItem(entity: itemEntity, insertInto: context)
        item.category = category
        item.position = position
        return item
    }

    func controller(grouped: Bool = true) -> NSFetchedResultsController<SectionItem> {
        let request = NSFetchRequest<SectionItem>(entityName: "SectionRecord")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \SectionItem.category, ascending: true),
            NSSortDescriptor(keyPath: \SectionItem.position, ascending: true),
        ]
        return NSFetchedResultsController(fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: grouped ? "category" : nil, cacheName: nil)
    }
}

@Suite("Typed fetched-results-controller sections")
@MainActor
struct FetchedResultsSectionTests {
    @Test func unavailableSectionInformationReturnsNil() throws {
        let stack = try SectionTestStack()
        let controller = stack.controller()
        #expect(controller.sections == nil)
        #expect(objects(inSectionAt: 0, of: controller) == nil)
        // Bounds have meaning only once native section information is available.
        #expect(objects(inSectionAt: -1, of: controller) == nil)
    }

    @Test func groupedSectionsPreserveNativeOrderAndIdentity() throws {
        let stack = try SectionTestStack()
        _ = stack.insert(category: "B", position: 1)
        _ = stack.insert(category: "A", position: 2)
        _ = stack.insert(category: "A", position: 1)
        try stack.context.save()
        let controller = stack.controller()
        try controller.performFetch()

        let sections = try #require(controller.sections)
        #expect(sections.map(\.name) == ["A", "B"])
        #expect(sections.map(\.numberOfObjects) == [2, 1])
        for sectionIndex in sections.indices {
            let typed: [SectionItem] = try #require(objects(inSectionAt: sectionIndex, of: controller))
            let native = try #require(sections[sectionIndex].objects as? [NSManagedObject])
            #expect(typed.count == native.count)
            for row in typed.indices {
                #expect(typed[row] === native[row])
                #expect(typed[row] === controller.object(at: IndexPath(indexes: [sectionIndex, row])))
            }
        }
        #expect(objects(inSectionAt: 0, of: controller)?.map(\.position) == [1, 2])
    }

    @Test func availableEmptySectionReturnsAnEmptyArray() throws {
        let stack = try SectionTestStack()
        let controller = stack.controller(grouped: false)
        try controller.performFetch()

        let sections = try #require(controller.sections)
        #expect(sections.count == 1)
        let nativeSection = try #require(sections.first)
        let nativeObjects = try #require(nativeSection.objects)
        #expect(nativeObjects.isEmpty)
        let typed = try #require(objects(inSectionAt: 0, of: controller))
        #expect(typed.isEmpty)
    }

    @Test func emptyGroupedFetchPreservesNativeNoSectionsState() throws {
        let stack = try SectionTestStack()
        let controller = stack.controller()
        try controller.performFetch()
        let sections = try #require(controller.sections)
        #expect(sections.isEmpty)
        // With available but empty section information every index is invalid;
        // isolated probes cover the precondition without terminating this suite.
    }

    @Test func parentResultTypeAcceptsSubentityObjects() throws {
        let stack = try SectionTestStack()
        let child = stack.insert(category: "A", position: 1, special: true)
        let parent = stack.insert(category: "A", position: 2)
        try stack.context.save()
        let controller = stack.controller()
        try controller.performFetch()

        let typed: [SectionItem] = try #require(objects(inSectionAt: 0, of: controller))
        #expect(typed.count == 2)
        #expect(typed.first === child)
        #expect(typed.last === parent)
        #expect(typed.first is SpecialSectionItem)
    }
}
