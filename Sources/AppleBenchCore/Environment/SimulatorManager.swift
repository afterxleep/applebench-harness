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

    /// Prefix every device this benchmark creates carries, and the only thing
    /// that makes one safe to delete. A developer's own simulators hold state
    /// they care about and are never touched.
    public static let deviceNamePrefix = "AppleBench-"

    /// The devices this benchmark left behind, from `simctl list devices --json`.
    ///
    /// A booted leftover counts: an unexpected booted device is what makes the
    /// next `xcodebuild test` hang against its own destination, so it is the
    /// most important one to reap, not the one to skip.
    public static func staleBenchmarkDeviceUDIDs(
        listJSON: String,
        excluding liveUDID: String?,
        claimedUDIDs: Set<String> = []
    ) throws -> [String] {
        struct Listing: Decodable {
            struct Device: Decodable {
                let udid: String
                let name: String
            }
            let devices: [String: [Device]]
        }
        guard let data = listJSON.data(using: .utf8) else {
            throw BenchmarkFailure.infrastructureFailure("simctl list produced no readable output")
        }
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        return listing.devices.values
            .flatMap { $0 }
            .filter {
                $0.name.hasPrefix(deviceNamePrefix)
                    && $0.udid != liveUDID
                    // Another run in flight owns this one. Deleting it fails
                    // that run's grading and records the loss against its
                    // model, which is how ops-005 and g2-flow-002 died.
                    && !claimedUDIDs.contains($0.udid)
            }
            .map(\.udid)
            .sorted()
    }

    /// Deletes every simulator this benchmark left behind, apart from the one
    /// a run is currently using.
    ///
    /// Runs are killed: by an operator, by a CI timeout, by a crash. None of
    /// those paths reach teardown, so each one strands a device, and a suite
    /// of a hundred-odd tasks strands a hundred-odd. Sweeping at the start of
    /// a run recovers from every one of them, whatever ended the last run.
    @discardableResult
    public func reapStaleDevices(
        excluding liveUDID: String? = nil,
        claimedUDIDs: Set<String> = []
    ) async -> Int {
        guard let json = try? await simctl(["list", "devices", "--json"], describe: "list devices"),
              let stale = try? Self.staleBenchmarkDeviceUDIDs(
                  listJSON: json, excluding: liveUDID, claimedUDIDs: claimedUDIDs
              )
        else { return 0 }
        var reaped = 0
        for udid in stale {
            await shutdown(udid: udid)
            if await deleteVerifying(udid: udid) { reaped += 1 }
        }
        return reaped
    }

    /// Deletes a device and confirms it is gone, retrying once.
    ///
    /// `simctl shutdown` returns before the device has finished shutting down,
    /// so a delete issued immediately after can fail on a busy device. The old
    /// code discarded that failure, which is how a run that looked clean left
    /// a simulator behind every time.
    @discardableResult
    public func deleteVerifying(udid: String) async -> Bool {
        for attempt in 0..<2 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(2))
                await shutdown(udid: udid)
            }
            _ = try? await simctl(["delete", udid], describe: "delete device")
            guard let json = try? await simctl(["list", "devices", "--json"], describe: "list devices") else {
                return false
            }
            if !json.contains(udid) { return true }
        }
        return false
    }

    public func erase(udid: String) async throws {
        try await simctl(["erase", udid], describe: "erase device")
    }

    public func delete(udid: String) async {
        await deleteVerifying(udid: udid)
    }

    /// Installs the app, re-booting and retrying when CoreSimulator is not
    /// ready for it yet.
    ///
    /// A benchmark sweep creates and destroys a simulator per run, and under
    /// that churn `simctl install` intermittently reports `Invalid device`,
    /// `Unable to lookup in current state: Shutdown`, or a `Failed to create
    /// promise` from the installer — none of which say anything about the app
    /// being installed. Treating those as a verdict turns an unstable service
    /// into a suite full of broken fixtures, which is exactly how they first
    /// showed up here.
    public func install(udid: String, appURL: URL) async throws {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await simctl(["install", udid, appURL.path], describe: "install app")
                return
            } catch {
                lastError = error
                guard attempt < 2 else { break }
                // The device is the thing that is usually wrong, so make sure
                // it is actually up before spending the next attempt.
                _ = try? await simctl(
                    ["bootstatus", udid, "-b"],
                    describe: "wait for device",
                    timeout: .seconds(300)
                )
                try? await Task.sleep(for: .seconds(3))
            }
        }
        throw lastError ?? BenchmarkFailure.infrastructureFailure("install app failed")
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
