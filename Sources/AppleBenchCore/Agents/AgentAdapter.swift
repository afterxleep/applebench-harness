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

/// Where an adapter's binary lives, when it has one on disk.
///
/// The sandbox needs it: the agent has to be allowed to execute itself while
/// everything outside the toolchain is refused.
public extension AgentAdapter {
    var executableURL: URL? { nil }
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
    /// Fresh input tokens — the part of the prompt that was not served from
    /// the provider's cache, and is billed at the full input rate.
    public var inputTokens: Int?
    public var outputTokens: Int?
    /// Prompt tokens served from cache, billed at the (much lower) cache-read
    /// rate.
    ///
    /// These dominate an agentic run: each step re-sends the whole
    /// conversation, so cache reads outnumber fresh input roughly seven to one
    /// here. Leaving them out does not merely lose a rounding error — it
    /// understates what the model was actually asked to read by most of it,
    /// and any cost computed from the remainder is far too low.
    public var cacheReadTokens: Int?
    /// Prompt tokens written into the cache, billed at the cache-write rate.
    public var cacheWriteTokens: Int?
    public var totalTokens: Int?
    public var estimatedCostUSD: Double?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        totalTokens: Int? = nil,
        estimatedCostUSD: Double? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    /// Every prompt token the model read, cached or not. `nil` when nothing
    /// was reported, because a run with no usage did not read nothing.
    public var promptTokens: Int? {
        let parts = [inputTokens, cacheReadTokens, cacheWriteTokens].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
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

    /// True when the agent process died without ever reaching the model.
    ///
    /// Grading carries on regardless: the fixture builds, its tests run, and
    /// the task records a FAIL indistinguishable from a model that tried and
    /// missed. A whole suite of those looks like a score of zero. Treating it
    /// as an infrastructure error instead keeps a broken harness out of the
    /// results.
    ///
    /// Spending a token or answering at all is proof enough that it ran, so a
    /// model that crashed mid-task still counts against it. Timeouts and
    /// budget stops are the harness ending a working model, never this.
    public var neverRan: Bool {
        guard terminationReason == .failed, (exitCode ?? 0) != 0 else { return false }
        return (usage.totalTokens ?? 0) == 0
            && (finalResponse?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
