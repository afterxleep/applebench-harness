import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Trajectory grader configuration")
struct TrajectoryGraderConfigurationTests {
    @Test("A grader with no clauses still claims the run used no wrapper")
    func emptyStillClaimsSomething() {
        // Asserting nothing about the commands is allowed. The grader still
        // checks the result was not reached through a wrapper, which is the
        // only claim it should make about how the work was done: two models
        // can reach the same correct outcome by different routes.
        #expect(throws: Never.self) { try TrajectoryGraderConfiguration().validate() }
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
