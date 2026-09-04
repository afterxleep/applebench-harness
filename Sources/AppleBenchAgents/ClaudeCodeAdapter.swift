import AppleBenchCore
import Foundation

/// Runs Anthropic's Claude Code CLI non-interactively via `claude -p`.
///
/// Claude Code is a single-model, single-vendor harness (Anthropic
/// only). It complements OpenCodeAdapter in calibration: where
/// OpenCode lets the same harness carry every provider/model, Claude
/// Code is the cleanest "I just want the actual Claude model" path
/// without going through OpenRouter.
///
/// Confinement:
/// - `--add-dir <workspace>` scopes file access to the run workspace;
///   everything else on disk is unreachable to the agent.
/// - `--permission-mode bypassPermissions` skips the per-action
///   approval prompt so the agent runs end-to-end without
///   blocking. Use sparingly — only for benchmark tasks where
///   the agent is supposed to operate freely inside its workspace.
/// - The environment is the minimal `RunContext.agentEnvironment`,
///   so unrelated host secrets are not exposed.
///
/// Telemetry: structured. `--output-format stream-json` emits one
/// JSON object per line. Each line is parsed and classified into
/// text / tool_use / result; the final `result` line carries the
/// usage block (input_tokens / output_tokens / cache_*) which is
/// mapped into `AgentUsage`.
public final class ClaudeCodeAdapter: AgentAdapter, @unchecked Sendable {
    public let identifier = "claude"
    public let telemetry = AgentTelemetryCapability.structured

    private let options: AgentRegistry.Options
    private let executable = "claude"
    private var sanitizedTempDir: URL?
    private var hermeticHome: URL?

    public init(options: AgentRegistry.Options) {
        self.options = options
    }

    public func prepare(context: RunContext) async throws {
        try CLIAgentSession.requireExecutable(executable)
    }

    public func run(
        task: BenchmarkTask,
        context: RunContext,
        recorder: EventRecorder
    ) async throws -> AgentRunResult {
        // The harness is already in the workspace directory; `--add-dir`
        // is what scopes Claude Code's file tools to that directory.
        var arguments: [String] = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--add-dir", context.workspaceURL.path,
            "--permission-mode", "bypassPermissions",
        ]
        if let model = context.model {
            arguments += ["--model", model]
        }
        if let effort = context.effort {
            // Claude Code accepts: low, medium, high (and `max` on Opus 4.6+).
            arguments += ["--effort", effort]
        }
        arguments += options.additionalArguments
        arguments.append(task.prompt)

        // When the calibration run strips wrapper CLIs, symlink the
        // `claude` binary into a fresh temp dir and put that dir at the
        // front of PATH. That way the original `claude` directory
        // (which also contains `flowdeck`) is removed entirely from
        // PATH, while the agent's binary is still reachable.
        var environment = context.agentEnvironment(extra: [
            "CLAUDE_CODE_DISABLE_TELEMETRY": "1",
        ])
        if let harnessPath = environment["PATH"] {
            do {
                let sanitized = try RunContext.sanitizedPath(
                    forAgentBinary: executable,
                    in: harnessPath
                )
                environment["PATH"] = sanitized.path
                sanitizedTempDir = sanitized.tempDir
            } catch {
                // Fall back to the unfiltered filter; the agent's
                // binary directory may or may not contain wrappers.
                environment["PATH"] = RunContext.filterWrapperCLIs(
                    from: harnessPath,
                    agentBinaryNames: [executable]
                )
            }
        }

        // HOME is redirected to a fresh temp dir so the agent cannot
        // auto-load user-installed skills (e.g. the `flowdeck` Skill that
        // ships with the host's ~/.claude/skills/). A skill is the same
        // shortcut as the binary, reached a different way. Auth must come
        // from `ANTHROPIC_API_KEY` (already passed through
        // `agentEnvironment`).
        do {
            let home = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("applebench-home-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            hermeticHome = home
            environment["HOME"] = home.path
            environment["XDG_CONFIG_HOME"] = home.appendingPathComponent(".config").path
            environment["XDG_CACHE_HOME"] = home.appendingPathComponent(".cache").path
            environment["XDG_DATA_HOME"] = home.appendingPathComponent(".local/share").path
        }

        let outcome = try await CLIAgentSession.execute(
            invocation: .init(
                executable: executable,
                arguments: arguments,
                environment: environment,
                parser: ClaudeCodeOutputParser()
            ),
            context: context,
            recorder: recorder
        )

        let version = await CLIAgentSession.toolVersion(executable: executable)
        var configuration = [
            "mode": "-p --output-format stream-json --verbose",
            "permissions": "bypassPermissions",
            "add_dir": context.workspaceURL.path,
        ]
        if let effort = context.effort {
            configuration["effort"] = effort
        }
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
}

/// Tolerant parser for `claude -p --output-format stream-json` event
/// lines.
///
/// Claude Code's stream-json emits one JSON object per line. We
/// classify the lines as text / tool_use / result and extract
/// usage tokens from the final `result` line. Anything we don't
/// recognize is recorded as `.other` so nothing is lost.
struct ClaudeCodeOutputParser: AgentOutputParser {
    func parse(line: String) -> ParsedAgentEvent? {
        guard let data = line.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object = value
        else { return nil }

        let type = value["type"]?.stringValue ?? ""

        var kind: ParsedAgentEvent.Kind = .other
        var usage: AgentUsage?
        var finalResponse: String?

        // Assistant text + tool_use blocks live on `message.content`.
        if type == "assistant",
           case .object(let message)? = value["message"],
           case .array(let blocks)? = message["content"] {
            var collectedText = ""
            var sawToolUse = false
            for block in blocks {
                guard case .object(let b) = block else { continue }
                let blockType = b["type"]?.stringValue ?? ""
                if blockType == "text", let text = b["text"]?.stringValue {
                    collectedText += text
                } else if blockType == "tool_use" {
                    sawToolUse = true
                }
            }
            if sawToolUse { kind = .toolCall }
            else if !collectedText.isEmpty { kind = .message }
            if !collectedText.isEmpty { finalResponse = collectedText }
        }

        // The `result` line carries the final text and the usage block.
        if type == "result" {
            if let result = value["result"]?.stringValue, !result.isEmpty {
                finalResponse = result
                kind = .message
            }
            if case .object(let u)? = value["usage"] {
                let input = u["input_tokens"]?.intValue
                let output = u["output_tokens"]?.intValue
                let cacheRead = u["cache_read_input_tokens"]?.intValue
                let cacheWrite = u["cache_creation_input_tokens"]?.intValue
                // Claude Code reports cache tokens separately; the harness
                // rolls them into the `totalTokens` sum.
                let total: Int? = (input == nil && output == nil
                                    && cacheRead == nil && cacheWrite == nil)
                    ? nil
                    : (input ?? 0) + (output ?? 0)
                usage = AgentUsage(
                    inputTokens: input,
                    outputTokens: output,
                    totalTokens: total,
                    estimatedCostUSD: nil
                )
            }
        }

        return ParsedAgentEvent(kind: kind, payload: value, usage: usage, finalResponse: finalResponse)
    }
}
