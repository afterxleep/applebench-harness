import Foundation

/// List prices and reasoning settings for the models the benchmark scores.
///
/// The agent CLI reports what the *caller* was billed, which moves with their
/// provider, plan and discounts. Fitting a price to the costs opencode reported
/// for the MiniMax runs gives a negative input rate, which no real tariff has,
/// so those numbers cannot be compared between two models — let alone
/// published as a property of the model.
///
/// Cost is therefore computed from tokens the harness counted and the model
/// owner's list price, taken from a pinned snapshot of models.dev. Pinned, not
/// fetched: a published score must not move because a provider changed its
/// prices after the run. `Scripts/update-model-catalog.py` refreshes it, and
/// `retrieved` records when the prices were true.
public struct ModelCatalog: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let sourceID: String
        /// USD per million tokens, as the model's owner charges.
        public let inputCostPerMillion: Double
        public let outputCostPerMillion: Double
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
            reasoning: Bool,
            maximumEffort: String?
        ) {
            self.sourceID = sourceID
            self.inputCostPerMillion = inputCostPerMillion
            self.outputCostPerMillion = outputCostPerMillion
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
    /// This is an upper bound. Providers discount cached input — models.dev
    /// carries a `cache_read` rate — but the adapters do not record how much
    /// of the input was a cache hit, so all input is priced at the full rate.
    public func listCostUSD(model: String?, inputTokens: Int?, outputTokens: Int?) -> Double? {
        guard let entry = entry(for: model), let inputTokens, let outputTokens else { return nil }
        let million = 1_000_000.0
        return Double(inputTokens) / million * entry.inputCostPerMillion
            + Double(outputTokens) / million * entry.outputCostPerMillion
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
        }
    }
}
