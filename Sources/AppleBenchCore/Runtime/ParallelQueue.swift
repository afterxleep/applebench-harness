import Foundation
import os

/// Bounded-occupancy queue used by `RunCoordinator.runJobs` to
/// distribute a flat list of (task, run) jobs across `slots`
/// concurrent workers.
///
/// The queue is deliberately small and does the minimum a parallel
/// job dispatcher needs:
///   * `cursor.claim(of:)` returns the next job index, or `nil` once
///     every job has been claimed.
///   * `aggregate.record(success:)` and `aggregate.recordFailure()`
///     fold the result of a single job into a single, shared
///     accumulator.
///   * `aggregate.snapshot()` returns the final accumulator.
///
/// The two pieces share a single `os_unfair_lock` so a TaskGroup of
/// any size cannot interleave a check and an update.
public final class ParallelJobAggregate: @unchecked Sendable {
    public init() {}
    private var attempted = 0
    private var passed = 0
    private var errored = 0
    private var durations: [Double] = []
    private var totalTokens: Int? = nil
    private var totalCost: Double? = nil
    private var results: [BenchmarkRunResult] = []
    private var lock = os_unfair_lock_s()

    public func record(success: BenchmarkRunResult) {
        os_unfair_lock_lock(&lock)
        attempted += 1
        if success.result.passed { passed += 1 }
        durations.append(success.result.durationSeconds)
        if let tokens = success.usage.totalTokens {
            totalTokens = (totalTokens ?? 0) + tokens
        }
        if let cost = success.usage.estimatedCostUSD {
            totalCost = (totalCost ?? 0) + cost
        }
        results.append(success)
        os_unfair_lock_unlock(&lock)
    }

    public func recordFailure() {
        os_unfair_lock_lock(&lock)
        errored += 1
        os_unfair_lock_unlock(&lock)
    }

    public func snapshot() -> (attempted: Int, passed: Int, errored: Int, durations: [Double], totalTokens: Int?, totalCost: Double?, results: [BenchmarkRunResult]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (attempted, passed, errored, durations, totalTokens, totalCost, results)
    }
}

/// A monotonic cursor shared across the workers in a parallel job
/// dispatcher. Returns `nil` once `total` jobs have been claimed, so
/// workers can stop their loop.
public final class ParallelCursor: @unchecked Sendable {
    public init() {}
    private var next: Int = 0
    private var lock = os_unfair_lock_s()

    private var abandoned = false

    /// Claim the next job index. Returns `nil` once every job in
    /// `[0, total)` has been claimed, or once the queue is abandoned.
    public func claim(of total: Int) -> Int? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard !abandoned, next < total else { return nil }
        let claimed = next
        next += 1
        return claimed
    }

    /// Stop handing out work.
    ///
    /// Deliberately not cancellation: a worker already inside a job keeps
    /// going to its own teardown, which is what deletes the simulator it
    /// created. Workers stop at their next claim instead.
    public func abandon() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        abandoned = true
    }

    public var wasAbandoned: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return abandoned
    }
}
