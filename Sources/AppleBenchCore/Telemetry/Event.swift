import Foundation

/// Everything AppleBench observes during a run is recorded as an ordered
/// stream of structured events, persisted as JSONL. The event log is the
/// ground truth for trajectory analysis; `result.json` metrics are derived
/// from it.
public struct BenchmarkEvent: Sendable, Codable, Equatable {
    public var sequence: Int
    public var timestamp: Date
    public var runID: String
    public var type: BenchmarkEventType
    public var payload: JSONValue

    public init(sequence: Int, timestamp: Date, runID: String, type: BenchmarkEventType, payload: JSONValue = .object([:])) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.runID = runID
        self.type = type
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case sequence, timestamp, type, payload
        case runID = "run_id"
    }
}

public enum BenchmarkEventType: String, Sendable, Codable, Equatable {
    case runStarted = "run_started"
    case environmentCaptured = "environment_captured"
    case workspaceCreated = "workspace_created"
    case simulatorPrepared = "simulator_prepared"
    case agentStarted = "agent_started"
    case agentOutput = "agent_output"
    /// A structured event surfaced by the agent's own output stream
    /// (tool call, message, usage report) when the adapter can parse one.
    case agentEvent = "agent_event"
    case agentFinished = "agent_finished"
    case commandStarted = "command_started"
    case commandOutput = "command_output"
    case commandFinished = "command_finished"
    case fileChanged = "file_changed"
    /// The fixture's graded tests were overlaid onto the workspace, after the
    /// agent exited and after its diff was captured.
    case verificationMaterialised = "verification_materialised"
    case gradingStarted = "grading_started"
    case graderStarted = "grader_started"
    case graderFinished = "grader_finished"
    case artifactCreated = "artifact_created"
    case runFinished = "run_finished"
    case warning = "warning"
}

/// A JSON-representable value used for event payloads, keeping the event
/// schema open without resorting to `[String: Any]`.
public enum JSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        default: return nil
        }
    }
}
