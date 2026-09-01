import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Reaping benchmark simulators")
struct SimulatorReapTests {
    private let listJSON = """
    {"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
        {"udid":"AAA","name":"AppleBench-2026-09-01T1200-runtime-002-opencode","state":"Shutdown","isAvailable":true},
        {"udid":"BBB","name":"AppleBench-2026-09-01T1300-build-002-fake","state":"Booted","isAvailable":true},
        {"udid":"CCC","name":"iPhone 17","state":"Shutdown","isAvailable":true}
      ],
      "com.apple.CoreSimulator.SimRuntime.iOS-18-5":[
        {"udid":"DDD","name":"AppleBench-2026-08-31T0900-ops-005-solution","state":"Shutdown","isAvailable":true},
        {"udid":"EEE","name":"My Test Phone","state":"Shutdown","isAvailable":true}
      ]
    }}
    """

    @Test("Only devices this benchmark created are reaped")
    func onlyBenchmarkDevices() throws {
        let stale = try SimulatorManager.staleBenchmarkDeviceUDIDs(listJSON: listJSON, excluding: nil)
        #expect(Set(stale) == ["AAA", "BBB", "DDD"])
    }

    @Test("A developer's own simulators are never touched")
    func leavesUserDevicesAlone() throws {
        let stale = try SimulatorManager.staleBenchmarkDeviceUDIDs(listJSON: listJSON, excluding: nil)
        // Deleting one of these would destroy state a person cares about.
        #expect(!stale.contains("CCC"))
        #expect(!stale.contains("EEE"))
    }

    @Test("The device the current run is using is left alone")
    func excludesTheLiveDevice() throws {
        let stale = try SimulatorManager.staleBenchmarkDeviceUDIDs(listJSON: listJSON, excluding: "BBB")
        #expect(Set(stale) == ["AAA", "DDD"])
    }

    @Test("A booted leftover is still reaped, since that is what wedges the next run")
    func reapsBootedLeftovers() throws {
        let stale = try SimulatorManager.staleBenchmarkDeviceUDIDs(listJSON: listJSON, excluding: nil)
        #expect(stale.contains("BBB"))
    }

    @Test("Unparseable output yields nothing rather than guessing")
    func unparseableIsEmpty() {
        #expect(throws: (any Error).self) {
            try SimulatorManager.staleBenchmarkDeviceUDIDs(listJSON: "not json", excluding: nil)
        }
    }
}
