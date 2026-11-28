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
        #expect(permission["websearch"] == "deny")
        #expect(permission["codesearch"] == "deny")
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

    @Test("A step the provider cut off for length is reported as truncated")
    func truncatedStep() throws {
        let parser = OpenCodeOutputParser()
        let line = """
        {"type":"step-finish","part":{"reason":"length"},"tokens":{"input":900,"output":0,"reasoning":31999}}
        """
        let event = try #require(parser.parse(line: line))
        #expect(event.outputTruncated)
    }

    @Test("A step that finished normally is not truncated")
    func completedStepIsNotTruncated() throws {
        let parser = OpenCodeOutputParser()
        let line = """
        {"type":"step-finish","part":{"reason":"stop"},"tokens":{"input":900,"output":120}}
        """
        let event = try #require(parser.parse(line: line))
        #expect(!event.outputTruncated)
    }

    @Test("A run whose last step was cut off for length is not reported as completed")
    func truncatedRunIsNotCompleted() throws {
        let outcome = CLIAgentSession.Outcome(
            processResult: ProcessExecutionResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                duration: .seconds(1),
                timedOut: false
            ),
            usage: AgentUsage(),
            finalResponse: nil,
            reportedFailure: nil,
            parsedEventCount: 3,
            outputTruncated: true
        )

        #expect(CLIAgentSession.terminationReason(for: outcome) == .outputTruncated)
    }

    @Test("The agent is given room to answer after thinking")
    func outputCeilingIsRaised() throws {
        let extra = OpenCodeAdapter.processEnvironment(configPath: "/tmp/opencode.json")

        #expect(extra["OPENCODE_CONFIG"] == "/tmp/opencode.json")
        // OpenCode caps output at 32k by default and a max-effort variant can
        // spend all of it on hidden reasoning, leaving nothing for the answer.
        #expect(extra["OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX"] == "64000")
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

    @Test("Provider errors preserve their message and retryability")
    func providerError() throws {
        let parser = OpenCodeOutputParser()
        let line = #"{"type":"error","error":{"name":"APIError","data":{"message":"User not found.","statusCode":401,"isRetryable":false}}}"#

        let event = try #require(parser.parse(line: line))

        #expect(event.kind == .error)
        #expect(event.failure?.message == "User not found.")
        #expect(event.failure?.statusCode == 401)
        #expect(event.failure?.isRetryable == false)
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

    @Test("Only the provider the run's model uses reaches its config")
    func providersAreScopedToTheModel() throws {
        let providers = #"{"minimax":{"options":{"apiKey":"minimax-secret"}},"openrouter":{"options":{"baseURL":"https://openrouter.ai/api/v1"}}}"#

        let scoped = try #require(
            OpenCodeAdapter.providers(providers, scopedTo: "openrouter/moonshotai/kimi-k3")
        )

        let json = try #require(try JSONSerialization.jsonObject(with: Data(scoped.utf8)) as? [String: Any])
        #expect(Set(json.keys) == ["openrouter"])
        #expect(!scoped.contains("minimax-secret"))
    }

    @Test("A model whose provider has no block receives no other provider's settings")
    func unrelatedProvidersAreDropped() {
        let providers = #"{"minimax":{"options":{"apiKey":"minimax-secret"}}}"#

        #expect(OpenCodeAdapter.providers(providers, scopedTo: "openrouter/moonshotai/kimi-k3") == nil)
    }

    /// A host OpenCode database with two logins and a private session.
    private func makeHostStore() throws -> (dir: URL, host: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let host = dir.appendingPathComponent("host.db")
        _ = try OpenCodeAdapter.sqlite(host, readOnly: false, [
            "create table migration (id text primary key, time_completed integer not null);",
            "create table credential (id text primary key, integration_id text, label text not null, value text not null, time_updated integer not null);",
            "create table session (id text primary key, title text);",
            "insert into migration values ('m1', 1);",
            #"insert into credential values ('cred_a', 'openai', 'OpenAI', '{"type":"oauth","refresh":"openai-refresh"}', 1);"#,
            #"insert into credential values ('cred_b', 'openrouter', 'API key', '{"type":"key","key":"router-key"}', 1);"#,
            #"insert into credential values ('cred_c', 'openrouter', 'Sign-in', '{"type":"oauth","refresh":"router-refresh"}', 1);"#,
            "insert into session values ('s1', 'private user session');",
        ])
        return (dir, host)
    }

    @Test("Credentials carried into a run hold only the model's provider")
    func credentialsAreScopedToTheModel() throws {
        let (dir, host) = try makeHostStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("run.db")

        let carried = try OpenCodeAdapter.carryCredentials(from: host, to: store, provider: "openrouter")

        // The API key stays out: it reaches the run through its environment variable.
        #expect(carried == ["cred_c": #"{"type":"oauth","refresh":"router-refresh"}"#])
        let dump = try OpenCodeAdapter.sqlite(store, readOnly: true, [".dump"])
        #expect(!dump.contains("openai-refresh"))
        #expect(!dump.contains("private user session"))
        #expect(dump.contains("'m1'"))
    }

    @Test("A credential the agent refreshed is kept without disturbing other providers")
    func refreshedCredentialIsWrittenBack() throws {
        let (dir, host) = try makeHostStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("run.db")
        let carried = try OpenCodeAdapter.carryCredentials(from: host, to: store, provider: "openai")
        _ = try OpenCodeAdapter.sqlite(store, readOnly: false, [
            #"update credential set value = '{"type":"oauth","refresh":"rotated"}' where id = 'cred_a';"#
        ])

        try OpenCodeAdapter.writeBackCredentials(from: store, original: carried, to: host)

        let values = try OpenCodeAdapter.credentialValues(in: host)
        #expect(values["cred_a"] == #"{"type":"oauth","refresh":"rotated"}"#)
        #expect(values["cred_b"] == #"{"type":"key","key":"router-key"}"#)
    }

    @Test("Only OpenCode 2 or later is accepted")
    func versionGate() {
        #expect(OpenCodeAdapter.isSupportedVersion("opencode v2.2.0"))
        #expect(!OpenCodeAdapter.isSupportedVersion("1.18.31"))
        #expect(!OpenCodeAdapter.isSupportedVersion(""))
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
        #expect(arguments.contains(["--model", "openrouter/anthropic/claude-sonnet-4.5#high"]))
        #expect(arguments.contains("--standalone"))
    }

    @Test("No effort means no variant, so the provider default stands")
    func absentEffortOmitsVariant() {
        let arguments = OpenCodeAdapter.agentArguments(
            model: "m",
            effort: nil,
            additionalArguments: [],
            prompt: "Fix it."
        )
        #expect(arguments.contains(["--model", "m"]))
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

    @Test("OpenCode resolves the ripgrep executable used by its file tools")
    func resolvesRipgrepHelper() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-rg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("rg")
        FileManager.default.createFile(
            atPath: helper.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        #expect(OpenCodeAdapter.helperExecutable(named: "rg", path: directory.path) == helper)
        #expect(OpenCodeAdapter.helperExecutable(named: "rg", path: "/usr/bin") == nil)
    }

    @Test("The Xcode shim disables only the nested package manifest sandbox")
    func installsXcodeShim() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-shim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        let directory = try OpenCodeAdapter.installToolchainShims(in: home)
        let shim = directory.appendingPathComponent("xcodebuild")
        let contents = try String(contentsOf: shim, encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: shim.path))
        #expect(contents.contains("/usr/bin/xcodebuild"))
        #expect(contents.contains("-IDEPackageSupportDisableManifestSandbox=1"))
        #expect(contents.contains("-IDEPackageSupportDisablePluginExecutionSandbox=1"))
        #expect(!contents.contains("sandbox-exec"))
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

    @Test("Subagent session ids are read from the launch notice, once each")
    func subagentSessionIDs() {
        let text = """
        {"output":"The subagent is working in the background (sessionID: ses_abc123). You will receive"}
        {"output":"(sessionID: ses_abc123)"} {"output":"(sessionID: ses_Def456)"}
        """
        #expect(OpenCodeAdapter.subagentSessionIDs(in: text) == ["ses_abc123", "ses_Def456"])
    }

    @Test("An exported child session's tool calls take the streamed part shape")
    func exportedToolParts() throws {
        let export = """
        {"info":{"id":"ses_x"},"messages":[{"type":"assistant","content":[
          {"type":"text","text":"hi"},
          {"type":"tool","name":"read","state":{"status":"completed","input":{"filePath":"/secret/x"},
           "content":[{"type":"text","text":"line one"},{"type":"text","text":"line two"}]}}]}]}
        """
        let object = try JSONSerialization.jsonObject(with: Data(export.utf8))
        let parts = OpenCodeAdapter.toolParts(inExport: object)
        #expect(parts.count == 1)
        #expect(parts.first?["tool"] as? String == "read")
        let state = parts.first?["state"] as? [String: Any]
        #expect(state?["output"] as? String == "line one\nline two")
        #expect((state?["input"] as? [String: Any])?["filePath"] as? String == "/secret/x")
    }
}
