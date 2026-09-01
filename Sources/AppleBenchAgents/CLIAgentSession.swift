import AppleBenchCore
import Foundation

/// Shared execution logic for CLI-based agent adapters.
///
/// Runs the agent CLI with the workspace as working directory and a minimal
/// allowlisted environment, streams raw output into the event recorder as it
/// arrives, enforces the task's wall-clock timeout on the process (terminating
/// the whole process group on expiry), and — when the adapter provides a
/// parser — extracts structured events, usage, and the final response from
/// stdout after the process exits.
enum CLIAgentSession {
    struct Invocation {
        var executable: String
        var arguments: [String]
        var environment: [String: String]?
        var parser: (any AgentOutputParser)?
        /// Display string recorded in events instead of the literal command,
        /// for invocations that carry secrets (e.g. sshpass passwords).
        var displayLabel: String?
    }

    struct Outcome {
        var processResult: ProcessExecutionResult
        var usage: AgentUsage
        var finalResponse: String?
        var parsedEventCount: Int
        /// True when the run was stopped for spending its token budget rather
        /// than for running out of time or finishing.
        var budgetExceeded: Bool = false
    }

    static func execute(
        invocation: Invocation,
        context: RunContext,
        recorder: EventRecorder,
        processRunner: any ProcessRunning = ProcessRunner()
    ) async throws -> Outcome {
        let command = ProcessCommand(
            executable: invocation.executable,
            arguments: invocation.arguments,
            workingDirectory: context.workspaceURL,
            environment: invocation.environment
        )
        let displayString = invocation.displayLabel ?? command.displayString
        await recorder.record(.commandStarted, payload: .object([
            "command": .string(displayString),
            "phase": .string("agent"),
        ]))

        // A token budget needs the adapter's parser: without one there is no
        // usage to count, and guessing from raw text would invent a number.
        let budget: TokenBudget? = {
            guard let cap = context.limits.maxTokens, cap > 0, let parser = invocation.parser else { return nil }
            return TokenBudget(cap: cap, parser: parser)
        }()

        let result: ProcessExecutionResult
        do {
            let runTask = Task { () -> ProcessExecutionResult in
                try await processRunner.run(
                    command,
                    timeout: .seconds(context.limits.timeoutSeconds)
                ) { stream, text in
                    // Live raw capture; structured extraction happens post-exit.
                    Task {
                        await recorder.record(.agentOutput, payload: .object([
                            "stream": .string(stream.rawValue),
                            "text": .string(text),
                        ]))
                        if let budget, stream == .stdout {
                            await budget.consume(text)
                        }
                    }
                }
            }
            await budget?.attach(runTask)
            result = try await runTask.value
        } catch let error as ProcessRunnerError {
            throw BenchmarkFailure.agentLaunchFailure("\(error)")
        } catch is CancellationError {
            throw BenchmarkFailure.agentLaunchFailure("Agent run was cancelled")
        }

        let budgetExceeded = await budget?.isExceeded ?? false
        if budgetExceeded {
            await recorder.record(.commandFinished, payload: .object([
                "phase": .string("agent"),
                "stopped_by": .string("token_budget"),
                "tokens_spent": .int(await budget?.spent ?? 0),
                "token_budget": .int(context.limits.maxTokens ?? 0),
            ]))
        }

        var payload: [String: JSONValue] = [
            "command": .string(displayString),
            "phase": .string("agent"),
            "duration_ms": .int(Int(result.duration.milliseconds)),
        ]
        if let code = result.exitCode { payload["exit_code"] = .int(Int(code)) }
        if result.timedOut { payload["timed_out"] = .bool(true) }
        await recorder.record(.commandFinished, payload: .object(payload))

        // The complete raw agent output is preserved as an artifact alongside
        // the chunked events, so downstream analysis never depends on
        // adapter parsing.
        let outputLogURL = context.logsDirectoryURL.appendingPathComponent("agent-output.log")
        let fullOutput = result.standardOutput
            + (result.standardError.isEmpty ? "" : "\n--- stderr ---\n" + result.standardError)
        if (try? fullOutput.write(to: outputLogURL, atomically: true, encoding: .utf8)) != nil {
            await recorder.record(.artifactCreated, payload: .object([
                "path": .string("logs/agent-output.log")
            ]))
        }

        var usage = AgentUsage()
        var finalResponse: String?
        var parsedCount = 0
        if let parser = invocation.parser {
            for line in result.standardOutput.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let event = parser.parse(line: String(line)) else { continue }
                parsedCount += 1
                await recorder.record(.agentEvent, payload: .object([
                    "kind": .string(event.kind.rawValue),
                    "data": event.payload,
                ]))
                if let eventUsage = event.usage {
                    usage = accumulate(usage, eventUsage)
                }
                if let response = event.finalResponse {
                    finalResponse = response
                }
            }
        }
        if finalResponse == nil, invocation.parser == nil {
            // Plain-text CLIs: the trailing stdout is the closest thing to a
            // final response. Recorded as-is, not interpreted.
            let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            finalResponse = trimmed.isEmpty ? nil : String(trimmed.suffix(4000))
        }

        return Outcome(
            processResult: result,
            usage: usage,
            finalResponse: finalResponse,
            parsedEventCount: parsedCount,
            budgetExceeded: budgetExceeded
        )
    }

    static func terminationReason(for result: ProcessExecutionResult) -> AgentTerminationReason {
        if result.timedOut { return .timeout }
        if result.exitCode == 0 { return .completed }
        return .failed
    }

    /// The budget check comes first: stopping an agent on spend kills the
    /// process, so the raw result would otherwise read as an ordinary failure
    /// and hide which limit actually ended the run.
    static func terminationReason(for outcome: Outcome) -> AgentTerminationReason {
        if outcome.budgetExceeded { return .budgetExceeded }
        return terminationReason(for: outcome.processResult)
    }

    /// Usage events are per-step reports (OpenCode emits tokens and cost per
    /// completed step), so raw totals are sums across events. Fields no event
    /// ever reported stay `nil`, never zero.
    private static func accumulate(_ current: AgentUsage, _ update: AgentUsage) -> AgentUsage {
        func add(_ a: Int?, _ b: Int?) -> Int? {
            if a == nil && b == nil { return nil }
            return (a ?? 0) + (b ?? 0)
        }
        func add(_ a: Double?, _ b: Double?) -> Double? {
            if a == nil && b == nil { return nil }
            return (a ?? 0) + (b ?? 0)
        }
        return AgentUsage(
            inputTokens: add(current.inputTokens, update.inputTokens),
            outputTokens: add(current.outputTokens, update.outputTokens),
            totalTokens: add(current.totalTokens, update.totalTokens),
            estimatedCostUSD: add(current.estimatedCostUSD, update.estimatedCostUSD)
        )
    }

    /// Best-effort CLI version lookup for reproducibility metadata.
    static func toolVersion(
        executable: String,
        processRunner: any ProcessRunning = ProcessRunner()
    ) async -> String? {
        guard let result = try? await processRunner.run(
            ProcessCommand(executable: executable, arguments: ["--version"]),
            timeout: .seconds(20),
            outputHandler: nil
        ), result.exitCode == 0 else { return nil }
        let text = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(100))
    }

    /// Verifies the CLI binary is resolvable before a run starts.
    static func requireExecutable(_ name: String) throws {
        do {
            _ = try ProcessRunner.resolveExecutable(ProcessCommand(executable: name))
        } catch {
            throw BenchmarkFailure.agentLaunchFailure(
                "Agent CLI '\(name)' not found on PATH. Install it or adjust PATH before running."
            )
        }
    }
}
