import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Live event log")
struct LiveEventLogTests {
    private func event(
        _ type: BenchmarkEventType,
        _ payload: [String: JSONValue] = [:]
    ) -> BenchmarkEvent {
        BenchmarkEvent(
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 0),
            runID: "run",
            type: type,
            payload: .object(payload)
        )
    }

    @Test("Off produces no observer, so the recorder does no work")
    func offHasNoObserver() {
        #expect(LiveEventLog(level: .off).observer() == nil)
        #expect(LiveEventLog(level: .activity).observer() != nil)
    }

    @Test("Commands and graders show at activity level")
    func showsStructure() throws {
        let command = try #require(LiveEventLog.render(
            event(.commandStarted, ["command": .string("xcodebuild build")]), level: .activity
        ))
        #expect(command.contains("xcodebuild build"))

        let grader = try #require(LiveEventLog.render(
            event(.graderFinished, ["grader": .string("build"), "passed": .bool(false)]), level: .activity
        ))
        #expect(grader.contains("FAIL"))
        #expect(grader.contains("build"))
    }

    @Test("An exit code that is not zero is called out")
    func marksFailingCommands() throws {
        let ok = try #require(LiveEventLog.render(
            event(.commandFinished, ["command": .string("swift build"), "exit_code": .int(0)]),
            level: .activity
        ))
        #expect(ok.contains("ok"))
        let bad = try #require(LiveEventLog.render(
            event(.commandFinished, ["command": .string("swift build"), "exit_code": .int(65)]),
            level: .activity
        ))
        #expect(bad.contains("exit 65"))
    }

    @Test("Model chatter is hidden at activity level and shown at output")
    func gatesModelOutput() {
        let talking = event(.agentOutput, ["text": .string("Let me look at the file")])
        #expect(LiveEventLog.render(talking, level: .activity) == nil)
        #expect(LiveEventLog.render(talking, level: .output) != nil)
    }

    @Test("A tool call is structure, so it shows without the noisy level")
    func toolCallsAreStructure() throws {
        let line = try #require(LiveEventLog.render(
            event(.agentEvent, ["kind": .string("tool_call"), "name": .string("edit")]),
            level: .activity
        ))
        #expect(line.contains("tool: edit"))
    }

    @Test("Command output stays hidden even at the noisiest level")
    func neverShowsCommandOutput() {
        // Build logs are the bulk of a run's bytes; showing them would bury
        // everything worth reading. They stay in events.jsonl.
        let noisy = event(.commandOutput, ["text": .string("compiling…")])
        #expect(LiveEventLog.render(noisy, level: .output) == nil)
    }

    @Test("A multi-line message is collapsed onto one line")
    func collapsesNewlines() throws {
        let line = try #require(LiveEventLog.render(
            event(.agentOutput, ["text": .string("first\n\nsecond   third")]), level: .output
        ))
        #expect(!line.dropFirst().contains("\n"))
        #expect(line.contains("first second third"))
    }

    @Test("A long line is truncated rather than wrapped")
    func truncatesLongLines() throws {
        let line = try #require(LiveEventLog.render(
            event(.commandStarted, ["command": .string(String(repeating: "x", count: 500))]),
            level: .activity
        ))
        #expect(line.count < 200)
        #expect(line.hasSuffix("…"))
    }

    @Test("An event with nothing to say produces no line at all")
    func skipsEmptyEvents() {
        #expect(LiveEventLog.render(event(.commandStarted), level: .output) == nil)
        #expect(LiveEventLog.render(event(.workspaceCreated), level: .output) == nil)
    }

    @Test("The observer writes every rendered line to its sink")
    func observerWritesLines() {
        let box = Box()
        let log = LiveEventLog(level: .activity, write: { line in box.append(line) })
        let observer = log.observer()
        observer?(event(.commandStarted, ["command": .string("git status")]))
        observer?(event(.workspaceCreated))
        #expect(box.lines.count == 1)
        #expect(box.lines[0].contains("git status"))
    }

    /// A tiny thread-safe collector, because the observer is `@Sendable`.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
        func append(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    }
}
