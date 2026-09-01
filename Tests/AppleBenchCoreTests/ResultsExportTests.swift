import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Results export")
struct ResultsExportTests {
    private func makeResult(
        task: String,
        category: BenchmarkCategory? = .build,
        difficulty: Int? = 3,
        passed: Bool = true,
        model: String? = "vendor/model-1",
        summary: String = "xcodebuild build succeeded",
        tokens: Int? = 1500,
        cost: Double? = 0.0125
    ) -> BenchmarkRunResult {
        BenchmarkRunResult(
            runID: "2026-01-01T000000-\(task)-opencode",
            task: task,
            category: category,
            difficulty: difficulty,
            tags: ["swiftui"],
            agent: AgentMetadata(agent: "opencode", model: model),
            environment: .init(macos: "27.0", architecture: "arm64", xcode: "27.0", xcodeBuild: "27A1"),
            result: .init(passed: passed, durationSeconds: 42.5, agentTermination: .completed),
            usage: AgentUsage(inputTokens: 1200, outputTokens: 300, totalTokens: tokens, estimatedCostUSD: cost),
            metrics: nil,
            graders: [.init(name: "build", passed: passed, durationSeconds: 1, summary: summary, evidence: [])],
            git: .init(baseCommit: "abc123", filesChanged: 2, insertions: 10, deletions: 4),
            artifacts: .init(events: "events.jsonl")
        )
    }

    @Test("CSV carries one header plus one row per run")
    func csvShape() throws {
        let csv = ResultsExport.csv(for: [makeResult(task: "build-002"), makeResult(task: "ops-004")])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("task,category,difficulty,agent,model,passed"))
        #expect(lines[1].hasPrefix("build-002,build,3,opencode,vendor/model-1,true"))
    }

    @Test("CSV quotes fields containing commas, quotes, and newlines")
    func csvQuoting() throws {
        let hostile = #"build failed: "no such module", line 2"# + "\nsecond line"
        let csv = ResultsExport.csv(for: [makeResult(task: "build-002", summary: hostile)])
        // The embedded newline must live inside a quoted field, so the
        // document still has exactly one header and one record.
        #expect(csv.contains(#""build:build failed: ""no such module"", line 2"#))
        let parsed = try #require(CSVProbe.parse(csv))
        #expect(parsed.count == 2)
        #expect(parsed[1].count == parsed[0].count)
    }

    @Test("Missing usage is empty, never zero")
    func missingUsageIsBlank() {
        let csv = ResultsExport.csv(for: [makeResult(task: "ops-004", tokens: nil, cost: nil)])
        let row = csv.split(separator: "\n")[1]
        let header = csv.split(separator: "\n")[0].split(separator: ",").map(String.init)
        let columns = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let tokenIndex = try! #require(header.firstIndex(of: "total_tokens"))
        #expect(columns[tokenIndex].isEmpty)
    }

    @Test("JSON export summarizes per-category and per-configuration totals")
    func jsonSummary() throws {
        let results = [
            makeResult(task: "build-002", category: .build, passed: true, cost: 0.02),
            makeResult(task: "build-002", category: .build, passed: false, cost: 0.03),
            makeResult(task: "ops-004", category: .ops, passed: true, cost: 0.05),
        ]
        let data = try ResultsExport.json(for: results)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(root["total"] as? Int == 3)
        #expect(root["passed"] as? Int == 2)

        let categories = try #require(root["categories"] as? [[String: Any]])
        let build = try #require(categories.first { $0["category"] as? String == "build" })
        #expect(build["total"] as? Int == 2)
        #expect(build["passed"] as? Int == 1)

        let configurations = try #require(root["configurations"] as? [[String: Any]])
        #expect(configurations.count == 1)
        let only = try #require(configurations.first)
        #expect(only["label"] as? String == "opencode · vendor/model-1")
        #expect(only["passed"] as? Int == 2)
        let cost = try #require(only["total_cost_usd"] as? Double)
        #expect(abs(cost - 0.10) < 0.0001)
    }

    @Test("Categories and configurations sort deterministically")
    func deterministicOrder() throws {
        let results = [
            makeResult(task: "ops-004", category: .ops, model: "z/model"),
            makeResult(task: "build-002", category: .build, model: "a/model"),
        ]
        let root = try #require(
            try JSONSerialization.jsonObject(with: ResultsExport.json(for: results)) as? [String: Any]
        )
        let categories = try #require(root["categories"] as? [[String: Any]])
        #expect(categories.map { $0["category"] as? String } == ["build", "ops"])
        let configurations = try #require(root["configurations"] as? [[String: Any]])
        #expect(configurations.map { $0["label"] as? String } == ["opencode · a/model", "opencode · z/model"])
    }

    @Test("Runs without a category are reported, not dropped")
    func uncategorizedRunsSurvive() throws {
        let results = [makeResult(task: "adhoc-001", category: nil)]
        let root = try #require(
            try JSONSerialization.jsonObject(with: ResultsExport.json(for: results)) as? [String: Any]
        )
        #expect(root["total"] as? Int == 1)
        let categories = try #require(root["categories"] as? [[String: Any]])
        #expect(categories.map { $0["category"] as? String } == ["uncategorized"])
    }
}

/// A minimal RFC 4180 reader used only to prove the exporter's quoting
/// survives a real parse. Not part of the shipped harness.
enum CSVProbe {
    static func parse(_ text: String) -> [[String]]? {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n": row.append(field); field = ""; rows.append(row); row = []
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return inQuotes ? nil : rows
    }
}
