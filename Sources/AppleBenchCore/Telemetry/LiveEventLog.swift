import Foundation

/// Renders a run's events as they happen, so a long task shows movement.
///
/// A task can spend ten minutes between "started" and a verdict, and silence
/// for that long is indistinguishable from a wedged simulator — which has
/// happened here often enough to be worth a line on screen. The events are
/// already recorded; this only shows them.
///
/// Two levels, because they answer different questions. `--stream` shows what
/// the run is *doing*: the commands it runs, the files it touches, the graders
/// it reaches. `--stream-output` adds what the model is *saying*, which is far
/// noisier and only worth it when the question is why a model went wrong.
public struct LiveEventLog: Sendable {
    public enum Level: String, Sendable, CaseIterable {
        /// Nothing. The default: a suite run's own progress lines are enough.
        case off
        /// Structure — tool calls, commands, graders.
        case activity
        /// Structure plus the model's own messages and reasoning.
        case output
    }

    private let level: Level
    private let write: @Sendable (String) -> Void

    public init(level: Level, write: (@Sendable (String) -> Void)? = nil) {
        self.level = level
        self.write = write ?? { line in
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }

    /// An observer for ``EventRecorder``, or `nil` when logging is off so the
    /// recorder does no work at all.
    public func observer() -> (@Sendable (BenchmarkEvent) -> Void)? {
        guard level != .off else { return nil }
        let level = level
        let write = write
        // Whether the agent is still running, so a command can be attributed to
        // the model or to the harness. Without it the two are indistinguishable
        // on screen: the uiflow grader drives the simulator through flowdeck
        // after the agent has exited, and an unlabelled `$ flowdeck ...` reads
        // as the model reaching for a wrapper the run explicitly denied it.
        let phase = PhaseTracker()
        return { event in
            let stage = phase.observe(event)
            guard let line = LiveEventLog.render(event, level: level) else { return }
            write("\(stage) \(line)")
        }
    }

    /// One line for an event, or `nil` when it is not worth showing.
    static func render(_ event: BenchmarkEvent, level: Level) -> String? {
        let stamp = timestamp(event.timestamp)
        switch event.type {
        case .agentStarted:
            return "\(stamp) agent started"
        case .agentFinished:
            return "\(stamp) agent finished\(field(event, "termination").map { " · \($0)" } ?? "")"
        case .commandStarted:
            guard let command = field(event, "command") ?? field(event, "executable") else { return nil }
            return "\(stamp) $ \(truncate(command, to: 140))"
        case .commandFinished:
            guard let command = field(event, "command") ?? field(event, "executable") else { return nil }
            let code = field(event, "exit_code") ?? "?"
            return "\(stamp) \(code == "0" ? "ok" : "exit \(code)") · \(truncate(command, to: 110))"
        case .graderStarted:
            return field(event, "grader").map { "\(stamp) grading: \($0)" }
        case .graderFinished:
            guard let grader = field(event, "grader") else { return nil }
            let passed = field(event, "passed") == "true"
            return "\(stamp) \(passed ? "PASS" : "FAIL") \(grader)"
        case .fileChanged:
            return field(event, "path").map { "\(stamp) edited \($0)" }
        case .warning:
            return field(event, "message").map { "\(stamp) !! \($0)" }
        case .simulatorReaped:
            return "\(stamp) !! reaped a stray simulator"
        case .agentEvent:
            // The adapter has already classified this one; a tool call is
            // structure, a message is the model talking.
            let kind = field(event, "kind") ?? ""
            if kind == "tool_call" {
                return field(event, "name").map { "\(stamp) tool: \($0)" }
            }
            guard level == .output else { return nil }
            guard let text = field(event, "text") ?? field(event, "message") else { return nil }
            return "\(stamp) « \(truncate(collapse(text), to: 180))"
        case .agentOutput:
            guard level == .output else { return nil }
            guard let text = field(event, "text") ?? field(event, "line") else { return nil }
            let collapsed = collapse(text)
            return collapsed.isEmpty ? nil : "\(stamp) « \(truncate(collapsed, to: 180))"
        case .commandOutput:
            // Deliberately not shown even at `output`: build logs are the bulk
            // of a run's bytes and drown everything worth reading. They are in
            // events.jsonl and in the per-grader logs.
            return nil
        default:
            return nil
        }
    }

    /// Tracks which side of the run an event belongs to.
    ///
    /// The agent and the harness both execute commands, and only one of them
    /// is being measured.
    final class PhaseTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var stage = "setup"

        func observe(_ event: BenchmarkEvent) -> String {
            lock.lock()
            defer { lock.unlock() }
            switch event.type {
            case .agentStarted: stage = "agent"
            case .agentFinished: stage = "harness"
            case .gradingStarted, .graderStarted: stage = "grading"
            default: break
            }
            return stage.padding(toLength: 7, withPad: " ", startingAt: 0)
        }
    }

    // MARK: - Payload access

    /// A payload value as a string, whatever JSON type it arrived as.
    static func field(_ event: BenchmarkEvent, _ key: String) -> String? {
        guard case .object(let payload) = event.payload, let value = payload[key] else { return nil }
        switch value {
        case .string(let text): return text.isEmpty ? nil : text
        case .int(let number): return String(number)
        case .double(let number): return String(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .array(let items): return items.isEmpty ? nil : items.compactMap {
            if case .string(let text) = $0 { return text } else { return nil }
        }.joined(separator: " ")
        case .object, .null: return nil
        }
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Newlines and runs of whitespace become single spaces, so one event
    /// stays on one line and the log remains scannable.
    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
