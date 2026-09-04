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

        // With no override and no host config to fall back on, there is no
        // provider block. The host is passed explicitly so the result does not
        // depend on whose machine runs the test.
        #expect(try OpenCodeAdapter.resolveProviderJSON(from: nil, hostConfigs: []) == nil)
        #expect(try OpenCodeAdapter.resolveProviderJSON(from: "   ", hostConfigs: []) == nil)
    }

    @Test("A provider override naming a missing file fails loudly")
    func providerMissingFile() {
        #expect(throws: BenchmarkFailure.self) {
            try OpenCodeAdapter.resolveProviderJSON(from: "/nonexistent/applebench/provider.json")
        }
    }
    @Test("Reasoning effort is passed to OpenCode as the model variant")
    func effortBecomesVariant() {
        let arguments = OpenCodeAdapter.agentArguments(
            model: "openrouter/anthropic/claude-sonnet-4.5",
            effort: "high",
            additionalArguments: [],
            prompt: "Fix it."
        )
        #expect(arguments.contains(["--variant", "high"]))
        #expect(arguments.contains(["--model", "openrouter/anthropic/claude-sonnet-4.5"]))
    }

    @Test("No effort means no variant, so the provider default stands")
    func absentEffortOmitsVariant() {
        let arguments = OpenCodeAdapter.agentArguments(
            model: "m",
            effort: nil,
            additionalArguments: [],
            prompt: "Fix it."
        )
        #expect(!arguments.contains("--variant"))
    }

    @Test("The prompt stays last, after any forwarded agent arguments")
    func promptIsLast() {
        let arguments = OpenCodeAdapter.agentArguments(
            model: "m",
            effort: "low",
            additionalArguments: ["--think", "hard"],
            prompt: "Fix it."
        )
        // A prompt that drifted in front of a flag would be read as its value.
        #expect(arguments.last == "Fix it.")
        #expect(arguments.contains(["--think", "hard"]))
    }

}

/// Carrying the host's provider definitions into a hermetic run.
///
/// Redirecting HOME keeps user-installed skills out of a scored run, but it
/// also hides `~/.config/opencode/opencode.jsonc`, where a custom provider's
/// base URL and key live. Only `auth.json` was carried over, so a run against
/// any provider defined in that file reached no model at all and every task
/// failed identically.
@Suite("OpenCode host providers")
struct OpenCodeHostProviderTests {
    private func write(_ contents: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("applebench-oc-\(UUID().uuidString).jsonc")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("The provider block is read out of the host config")
    func readsTheProviderBlock() throws {
        let url = try write("""
        {
          "$schema": "https://opencode.ai/config.json",
          "provider": { "minimax": { "options": { "apiKey": "k" } } }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let providers = try #require(try OpenCodeAdapter.hostProviders(at: [url]))
        #expect(providers.contains("minimax"))
        #expect(providers.contains("\"apiKey\""))
    }

    @Test("Comments and trailing commas do not stop it")
    func toleratesJSONC() throws {
        // The file is .jsonc and OpenCode's own docs show it commented, so a
        // strict JSON parse would fail on most real configs.
        let url = try write("""
        {
          // the provider I actually use
          "provider": {
            "minimax": { "options": { "apiKey": "k" } }, // trailing comma next
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try OpenCodeAdapter.hostProviders(at: [url]) != nil)
    }

    @Test("A config with no providers contributes nothing")
    func noProvidersIsNil() throws {
        let url = try write("{ \"$schema\": \"x\" }")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try OpenCodeAdapter.hostProviders(at: [url]) == nil)
    }

    @Test("A missing config is not an error")
    func missingConfigIsNil() throws {
        let absent = URL(fileURLWithPath: "/nowhere/\(UUID().uuidString).jsonc")
        #expect(try OpenCodeAdapter.hostProviders(at: [absent]) == nil)
    }

    @Test("The first config that defines providers wins")
    func firstMatchWins() throws {
        let empty = try write("{}")
        let real = try write("{ \"provider\": { \"ollama\": {} } }")
        defer {
            try? FileManager.default.removeItem(at: empty)
            try? FileManager.default.removeItem(at: real)
        }
        let providers = try #require(try OpenCodeAdapter.hostProviders(at: [empty, real]))
        #expect(providers.contains("ollama"))
    }

    @Test("An explicit override is preferred over the host config")
    func explicitOverrideWins() throws {
        // A run pointed at a proxy must not silently pick up the operator's
        // own endpoint instead.
        let url = try write("{ \"provider\": { \"minimax\": {} } }")
        defer { try? FileManager.default.removeItem(at: url) }
        let resolved = try #require(
            try OpenCodeAdapter.resolveProviderJSON(from: "{\"proxy\":{}}", hostConfigs: [url])
        )
        #expect(resolved.contains("proxy"))
        #expect(!resolved.contains("minimax"))
    }

    @Test("With no override the host providers are carried over")
    func hostProvidersAreCarried() throws {
        let url = try write("{ \"provider\": { \"minimax\": {} } }")
        defer { try? FileManager.default.removeItem(at: url) }
        let resolved = try #require(
            try OpenCodeAdapter.resolveProviderJSON(from: nil, hostConfigs: [url])
        )
        #expect(resolved.contains("minimax"))
    }
}
