import Foundation

/// Inspects the machine and validates that a task's environment requirements
/// can be satisfied.
///
/// Validation is strict: if the required Xcode version or simulator runtime
/// is unavailable, the run fails before any agent is launched. Environments
/// are never silently substituted.
public protocol BenchmarkEnvironment: Sendable {
    func snapshot() async throws -> EnvironmentSnapshot
    func validate(task: BenchmarkTask, against snapshot: EnvironmentSnapshot) throws
}

extension BenchmarkEnvironment {
    public func validate(task: BenchmarkTask) async throws {
        try validate(task: task, against: try await snapshot())
    }
}

/// Production environment inspection built on `sw_vers`, `uname`,
/// `xcode-select`, `xcodebuild` and `simctl`.
public struct XcodeEnvironment: BenchmarkEnvironment {
    private let processRunner: any ProcessRunning

    public init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    public func snapshot() async throws -> EnvironmentSnapshot {
        async let macos = output("/usr/bin/sw_vers", ["-productVersion"])
        async let architecture = output("/usr/bin/uname", ["-m"])
        async let xcodePath = output("/usr/bin/xcode-select", ["-p"])
        async let xcodeVersionText = output("/usr/bin/xcodebuild", ["-version"])
        async let simulators = simulatorInventory()

        let versionLines = try await xcodeVersionText.split(separator: "\n").map(String.init)
        let version = versionLines.first?.replacingOccurrences(of: "Xcode ", with: "") ?? "unknown"
        let build = versionLines
            .first { $0.hasPrefix("Build version") }?
            .replacingOccurrences(of: "Build version ", with: "") ?? "unknown"

        let inventory = try await simulators
        return EnvironmentSnapshot(
            macosVersion: try await macos,
            architecture: try await architecture,
            xcodePath: try await xcodePath,
            xcodeVersion: version,
            xcodeBuildNumber: build,
            runtimes: inventory.runtimes,
            deviceTypes: inventory.deviceTypes,
            devices: inventory.devices
        )
    }

    public func validate(task: BenchmarkTask, against snapshot: EnvironmentSnapshot) throws {
        if let requiredXcode = task.environment.xcode {
            guard snapshot.xcodeVersion == requiredXcode
                || snapshot.xcodeVersion.hasPrefix("\(requiredXcode).")
            else {
                throw BenchmarkFailure.environmentUnavailable(
                    "Task requires Xcode \(requiredXcode) but \(snapshot.xcodeVersion) is selected at \(snapshot.xcodePath)"
                )
            }
        }
        if let simulator = task.environment.simulator {
            guard let runtime = snapshot.runtime(named: simulator.runtime), runtime.isAvailable else {
                let available = snapshot.runtimes.filter(\.isAvailable).map(\.name).joined(separator: ", ")
                throw BenchmarkFailure.environmentUnavailable(
                    "Simulator runtime '\(simulator.runtime)' is not installed. Available: \(available)"
                )
            }
            guard snapshot.deviceTypes.contains(where: { $0.name == simulator.device }) else {
                throw BenchmarkFailure.environmentUnavailable(
                    "Simulator device type '\(simulator.device)' is not available"
                )
            }
        }
    }

    // MARK: - simctl inventory

    private struct SimulatorInventory {
        var runtimes: [SimulatorRuntime]
        var deviceTypes: [SimulatorDeviceType]
        var devices: [SimulatorDevice]
    }

    private struct RuntimeList: Decodable {
        struct Runtime: Decodable {
            var name: String
            var identifier: String
            var version: String
            var isAvailable: Bool
        }
        var runtimes: [Runtime]
    }

    private struct DeviceTypeList: Decodable {
        struct DeviceType: Decodable {
            var name: String
            var identifier: String
        }
        var devicetypes: [DeviceType]
    }

    private struct DeviceList: Decodable {
        struct Device: Decodable {
            var name: String
            var udid: String
            var state: String
            var isAvailable: Bool
        }
        var devices: [String: [Device]]
    }

    private func simulatorInventory() async throws -> SimulatorInventory {
        async let runtimesJSON = output("/usr/bin/xcrun", ["simctl", "list", "runtimes", "--json"])
        async let deviceTypesJSON = output("/usr/bin/xcrun", ["simctl", "list", "devicetypes", "--json"])
        async let devicesJSON = output("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])

        let decoder = JSONDecoder()
        let runtimes = try decoder.decode(RuntimeList.self, from: Data(try await runtimesJSON.utf8))
        let deviceTypes = try decoder.decode(DeviceTypeList.self, from: Data(try await deviceTypesJSON.utf8))
        let devices = try decoder.decode(DeviceList.self, from: Data(try await devicesJSON.utf8))

        return SimulatorInventory(
            runtimes: runtimes.runtimes.map {
                SimulatorRuntime(name: $0.name, identifier: $0.identifier, version: $0.version, isAvailable: $0.isAvailable)
            },
            deviceTypes: deviceTypes.devicetypes.map {
                SimulatorDeviceType(name: $0.name, identifier: $0.identifier)
            },
            devices: devices.devices.flatMap { runtimeIdentifier, devices in
                devices.map {
                    SimulatorDevice(
                        name: $0.name,
                        udid: $0.udid,
                        runtimeIdentifier: runtimeIdentifier,
                        state: $0.state,
                        isAvailable: $0.isAvailable
                    )
                }
            }
        )
    }

    private func output(_ executable: String, _ arguments: [String]) async throws -> String {
        let result = try await processRunner.run(
            ProcessCommand(executable: executable, arguments: arguments),
            timeout: .seconds(60),
            outputHandler: nil
        )
        guard result.exitCode == 0 else {
            throw BenchmarkFailure.infrastructureFailure(
                "'\(executable) \(arguments.joined(separator: " "))' failed: \(result.standardError)"
            )
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension EnvironmentSnapshot {
    public func runtime(named name: String) -> SimulatorRuntime? {
        runtimes.first { $0.name == name }
    }

    public func deviceType(named name: String) -> SimulatorDeviceType? {
        deviceTypes.first { $0.name == name }
    }

    public func summary(for task: BenchmarkTask) -> BenchmarkRunResult.EnvironmentSummary {
        BenchmarkRunResult.EnvironmentSummary(
            macos: macosVersion,
            architecture: architecture,
            xcode: xcodeVersion,
            xcodeBuild: xcodeBuildNumber,
            simulator: task.environment.simulator?.device,
            runtime: task.environment.simulator?.runtime
        )
    }
}
