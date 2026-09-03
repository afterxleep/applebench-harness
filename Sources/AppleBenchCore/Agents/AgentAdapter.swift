import Foundation

/// The seam between AppleBench and any external coding agent.
///
/// Adapters are thin process launchers: they expose the task prompt to the
/// agent, stream whatever telemetry the agent's CLI provides into the event
/// recorder, and report how the process ended. They never grade, never see
/// grader configuration, and never contain Apple-specific benchmark logic.
public protocol AgentAdapter: Sendable {
    /// Stable identifier used on the command line (`--agent codex`).
    var identifier: String { get }

    /// Describes how rich this adapter's telemetry is, for honest reporting.
    var telemetry: AgentTelemetryCapability { get }

    /// Verify the agent is invocable (binary present, etc.) and perform any
    /// per-run setup. Called before the workspace is handed over.
    func prepare(context: RunContext) async throws

    /// Launch the agent against the workspace and block until it exits or is
    /// terminated. Implementations must run the agent with the workspace as
    /// its working directory and must not enforce the wall-clock timeout
    /// themselves — the runner does.
    func run(
        task: BenchmarkTask,
        context: RunContext,
        recorder: EventRecorder
    ) async throws -> AgentRunResult

    /// Always called after the run, even on failure.
    func cleanup(context: RunContext) async
}

/// How much structure an adapter can genuinely extract from its agent.
public enum AgentTelemetryCapability: String, Sendable, Codable {
    /// Structured events: messages, tool calls, token usage.
    case structured
    /// Raw stdout/stderr with timestamps only.
    case plainText
}

public struct AgentMetadata: Sendable, Codable, Equatable {
    public var agent: String
    public var model: String?
    public var version: String?
    /// Adapter-specific configuration worth recording for reproducibility
    /// (flags, endpoints). Never secrets.
    public var configuration: [String: String]

    public init(agent: String, model: String? = nil, version: String? = nil, configuration: [String: String] = [:]) {
        self.agent = agent
        self.model = model
        self.version = version
        self.configuration = configuration
    }

    /// The reasoning effort this run asked for, or `nil` when it asked for
    /// none and took the provider's default.
    ///
    /// Effort changes both what a model scores and what it costs, so a report
    /// that omits it is not reproducible. It lives inside `configuration`
    /// because that is what the adapters already record and what existing
    /// `result.json` files already contain; `variant` is read as well as
    /// `effort` so runs recorded before the key was named stay readable.
    public var effort: String? {
        configuration["effort"] ?? configuration["variant"]
    }
}

/// Token/cost usage as observed by the adapter. All fields are optional:
/// adapters record what their agent actually reports and leave the rest
/// `nil` — never guessed values.
public struct AgentUsage: Sendable, Codable, Equatable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var estimatedCostUSD: Double?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        estimatedCostUSD: Double? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case estimatedCostUSD = "estimated_cost_usd"
    }
}

public enum AgentTerminationReason: String, Sendable, Codable {
    case completed
    case timeout
    case failed
    case cancelled
    /// Stopped by AppleBench for exceeding the task's token budget. Distinct
    /// from `timeout` because it says which limit bound the run, and a reader
    /// comparing two models needs to know a task was cut short on spend
    /// rather than on the clock.
    case budgetExceeded = "budget_exceeded"
}

public struct AgentRunResult: Sendable {
    public var metadata: AgentMetadata
    public var terminationReason: AgentTerminationReason
    public var exitCode: Int32?
    public var usage: AgentUsage
    /// The agent's final textual response, when the CLI surfaces one.
    public var finalResponse: String?

    public init(
        metadata: AgentMetadata,
        terminationReason: AgentTerminationReason,
        exitCode: Int32? = nil,
        usage: AgentUsage = AgentUsage(),
        finalResponse: String? = nil
    ) {
        self.metadata = metadata
        self.terminationReason = terminationReason
        self.exitCode = exitCode
        self.usage = usage
        self.finalResponse = finalResponse
    }
}
