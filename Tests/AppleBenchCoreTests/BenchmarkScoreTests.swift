import Foundation
import Testing
@testable import AppleBenchCore

@Suite("AppleBench empirical points")
struct BenchmarkScoreTests {
    private func makeResult(
        task: String,
        model: String = "vendor/model-1",
        passed: Bool = true,
        costUSD: Double? = 0.01,
        activeTimeSeconds: Double? = 120
    ) -> BenchmarkRunResult {
        var metrics = TrajectoryMetrics(events: [])
        metrics.agentDurationSeconds = activeTimeSeconds
        return BenchmarkRunResult(
            runID: "2026-01-01T000000-\(task)-opencode",
            task: task,
            category: .build,
            difficulty: 5,
            tags: [],
            agent: AgentMetadata(agent: "opencode", model: model),
            environment: .init(macos: "27.0", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A1"),
            result: .init(passed: passed, durationSeconds: 1, agentTermination: .completed),
            usage: AgentUsage(totalTokens: 10_000, estimatedCostUSD: costUSD),
            metrics: metrics,
            graders: [],
            git: .init(baseCommit: "abc123", filesChanged: 1, insertions: 1, deletions: 0),
            artifacts: .init(events: "events.jsonl")
        )
    }

    private func runsByModel(_ spec: [(model: String, task: String, passed: Bool)]) -> [String: [BenchmarkRunResult]] {
        var grouped: [String: [BenchmarkRunResult]] = [:]
        for entry in spec {
            grouped[entry.model, default: []].append(makeResult(task: entry.task, model: entry.model, passed: entry.passed))
        }
        return grouped
    }

    @Test("Task weight scales with how rare a pass is, capped at 2000")
    func weightFromPassRates() {
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: 5) == 100)
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: 4) == 125)
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: 3) == 167)
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: 2) == 250)
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: 1) == 500)
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: 0) == 2000)
        #expect(AppleBenchScore.weight(modelCount: 25, passingModelCount: 1) == 2000)
    }

    @Test("Impossible pass counts produce no weight rather than a wrong one")
    func invalidCountsProduceNoWeight() {
        #expect(AppleBenchScore.weight(modelCount: 0, passingModelCount: 0) == nil)
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: 6) == nil)
        #expect(AppleBenchScore.weight(modelCount: 5, passingModelCount: -1) == nil)
    }

    @Test("Weights are derived from the pass rates of the given complete runs")
    func weightsFromRuns() {
        let weights = AppleBenchScore.weights(for: runsByModel([
            ("m1", "shared", true), ("m1", "solo", true),
            ("m2", "shared", true),
            ("m3", "shared", false),
            ("m1", "impossible", false), ("m2", "impossible", false),
        ]))
        #expect(weights["shared"] == 150)
        #expect(weights["solo"] == 100)
        #expect(weights["impossible"] == 2000)
        #expect(weights.count == 3)
    }

    @Test("Authored difficulty does not change the score")
    func difficultyDoesNotChangePoints() {
        let weights = ["task": 500]
        let easy = makeResult(task: "task", passed: true)
        #expect(AppleBenchScore.points(for: easy, weights: weights) == 500)
    }

    @Test("A pass earns the full weight and a failure earns none")
    func verdictDeterminesEarnedPoints() {
        #expect(AppleBenchScore.points(passed: true, weight: 167) == 167)
        #expect(AppleBenchScore.points(passed: false, weight: 167) == 0)
        #expect(AppleBenchScore.points(passed: true, weight: nil) == nil)
        #expect(AppleBenchScore.points(passed: true, weight: 0) == nil)
    }

    @Test("Cost and time do not change capability points")
    func resourcesDoNotChangePoints() {
        let weights = ["fast": 500, "slow": 500]
        let efficient = makeResult(task: "fast", costUSD: 0, activeTimeSeconds: 1)
        let expensive = makeResult(task: "slow", costUSD: 100, activeTimeSeconds: 100_000)
        #expect(AppleBenchScore.points(for: efficient, weights: weights) == 500)
        #expect(AppleBenchScore.points(for: expensive, weights: weights) == 500)
    }

    @Test("Total percentage is earned weight divided by available weight")
    func totalUsesWeights() {
        let weights = ["easy": 500, "hard": 100]
        let total = AppleBenchScore.total(for: [
            makeResult(task: "easy", passed: false),
            makeResult(task: "hard", passed: true),
        ], weights: weights)
        #expect(total.points == 100)
        #expect(total.available == 600)
        #expect(total.fractionOfAvailable == 100.0 / 600.0)
        #expect(total.percentage == (100.0 / 600.0) * 100.0)
    }

    @Test("Runs without a weight stay visible but are not scored")
    func unweightedRunsAreUnscored() {
        let total = AppleBenchScore.total(for: [
            makeResult(task: "scored"),
            makeResult(task: "missing"),
        ], weights: ["scored": 100])
        #expect(total.points == 100)
        #expect(total.available == 100)
        #expect(total.scoredRuns == 1)
        #expect(total.unscoredRuns == 1)
    }

    @Test("Scoring two sets separately and adding them equals scoring the union")
    func scoreIsAdditiveAcrossTaskSets() {
        let weights = ["build-001": 100, "ops-001": 500, "widget-001": 125, "swiftdata-001": 100]
        let first = AppleBenchScore.total(for: [
            makeResult(task: "build-001", passed: true),
            makeResult(task: "ops-001", passed: false),
        ], weights: weights)
        let second = AppleBenchScore.total(for: [
            makeResult(task: "widget-001", passed: true),
            makeResult(task: "swiftdata-001", passed: true),
        ], weights: weights)
        let union = AppleBenchScore.total(for: [
            makeResult(task: "build-001", passed: true),
            makeResult(task: "ops-001", passed: false),
            makeResult(task: "widget-001", passed: true),
            makeResult(task: "swiftdata-001", passed: true),
        ], weights: weights)

        #expect(first.points + second.points == union.points)
        #expect(first.available + second.available == union.available)
    }

    @Test("An empty set scores zero percent")
    func emptySetIsSafe() {
        let total = AppleBenchScore.total(for: [], weights: [:])
        #expect(total.points == 0)
        #expect(total.available == 0)
        #expect(total.fractionOfAvailable == 0)
        #expect(total.percentage == 0)
    }

    @Test("The score records the empirical-v1 specification")
    func specificationIsEmpirical() {
        #expect(AppleBenchScore.specification == "empirical-v1")
        let total = AppleBenchScore.total(for: [makeResult(task: "task")], weights: ["task": 100])
        #expect(total.specification == "empirical-v1")
    }
}
