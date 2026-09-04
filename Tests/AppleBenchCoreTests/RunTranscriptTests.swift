import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Run transcript")
struct RunTranscriptTests {
    /// A tool part as OpenCode emits it.
    private func toolPart(
        name: String = "bash",
        input: [String: Any] = [:],
        output: String? = nil
    ) -> [String: Any] {
        var state: [String: Any] = ["input": input]
        if let output { state["output"] = output }
        return ["type": "tool", "tool": name, "state": state]
    }

    @Test("A long tool output is kept whole")
    func toolOutputIsNotTruncated() throws {
        // The transcript exists to answer "was this graded correctly", and the
        // evidence for that is usually near the end of a long build log.
        let output = (1...400).map { "line \($0)" }.joined(separator: "\n")
        let rendered = try #require(RunTranscript.describe(toolPart(output: output)))
        #expect(rendered.contains("line 1"))
        #expect(rendered.contains("line 400"))
        #expect(!rendered.contains("…"))
    }

    @Test("A long tool argument is kept whole")
    func toolInputIsNotTruncated() throws {
        // The file an agent wrote is the argument, not the output. Clipping it
        // hides the change the verdict is about.
        let content = String(repeating: "x", count: 5_000)
        let rendered = try #require(
            RunTranscript.describe(toolPart(name: "write", input: ["content": content]))
        )
        #expect(rendered.contains(content))
    }

    @Test("A multi-line argument keeps its lines")
    func multiLineArgumentsStayReadable() throws {
        let rendered = try #require(
            RunTranscript.describe(toolPart(name: "write", input: ["content": "first\nsecond"]))
        )
        #expect(rendered.contains("first"))
        #expect(rendered.contains("second"))
        // Flattening a written file onto one line makes it unreadable, which
        // is the same as losing it.
        #expect(!rendered.contains("first second"))
    }

    @Test("Reasoning is kept verbatim and marked as thinking")
    func reasoningIsMarked() throws {
        let rendered = try #require(
            RunTranscript.describe(["type": "reasoning", "text": "  weighing two fixes  "])
        )
        #expect(rendered == "[reasoning]\nweighing two fixes")
    }

    @Test("Bookkeeping parts render nothing")
    func stepPartsAreDropped() {
        #expect(RunTranscript.describe(["type": "step-start"]) == nil)
        #expect(RunTranscript.describe(["type": "text", "text": "   "]) == nil)
    }

    private func event(_ type: BenchmarkEventType, _ payload: [String: JSONValue]) -> BenchmarkEvent {
        BenchmarkEvent(
            sequence: 0, timestamp: .init(), runID: "r1", type: type, payload: .object(payload)
        )
    }

    @Test("A part recorded both parsed and raw is rendered once")
    func parsedAndRawAreNotBothRendered() {
        // The runner records each line twice: once parsed by the adapter and
        // once as raw stdout. Rendering both doubled every tool call.
        let part: JSONValue = .object([
            "part": .object(["type": .string("text"), "text": .string("hello")])
        ])
        let raw = "{\"part\":{\"type\":\"text\",\"text\":\"hello\"}}\n"
        let entries = RunTranscript.entries(from: [
            event(.agentEvent, ["data": part]),
            event(.agentOutput, ["text": .string(raw)]),
        ]).agent
        #expect(entries == ["hello"])
    }

    @Test("A run with only raw output still renders")
    func rawOnlyRunsStillRender() {
        // Older runs, and adapters that cannot parse their own CLI, record
        // nothing but stdout. That is the archive, not a broken case.
        let raw = "{\"part\":{\"type\":\"text\",\"text\":\"hello\"}}\n"
        let entries = RunTranscript.entries(from: [
            event(.agentOutput, ["text": .string(raw)])
        ]).agent
        #expect(entries == ["hello"])
    }

    @Test("The raw output is taken from the run's own capture")
    func rawOutputPrefersTheCapturedFile() throws {
        let run = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: run.appendingPathComponent("logs"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: run) }
        try "everything the agent printed\n".write(
            to: run.appendingPathComponent("logs/agent-output.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(
            RunTranscript.rawOutput(events: [], runDirectoryURL: run)
                == "everything the agent printed\n"
        )
    }

    @Test("Without a run directory the chunks are rejoined unaltered")
    func rawOutputFallsBackToTheChunks() {
        // A cleaned run directory must not cost the raw record, and rejoining
        // has to add nothing: a separator here would corrupt a split JSON line.
        let events = ["{\"a\":", "1}\n"].enumerated().map {
            BenchmarkEvent(
                sequence: $0.offset, timestamp: .init(), runID: "r1",
                type: .agentOutput, payload: .object(["text": .string($0.element)])
            )
        }
        #expect(RunTranscript.rawOutput(events: events, runDirectoryURL: nil) == "{\"a\":1}\n")
    }

    @Test("A model name becomes one folder name")
    func slugsCollapseModelNames() {
        #expect(RunTranscript.slug(for: "minimax/MiniMax-M2.7") == "minimax-m2-7")
        #expect(RunTranscript.slug(for: nil) == "default")
    }
}
