import AppleBenchCore
import Foundation

/// Configuration for running the agent inside a Tart virtual machine.
public struct TartConfiguration: Sendable {
    /// Name of a user-prepared Tart image with Xcode and OpenCode installed.
    /// The image is booted directly (no per-run clone) and stopped afterwards.
    public var image: String
    public var sshUser: String
    public var sshPassword: String
    /// CIDRs the guest may reach. Egress is default-deny
    /// (`--net-softnet-block=0.0.0.0/0`); leave empty for a fully offline VM
    /// (local models), or allow the model provider's ranges.
    public var allowedCIDRs: [String]

    public init(
        image: String,
        sshUser: String = "admin",
        sshPassword: String = "admin",
        allowedCIDRs: [String] = []
    ) {
        self.image = image
        self.sshUser = sshUser
        self.sshPassword = sshPassword
        self.allowedCIDRs = allowedCIDRs
    }
}

/// Boots and drives the benchmark VM through the `tart` CLI.
///
/// The guest sees exactly two virtiofs shares: the run workspace
/// (read-write — it is the agent's working copy) and a read-only directory
/// containing only the hermetic OpenCode configuration. Nothing else from the
/// host is reachable, and Softnet blocks all network egress except explicitly
/// allowed CIDRs.
actor TartVM {
    static let workspaceGuestPath = "/Volumes/My Shared Files/workspace"
    static let configGuestPath = "/Volumes/My Shared Files/benchconfig"

    private let configuration: TartConfiguration
    private let processRunner: any ProcessRunning
    private var runTask: Task<Void, Never>?
    private(set) var ipAddress: String?

    init(configuration: TartConfiguration, processRunner: any ProcessRunning = ProcessRunner()) {
        self.configuration = configuration
        self.processRunner = processRunner
    }

    /// The `tart run` arguments that define the guest's isolation: what it can
    /// reach on the network and what it can see of this host.
    ///
    /// Separate from `start` so the isolation is assertable without booting a
    /// VM. The properties a published run depends on are all decided here.
    static func runArguments(
        configuration: TartConfiguration,
        workspaceURL: URL,
        configDirectoryURL: URL
    ) -> [String] {
        var arguments = [
            "run", configuration.image,
            "--no-graphics",
            "--net-softnet",
            // No internet: default-deny every destination…
            "--net-softnet-block=0.0.0.0/0",
        ]
        // …then allow only what the operator explicitly opened. The block
        // stays in place, so an allow narrows the denial rather than lifting it.
        if !configuration.allowedCIDRs.isEmpty {
            arguments.append("--net-softnet-allow=\(configuration.allowedCIDRs.joined(separator: ","))")
        }
        // The only two paths on this host the guest can see. The harness, the
        // graders and the rest of the filesystem stay unreachable.
        arguments.append("--dir=workspace:\(workspaceURL.path)")
        arguments.append("--dir=benchconfig:\(configDirectoryURL.path):ro")
        return arguments
    }

    /// Boots the image with the two benchmark mounts and waits until SSH is
    /// accepting commands.
    func start(workspaceURL: URL, configDirectoryURL: URL) async throws {
        let arguments = Self.runArguments(
            configuration: configuration,
            workspaceURL: workspaceURL,
            configDirectoryURL: configDirectoryURL
        )
        let command = ProcessCommand(executable: "tart", arguments: arguments)
        let runner = processRunner
        runTask = Task {
            // Runs for the lifetime of the VM; cancellation (via stop())
            // terminates the process group, shutting the VM down.
            _ = try? await runner.run(command, timeout: nil, outputHandler: nil)
        }

        // Resolve the guest IP, then wait for SSH readiness.
        let ip = try await resolveIP()
        ipAddress = ip
        try await waitForSSH()
    }

    /// Runs a command in the guest over SSH. The remote command string must
    /// already be safely quoted (see `shellQuote`).
    nonisolated func sshInvocation(remoteCommand: String, ip: String) -> ProcessCommand {
        ProcessCommand(
            executable: "sshpass",
            arguments: [
                "-p", configuration.sshPassword,
                "ssh",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-o", "ConnectTimeout=15",
                "\(configuration.sshUser)@\(ip)",
                "--",
                remoteCommand,
            ]
        )
    }

    func execute(remoteCommand: String, timeout: Duration?) async throws -> ProcessExecutionResult {
        guard let ipAddress else {
            throw BenchmarkFailure.agentLaunchFailure("Tart VM is not running")
        }
        return try await processRunner.run(
            sshInvocation(remoteCommand: remoteCommand, ip: ipAddress),
            timeout: timeout,
            outputHandler: nil
        )
    }

    /// Stops the VM (graceful `tart stop`, then hard-cancels the run task).
    func stop() async {
        _ = try? await processRunner.run(
            ProcessCommand(executable: "tart", arguments: ["stop", configuration.image]),
            timeout: .seconds(60),
            outputHandler: nil
        )
        runTask?.cancel()
        runTask = nil
        ipAddress = nil
    }

    // MARK: - Boot internals

    private func resolveIP() async throws -> String {
        for _ in 0..<6 {
            let result = try? await processRunner.run(
                ProcessCommand(executable: "tart", arguments: ["ip", configuration.image, "--wait", "30"]),
                timeout: .seconds(45),
                outputHandler: nil
            )
            if let result, result.exitCode == 0 {
                let ip = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !ip.isEmpty { return ip }
            }
            try await Task.sleep(for: .seconds(5))
        }
        throw BenchmarkFailure.agentLaunchFailure(
            "Tart VM '\(configuration.image)' did not report an IP address. Is the image name correct (`tart list`)?"
        )
    }

    private func waitForSSH() async throws {
        for _ in 0..<36 {
            if let result = try? await execute(remoteCommand: "true", timeout: .seconds(20)),
               result.exitCode == 0 {
                return
            }
            try await Task.sleep(for: .seconds(5))
        }
        throw BenchmarkFailure.agentLaunchFailure(
            "Could not reach the Tart VM over SSH as '\(configuration.sshUser)'. Check the image's SSH credentials."
        )
    }
}

/// Quotes a string for safe inclusion in a POSIX shell command line
/// (single-quote quoting with embedded-quote escaping). SSH hands the guest a
/// command string that the remote shell interprets, so every dynamic value —
/// including the task prompt — must pass through this.
func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
