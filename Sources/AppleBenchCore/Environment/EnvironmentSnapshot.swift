import Foundation

/// A record of the machine environment at run time, captured for
/// reproducibility and embedded (summarized) in `result.json`.
public struct EnvironmentSnapshot: Sendable, Codable, Equatable {
    public var macosVersion: String
    public var architecture: String
    public var xcodePath: String
    /// e.g. "27.0"
    public var xcodeVersion: String
    /// e.g. "17A123"
    public var xcodeBuildNumber: String
    public var runtimes: [SimulatorRuntime]
    public var deviceTypes: [SimulatorDeviceType]
    public var devices: [SimulatorDevice]
    public var capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case macosVersion = "macos_version"
        case architecture
        case xcodePath = "xcode_path"
        case xcodeVersion = "xcode_version"
        case xcodeBuildNumber = "xcode_build_number"
        case runtimes
        case deviceTypes = "device_types"
        case devices
        case capturedAt = "captured_at"
    }

    public init(
        macosVersion: String,
        architecture: String,
        xcodePath: String,
        xcodeVersion: String,
        xcodeBuildNumber: String,
        runtimes: [SimulatorRuntime] = [],
        deviceTypes: [SimulatorDeviceType] = [],
        devices: [SimulatorDevice] = [],
        capturedAt: Date = Date()
    ) {
        self.macosVersion = macosVersion
        self.architecture = architecture
        self.xcodePath = xcodePath
        self.xcodeVersion = xcodeVersion
        self.xcodeBuildNumber = xcodeBuildNumber
        self.runtimes = runtimes
        self.deviceTypes = deviceTypes
        self.devices = devices
        self.capturedAt = capturedAt
    }
}

public struct SimulatorRuntime: Sendable, Codable, Equatable {
    /// e.g. "iOS 27.0"
    public var name: String
    /// e.g. "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    public var identifier: String
    /// e.g. "27.0"
    public var version: String
    public var isAvailable: Bool

    public init(name: String, identifier: String, version: String, isAvailable: Bool) {
        self.name = name
        self.identifier = identifier
        self.version = version
        self.isAvailable = isAvailable
    }
}

public struct SimulatorDeviceType: Sendable, Codable, Equatable {
    /// e.g. "iPhone 17 Pro"
    public var name: String
    /// e.g. "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
    public var identifier: String

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

public struct SimulatorDevice: Sendable, Codable, Equatable {
    public var name: String
    public var udid: String
    public var runtimeIdentifier: String
    /// e.g. "Booted", "Shutdown"
    public var state: String
    public var isAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case name, udid, state
        case runtimeIdentifier = "runtime_identifier"
        case isAvailable = "is_available"
    }

    public init(name: String, udid: String, runtimeIdentifier: String, state: String, isAvailable: Bool) {
        self.name = name
        self.udid = udid
        self.runtimeIdentifier = runtimeIdentifier
        self.state = state
        self.isAvailable = isAvailable
    }
}
