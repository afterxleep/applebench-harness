import Foundation

/// Wraps `xcrun simctl` for benchmark simulator lifecycle management.
///
/// Isolation: AppleBench creates a dedicated simulator per run (named after
/// the run ID) rather than mutating the developer's existing simulators, and
/// deletes it afterwards. The device is erased state by construction.
public struct SimulatorManager: Sendable {
    private let processRunner: any ProcessRunning
    private let commandTimeout: Duration = .seconds(300)

    public init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Creates a fresh, dedicated simulator for this run.
    public func createDevice(
        name: String,
        requirement: SimulatorRequirement,
        snapshot: EnvironmentSnapshot
    ) async throws -> String {
        guard let deviceType = snapshot.deviceType(named: requirement.device) else {
            throw BenchmarkFailure.environmentUnavailable("Unknown simulator device type '\(requirement.device)'")
        }
        guard let runtime = snapshot.runtime(named: requirement.runtime), runtime.isAvailable else {
            throw BenchmarkFailure.environmentUnavailable("Simulator runtime '\(requirement.runtime)' unavailable")
        }
        let udid = try await simctl(
            ["create", name, deviceType.identifier, runtime.identifier],
            describe: "create device"
        )
        return udid
    }

    /// Boots the device and blocks until it has finished booting.
    public func bootAndWait(udid: String) async throws {
        try await simctl(["bootstatus", udid, "-b"], describe: "boot device", timeout: .seconds(600))
    }

    public func shutdown(udid: String) async {
        // Best effort; the device may already be shut down.
        _ = try? await simctl(["shutdown", udid], describe: "shutdown device")
    }

    public func erase(udid: String) async throws {
        try await simctl(["erase", udid], describe: "erase device")
    }

    public func delete(udid: String) async {
        _ = try? await simctl(["delete", udid], describe: "delete device")
    }

    public func install(udid: String, appURL: URL) async throws {
        try await simctl(["install", udid, appURL.path], describe: "install app")
    }

    /// Launches the app and returns the host-visible process identifier.
    public func launch(udid: String, bundleIdentifier: String) async throws -> pid_t {
        let output = try await simctl(["launch", udid, bundleIdentifier], describe: "launch app")
        // Output shape: "<bundle-identifier>: <pid>"
        guard let pidText = output.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
              let pid = pid_t(pidText)
        else {
            throw BenchmarkFailure.infrastructureFailure("Could not parse launch output: '\(output)'")
        }
        return pid
    }

    public func terminate(udid: String, bundleIdentifier: String) async {
        _ = try? await simctl(["terminate", udid, bundleIdentifier], describe: "terminate app")
    }

    public func screenshot(udid: String, to url: URL) async throws {
        try await simctl(["io", udid, "screenshot", url.path], describe: "screenshot")
    }

    /// Whether a process is still alive. Simulator app processes run as host
    /// processes, so a plain signal-0 probe works.
    public func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    @discardableResult
    private func simctl(
        _ arguments: [String],
        describe description: String,
        timeout: Duration? = nil
    ) async throws -> String {
        let result: ProcessExecutionResult
        do {
            result = try await processRunner.run(
                ProcessCommand(executable: "/usr/bin/xcrun", arguments: ["simctl"] + arguments),
                timeout: timeout ?? commandTimeout,
                outputHandler: nil
            )
        } catch {
            throw BenchmarkFailure.infrastructureFailure("simctl \(description): \(error)")
        }
        guard result.exitCode == 0 else {
            throw BenchmarkFailure.infrastructureFailure(
                "simctl \(description) failed (exit \(result.exitCode.map(String.init) ?? "signal")): \(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
