import Foundation

/// Executes suites: tasks × agents × repetitions, sequentially for
/// correctness (no parallel simulator contention in v1), and aggregates
/// completion metrics from the machine-readable run results.
public struct RunCoordinator: Sendable {
    public struct SuiteReport: Sendable {
        public struct AgentReport: Sendable {
            public var agent: String
            public var attempted: Int
            public var passed: Int
            public var failed: Int
            /// Runs that could not complete due to infrastructure errors —
            /// excluded from the completion rate but reported.
            public var errored: Int
            public var medianDurationSeconds: Double?
            /// Sum of tokens across runs that reported usage; `nil` when none did.
            public var totalTokens: Int?
            /// Sum of cost across runs that reported it; `nil` when none did.
            public var totalCostUSD: Double?

            public var completionRate: Double {
                attempted == 0 ? 0 : Double(passed) / Double(attempted)
            }

            /// Raw cost/performance variable: spend per solved task.
            public var costPerSolvedTaskUSD: Double? {
                guard let totalCostUSD, passed > 0 else { return nil }
                return totalCostUSD / Double(passed)
            }
        }

        public var suiteID: String
        public var agents: [AgentReport]
        public var results: [BenchmarkRunResult]
    }

    public enum SuiteProgress: Sendable {
        case taskStarted(task: String, agent: String, run: Int, totalRuns: Int)
        case taskFinished(BenchmarkRunResult)
        case taskErrored(task: String, agent: String, error: String)
        /// The suite stopped early because the agent never reached its model.
        /// Jobs already running finish; nothing new is claimed.
        case suiteAbandoned(reason: String)
    }

    /// One row of a suite comparison: an agent harness, optionally pinned to
    /// a specific model. Comparing models through one fixed harness means one
    /// entry per model.
    public struct Entry: Sendable {
        public let adapter: any AgentAdapter
        public let model: String?
        public let effort: String?

        public init(adapter: any AgentAdapter, model: String? = nil, effort: String? = nil) {
            self.adapter = adapter
            self.model = model
            self.effort = effort
        }

        public var label: String {
            model.map { "\(adapter.identifier) · \($0)" } ?? adapter.identifier
        }
    }

    private let runner: BenchmarkRunner

    public init(runner: BenchmarkRunner) {
        self.runner = runner
    }

    /// Runs every task in the suite for every entry, `runs` times each.
    /// Infrastructure failures on one run are recorded and do not abort the
    /// rest of the suite.
    ///
    /// Concurrency: when `parallelism` is greater than 1, work for a single
    /// entry is dispatched across that many concurrent task slots. Each slot
    /// runs a complete `BenchmarkRunner.run(...)` so simulator creation,
    /// agent invocation, grading, and `teardown()` (which deletes the
    /// simulator) all happen inside one slot — no shared simulator state
    /// crosses slot boundaries. Defaults to 1 (serial) to preserve the
    /// v1 calibration contract.
    public func runSuite(
        suite: BenchmarkSuite,
        tasks: [BenchmarkTask],
        entries: [Entry],
        runs: Int,
        options: RunnerOptions,
        parallelism: Int = 1,
        progress: @escaping @Sendable (SuiteProgress) -> Void = { _ in }
    ) async -> SuiteReport {
        var allResults: [BenchmarkRunResult] = []
        var agentReports: [AgentReport] = []

        for entry in entries {
            var entryOptions = options
            entryOptions.model = entry.model ?? options.model
            entryOptions.effort = entry.effort ?? options.effort

            // Build a flat list of (task, runIndex) jobs so concurrency
            // is straight-forward — every job is independent.
            var jobs: [(task: BenchmarkTask, runIndex: Int)] = []
            for task in tasks {
                for runIndex in 1...max(1, runs) {
                    jobs.append((task, runIndex))
                }
            }

            let slots = max(1, parallelism)
            let perEntry = await runJobs(
                jobs: jobs,
                slots: slots,
                adapter: entry.adapter,
                options: entryOptions,
                progress: progress
            )

            agentReports.append(AgentReport(
                agent: entry.label,
                attempted: perEntry.attempted,
                passed: perEntry.passed,
                failed: perEntry.attempted - perEntry.passed,
                errored: perEntry.errored,
                medianDurationSeconds: Self.median(perEntry.durations),
                totalTokens: perEntry.totalTokens,
                totalCostUSD: perEntry.totalCost
            ))
            allResults.append(contentsOf: perEntry.results)
        }

        return SuiteReport(suiteID: suite.id, agents: agentReports, results: allResults)
    }

    /// Run a flat list of (task, run) jobs across `slots` concurrent
    /// tasks. Every job runs a full `runner.run(...)` so the harness's
    /// own `teardown()` (which is called on both success and error
    /// paths and deletes the per-run simulator) stays in charge of
    /// lifecycle — the queue never sees a simulator directly.
    private struct JobOutcome: Sendable {
        var attempted: Int = 0
        var passed: Int = 0
        var errored: Int = 0
        var durations: [Double] = []
        var totalTokens: Int? = nil
        var totalCost: Double? = nil
        var results: [BenchmarkRunResult] = []
    }

    private func runJobs(
        jobs: [(task: BenchmarkTask, runIndex: Int)],
        slots: Int,
        adapter: any AgentAdapter,
        options: RunnerOptions,
        progress: @escaping @Sendable (SuiteProgress) -> Void
    ) async -> JobOutcome {
        // Serialized aggregate state. The `NonReentrantLock` (an
        // os_unfair_lock wrapper) keeps the writes from a TaskGroup
        // race; the `progress` callback is `@Sendable` so it can be
        // called from any worker.
        let aggregate = ParallelJobAggregate()
        let cursor = ParallelCursor()
        let totalJobs = jobs.count
        let adapterID = adapter.identifier

        await withTaskGroup(of: Void.self) { group in
            // Capacity is `slots`, not `jobs.count`, so the group
            // throttles itself: once `slots` tasks are running, the
            // next `addTask` is suspended until one finishes. That is
            // the whole point — bounded simulator contention.
            for _ in 0..<slots {
                group.addTask {
                    while true {
                        // Claim the next job index. The cursor is
                        // behind a lock, so two workers never take
                        // the same job.
                        let claimed = cursor.claim(of: totalJobs)
                        guard let index = claimed else { return }
                        let job = jobs[index]

                        progress(.taskStarted(
                            task: job.task.id,
                            agent: adapterID,
                            run: job.runIndex,
                            totalRuns: 1
                        ))

                        let result: BenchmarkRunResult?
                        let errorMessage: String?
                        do {
                            result = try await runner.run(
                                task: job.task,
                                adapter: adapter,
                                options: options
                            )
                            errorMessage = nil
                        } catch {
                            result = nil
                            errorMessage = "\(error)"
                            // An agent that never reached its model says
                            // nothing about this task, and the next task will
                            // hit the same wall. Stop claiming work rather
                            // than grading a suite of untouched fixtures and
                            // publishing it as a score.
                            if case BenchmarkFailure.agentNeverRan(let why) = error,
                               !cursor.wasAbandoned {
                                cursor.abandon()
                                progress(.suiteAbandoned(
                                    reason: "the agent never reached its model on "
                                        + "\(job.task.id): \(why)"
                                ))
                            }
                        }

                        if let r = result {
                            aggregate.record(success: r)
                            progress(.taskFinished(r))
                        } else if let msg = errorMessage {
                            aggregate.recordFailure()
                            progress(.taskErrored(
                                task: job.task.id,
                                agent: adapterID,
                                error: msg
                            ))
                        }
                    }
                }
            }
        }

        let s = aggregate.snapshot()
        return JobOutcome(
            attempted: s.attempted,
            passed: s.passed,
            errored: s.errored,
            durations: s.durations,
            totalTokens: s.totalTokens,
            totalCost: s.totalCost,
            results: s.results
        )
    }

    public typealias AgentReport = SuiteReport.AgentReport

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
