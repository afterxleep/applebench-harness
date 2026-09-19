import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Simulator claims")
struct SimulatorClaimsTests {
    @Test("A device claimed by a run under one runs directory is protected from a run under another")
    func claimsAreSharedAcrossRunsDirectories() throws {
        let benchmarkRuns = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-claims-benchmark-\(UUID().uuidString)", isDirectory: true)
        let verificationRuns = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-claims-verify-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: benchmarkRuns)
            try? FileManager.default.removeItem(at: verificationRuns)
        }
        let udid = "CLAIM-\(UUID().uuidString)"

        SimulatorClaims.claim(udid, in: benchmarkRuns)
        defer { SimulatorClaims.release(udid, in: benchmarkRuns) }

        #expect(SimulatorClaims.active(in: verificationRuns).contains(udid))
    }

    @Test("A released device is no longer protected anywhere")
    func releaseRemovesTheClaimEverywhere() throws {
        let runs = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-claims-release-\(UUID().uuidString)", isDirectory: true)
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-claims-other-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: runs)
            try? FileManager.default.removeItem(at: other)
        }
        let udid = "CLAIM-\(UUID().uuidString)"

        SimulatorClaims.claim(udid, in: runs)
        SimulatorClaims.release(udid, in: runs)

        #expect(!SimulatorClaims.active(in: runs).contains(udid))
        #expect(!SimulatorClaims.active(in: other).contains(udid))
    }
}
