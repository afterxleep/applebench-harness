import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Model catalog")
struct ModelCatalogTests {
    private func makeCatalog(
        maximumEffort: String? = "high"
    ) -> ModelCatalog {
        ModelCatalog(
            source: "https://models.dev/api.json",
            retrieved: "2026-09-03",
            models: [
                "vendor/Model-One": .init(
                    sourceID: "vendor/Model-One",
                    inputCostPerMillion: 0.3,
                    outputCostPerMillion: 1.2,
                    cacheReadCostPerMillion: 0.06,
                    cacheWriteCostPerMillion: 0.375,
                    reasoning: true,
                    maximumEffort: maximumEffort
                )
            ]
        )
    }

    private func makeResult(
        task: String = "build-002",
        model: String? = "vendor/Model-One",
        effort: String? = nil,
        inputTokens: Int? = 1_000_000,
        outputTokens: Int? = 1_000_000,
        reportedCost: Double? = 9.99
    ) -> BenchmarkRunResult {
        var configuration: [String: String] = [:]
        if let effort { configuration["effort"] = effort }
        return BenchmarkRunResult(
            runID: "2026-09-03T000000-\(task)-opencode",
            task: task,
            category: .build,
            difficulty: 3,
            tags: [],
            agent: AgentMetadata(agent: "opencode", model: model, configuration: configuration),
            environment: .init(macos: "27.0", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A1"),
            result: .init(passed: true, durationSeconds: 1, agentTermination: .completed),
            usage: AgentUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                totalTokens: (inputTokens ?? 0) + (outputTokens ?? 0),
                estimatedCostUSD: reportedCost
            ),
            metrics: nil,
            graders: [.init(name: "build", passed: true, durationSeconds: 1, summary: "ok", evidence: [])],
            git: .init(baseCommit: "abc123", filesChanged: 0, insertions: 0, deletions: 0),
            artifacts: .init(events: "events.jsonl")
        )
    }

    // MARK: - Pricing

    @Test("A million tokens each way costs the input rate plus the output rate")
    func pricesFromTokens() {
        let cost = makeCatalog().listCostUSD(
            model: "vendor/Model-One",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        #expect(cost == 1.5)
    }

    @Test("Cost scales with the tokens actually used")
    func pricesPartialMillions() throws {
        let cost = try #require(makeCatalog().listCostUSD(
            model: "vendor/Model-One",
            inputTokens: 250_000,
            outputTokens: 100_000
        ))
        // 0.25 × 0.3 + 0.1 × 1.2
        #expect(abs(cost - 0.195) < 1e-9)
    }

    @Test("A model the catalog does not price reports no cost rather than zero")
    func unknownModelHasNoCost() {
        #expect(makeCatalog().listCostUSD(
            model: "vendor/Not-Listed",
            inputTokens: 1000,
            outputTokens: 1000
        ) == nil)
    }

    @Test("A run that reported no tokens reports no cost rather than zero")
    func missingTokensHaveNoCost() {
        #expect(makeCatalog().listCostUSD(
            model: "vendor/Model-One",
            inputTokens: nil,
            outputTokens: 500
        ) == nil)
    }

    @Test("The same model reached through a gateway prices identically")
    func resolvesGatewayPrefixedIDs() {
        let catalog = makeCatalog()
        let direct = catalog.listCostUSD(model: "vendor/Model-One", inputTokens: 1_000_000, outputTokens: 0)
        let gateway = catalog.listCostUSD(model: "openrouter/vendor/model-one", inputTokens: 1_000_000, outputTokens: 0)
        #expect(direct == gateway)
        #expect(gateway == 0.3)
    }

    // MARK: - Effort

    @Test("A run that asked for the strongest setting is recorded as such")
    func recognisesMaximumEffort() throws {
        let totals = ResultsExport.ReasoningTotals.all(
            for: [makeResult(effort: "high")],
            catalog: makeCatalog()
        )
        let only = try #require(totals.first)
        #expect(only.effort == "high")
        #expect(only.maximumEffort == "high")
        #expect(only.atMaximumEffort)
    }

    @Test("A run below the strongest setting is not reported as maximum")
    func detectsBelowMaximumEffort() throws {
        let totals = ResultsExport.ReasoningTotals.all(
            for: [makeResult(effort: "low")],
            catalog: makeCatalog()
        )
        #expect(try #require(totals.first).atMaximumEffort == false)
    }

    @Test("A model exposing no effort ladder cannot be at maximum effort")
    func modelWithoutLadderIsNeverAtMaximum() throws {
        let totals = ResultsExport.ReasoningTotals.all(
            for: [makeResult()],
            catalog: makeCatalog(maximumEffort: nil)
        )
        let only = try #require(totals.first)
        #expect(only.maximumEffort == nil)
        #expect(only.effort == nil)
        // The claim would be flattering and false: there is no such setting.
        #expect(only.atMaximumEffort == false)
    }

    @Test("The same model at two efforts stays two measurements")
    func doesNotBlendDifferentEfforts() throws {
        let totals = ResultsExport.ReasoningTotals.all(
            for: [makeResult(task: "a", effort: "low"), makeResult(task: "b", effort: "high")],
            catalog: makeCatalog()
        )
        #expect(totals.count == 2)
        #expect(totals.map(\.effort) == ["high", "low"])
        #expect(totals.allSatisfy { $0.runs == 1 })
    }

    @Test("Effort recorded under the older key is still read")
    func readsLegacyVariantKey() {
        let metadata = AgentMetadata(
            agent: "opencode",
            model: "vendor/Model-One",
            configuration: ["variant": "high"]
        )
        #expect(metadata.effort == "high")
    }

    // MARK: - Reported versus list cost

    @Test("List cost and the agent's reported cost are both kept, and differ")
    func keepsBothCosts() throws {
        let totals = ResultsExport.ReasoningTotals.all(
            for: [makeResult(reportedCost: 9.99)],
            catalog: makeCatalog()
        )
        let only = try #require(totals.first)
        #expect(only.listCostUSD == 1.5)
        #expect(only.reportedCostUSD == 9.99)
        #expect(only.priceSource == "https://models.dev/api.json")
        #expect(only.priceRetrieved == "2026-09-03")
    }

    @Test("Without a catalog the export omits reasoning rather than guessing")
    func summaryOmitsReasoningWithoutCatalog() {
        let summary = ResultsExport.Summary(results: [makeResult()], attempt: .all)
        #expect(summary.reasoning == nil)
    }

    // MARK: - The pinned file on disk

    @Test("The pinned catalog decodes and prices every model it names")
    func pinnedCatalogIsUsable() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Data/model-catalog.json")
        let catalog = try ModelCatalog.load(from: url)
        #expect(!catalog.models.isEmpty)
        #expect(catalog.source.contains("models.dev"))
        for (identifier, entry) in catalog.models {
            // Zero is a real rate: free tiers exist, and a model priced at
            // zero must stay in the catalog rather than be read as unpriced.
            #expect(entry.inputCostPerMillion >= 0, "\(identifier) has no input rate")
            #expect(entry.outputCostPerMillion >= 0, "\(identifier) has no output rate")
            #expect(catalog.listCostUSD(model: identifier, inputTokens: 1_000, outputTokens: 1_000) != nil)
        }
    }

    @Test("An absent effort is written as an explicit null, not dropped")
    func encodesAbsentEffortExplicitly() throws {
        let data = try ResultsExport.json(
            for: [makeResult()],
            attempt: .latest,
            catalog: makeCatalog(maximumEffort: nil)
        )
        let document = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let reasoning = try #require(document["reasoning"] as? [[String: Any]])
        let only = try #require(reasoning.first)
        // Present-and-null, so a reader can tell "no effort was requested"
        // from "this report predates effort being recorded".
        #expect(only.keys.contains("effort"))
        #expect(only["effort"] is NSNull)
        #expect(only.keys.contains("maximum_effort"))
        #expect(only["maximum_effort"] is NSNull)
    }

    // MARK: - Cached prompt tokens

    @Test("Cached prompt tokens are priced at the cached rate, not the input rate")
    func pricesCacheSeparately() throws {
        let cost = try #require(makeCatalog().listCostUSD(
            model: "vendor/Model-One",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheReadTokens: 1_000_000
        ))
        // 0.3 for the fresh million, 0.06 for the cached one — not 0.6.
        #expect(abs(cost - 0.36) < 1e-9)
    }

    @Test("Ignoring cache understates an agentic run by multiples")
    func cacheDominatesAnAgenticRun() throws {
        // The ratio measured on real runs: roughly seven cached prompt tokens
        // for every fresh one. This is the bug that published a cost five
        // times too low, so it is pinned.
        let catalog = makeCatalog()
        let withCache = try #require(catalog.listCostUSD(
            model: "vendor/Model-One",
            inputTokens: 100_000, outputTokens: 20_000, cacheReadTokens: 700_000
        ))
        let ignoringCache = try #require(catalog.listCostUSD(
            model: "vendor/Model-One", inputTokens: 100_000, outputTokens: 20_000
        ))
        #expect(withCache > ignoringCache)
        #expect(ignoringCache / withCache < 0.8)
    }

    @Test("A run's usage prices itself, cache included")
    func pricesFromUsage() throws {
        let usage = AgentUsage(
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheReadTokens: 1_000_000,
            cacheWriteTokens: 1_000_000,
            totalTokens: 1_000_000
        )
        let cost = try #require(makeCatalog().listCostUSD(model: "vendor/Model-One", usage: usage))
        #expect(abs(cost - (0.3 + 0.06 + 0.375)) < 1e-9)
    }

    @Test("Prompt tokens count every token the model read")
    func promptTokensIncludeCache() {
        let usage = AgentUsage(inputTokens: 10, outputTokens: 99, cacheReadTokens: 70, cacheWriteTokens: 20)
        #expect(usage.promptTokens == 100)
        // Output is not a prompt token, and a run with no usage reports none.
        #expect(AgentUsage().promptTokens == nil)
    }

    @Test("The score-bearing total excludes cache, so scoring stays comparable")
    func totalTokensExcludeCache() {
        // total feeds the points efficiency multiplier. Folding cache into it
        // would rescore future runs against a different definition than every
        // published one.
        let usage = AgentUsage(
            inputTokens: 10_000, outputTokens: 2_000,
            cacheReadTokens: 500_000, totalTokens: 12_000
        )
        #expect(usage.totalTokens == 12_000)
        #expect(AppleBenchScore.efficiency(totalTokens: usage.totalTokens) == 1.0)
    }
}
