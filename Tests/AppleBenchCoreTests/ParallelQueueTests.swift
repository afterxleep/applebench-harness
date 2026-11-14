import AppleBenchCore
import Foundation
import Testing

@Suite("ParallelJobAggregate + ParallelCursor")
struct ParallelQueueTests {
    @Test("record folds successes and failures into a single snapshot")
    func aggregateFoldsAllJobs() {
        let agg = ParallelJobAggregate()
        // Use a fake BenchmarkRunResult by replaying events; this is
        // cheap and keeps the test independent of full task loading.
        let r1 = makeResult(taskID: "t1", passed: true, tokens: 100, cost: 0.01)
        let r2 = makeResult(taskID: "t2", passed: false, tokens: 200, cost: 0.02)
        let r3 = makeResult(taskID: "t3", passed: true, tokens: 50, cost: nil)

        agg.record(success: r1)
        agg.record(success: r2)
        agg.recordFailure()
        agg.record(success: r3)

        let s = agg.snapshot()
        #expect(s.attempted == 3)
        #expect(s.passed == 2)
        #expect(s.errored == 1)
        #expect(s.totalTokens == 350)
        #expect(s.totalCost == 0.03)
        #expect(s.results.count == 3)
        #expect(s.durations.count == 3)
    }

    @Test("ParallelCursor hands out unique indexes up to the limit, then nil")
    func cursorUniqueIndexes() {
        let cursor = ParallelCursor()
        let total = 7
        var seen: Set<Int> = []
        for _ in 0..<total {
            let claimed = cursor.claim(of: total)
            #expect(claimed != nil)
            #expect(seen.insert(claimed!).inserted, "cursor handed out duplicate index")
        }
        #expect(cursor.claim(of: total) == nil)
    }

    @Test("Abandoning the queue stops every worker claiming more")
    func cursorAbandonsTheRest() {
        // When the agent cannot reach its model, every remaining task will
        // fail the same way. Finishing the suite would spend an hour to
        // report a score of zero that says nothing about the model.
        let cursor = ParallelCursor()
        #expect(cursor.claim(of: 10) == 0)
        cursor.abandon()
        #expect(cursor.claim(of: 10) == nil)
        #expect(cursor.wasAbandoned)
    }

    @Test("A queue nobody abandoned does not report that it was")
    func cursorIsNotAbandonedByDefault() {
        let cursor = ParallelCursor()
        while cursor.claim(of: 3) != nil {}
        #expect(!cursor.wasAbandoned)
    }

    @Test("In-flight workers stop at their next claim, not mid-job")
    func abandonLetsRunningJobsFinish() async {
        // Abandoning cancels nothing that is already running: a task holding
        // a simulator has to reach its own teardown, or the run leaks one.
        let cursor = ParallelCursor()
        let total = 100
        let claimed = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    var mine = 0
                    while let index = cursor.claim(of: total) {
                        mine += 1
                        if index == 0 { cursor.abandon() }
                    }
                    return mine
                }
            }
            var sum = 0
            for await count in group { sum += count }
            return sum
        }
        #expect(claimed < total, "abandoning did not stop the queue")
        #expect(claimed >= 1)
    }

    @Test("Many concurrent claimers never get the same index")
    func cursorConcurrentClaimers() async {
        let cursor = ParallelCursor()
        let total = 200
        let workers = 8

        // Spin up workers that each try to claim every index.
        let results: [Set<Int>] = await withTaskGroup(of: Set<Int>.self) { group in
            for _ in 0..<workers {
                group.addTask {
                    var mine: Set<Int> = []
                    while let idx = cursor.claim(of: total) {
                        mine.insert(idx)
                    }
                    return mine
                }
            }
            var aggregate: [Set<Int>] = []
            for await partial in group {
                aggregate.append(partial)
            }
            return aggregate
        }

        // Every index 0..<total was handed out exactly once.
        let all: Set<Int> = results.reduce(into: []) { $0.formUnion($1) }
        #expect(all.count == total)
        #expect(all == Set(0..<total))
    }

    @Test("Parallel aggregate + cursor together: 50 jobs, 4 slots, all accounted for")
    func integratedRun() async {
        let agg = ParallelJobAggregate()
        let cursor = ParallelCursor()
        let total = 50
        let slots = 4

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<slots {
                group.addTask {
                    while let idx = cursor.claim(of: total) {
                        let passed = idx.isMultiple(of: 2)
                        let result = makeResult(
                            taskID: "t\(idx)",
                            passed: passed,
                            tokens: 10,
                            cost: 0.001
                        )
                        agg.record(success: result)
                    }
                }
            }
        }

        let s = agg.snapshot()
        #expect(s.attempted == total)
        // Even indices 0, 2, 4, …, 48 → 25 passes.
        #expect(s.passed == 25)
        #expect(s.errored == 0)
        #expect(s.results.count == total)
    }

    // MARK: - Helpers

    private func makeResult(
        taskID: String,
        passed: Bool,
        tokens: Int,
        cost: Double?
    ) -> BenchmarkRunResult {
        let now = Date()
        let events = [
            BenchmarkEvent(
                sequence: 1,
                timestamp: now,
                runID: "test-\(taskID)",
                type: .runStarted,
                payload: .object(["task": .string(taskID)])
            ),
            BenchmarkEvent(
                sequence: 2,
                timestamp: now.addingTimeInterval(0.1),
                runID: "test-\(taskID)",
                type: .runFinished,
                payload: .object(["passed": .bool(passed), "duration_ms": .int(100)])
            ),
        ]
        return BenchmarkRunResult(
            runID: "test-\(taskID)",
            task: taskID,
            category: .ops,
            difficulty: 1,
            tags: [],
            agent: .init(agent: "fake", model: nil as String?),
            environment: .init(macos: "27.0", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A5252f", simulator: nil),
            result: .init(passed: passed, durationSeconds: 0.1, agentTermination: .completed),
            usage: .init(inputTokens: tokens, outputTokens: 0, totalTokens: tokens, estimatedCostUSD: cost),
            metrics: TrajectoryMetrics(events: events),
            graders: [],
            git: .init(baseCommit: "x", finalCommit: "y", filesChanged: 0, insertions: 0, deletions: 0),
            artifacts: .init(events: "events.jsonl", diff: "diff.patch", logs: "logs")
        )
    }
}
