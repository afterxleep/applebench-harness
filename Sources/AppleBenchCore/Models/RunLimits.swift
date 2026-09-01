import Foundation

/// Execution limits for a benchmark run.
///
/// The wall-clock timeout is enforced by AppleBench itself: when exceeded the
/// agent's process tree is terminated, the timeout is recorded, and grading
/// still runs against whatever workspace state remains. Token and cost limits
/// are advisory — they are passed to adapters that expose control over them
/// and ignored otherwise.
public struct RunLimits: Sendable, Codable, Equatable {
    /// Wall-clock timeout for the agent phase, in seconds.
    public var timeoutSeconds: Int
    /// Maximum spend in USD, if the adapter supports enforcing it.
    public var maxCostUSD: Double?
    /// Maximum token usage, if the adapter supports enforcing it.
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
