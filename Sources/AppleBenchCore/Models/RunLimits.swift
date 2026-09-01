import Foundation

/// Execution limits for a benchmark run.
///
/// The wall-clock timeout is enforced by AppleBench itself: when exceeded the
/// agent's process tree is terminated, the timeout is recorded, and grading
/// still runs against whatever workspace state remains.
///
/// The token limit is enforced the same way, for adapters whose CLI reports
/// usage as it works: spend is counted live from the agent's own output and
/// the process tree is torn down when it crosses the budget. The cost limit
/// is still advisory, since no adapter reports cost in time to act on it.
public struct RunLimits: Sendable, Codable, Equatable {
    /// Wall-clock timeout for the agent phase, in seconds.
    public var timeoutSeconds: Int
    /// Maximum spend in USD. Advisory: recorded, never enforced.
    public var maxCostUSD: Double?
    /// Maximum tokens the agent may spend before it is stopped. Enforced for
    /// adapters that stream usage; ignored by those that report none.
    public var maxTokens: Int?

    public static let defaultTimeoutSeconds = 900

    public init(
        timeoutSeconds: Int = RunLimits.defaultTimeoutSeconds,
        maxCostUSD: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.maxCostUSD = maxCostUSD
        self.maxTokens = maxTokens
    }

    enum CodingKeys: String, CodingKey {
        case timeoutSeconds = "timeout_seconds"
        case maxCostUSD = "max_cost_usd"
        case maxTokens = "max_tokens"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds)
            ?? RunLimits.defaultTimeoutSeconds
        maxCostUSD = try container.decodeIfPresent(Double.self, forKey: .maxCostUSD)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
    }
}

/// Ceilings applied to every task in a run, from the command line rather than
/// from the task files.
///
/// A suite's cost is concentrated in the tasks a model cannot solve, because
/// those are the ones that run to their full limit. Editing every task file to
/// bound that would change what the tasks are; a cap bounds one run and leaves
/// the set alone.
///
/// Caps only ever tighten. Raising a task's own limit would give it more room
/// than its author allowed, which changes what it measures.
public struct LimitCaps: Sendable, Equatable {
    public var timeoutSeconds: Int?
    public var maxTokens: Int?

    public init(timeoutSeconds: Int? = nil, maxTokens: Int? = nil) {
        self.timeoutSeconds = timeoutSeconds
        self.maxTokens = maxTokens
    }

    public var isEmpty: Bool { timeoutSeconds == nil && maxTokens == nil }
}

extension RunLimits {
    public func capped(by caps: LimitCaps) -> RunLimits {
        var capped = self
        if let cap = caps.timeoutSeconds {
            capped.timeoutSeconds = min(timeoutSeconds, cap)
        }
        if let cap = caps.maxTokens {
            capped.maxTokens = min(maxTokens ?? cap, cap)
        }
        return capped
    }
}
