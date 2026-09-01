import Foundation

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
        case other
    }

    public var kind: Kind
    /// The structured payload as parsed, preserved verbatim.
    public var payload: JSONValue
    /// Token usage carried by this event, if any.
    public var usage: AgentUsage?
    /// The agent's final response text, if this event carries it.
    public var finalResponse: String?

    public init(kind: Kind, payload: JSONValue, usage: AgentUsage? = nil, finalResponse: String? = nil) {
        self.kind = kind
        self.payload = payload
        self.usage = usage
        self.finalResponse = finalResponse
    }
}

/// Parses one line of agent stdout into a structured event, or `nil` when the
/// line carries no structure this parser understands.
public protocol AgentOutputParser: Sendable {
    func parse(line: String) -> ParsedAgentEvent?
}
