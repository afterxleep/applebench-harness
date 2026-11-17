import Foundation

/// A named collection of task identifiers, loaded from YAML.
public struct BenchmarkSuite: Sendable, Codable, Equatable {
    public var id: String
    public var name: String
    public var tasks: [String]

    public init(id: String, name: String, tasks: [String]) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}
