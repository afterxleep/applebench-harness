import Foundation

/// The stable machine-readable record of one run, serialized as `result.json`.
public struct BenchmarkRunResult: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var task: String
    /// The task's category, so results can be grouped without re-reading the
    /// task file.
    public var category: BenchmarkCategory?
    public var difficulty: Int?
    public var tags: [String]
    public var agent: AgentMetadata
    public var environment: EnvironmentSummary
    public var result: Outcome
    public var usage: AgentUsage
    public var metrics: TrajectoryMetrics?
    public var graders: [GraderOutcome]
    public var git: GitSummary
    public var artifacts: ArtifactIndex

    public struct Outcome: Sendable, Codable, Equatable {
        /// Overall verdict: all required graders passed.
        public var passed: Bool
        public var durationSeconds: Double
        /// How the agent phase ended. A timeout here can coexist with
        /// `passed == true` — the workspace may still grade successfully;
        /// both facts are recorded, never collapsed.
        public var agentTermination: AgentTerminationReason

        enum CodingKeys: String, CodingKey {
            case passed
            case durationSeconds = "duration_seconds"
            case agentTermination = "agent_termination"
        }

        public init(passed: Bool, durationSeconds: Double, agentTermination: AgentTerminationReason) {
            self.passed = passed
            self.durationSeconds = durationSeconds
            self.agentTermination = agentTermination
        }
    }

    public struct EnvironmentSummary: Sendable, Codable, Equatable {
        public var macos: String
        public var architecture: String
        public var xcode: String
        public var xcodeBuild: String
        public var simulator: String?
        public var runtime: String?

        enum CodingKeys: String, CodingKey {
            case macos, architecture, xcode, simulator, runtime
            case xcodeBuild = "xcode_build"
        }

        public init(
            macos: String,
            architecture: String,
            xcode: String,
            xcodeBuild: String,
            simulator: String? = nil,
            runtime: String? = nil
        ) {
            self.macos = macos
            self.architecture = architecture
            self.xcode = xcode
            self.xcodeBuild = xcodeBuild
            self.simulator = simulator
            self.runtime = runtime
        }
    }

    public struct GraderOutcome: Sendable, Codable, Equatable {
        public var name: String
        public var passed: Bool
        public var durationSeconds: Double
        public var summary: String
        public var evidence: [Artifact]

        enum CodingKeys: String, CodingKey {
            case name, passed, summary, evidence
            case durationSeconds = "duration_seconds"
        }

        public init(name: String, passed: Bool, durationSeconds: Double, summary: String, evidence: [Artifact]) {
            self.name = name
            self.passed = passed
            self.durationSeconds = durationSeconds
            self.summary = summary
            self.evidence = evidence
        }

        public init(_ result: GradingResult) {
            self.init(
                name: result.grader,
                passed: result.passed,
                durationSeconds: result.duration.seconds,
                summary: result.summary,
                evidence: result.evidence
            )
        }
    }

    public struct GitSummary: Sendable, Codable, Equatable {
        public var baseCommit: String
        public var finalCommit: String?
        public var filesChanged: Int
        public var insertions: Int
        public var deletions: Int

        enum CodingKeys: String, CodingKey {
            case baseCommit = "base_commit"
            case finalCommit = "final_commit"
            case filesChanged = "files_changed"
            case insertions, deletions
        }

        public init(baseCommit: String, finalCommit: String? = nil, filesChanged: Int, insertions: Int, deletions: Int) {
            self.baseCommit = baseCommit
            self.finalCommit = finalCommit
            self.filesChanged = filesChanged
            self.insertions = insertions
            self.deletions = deletions
        }
    }

    public struct ArtifactIndex: Sendable, Codable, Equatable {
        public var events: String
        public var diff: String?
        public var logs: String?

        public init(events: String, diff: String? = nil, logs: String? = nil) {
            self.events = events
            self.diff = diff
            self.logs = logs
        }
    }

    enum CodingKeys: String, CodingKey {
        case task, category, difficulty, tags, agent, environment, result, usage, metrics, graders, git, artifacts
        case schemaVersion = "schema_version"
        case runID = "run_id"
    }

    public init(
        runID: String,
        task: String,
        category: BenchmarkCategory? = nil,
        difficulty: Int? = nil,
        tags: [String] = [],
        agent: AgentMetadata,
        environment: EnvironmentSummary,
        result: Outcome,
        usage: AgentUsage,
        metrics: TrajectoryMetrics?,
        graders: [GraderOutcome],
        git: GitSummary,
        artifacts: ArtifactIndex
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.task = task
        self.category = category
        self.difficulty = difficulty
        self.tags = tags
        self.agent = agent
        self.environment = environment
        self.result = result
        self.usage = usage
        self.metrics = metrics
        self.graders = graders
        self.git = git
        self.artifacts = artifacts
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url)
    }

    public static func read(from url: URL) throws -> BenchmarkRunResult {
        try JSONDecoder().decode(BenchmarkRunResult.self, from: Data(contentsOf: url))
    }
}
