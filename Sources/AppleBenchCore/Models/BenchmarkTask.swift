import Foundation

/// The capabilities AppleBench measures.
///
/// The set is skewed toward Apple frameworks and operational toolchain
/// work. Language-level Swift and concurrency belong to other benches.
public enum BenchmarkCategory: String, Sendable, Codable, Equatable, CaseIterable {
    /// Understanding Xcode/compiler failures.
    case build
    /// Diagnose → fix → rerun against existing tests.
    case tests
    /// Problems invisible at compile time.
    case runtime
    /// Reading a design spec and fixing layout.
    case visual
    /// Running and driving the simulator.
    case interaction
    /// Apple-specific project configuration.
    case project
    /// Apple framework APIs: SwiftData, Core Data, WidgetKit, App Intents.
    case frameworks
    /// Operational Apple-platform engineering: build, test, run, clean,
    /// manage simulators, stream logs, and exercise the same surface as
    /// a wrapper CLI (e.g. FlowDeck) but using only raw `xcodebuild`,
    /// `simctl`, `devicectl`, and friends.
    case ops
}

/// A declarative benchmark task, loaded from YAML.
///
/// A task couples a natural-language prompt with the exact repository state,
/// Apple-platform environment requirements, execution limits, and the graders
/// that independently verify the agent's work.
public struct BenchmarkTask: Sendable, Codable, Equatable {
    /// The valid difficulty range. Difficulty is comparative within a
    /// category, not an absolute scale across the set.
    ///
    /// d1...d5 are the calibration tier: single-bug, fast tasks that
    /// almost any agent passes. d6...d10 are the capability tier: multi-bug,
    /// real-spec, race-condition-bearing tasks where only top models pass.
    public static let difficultyRange = 1...10

    public var id: String
    public var title: String
    /// The capability this task measures. Optional in the model so ad-hoc and
    /// third-party tasks stay loadable; every shipped task declares one.
    public var category: BenchmarkCategory?
    /// 1...10 within the category. Validated at load time when present.
    public var difficulty: Int?
    public var repository: RepositorySpecification
    public var prompt: String
    public var environment: EnvironmentRequirements
    public var limits: RunLimits
    /// Graders may be absent in the public half of a split task/evaluation
    /// distribution; they are then supplied separately (see `EvaluationFile`).
    public var graders: [GraderSpecification]
    /// Free-form labels for filtering and reporting (`threading`, `swiftui`).
    /// Carries no structural meaning — `category` does.
    public var tags: [String]

    public init(
        id: String,
        title: String,
        category: BenchmarkCategory? = nil,
        difficulty: Int? = nil,
        repository: RepositorySpecification,
        prompt: String,
        environment: EnvironmentRequirements,
        limits: RunLimits = RunLimits(),
        graders: [GraderSpecification] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.difficulty = difficulty
        self.repository = repository
        self.prompt = prompt
        self.environment = environment
        self.limits = limits
        self.graders = graders
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case id, title, category, difficulty, repository, prompt, environment, limits, graders, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decodeIfPresent(BenchmarkCategory.self, forKey: .category)
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty)
        repository = try container.decode(RepositorySpecification.self, forKey: .repository)
        prompt = try container.decode(String.self, forKey: .prompt)
        environment = try container.decode(EnvironmentRequirements.self, forKey: .environment)
        limits = try container.decodeIfPresent(RunLimits.self, forKey: .limits) ?? RunLimits()
        graders = try container.decodeIfPresent([GraderSpecification].self, forKey: .graders) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// The repository and exact commit a task runs against.
public struct RepositorySpecification: Sendable, Codable, Equatable {
    /// A git URL or a local filesystem path.
    public var url: String
    /// The commit to check out. `HEAD` is allowed for local development fixtures.
    public var commit: String

    public init(url: String, commit: String) {
        self.url = url
        self.commit = commit
    }
}

/// The Apple-platform environment a task requires.
public struct EnvironmentRequirements: Sendable, Codable, Equatable {
    public var xcode: String?
    public var platform: BenchmarkPlatform
    public var simulator: SimulatorRequirement?

    public init(xcode: String? = nil, platform: BenchmarkPlatform, simulator: SimulatorRequirement? = nil) {
        self.xcode = xcode
        self.platform = platform
        self.simulator = simulator
    }
}

public enum BenchmarkPlatform: String, Sendable, Codable, Equatable {
    case ios
    case macos
}

public struct SimulatorRequirement: Sendable, Codable, Equatable {
    /// Device name, e.g. "iPhone 17 Pro".
    public var device: String
    /// Runtime name, e.g. "iOS 27.0".
    public var runtime: String

    public init(device: String, runtime: String) {
        self.device = device
        self.runtime = runtime
    }
}
