import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Trajectory grader configuration")
struct TrajectoryGraderConfigurationTests {
    @Test("A grader that claims nothing is rejected")
    func emptyIsInvalid() {
        #expect(throws: BenchmarkFailure.self) { try TrajectoryGraderConfiguration().validate() }
    }

    @Test("An assertion needs a pattern, and the pattern has to compile")
    func patternIsChecked() {
        #expect(throws: BenchmarkFailure.self) {
            try TrajectoryGraderConfiguration(assertions: [.init(atLeast: 1)]).validate()
        }
        #expect(throws: BenchmarkFailure.self) {
            try TrajectoryGraderConfiguration(assertions: [.init(commandMatches: "xcodebuild[")]).validate()
        }
        #expect(throws: Never.self) {
            try TrajectoryGraderConfiguration(minTestInvocations: 1).validate()
        }
    }

    @Test("Decodes from the shape a task file writes")
    func decodes() throws {
        let json = """
        {"min_test_invocations": 1,
         "assertions": [{"command_matches": "xcodebuild.*test", "at_least": 2}]}
        """
        let c = try JSONDecoder().decode(TrajectoryGraderConfiguration.self, from: Data(json.utf8))
        #expect(c.minTestInvocations == 1)
        #expect(c.assertions.first?.atLeast == 2)
    }
}
