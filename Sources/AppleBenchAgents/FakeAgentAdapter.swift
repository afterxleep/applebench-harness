import AppleBenchCore
import Foundation

/// A scriptable agent for testing the harness itself (Phase 3 of the
/// execution plan and the unit/integration test suites).
///
/// The `actions` closure receives the run context and may edit the workspace
/// however a real agent would. Registered on the CLI as `fake` so the full
/// pipeline can be smoke-tested without spending agent tokens; the default
/// registration performs no edits.
public struct FakeAgentAdapter: AgentAdapter {
    public let identifier = "fake"
    public let telemetry = AgentTelemetryCapability.plainText

    private let actions: @Sendable (RunContext) async throws -> Void

    public init(actions: @escaping @Sendable (RunContext) async throws -> Void = { _ in }) {
        self.actions = actions
    }

    public func prepare(context: RunContext) async throws {}

    public func run(
        task: BenchmarkTask,
        context: RunContext,
        recorder: EventRecorder
    ) async throws -> AgentRunResult {
        await recorder.record(.agentOutput, payload: .object([
            "stream": .string("stdout"),
            "text": .string("fake agent: executing scripted actions"),
        ]))
        try await actions(context)
        return AgentRunResult(
            metadata: AgentMetadata(agent: identifier, model: nil, version: "0"),
            terminationReason: .completed,
            exitCode: 0,
            finalResponse: "fake agent completed scripted actions"
        )
    }

    public func cleanup(context: RunContext) async {}
}

/// Registers the built-in adapters. AppleBench ships two real harnesses —
/// OpenCode (multi-provider, one harness across every model) and
/// Claude Code (Anthropic-only, the local `claude` CLI) — plus two
/// in-process adapters used to check the fixtures themselves:
/// `fake` changes nothing (a sound fixture must FAIL) and
/// `solution` applies the reference fix (a sound fixture must
/// PASS). Additional harnesses plug in here through the same
/// `AgentAdapter` seam without touching core runner logic.
public enum AgentCatalog {
    public static func defaultRegistry() -> AgentRegistry {
        var registry = AgentRegistry()
        registry.register("opencode") { OpenCodeAdapter(options: $0) }
        registry.register("claude") { ClaudeCodeAdapter(options: $0) }
        registry.register("fake") { _ in FakeAgentAdapter() }
        registry.register("solution") { _ in SolutionAgentAdapter() }
        return registry
    }
}
