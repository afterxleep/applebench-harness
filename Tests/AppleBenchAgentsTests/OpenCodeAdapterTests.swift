import Foundation
import Testing
@testable import AppleBenchAgents
@testable import AppleBenchCore

@Suite("OpenCode adapter")
struct OpenCodeAdapterTests {
    @Test("Hermetic configuration denies web access and auto-approves edits")
    func hermeticConfig() throws {
        let data = Data(OpenCodeAdapter.hermeticConfiguration.utf8)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let permission = try #require(json["permission"] as? [String: String])
        #expect(permission["webfetch"] == "deny")
        #expect(permission["edit"] == "allow")
        #expect(permission["bash"] == "allow")
        let tools = try #require(json["tools"] as? [String: Bool])
        #expect(tools["webfetch"] == false)
    }

    @Test("Tool events classify as tool calls")
    func toolEvents() throws {
        let parser = OpenCodeOutputParser()
        let line = """
        {"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"xcodebuild build"}}}
        """
        let event = try #require(parser.parse(line: line))
        #expect(event.kind == .toolCall)
    }

    @Test("Step token usage and cost accumulate as raw sums")
    func usageExtraction() throws {
        let parser = OpenCodeOutputParser()
        let line = """
        {"type":"step-finish","tokens":{"input":1200,"output":300,"reasoning":150},"cost":0.0125}
        """
        let event = try #require(parser.parse(line: line))
        #expect(event.kind == .usage)
        #expect(event.usage?.inputTokens == 1200)
        #expect(event.usage?.outputTokens == 300)
        #expect(event.usage?.totalTokens == 1650)
        #expect(event.usage?.estimatedCostUSD == 0.0125)
    }

    @Test("Nested part payloads are understood")
    func nestedPart() throws {
        let parser = OpenCodeOutputParser()
        let line = """
        {"type":"message.part.updated","part":{"type":"text","text":"Fixed the decoding bug."}}
        """
        let event = try #require(parser.parse(line: line))
        #expect(event.kind == .message)
        #expect(event.finalResponse == "Fixed the decoding bug.")
    }

    @Test("Non-JSON lines are ignored, never faked")
    func nonJSON() {
        let parser = OpenCodeOutputParser()
        #expect(parser.parse(line: "Compiling FeedFixture...") == nil)
        #expect(parser.parse(line: "") == nil)
    }

    @Test("Configuration without a provider override is the hermetic base verbatim")
    func configurationWithoutProvider() throws {
        let config = try OpenCodeAdapter.configuration(providerJSON: nil)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        #expect(json["provider"] == nil)
        let permission = try #require(json["permission"] as? [String: String])
        #expect(permission["webfetch"] == "deny")
    }

    @Test("A provider override is merged in without weakening the hermetic keys")
    func configurationWithProvider() throws {
        let provider = #"{"local":{"npm":"@ai-sdk/anthropic","options":{"baseURL":"http://127.0.0.1:8765/v1"}}}"#
        let config = try OpenCodeAdapter.configuration(providerJSON: provider)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])

        let providers = try #require(json["provider"] as? [String: Any])
        let local = try #require(providers["local"] as? [String: Any])
        #expect(local["npm"] as? String == "@ai-sdk/anthropic")

        // The sandbox guarantees survive the merge.
        let permission = try #require(json["permission"] as? [String: String])
        #expect(permission["webfetch"] == "deny")
        let tools = try #require(json["tools"] as? [String: Bool])
        #expect(tools["webfetch"] == false)
    }

    @Test("A provider override that is not a JSON object is rejected, not spliced")
    func configurationRejectsMalformedProvider() {
        #expect(throws: BenchmarkFailure.self) {
            try OpenCodeAdapter.configuration(providerJSON: "not json at all")
        }
        #expect(throws: BenchmarkFailure.self) {
            try OpenCodeAdapter.configuration(providerJSON: #"["an","array"]"#)
        }
    }

    @Test("A provider override cannot re-enable web access")
    func providerCannotReopenTheSandbox() throws {
        let hostile = #"{"__proto__":{},"local":{"npm":"x"}}"#
        let config = try OpenCodeAdapter.configuration(providerJSON: hostile)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        let tools = try #require(json["tools"] as? [String: Bool])
        #expect(tools["webfetch"] == false)
    }

    @Test("Provider override resolves from inline JSON or a file path")
    func providerResolution() throws {
        let inline = #"{"local":{"npm":"@ai-sdk/anthropic"}}"#
        #expect(try OpenCodeAdapter.resolveProviderJSON(from: inline) == inline)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-provider-\(UUID().uuidString).json")
        try inline.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        #expect(try OpenCodeAdapter.resolveProviderJSON(from: fileURL.path) == inline)

        #expect(try OpenCodeAdapter.resolveProviderJSON(from: nil) == nil)
        #expect(try OpenCodeAdapter.resolveProviderJSON(from: "   ") == nil)
    }

    @Test("A provider override naming a missing file fails loudly")
    func providerMissingFile() {
        #expect(throws: BenchmarkFailure.self) {
            try OpenCodeAdapter.resolveProviderJSON(from: "/nonexistent/applebench/provider.json")
        }
    }
}
