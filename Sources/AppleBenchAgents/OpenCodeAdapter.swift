import AppleBenchCore
import Foundation

/// Runs OpenCode non-interactively via `opencode run`.
///
/// OpenCode is multi-provider, so it doubles as the single fixed harness for
/// comparing models: `--model <provider/model>` (and `--effort`, mapped to
/// OpenCode's `--variant`) vary the model while the harness stays constant.
///
/// Hermetic by default:
/// - `OPENCODE_CONFIG` points at a benchmark-owned config written into the
///   run directory (outside the workspace), replacing the user's global
///   configuration — no user MCP servers, instructions, or providers leak in.
/// - The config denies the `webfetch` tool: no internet from the agent's
///   toolset.
/// - `--pure` disables external plugins.
/// - `--auto` approves the remaining (explicitly allowed) permissions so runs
///   never block on prompts.
/// What this does not do is isolate the process. OpenCode exposes no OS
/// sandbox, so folder confinement relies on the isolated workspace plus
/// AppleBench's deferred evaluator metadata, and denying `webfetch` removes
/// the agent's network tool without stopping it shelling out to `curl`.
/// `TartOpenCodeAdapter` is the mode where both are enforced rather than
/// configured, and a published run should say which one it used.
///
/// Telemetry: structured. `--format json` emits raw JSON events which are
/// preserved verbatim; tool events, per-step token usage, and cost are
/// extracted where present and left `null` where not — never guessed.
public final class OpenCodeAdapter: AgentAdapter, @unchecked Sendable {
    public let identifier = "opencode"
    public let telemetry = AgentTelemetryCapability.structured

    private let options: AgentRegistry.Options
    private let executable = "opencode"
    private var sanitizedTempDir: URL?
    private var hermeticHome: URL?

    public init(options: AgentRegistry.Options) {
        self.options = options
    }

    /// Resolved from PATH so the sandbox can allow the agent to run itself.
    public var executableURL: URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":").map(String.init) {
            let candidate = "\(directory)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Environment variable naming an OpenCode `provider` block to merge into
    /// the hermetic config. The value is either inline JSON or a path to a
    /// JSON file. Use it to point runs at a self-hosted or proxied endpoint
    /// without giving the harness knowledge of any particular vendor.
    public static let providerOverrideEnvironmentKey = "APPLEBENCH_OPENCODE_PROVIDER"

    public func prepare(context: RunContext) async throws {
        try CLIAgentSession.requireExecutable(executable)
        let providerJSON = try Self.resolveProviderJSON(
            from: ProcessInfo.processInfo.environment[Self.providerOverrideEnvironmentKey]
        )
        let config = try Self.configuration(providerJSON: providerJSON)
        do {
            try config.write(to: Self.configURL(for: context), atomically: true, encoding: .utf8)
        } catch {
            throw BenchmarkFailure.agentLaunchFailure("Could not write OpenCode config: \(error)")
        }
    }

    /// Interprets the provider-override value as either a path to a JSON file
    /// or inline JSON. A value that names a file which cannot be read is an
    /// error rather than a silent fallback: a run that quietly ignores the
    /// requested provider would be scored against the wrong endpoint.
    static func resolveProviderJSON(
        from value: String?,
        hostConfigs: [URL] = hostConfigURLs
    ) throws -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Nothing was asked for, so carry over whatever the host defines.
            // A scored run redirects HOME to keep user skills out, which also
            // hides the config where a custom provider's endpoint and key
            // live. Without this the agent has no provider and every task
            // fails before reaching a model.
            return try hostProviders(at: hostConfigs)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        guard let contents = try? String(contentsOfFile: trimmed, encoding: .utf8) else {
            throw BenchmarkFailure.agentLaunchFailure(
                "\(providerOverrideEnvironmentKey) names a file that could not be read: \(trimmed)"
            )
        }
        return contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where OpenCode keeps its user configuration, in the order it reads them.
    static var hostConfigURLs: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return ["opencode.jsonc", "opencode.json"].map {
            home.appendingPathComponent(".config/opencode/\($0)")
        }
    }

    /// The `provider` block from the first host config that defines one.
    ///
    /// Only `provider` is taken. Skills, agents and the rest of the user's
    /// configuration stay out, which is the whole point of the hermetic home:
    /// a scored run must not inherit tooling the next machine will not have.
    static func hostProviders(at urls: [URL]) throws -> String? {
        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let root = jsonObject(from: text),
                  let provider = root["provider"] as? [String: Any],
                  !provider.isEmpty,
                  let data = try? JSONSerialization.data(
                      withJSONObject: provider, options: [.sortedKeys, .withoutEscapingSlashes]
                  )
            else { continue }
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }

    /// Parses JSON with comments and trailing commas, which is what OpenCode's
    /// own `.jsonc` config is written in.
    static func jsonObject(from text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return root
        }
        var cleaned = text.replacingOccurrences(
            of: #"(?m)(^|\s)//[^\n]*"#, with: "", options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #",(\s*[}\]])"#, with: "$1", options: .regularExpression
        )
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The `opencode run` argument list for one task.
    ///
    /// Separate from `run` so what reaches the agent can be asserted without
    /// launching one. Two things here change a published number: the variant,
    /// which is how OpenCode names reasoning effort, and the prompt staying
    /// last, since a prompt that drifted in front of a flag would be read as
    /// that flag's value.
    static func agentArguments(
        model: String?,
        effort: String?,
        additionalArguments: [String],
        prompt: String
    ) -> [String] {
        var arguments = ["run", "--format", "json", "--pure", "--auto"]
        if let model {
            arguments += ["--model", model]
        }
        if let effort {
            // OpenCode calls reasoning effort a model "variant" (minimal,
            // low, medium, high, max), and which of those exist is decided by
            // the provider, so the value is forwarded rather than checked.
            arguments += ["--variant", effort]
        }
        arguments += additionalArguments
        arguments.append(prompt)
        return arguments
    }

    public func run(
        task: BenchmarkTask,
        context: RunContext,
        recorder: EventRecorder
    ) async throws -> AgentRunResult {
        let arguments = Self.agentArguments(
            model: context.model,
            effort: context.effort,
            additionalArguments: options.additionalArguments,
            prompt: task.prompt
        )

        var environment = context.agentEnvironment(
            extra: [
                "OPENCODE_CONFIG": Self.configURL(for: context).path
            ]
        )
        if context.stripWrapperCLIs, let harnessPath = environment["PATH"] {
            do {
                let sanitized = try RunContext.sanitizedPath(
                    forAgentBinary: executable,
                    in: harnessPath
                )
                environment["PATH"] = sanitized.path
                sanitizedTempDir = sanitized.tempDir
            } catch {
                environment["PATH"] = RunContext.filterWrapperCLIs(
                    from: harnessPath,
                    agentBinaryNames: [executable]
                )
            }
        }

        // When the run strips wrapper CLIs, also redirect HOME to a
        // fresh temp dir so the agent cannot auto-load user-installed
        // skills (e.g. `flowdeck`) that would shortcut the raw-toolchain
        // requirement. Auth is carried over by symlinking the host's
        // opencode auth dir into the hermetic home — without that, the
        // harness launches an authenticated binary that cannot reach the
        // provider. (Skills are still absent because the symlink is to
        // the auth dir only, not to ~/.config/opencode/skills.)
        if context.stripWrapperCLIs {
            let home = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("applebench-home-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            hermeticHome = home
            for key in ["HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME"] {
                switch key {
                case "HOME": environment["HOME"] = home.path
                case "XDG_CONFIG_HOME": environment[key] = home.appendingPathComponent(".config").path
                case "XDG_CACHE_HOME": environment[key] = home.appendingPathComponent(".cache").path
                case "XDG_DATA_HOME": environment[key] = home.appendingPathComponent(".local/share").path
                default: break
                }
            }
            // Carry auth over so the agent can still reach its
            // provider. OpenCode stores its auth at
            // ~/.local/share/opencode/auth.json. Symlink just that
            // file (not the whole .local/share dir) so no skills or
            // state leak in.
            let realAuth = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".local/share/opencode/auth.json")
            let hermeticAuthDir = home.appendingPathComponent(".local/share/opencode")
            try? FileManager.default.createDirectory(
                at: hermeticAuthDir,
                withIntermediateDirectories: true
            )
            let hermeticAuth = hermeticAuthDir.appendingPathComponent("auth.json")
            if FileManager.default.fileExists(atPath: realAuth.path) {
                try? FileManager.default.createSymbolicLink(
                    atPath: hermeticAuth.path,
                    withDestinationPath: realAuth.path
                )
            }
        }

        // Seal the agent inside its workspace. Hiding wrapper CLIs from PATH
        // stops it reaching for a tool; it does nothing about reading the
        // answer, which sits on the same disk under the same user. Applied to
        // the agent only: the graders run afterwards and need the paths this
        // denies.
        var launchExecutable = executable
        var launchArguments = arguments
        var sandboxApplied = false
        if let sandbox = context.sandbox {
            // The run directory is denied because it holds the task's grader
            // specification and every other run's results. OpenCode's own
            // config lives there too, and it cannot start without reading it.
            let sealed = sandbox.allowingRead([Self.configURL(for: context)])
            guard let wrapped = try sealed.wrap(
                executable: executable,
                arguments: arguments,
                profileURL: context.runDirectoryURL.appendingPathComponent("agent.sb")
            ) else {
                throw BenchmarkFailure.agentLaunchFailure(
                    "This run asked for a sealed agent but \(AgentSandbox.sandboxExec) is missing, "
                        + "so the answers would be readable. Refusing rather than running unsealed."
                )
            }
            launchExecutable = wrapped.executable
            launchArguments = wrapped.arguments
            sandboxApplied = true
            await recorder.record(.warning, payload: .object([
                "message": .string("Agent sealed: reference solutions, task files and other runs are unreadable.")
            ]))
        }

        let outcome = try await CLIAgentSession.execute(
            invocation: .init(
                executable: launchExecutable,
                arguments: launchArguments,
                environment: environment,
                parser: OpenCodeOutputParser()
            ),
            context: context,
            recorder: recorder
        )

        let version = await CLIAgentSession.toolVersion(executable: executable)
        var configuration = [
            "mode": "run --format json --pure --auto",
            "isolation": "none (host process)",
            // Denying webfetch takes away the agent's network tool. It does
            // not stop the process reaching the network, because bash is
            // allowed and curl is on PATH. Only the VM adapter enforces
            // egress, so saying so here stops a local run's own record from
            // reading as a stronger claim than it is.
            "network": "unrestricted (host egress; --vm denies it)",
            "web_access": "disabled (webfetch denied)",
            "plugins": "disabled (--pure)",
            "user_config": "ignored (OPENCODE_CONFIG)",
        ]
        if let effort = context.effort {
            configuration["effort"] = effort
        }
        configuration["answer_isolation"] = sandboxApplied
            ? "sealed (solutions, task files and other runs denied)"
            : "none (answers readable on the host filesystem)"
        return AgentRunResult(
            metadata: AgentMetadata(
                agent: identifier,
                model: context.model,
                version: version,
                configuration: configuration
            ),
            terminationReason: CLIAgentSession.terminationReason(for: outcome),
            exitCode: outcome.processResult.exitCode,
            usage: outcome.usage,
            finalResponse: outcome.finalResponse
        )
    }

    public func cleanup(context: RunContext) async {
        if let dir = sanitizedTempDir {
            try? FileManager.default.removeItem(at: dir)
            sanitizedTempDir = nil
        }
        if let home = hermeticHome {
            try? FileManager.default.removeItem(at: home)
            hermeticHome = nil
        }
    }

    static func configURL(for context: RunContext) -> URL {
        context.runDirectoryURL.appendingPathComponent("opencode.json")
    }

    /// Benchmark-owned OpenCode configuration: hermetic and non-interactive.
    ///
    /// A `provider` block may be merged in at `prepare(context:)` time from
    /// `APPLEBENCH_OPENCODE_PROVIDER`, so a run can target a self-hosted or
    /// proxied endpoint. The merge never relaxes the sandbox keys below.
    static let hermeticConfiguration = """
    {
      "$schema": "https://opencode.ai/config.json",
      "permission": {
        "edit": "allow",
        "bash": "allow",
        "webfetch": "deny"
      },
      "tools": {
        "webfetch": false
      }
    }
    """

    /// Builds the on-disk OpenCode config, merging an optional `provider`
    /// block into the hermetic base.
    ///
    /// The merge goes through `JSONSerialization` rather than string splicing:
    /// a malformed override then fails the run loudly instead of writing a
    /// config OpenCode silently rejects, and the sandbox keys are re-applied
    /// after the merge so an override can never re-open web access.
    static func configuration(providerJSON: String?) throws -> String {
        guard var root = try? JSONSerialization.jsonObject(with: Data(hermeticConfiguration.utf8)) as? [String: Any] else {
            throw BenchmarkFailure.agentLaunchFailure("The built-in OpenCode configuration is not valid JSON")
        }

        if let providerJSON, !providerJSON.isEmpty {
            guard let data = providerJSON.data(using: .utf8),
                  let provider = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw BenchmarkFailure.agentLaunchFailure(
                    "\(providerOverrideEnvironmentKey) must be a JSON object mapping provider ids to their configuration"
                )
            }
            root["provider"] = provider
        }

        // Re-assert the sandbox after any merge.
        root["permission"] = ["edit": "allow", "bash": "allow", "webfetch": "deny"]
        root["tools"] = ["webfetch": false]

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }
}

/// Tolerant parser for `opencode run --format json` event lines.
///
/// The event stream is versioned by OpenCode, so this parser avoids exact
/// shapes: every JSON line is preserved verbatim as a structured event;
/// classification and usage extraction use OpenCode's stable vocabulary
/// (part types, `tokens` objects with input/output/reasoning, per-step
/// `cost`) and degrade to `.other` rather than guessing.
struct OpenCodeOutputParser: AgentOutputParser {
    func parse(line: String) -> ParsedAgentEvent? {
        guard let data = line.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object = value
        else { return nil }

        // Events may carry the payload at the top level or under "part".
        let part = value["part"] ?? value
        let type = part["type"]?.stringValue ?? value["type"]?.stringValue ?? ""

        var kind: ParsedAgentEvent.Kind = .other
        if type.contains("tool") {
            kind = .toolCall
        } else if type == "text" || type == "reasoning" || type.contains("message") {
            kind = .message
        } else if type.contains("finish") || type.contains("step") {
            kind = .usage
        }

        var usage: AgentUsage?
        if let tokens = part["tokens"] ?? value["tokens"] {
            let input = tokens["input"]?.intValue
            let output = tokens["output"]?.intValue
            let reasoning = tokens["reasoning"]?.intValue
            // OpenCode reports cached prompt tokens separately from fresh
            // input, and on an agentic run they are most of what the model
            // read: every step re-sends the whole conversation, so cache reads
            // outrun fresh input by roughly seven to one. Dropping them
            // understates the prompt by most of its size and prices the run at
            // a fraction of what it cost.
            let cache = tokens["cache"]
            let cacheRead = cache?["read"]?.intValue
            let cacheWrite = cache?["write"]?.intValue
            // `total` deliberately excludes cache: it feeds the points score's
            // efficiency multiplier, and folding cache reads into it would
            // rescore every future run against a different definition than the
            // published ones, making the two incomparable. Cache is carried in
            // its own fields, where cost can price it without moving a score.
            let counted = [input, output, reasoning].compactMap { $0 }
            let total: Int? = counted.isEmpty ? nil : counted.reduce(0, +)
            var cost: Double?
            if case .double(let value)? = part["cost"] ?? value["cost"] { cost = value }
            if case .int(let value)? = part["cost"] ?? value["cost"] { cost = Double(value) }
            usage = AgentUsage(
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite,
                totalTokens: total,
                estimatedCostUSD: cost
            )
            if kind == .other { kind = .usage }
        }

        var finalResponse: String?
        if type == "text", let text = part["text"]?.stringValue {
            finalResponse = text
        }

        return ParsedAgentEvent(kind: kind, payload: value, usage: usage, finalResponse: finalResponse)
    }
}
