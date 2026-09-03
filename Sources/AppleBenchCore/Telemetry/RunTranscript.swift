import Foundation

/// A readable record of one task: what the model was asked, what it thought,
/// what it ran, and what it said.
///
/// `events.jsonl` already holds all of this, and is unreadable on purpose: it
/// is a machine record with one JSON object per line, and the agent's own
/// output arrives inside it as further JSON. Answering "what did this model
/// actually do on ui-auto-010" meant writing a parser every time. This is that
/// parser, written once.
///
/// It reads both shapes an agent's output arrives in. An adapter that parses
/// its CLI records `agent_event` with the part already extracted; one that
/// cannot records the raw stdout line. Older runs are the second kind, so the
/// raw path is not a fallback for broken data — it is how most of the archive
/// is stored.
public enum RunTranscript {
    /// Renders the transcript for a finished run.
    public static func render(
        task: BenchmarkTask,
        result: BenchmarkRunResult,
        events: [BenchmarkEvent]
    ) -> String {
        var out: [String] = []

        out.append("# \(task.id): \(task.title)")
        out.append("")
        out.append("model     \(result.agent.model ?? "default")")
        out.append("effort    \(result.agent.effort ?? "provider default")")
        out.append("agent     \(result.agent.agent)\(result.agent.version.map { " \($0)" } ?? "")")
        out.append("run       \(result.runID)")
        out.append("verdict   \(result.result.passed ? "PASS" : "FAIL") "
            + "· \(result.result.agentTermination.rawValue) "
            + "· \(String(format: "%.0fs", result.result.durationSeconds))")
        if let tokens = result.usage.totalTokens {
            var line = "tokens    \(tokens)"
            if let prompt = result.usage.promptTokens { line += " (\(prompt) prompt)" }
            out.append(line)
        }
        out.append("")

        out.append("## Prompt")
        out.append("")
        out.append(task.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        out.append("")

        // Split by phase. Reading a transcript to decide whether a verdict is
        // sound means telling what the model did from what the harness did to
        // it afterwards, and the two are interleaved in the event stream.
        let (agent, grading) = entries(from: events)

        out.append("## What the model did")
        out.append("")
        out.append(agent.isEmpty ? "(the agent produced no readable output)" : agent.joined(separator: "\n\n"))
        out.append("")

        out.append("## How it was graded")
        out.append("")
        for grader in result.graders {
            out.append("\(grader.passed ? "PASS" : "FAIL")  \(grader.name)  \(grader.summary)")
            for evidence in grader.evidence {
                out.append("      evidence: \(evidence.path)")
            }
        }
        if !grading.isEmpty {
            out.append("")
            out.append("Commands the graders ran:")
            out.append("")
            out.append(grading.joined(separator: "\n"))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// One block per thing that happened, split into what the agent did and
    /// what the graders did afterwards.
    static func entries(from events: [BenchmarkEvent]) -> (agent: [String], grading: [String]) {
        var entries: [String] = []
        var grading: [String] = []
        var isGrading = false
        for event in events {
            switch event.type {
            case .agentFinished, .gradingStarted, .verificationMaterialised:
                isGrading = true
            case .agentEvent:
                if let part = payload(event, "data"), let entry = describe(part) {
                    entries.append(entry)
                }
            case .agentOutput:
                // Raw stdout: one JSON object per line, each carrying a part.
                guard let text = string(event, "text") else { continue }
                for line in text.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("{"),
                          let data = trimmed.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }
                    if let entry = describe(object["part"] as? [String: Any] ?? object) {
                        entries.append(entry)
                    }
                }
            case .commandStarted:
                guard let command = string(event, "command") ?? string(event, "executable") else {
                    continue
                }
                if isGrading { grading.append("$ \(command)") } else { entries.append("$ \(command)") }
            default:
                continue
            }
        }
        return (entries, grading)
    }

    /// Renders one OpenCode part, or nothing when it is bookkeeping.
    ///
    /// `step-start` and `step-finish` carry token counts and no content; they
    /// belong in the usage totals, not in a record of what the model said.
    static func describe(_ part: [String: Any]) -> String? {
        switch part["type"] as? String {
        case "text":
            guard let text = (part["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        case "reasoning":
            // The model's own thinking, kept verbatim and marked as thinking so
            // it is never mistaken for something it told the user.
            let text = (part["text"] as? String ?? part["reasoning"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : "[reasoning]\n\(text)"
        case "tool":
            let name = part["tool"] as? String ?? "tool"
            var block = "[tool: \(name)]"
            if let state = part["state"] as? [String: Any] {
                if let input = state["input"] as? [String: Any], !input.isEmpty {
                    block += "\n  in:  " + summarise(input)
                }
                if let output = state["output"] as? String {
                    let flat = output.split(whereSeparator: \.isNewline).joined(separator: " ")
                    block += "\n  out: " + String(flat.prefix(600))
                        + (flat.count > 600 ? "…" : "")
                }
            }
            return block
        default:
            return nil
        }
    }

    /// A tool's arguments on one line, longest values clipped.
    static func summarise(_ input: [String: Any]) -> String {
        input.keys.sorted().map { key in
            let value = String(describing: input[key] ?? "")
                .split(whereSeparator: \.isNewline).joined(separator: " ")
            return "\(key)=\(value.count > 200 ? String(value.prefix(200)) + "…" : value)"
        }
        .joined(separator: " ")
    }

    // MARK: - Payload access

    static func string(_ event: BenchmarkEvent, _ key: String) -> String? {
        guard case .object(let payload) = event.payload,
              case .string(let value)? = payload[key] else { return nil }
        return value
    }

    static func payload(_ event: BenchmarkEvent, _ key: String) -> [String: Any]? {
        guard case .object(let payload) = event.payload, let nested = payload[key],
              let data = try? JSONEncoder().encode(nested),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (object["part"] as? [String: Any]) ?? object
    }

    /// `minimax/MiniMax-M2.7` becomes `minimax-m2-7`, so a model gets one
    /// folder rather than one per spelling of its name.
    public static func slug(for model: String?) -> String {
        guard let model, !model.isEmpty else { return "default" }
        let name = model.split(separator: "/").last.map(String.init) ?? model
        let mapped = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "default" : collapsed
    }

    /// Writes the transcript and returns where it went.
    ///
    /// One file per task inside a folder per model, so a re-run overwrites the
    /// task it re-ran and leaves the rest of that model's history alone.
    @discardableResult
    public static func write(
        task: BenchmarkTask,
        result: BenchmarkRunResult,
        events: [BenchmarkEvent],
        root: URL
    ) throws -> URL {
        let directory = root.appendingPathComponent(slug(for: result.agent.model), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(task.id).log")
        try render(task: task, result: result, events: events).write(
            to: url, atomically: true, encoding: .utf8
        )
        return url
    }
}
