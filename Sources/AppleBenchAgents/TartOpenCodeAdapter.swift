import AppleBenchCore
import Foundation

/// Runs OpenCode inside a Tart VM — the required mode for real benchmark
/// runs ("This should be run on an isolated VM with no internet access").
///
/// Isolation properties:
/// - The guest is a user-prepared Tart image (Xcode + OpenCode installed,
///   models authenticated). It is booted directly and stopped after the run.
/// - The guest sees exactly two host folders: the run workspace (read-write)
///   and a read-only mount containing only the hermetic OpenCode config.
///   The evaluation harness, grader configuration, and the rest of the host
///   filesystem are physically unreachable.
/// - Softnet default-denies all network egress (`--net-softnet-block=
///   0.0.0.0/0`). A fully offline image (local models) needs nothing more;
///   hosted-model images may open provider CIDRs via `--vm-allow`.
/// - The same hermetic OpenCode config as local runs applies (webfetch
///   denied, `--pure`, benchmark-owned config, auto-approved permissions).
///
/// Grading still happens on the host, against the workspace, after the VM
/// has been stopped.
public struct TartOpenCodeAdapter: AgentAdapter {
    public let identifier = "opencode-vm"
    public let telemetry = AgentTelemetryCapability.structured

    private let options: AgentRegistry.Options
    private let tart: TartConfiguration
    private let vm: TartVM

    public init(options: AgentRegistry.Options, tart: TartConfiguration) {
        self.options = options
        self.tart = tart
        self.vm = TartVM(configuration: tart)
    }

    public func prepare(context: RunContext) async throws {
        for binary in ["tart", "sshpass"] {
            do {
                _ = try ProcessRunner.resolveExecutable(ProcessCommand(executable: binary))
            } catch {
                throw BenchmarkFailure.agentLaunchFailure(
                    "'\(binary)' is required for --vm runs and was not found on PATH (brew install \(binary))."
                )
            }
        }

        // The only non-workspace file the guest can see: the hermetic
        // OpenCode configuration, in its own read-only mount.
        let configDirectory = context.runDirectoryURL.appendingPathComponent("agent-config", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try OpenCodeAdapter.hermeticConfiguration.write(
                to: configDirectory.appendingPathComponent("opencode.json"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw BenchmarkFailure.agentLaunchFailure("Could not write OpenCode config: \(error)")
        }

        try await vm.start(workspaceURL: context.workspaceURL, configDirectoryURL: configDirectory)
    }

    public func run(
        task: BenchmarkTask,
        context: RunContext,
        recorder: EventRecorder
    ) async throws -> AgentRunResult {
        guard let ip = await vm.ipAddress else {
            throw BenchmarkFailure.agentLaunchFailure("Tart VM is not running")
        }

        let remoteCommand = Self.remoteCommand(
            task: task,
            model: context.model,
            effort: context.effort,
            additionalArguments: options.additionalArguments,
            environmentAllowlist: context.environmentAllowlist
        )
        let invocation = vm.sshInvocation(remoteCommand: remoteCommand, ip: ip)

        let outcome = try await CLIAgentSession.execute(
            invocation: .init(
                executable: invocation.executable,
                arguments: invocation.arguments,
                environment: nil,
                parser: OpenCodeOutputParser(),
                displayLabel: "ssh \(tart.sshUser)@\(ip) opencode run … (vm: \(tart.image))"
            ),
            context: context,
            recorder: recorder
        )

        let version = await versionInGuest()
        var configuration = [
            "mode": "run --format json --pure --auto",
            "isolation": "tart-vm",
            "vm_image": tart.image,
            "network": tart.allowedCIDRs.isEmpty
                ? "denied (0.0.0.0/0 blocked)"
                : "denied except \(tart.allowedCIDRs.joined(separator: ","))",
            "web_access": "disabled (webfetch denied)",
            "plugins": "disabled (--pure)",
            "user_config": "ignored (OPENCODE_CONFIG)",
        ]
        if let effort = context.effort {
            configuration["variant"] = effort
        }
        return AgentRunResult(
            metadata: AgentMetadata(
                agent: identifier,
                model: context.model,
                version: version,
                configuration: configuration
            ),
            terminationReason: CLIAgentSession.terminationReason(for: outcome.processResult),
            exitCode: outcome.processResult.exitCode,
            usage: outcome.usage,
            finalResponse: outcome.finalResponse
        )
    }

    public func cleanup(context: RunContext) async {
        await vm.stop()
    }

    /// Builds the full command line executed by the guest shell. Every
    /// dynamic value — including the task prompt — is shell-quoted; the
    /// benchmark config path is fixed by the read-only mount.
    static func remoteCommand(
        task: BenchmarkTask,
        model: String?,
        effort: String?,
        additionalArguments: [String],
        environmentAllowlist: [String]
    ) -> String {
        var components: [String] = [
            "cd", shellQuote(TartVM.workspaceGuestPath), "&&",
            "OPENCODE_CONFIG=\(shellQuote("\(TartVM.configGuestPath)/opencode.json"))",
        ]
        // Explicitly allowlisted host variables (e.g. provider keys when the
        // guest image is not pre-authenticated) are forwarded by value.
        let hostEnvironment = ProcessInfo.processInfo.environment
        for key in environmentAllowlist {
            if let value = hostEnvironment[key] {
                components.append("\(key)=\(shellQuote(value))")
            }
        }
        components += ["opencode", "run", "--format", "json", "--pure", "--auto"]
        if let model {
            components += ["--model", shellQuote(model)]
        }
        if let effort {
            components += ["--variant", shellQuote(effort)]
        }
        components += additionalArguments.map(shellQuote)
        components.append(shellQuote(task.prompt))
        return components.joined(separator: " ")
    }

    private func versionInGuest() async -> String? {
        guard let result = try? await vm.execute(remoteCommand: "opencode --version", timeout: .seconds(30)),
              result.exitCode == 0 else { return nil }
        let text = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(100))
    }
}
