import Foundation

/// A structured failure reported by an agent CLI before a model response.
public struct AgentReportedFailure: Sendable, Equatable {
    public var message: String
    public var statusCode: Int?
    public var isRetryable: Bool

    public init(message: String, statusCode: Int? = nil, isRetryable: Bool) {
        self.message = message
        self.statusCode = statusCode
        self.isRetryable = isRetryable
    }

    public var summary: String {
        statusCode.map { "\(message) (HTTP \($0))" } ?? message
    }
}

/// A structured event extracted from an agent CLI's output stream.
///
/// Different CLIs expose very different observability. Where a CLI emits
/// structured output (JSONL event streams), an `AgentOutputParser` turns each
/// line into one of these; where only plain text is available, no parser is
/// used and AppleBench records raw stdout/stderr with timestamps. Tool-call
/// information is never fabricated from terminal strings.
public struct ParsedAgentEvent: Sendable {
    public enum Kind: String, Sendable {
        case message
        case toolCall = "tool_call"
        case usage
        case result
        case error
        case other
    }

    public var kind: Kind
    /// The structured payload as parsed, preserved verbatim.
    public var payload: JSONValue
    /// Token usage carried by this event, if any.
    public var usage: AgentUsage?
    /// The agent's final response text, if this event carries it.
    public var finalResponse: String?
    /// A provider or agent failure surfaced by this event, if present.
    public var failure: AgentReportedFailure?

    public init(
        kind: Kind,
        payload: JSONValue,
        usage: AgentUsage? = nil,
        finalResponse: String? = nil,
        failure: AgentReportedFailure? = nil
    ) {
        self.kind = kind
        self.payload = payload
        self.usage = usage
        self.finalResponse = finalResponse
        self.failure = failure
    }
}

/// Parses one line of agent stdout into a structured event, or `nil` when the
/// line carries no structure this parser understands.
public protocol AgentOutputParser: Sendable {
    func parse(line: String) -> ParsedAgentEvent?
}

/// Usage observed while an agent process is still running.
///
/// The runner normally receives final usage from the adapter. Its independent
/// timeout backstop can cancel an adapter before that return happens, though,
/// so streamed usage must also have a small, shared landing place. Parsing is
/// synchronous under a lock because process output callbacks are synchronous
/// and may arrive in arbitrary chunks.
public final class AgentProgressTracker: @unchecked Sendable {
    public struct Snapshot: Sendable, Equatable {
        public var usage: AgentUsage
        public var finalResponse: String?
    }

    private let lock = NSLock()
    private var pending = ""
    private var usage = AgentUsage()
    private var finalResponse: String?

    public init() {}

    public func observe(_ text: String, parser: any AgentOutputParser) {
        lock.withLock {
            pending += text
            while let newline = pending.firstIndex(of: "\n") {
                let line = String(pending[pending.startIndex..<newline])
                pending = String(pending[pending.index(after: newline)...])
                guard let event = parser.parse(line: line) else { continue }
                if let update = event.usage {
                    usage = Self.accumulate(usage, update)
                }
                if let response = event.finalResponse {
                    finalResponse = response
                }
            }
        }
    }

    public func snapshot() -> Snapshot {
        lock.withLock { Snapshot(usage: usage, finalResponse: finalResponse) }
    }

    private static func accumulate(_ current: AgentUsage, _ update: AgentUsage) -> AgentUsage {
        func add(_ lhs: Int?, _ rhs: Int?) -> Int? {
            if lhs == nil && rhs == nil { return nil }
            return (lhs ?? 0) + (rhs ?? 0)
        }
        func add(_ lhs: Double?, _ rhs: Double?) -> Double? {
            if lhs == nil && rhs == nil { return nil }
            return (lhs ?? 0) + (rhs ?? 0)
        }
        return AgentUsage(
            inputTokens: add(current.inputTokens, update.inputTokens),
            outputTokens: add(current.outputTokens, update.outputTokens),
            cacheReadTokens: add(current.cacheReadTokens, update.cacheReadTokens),
            cacheWriteTokens: add(current.cacheWriteTokens, update.cacheWriteTokens),
            totalTokens: add(current.totalTokens, update.totalTokens),
            estimatedCostUSD: add(current.estimatedCostUSD, update.estimatedCostUSD)
        )
    }
}
