import Foundation

/// List prices and reasoning settings for the models the benchmark scores.
///
/// Cost is computed from the tokens a run actually spent and the model owner's
/// list price, taken from a pinned snapshot of models.dev. Pinned, not fetched:
/// a published score must not move because a provider changed its prices after
/// the run. `Scripts/update-model-catalog.py` refreshes it, and `retrieved`
/// records when the prices were true.
///
/// Computing it here rather than trusting the agent CLI keeps one definition
/// of cost across agents — the Claude Code adapter reports none at all — and
/// means a run can be re-priced from its recorded tokens. On the runs measured
/// so far it agrees with what OpenCode reported to the cent, which is the
/// check worth running whenever an adapter changes: a mismatch means a token
/// category is being missed, as cached prompt tokens were before they were
/// counted here.
public struct ModelCatalog: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let sourceID: String
        /// USD per million tokens, as the model's owner charges.
        public let inputCostPerMillion: Double
        public let outputCostPerMillion: Double
        /// Rate for prompt tokens served from cache. Zero when the model has
        /// no cached tier, which prices them at nothing rather than dropping
        /// them from the count.
        public let cacheReadCostPerMillion: Double
        public let cacheWriteCostPerMillion: Double
        public let reasoning: Bool
        /// The strongest effort setting the model exposes, or `nil` when it
        /// exposes no effort ladder at all. `nil` is not "low": it means the
        /// question does not apply, and a report that printed "max" for such a
        /// model would be claiming a setting that does not exist.
        public let maximumEffort: String?

        public init(
            sourceID: String,
            inputCostPerMillion: Double,
            outputCostPerMillion: Double,
            cacheReadCostPerMillion: Double = 0,
            cacheWriteCostPerMillion: Double = 0,
            reasoning: Bool,
            maximumEffort: String?
        ) {
            self.sourceID = sourceID
            self.inputCostPerMillion = inputCostPerMillion
            self.outputCostPerMillion = outputCostPerMillion
            self.cacheReadCostPerMillion = cacheReadCostPerMillion
            self.cacheWriteCostPerMillion = cacheWriteCostPerMillion
            self.reasoning = reasoning
            self.maximumEffort = maximumEffort
        }
    }

    public let source: String
    public let retrieved: String
    public let models: [String: Entry]

    public init(source: String, retrieved: String, models: [String: Entry]) {
        self.source = source
        self.retrieved = retrieved
        self.models = models
    }

    /// Reads a catalog written by `Scripts/update-model-catalog.py`.
    public static func load(from url: URL) throws -> ModelCatalog {
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        return ModelCatalog(
            source: document.source,
            retrieved: document.retrieved,
            models: document.models.mapValues { model in
                Entry(
                    sourceID: model.sourceID,
                    inputCostPerMillion: model.costPerMillion.input,
                    outputCostPerMillion: model.costPerMillion.output,
                    cacheReadCostPerMillion: model.costPerMillion.cacheRead ?? 0,
                    cacheWriteCostPerMillion: model.costPerMillion.cacheWrite ?? 0,
                    reasoning: model.reasoning,
                    maximumEffort: model.maxEffort
                )
            }
        )
    }

    /// The entry for a model id, matching the way ids actually reach us.
    ///
    /// The same model arrives as `minimax/MiniMax-M2.7` when called directly
    /// and `openrouter/minimax/minimax-m3` through a gateway. Both name the
    /// same model and both must price the same, so an exact match is tried
    /// first and the trailing component is matched case-insensitively after.
    public func entry(for model: String?) -> Entry? {
        guard let model else { return nil }
        if let exact = models[model] { return exact }
        let wanted = model.split(separator: "/").last.map { $0.lowercased() }
        guard let wanted else { return nil }
        return models.first { key, _ in
            key.split(separator: "/").last?.lowercased() == wanted
        }?.value
    }

    /// What the run would have cost at list price, or `nil` when either the
    /// model or its token counts are unknown.
    ///
    /// Absent, not zero: a run whose agent reported no usage did not cost
    /// nothing, we simply cannot say, and a zero would sum into a total that
    /// reads as fact.
    ///
    /// Cached prompt tokens are priced at their own, much lower rate. They are
    /// most of an agentic run — every step re-sends the conversation — so
    /// pricing them as fresh input, or leaving them out, both give a number
    /// that is wrong by multiples rather than by a rounding error.
    public func listCostUSD(
        model: String?,
        inputTokens: Int?,
        outputTokens: Int?,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil
    ) -> Double? {
        guard let entry = entry(for: model), let inputTokens, let outputTokens else { return nil }
        let million = 1_000_000.0
        return Double(inputTokens) / million * entry.inputCostPerMillion
            + Double(outputTokens) / million * entry.outputCostPerMillion
            + Double(cacheReadTokens ?? 0) / million * entry.cacheReadCostPerMillion
            + Double(cacheWriteTokens ?? 0) / million * entry.cacheWriteCostPerMillion
    }

    /// Convenience for the common case: price a run from its own usage.
    public func listCostUSD(model: String?, usage: AgentUsage) -> Double? {
        listCostUSD(
            model: model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: usage.cacheReadTokens,
            cacheWriteTokens: usage.cacheWriteTokens
        )
    }

    // MARK: - On-disk shape

    private struct Document: Decodable {
        let source: String
        let retrieved: String
        let models: [String: Model]

        struct Model: Decodable {
            let sourceID: String
            let costPerMillion: Rates
            let reasoning: Bool
            let maxEffort: String?

            enum CodingKeys: String, CodingKey {
                case sourceID = "source_id"
                case costPerMillion = "cost_per_million"
                case reasoning
                case maxEffort = "max_effort"
            }
        }

        struct Rates: Decodable {
            let input: Double
            let output: Double
            let cacheRead: Double?
            let cacheWrite: Double?

            enum CodingKeys: String, CodingKey {
                case input, output
                case cacheRead = "cache_read"
                case cacheWrite = "cache_write"
            }
        }
    }
}
