import Foundation

/// Maps agent identifiers to adapter factories.
///
/// Adding an agent means registering a factory here — core runner logic never
/// changes. Factories receive the command-line agent options so adapters can
/// honor model overrides and pass-through arguments.
public struct AgentRegistry: Sendable {
    /// Adapter-facing options collected from the CLI.
    public struct Options: Sendable {
        public var model: String?
        /// Reasoning effort requested for the agent (e.g. low/medium/high).
        /// Applied by adapters whose CLI exposes control; recorded but not
        /// applied otherwise — never silently translated into invented flags.
        public var effort: String?
        /// Extra arguments forwarded verbatim to the agent CLI.
        public var additionalArguments: [String]

        public init(model: String? = nil, effort: String? = nil, additionalArguments: [String] = []) {
            self.model = model
            self.effort = effort
            self.additionalArguments = additionalArguments
        }
    }

    public typealias Factory = @Sendable (Options) -> any AgentAdapter

    private var factories: [String: Factory] = [:]

    public init() {}

    public mutating func register(_ identifier: String, factory: @escaping Factory) {
        factories[identifier] = factory
    }

    public func makeAdapter(identifier: String, options: Options) throws -> any AgentAdapter {
        guard let factory = factories[identifier] else {
            throw BenchmarkFailure.invalidTask(
                "Unknown agent '\(identifier)'. Registered agents: \(registeredIdentifiers.joined(separator: ", "))"
            )
        }
        return factory(options)
    }

    public var registeredIdentifiers: [String] {
        factories.keys.sorted()
    }
}
