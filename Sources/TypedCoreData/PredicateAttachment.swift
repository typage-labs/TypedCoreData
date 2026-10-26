import CoreData
import Foundation

/// A native Swift predicate could not be converted to `NSPredicate`.
///
/// This error describes Foundation conversion only. A successful conversion
/// does not establish that a Core Data model or persistent store supports the
/// expression. Native fetch errors and Objective-C exceptions remain native.
public enum PredicateConversionError: Error, Equatable, Sendable {
    /// Foundation's failable `NSPredicate` initializer returned `nil`.
    case unsupportedPredicate
}

/// Attaches a native Swift predicate with the same root as the request.
///
/// Uses Foundation's failable `NSPredicate` conversion. Conversion must
/// succeed before the request is changed, so failure preserves the previous
/// predicate, including `nil`. No in-memory filtering or unfiltered fetch
/// is used as a fallback.
///
/// A single generic parameter ties the predicate root to the request's
/// result type. This is a free function because Swift cannot access a
/// generic Objective-C class's type parameter at runtime from an extension.
/// The root type is checked by Swift, but the request's runtime entity and
/// the store's expression support remain Core Data concerns. Successful
/// conversion does not guarantee SQLite compatibility or the same results
/// as Swift predicate evaluation. In particular, optional comparisons and
/// their negations retain Core Data's native nil semantics.
///
/// Configure and execute the request according to the context's queue rules;
/// do not mutate a request concurrently. This function schedules no work.
///
/// - Parameters:
///   - predicate: A predicate whose input matches the request's result type.
///   - request: The native request to configure.
/// - Throws: ``PredicateConversionError/unsupportedPredicate`` if Foundation
///   cannot convert the expression. The request remains unchanged.
@available(iOS 17, macOS 14, *)
public func setPredicate<Entity: NSManagedObject>(
    _ predicate: Predicate<Entity>,
    on request: NSFetchRequest<Entity>
) throws {
    guard let native = NSPredicate(predicate) else {
        throw PredicateConversionError.unsupportedPredicate
    }
    request.predicate = native
}
