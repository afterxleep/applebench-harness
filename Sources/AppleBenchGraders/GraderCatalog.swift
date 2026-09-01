import AppleBenchCore

/// Wires all built-in graders into a registry. Adding a grader type means
/// extending this catalog — core runner logic never changes.
public enum GraderCatalog {
    public static func defaultRegistry() -> GraderRegistry {
        var registry = GraderRegistry()
        registry.register { specification in
            switch specification {
            case .build(let configuration):
                BuildGrader(configuration: configuration)
            case .xctest(let configuration):
                XCTestGrader(configuration: configuration, identifier: "xctest")
            case .xcuitest(let configuration):
                XCTestGrader(configuration: configuration, identifier: "xcuitest")
            case .file(let configuration):
                FileGrader(configuration: configuration)
            case .runtime(let configuration):
                RuntimeGrader(configuration: configuration)
            case .xcodeproj(let configuration):
                XcodeprojGrader(configuration: configuration)
            }
        }
        return registry
    }
}
