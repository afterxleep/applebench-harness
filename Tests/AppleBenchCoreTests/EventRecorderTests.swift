import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Event recording")
struct EventRecorderTests {
    @Test("Events get monotonically increasing sequence numbers")
    func sequencing() async throws {
        let recorder = try EventRecorder(runID: "run-1", fileURL: nil)
        await recorder.record(.runStarted)
        await recorder.record(.agentStarted)
        await recorder.record(.runFinished)

        let events = await recorder.allEvents()
        #expect(events.map(\.sequence) == [1, 2, 3])
        #expect(events.allSatisfy { $0.runID == "run-1" })
    }

    @Test("Concurrent recording never duplicates sequence numbers")
    func concurrentRecording() async throws {
        let recorder = try EventRecorder(runID: "run-2", fileURL: nil)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    await recorder.record(.agentOutput, payload: .object(["i": .int(index)]))
                }
            }
        }
        let events = await recorder.allEvents()
        #expect(events.count == 100)
        #expect(Set(events.map(\.sequence)).count == 100)
        #expect(events.map(\.sequence).sorted() == Array(1...100))
    }

    @Test("Events stream to JSONL and decode back")
    func jsonlPersistence() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let recorder = try EventRecorder(runID: "run-3", fileURL: fileURL)
        await recorder.record(.runStarted, payload: .object(["task": .string("t-1")]))
        await recorder.record(.commandFinished, payload: .object([
            "command": .string("xcodebuild build"),
            "exit_code": .int(65),
        ]))
        await recorder.close()

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 2)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        let second = try decoder.decode(BenchmarkEvent.self, from: Data(lines[1].utf8))
        #expect(second.sequence == 2)
        #expect(second.type == .commandFinished)
        #expect(second.payload["exit_code"]?.intValue == 65)
    }

    @Test("Trajectory metrics derive counts from the event stream")
    func trajectoryMetrics() async throws {
        let recorder = try EventRecorder(runID: "run-4", fileURL: nil)
        await recorder.record(.runStarted)
        await recorder.record(.agentStarted)
        await recorder.record(.agentOutput, payload: .object(["stream": .string("stdout"), "text": .string("12345")]))
        await recorder.record(.agentEvent, payload: .object(["kind": .string("tool_call")]))
        await recorder.record(.agentEvent, payload: .object(["kind": .string("message")]))
        await recorder.record(.agentFinished)
        await recorder.record(.commandFinished, payload: .object(["command": .string("xcodebuild -scheme App build")]))
        await recorder.record(.commandFinished, payload: .object(["command": .string("xcodebuild -scheme App test")]))
        await recorder.record(.commandFinished, payload: .object(["command": .string("git diff")]))
        await recorder.record(.gradingStarted)
        await recorder.record(.runFinished)

        let metrics = TrajectoryMetrics(events: await recorder.allEvents())
        #expect(metrics.totalEvents == 11)
        #expect(metrics.agentEvents == 2)
        #expect(metrics.toolCalls == 1)
        #expect(metrics.agentOutputChunks == 1)
        #expect(metrics.agentOutputBytes == 5)
        #expect(metrics.commandsExecuted == 3)
        #expect(metrics.buildInvocations == 1)
        #expect(metrics.testInvocations == 1)
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            return try Date(text, strategy: style)
        }
    }
}
