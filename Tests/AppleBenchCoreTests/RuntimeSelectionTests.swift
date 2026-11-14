import Testing
@testable import AppleBenchCore

@Suite("Simulator runtime selection")
struct RuntimeSelectionTests {
    private let phone = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"

    /// A hardware variant (the iPhone Duo runtime) can be installed beside the
    /// stock runtime under the same name. Picking it first made every device
    /// creation fail with "Incompatible device".
    private var snapshot: EnvironmentSnapshot {
        EnvironmentSnapshot(
            macosVersion: "27.0", architecture: "arm64", xcodePath: "/Applications/Xcode.app",
            xcodeVersion: "27.2", xcodeBuildNumber: "27B52",
            runtimes: [
                SimulatorRuntime(
                    name: "iOS 27.2", identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4",
                    version: "27.2", isAvailable: true,
                    supportedDeviceTypes: ["com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"]),
                SimulatorRuntime(
                    name: "iOS 27.2", identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                    version: "27.2", isAvailable: true,
                    supportedDeviceTypes: [phone, "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"]),
            ]
        )
    }

    @Test("The runtime that supports the device type wins")
    func supportingRuntimeWins() {
        #expect(snapshot.runtime(named: "iOS 27.2", supporting: phone)?.identifier
                == "com.apple.CoreSimulator.SimRuntime.iOS-27-2")
    }

    @Test("Without a device type, the stock runtime wins over a single-device variant")
    func stockRuntimeWinsByDefault() {
        #expect(snapshot.runtime(named: "iOS 27.2")?.identifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-2")
    }
}
