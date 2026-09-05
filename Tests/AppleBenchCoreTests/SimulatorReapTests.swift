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

/// Reaping must not delete a device another run is using.
@Suite("Reaping and concurrent runs")
struct SimulatorReapOwnershipTests {
    private func listing(_ names: [(String, String)]) -> String {
        let devices = names.map { #"{"udid":"\#($0.1)","name":"\#($0.0)"}"# }.joined(separator: ",")
        return #"{"devices":{"iOS 26.5":[\#(devices)]}}"#
    }

    @Test("A device belonging to another live run is left alone")
    func spareOtherLiveRuns() throws {
        // Every AppleBench device except the caller's own was reaped, so a
        // second run lost its simulator mid-grade and the failure was recorded
        // against the model. ops-005 and g2-flow-002 both died this way.
        let json = listing([
            ("AppleBench-run-a", "AAA"),   // the caller's
            ("AppleBench-run-b", "BBB"),   // another run, still going
            ("AppleBench-run-c", "CCC"),   // finished, fair game
        ])
        let stale = try SimulatorManager.staleBenchmarkDeviceUDIDs(
            listJSON: json, excluding: "AAA", claimedUDIDs: ["BBB"]
        )
        #expect(stale == ["CCC"])
    }

    @Test("With nothing claimed, everything but the caller's is still reaped")
    func stillCleansStrandedDevices() throws {
        let json = listing([("AppleBench-a", "AAA"), ("AppleBench-b", "BBB")])
        let stale = try SimulatorManager.staleBenchmarkDeviceUDIDs(
            listJSON: json, excluding: "AAA", claimedUDIDs: []
        )
        #expect(stale == ["BBB"])
    }
}
