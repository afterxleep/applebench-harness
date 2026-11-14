import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Result serialization")
struct ResultSerializationTests {
    private func makeResult() -> BenchmarkRunResult {
        BenchmarkRunResult(
            runID: "2026-08-08T105500-navigation-001-codex",
            task: "navigation-001",
            category: .runtime,
            difficulty: 1,
            tags: ["navigation"],
            agent: AgentMetadata(agent: "codex", model: "gpt-x", version: "1.0"),
            environment: .init(
                macos: "26.5",
                architecture: "arm64",
                xcode: "27.0",
                xcodeBuild: "27A5228h",
                simulator: "iPhone 17",
                runtime: "iOS 26.5"
            ),
            result: .init(passed: true, durationSeconds: 243.2, agentTermination: .timeout),
            usage: AgentUsage(inputTokens: 1000, outputTokens: 500, totalTokens: 1500, estimatedCostUSD: nil),
            metrics: nil,
            graders: [
                .init(name: "build", passed: true, durationSeconds: 37.2, summary: "ok", evidence: []),
            ],
            git: .init(baseCommit: "abc123", finalCommit: nil, filesChanged: 3, insertions: 24, deletions: 7),
            artifacts: .init(events: "events.jsonl", diff: "diff.patch", logs: "logs")
        )
    }

    @Test("result.json round-trips and uses snake_case keys")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-result-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = makeResult()
        try result.write(to: url)
        let restored = try BenchmarkRunResult.read(from: url)
        #expect(restored == result)

        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(json.contains("\"schema_version\" : 1"))
        #expect(json.contains("\"run_id\""))
        #expect(json.contains("\"input_tokens\""))
        #expect(json.contains("\"base_commit\""))
        #expect(json.contains("\"duration_seconds\""))
        // Timeout and PASS coexist without being collapsed.
        #expect(json.contains("\"agent_termination\" : \"timeout\""))
        #expect(json.contains("\"passed\" : true"))
    }

    @Test("Unavailable usage stays null, never zero")
    func nullUsage() throws {
        var result = makeResult()
        result.usage = AgentUsage()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-result-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try result.write(to: url)
        let restored = try BenchmarkRunResult.read(from: url)
        #expect(restored.usage.inputTokens == nil)
        #expect(restored.usage.estimatedCostUSD == nil)
    }
}
