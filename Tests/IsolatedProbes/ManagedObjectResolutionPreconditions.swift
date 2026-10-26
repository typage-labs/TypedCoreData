// Standalone subprocess probe. This deliberately violates the model/class
// invariant through a mismatched native designated initializer. It is injection
// coverage of the production guard, not a valid Core Data configuration.
// No attached model is mutated and no context or object ID is mocked.
import CoreData
import TypedCoreData

@objc(TypedCoreDataResolutionProbeExpected)
private final class ResolutionProbeExpected: NSManagedObject {}

@objc(TypedCoreDataResolutionProbeActual)
private final class ResolutionProbeActual: NSManagedObject {}

@main
private enum ManagedObjectResolutionPreconditionProbe {
    @MainActor
    static func main() throws {
        guard let scenario = CommandLine.arguments.dropFirst().first else {
            fatalError("Pass existing-object, object, or registered-object")
        }
        let entity = NSEntityDescription()
        entity.name = "ResolutionProbeRecord"
        entity.managedObjectClassName = NSStringFromClass(ResolutionProbeExpected.self)
        let model = NSManagedObjectModel()
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType,
            configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        // Intentional invalid input: the static initializer type disagrees with
        // the model. Core Data uses the model's Expected class at runtime, while
        // managedID retains the variable's static Actual type. Check that setup
        // explicitly before invoking any production resolver.
        let injected = ResolutionProbeActual(entity: entity, insertInto: context)
        let id: ManagedID<ResolutionProbeActual> = injected.managedID
        guard let registered = context.registeredObject(for: id.objectID),
              registered is ResolutionProbeExpected,
              !(registered is ResolutionProbeActual),
              context.object(with: id.objectID) === registered,
              try context.existingObject(with: id.objectID) === registered else {
            fatalError("Probe setup did not produce the injected native class mismatch")
        }

        switch scenario {
        case "existing-object":
            _ = try context.existingObject(with: id)
        case "object":
            _ = context.object(with: id)
        case "registered-object":
            _ = context.registeredObject(for: id)
        default:
            fatalError("Unknown resolver probe scenario: \(scenario)")
        }
        fatalError("Expected the production typed resolver's class precondition to fail")
    }
}
