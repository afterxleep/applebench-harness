import Foundation

/// Maps grader specifications to grader implementations.
///
/// Grader implementations live outside core (in `AppleBenchGraders`); the
/// registry is how they plug in without the runner knowing concrete types.
public struct GraderRegistry: Sendable {
    public typealias Factory = @Sendable (GraderSpecification) -> (any Grader)?

    private var factories: [Factory] = []

    public init() {}

    public mutating func register(_ factory: @escaping Factory) {
        factories.append(factory)
    }

    public func makeGrader(for specification: GraderSpecification) throws -> any Grader {
        for factory in factories {
            if let grader = factory(specification) {
                return grader
            }
        }
        throw BenchmarkFailure.invalidTask("No grader registered for type '\(specification.type.rawValue)'")
    }
}
