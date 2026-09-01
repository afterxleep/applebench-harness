import Foundation

/// Explicit failure categories for everything that can go wrong before,
/// during, or after a run.
///
/// The central distinction: a grader returning `passed = false` is a valid
/// benchmark result and is **not** represented here. `BenchmarkFailure` is for
/// situations where the benchmark itself could not run credibly —
/// `xcodebuild` reporting failing tests is a FAIL result; `xcodebuild` being
/// unlaunchable is `.infrastructureFailure`.
public enum BenchmarkFailure: Error, Sendable {
    /// The task definition is malformed or references impossible configuration.
    case invalidTask(String)
    /// The machine cannot satisfy the task's environment requirements.
    case environmentUnavailable(String)
    /// Cloning, checking out, or inspecting the task repository failed.
    case repositoryFailure(String)
    /// The agent process could not be launched at all.
    case agentLaunchFailure(String)
    /// The agent exceeded the wall-clock limit and was terminated. Grading
    /// still runs; this failure is recorded as the termination reason rather
    /// than aborting the run.
    case agentTimeout
    /// A grader could not execute (as opposed to grading a failure).
    case graderFailure(grader: String, message: String)
    /// AppleBench's own machinery failed (I/O, serialization, tooling missing).
    case infrastructureFailure(String)
}

extension BenchmarkFailure: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidTask(let message):
            "Invalid task: \(message)"
        case .environmentUnavailable(let message):
            "Environment unavailable: \(message)"
        case .repositoryFailure(let message):
            "Repository failure: \(message)"
        case .agentLaunchFailure(let message):
            "Agent launch failure: \(message)"
        case .agentTimeout:
            "Agent exceeded wall-clock timeout"
        case .graderFailure(let grader, let message):
            "Grader '\(grader)' failed to execute: \(message)"
        case .infrastructureFailure(let message):
            "Infrastructure failure: \(message)"
        }
    }
}
