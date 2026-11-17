import Foundation

/// Aggregate metrics derived from a run's event stream.
///
/// These are computed by AppleBench from what it observed — never taken from
/// agent self-reporting. Counters that depend on adapter telemetry richness
/// (tool calls, agent events) reflect what the adapter could actually parse;
/// adapters that only expose raw stdout produce zero tool-call counts, which
/// is honest rather than wrong.
public struct TrajectoryMetrics: Sendable, Codable, Equatable {
    public var totalEvents: Int
    /// Structured agent events the adapter could parse (messages, tool calls, usage reports).
    public var agentEvents: Int
    /// Tool calls surfaced by the agent's structured output, when available.
    public var toolCalls: Int
    /// Raw output chunks captured from the agent process.
    public var agentOutputChunks: Int
    public var agentOutputBytes: Int
    /// Shell commands AppleBench itself executed during the run (grading included).
    public var commandsExecuted: Int
    public var buildInvocations: Int
    public var testInvocations: Int
    public var agentDurationSeconds: Double?
    public var gradingDurationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case totalEvents = "total_events"
        case agentEvents = "agent_events"
        case toolCalls = "tool_calls"
        case agentOutputChunks = "agent_output_chunks"
        case agentOutputBytes = "agent_output_bytes"
        case commandsExecuted = "commands_executed"
        case buildInvocations = "build_invocations"
        case testInvocations = "test_invocations"
        case agentDurationSeconds = "agent_duration_seconds"
        case gradingDurationSeconds = "grading_duration_seconds"
    }

    public init(events: [BenchmarkEvent]) {
        totalEvents = events.count
        agentEvents = events.count { $0.type == .agentEvent }
        toolCalls = events.count { event in
            event.type == .agentEvent && event.payload["kind"]?.stringValue == "tool_call"
        }

        let outputEvents = events.filter { $0.type == .agentOutput }
        agentOutputChunks = outputEvents.count
        agentOutputBytes = outputEvents.reduce(0) { total, event in
            total + (event.payload["text"]?.stringValue?.utf8.count ?? 0)
        }

        let finishedCommands = events.filter { $0.type == .commandFinished }
        commandsExecuted = finishedCommands.count
        buildInvocations = finishedCommands.count { event in
            guard let command = event.payload["command"]?.stringValue else { return false }
            return command.contains("xcodebuild") && !command.contains(" test")
        }
        testInvocations = finishedCommands.count { event in
            guard let command = event.payload["command"]?.stringValue else { return false }
            return command.contains("xcodebuild") && command.contains(" test")
        }

        agentDurationSeconds = Self.interval(in: events, from: .agentStarted, to: .agentFinished)
        gradingDurationSeconds = Self.interval(in: events, from: .gradingStarted, to: .runFinished)
    }

    private static func interval(
        in events: [BenchmarkEvent],
        from start: BenchmarkEventType,
        to end: BenchmarkEventType
    ) -> Double? {
        guard
            let started = events.first(where: { $0.type == start }),
            let finished = events.last(where: { $0.type == end })
        else { return nil }
        return finished.timestamp.timeIntervalSince(started.timestamp)
    }
}
