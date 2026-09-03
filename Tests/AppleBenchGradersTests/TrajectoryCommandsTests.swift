import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("Trajectory command reading")
struct TrajectoryCommandsTests {
    @Test("Only finished commands are read, and only their command text")
    func readsFinishedCommands() {
        let log = """
        {"type":"command_started","payload":{"command":"/usr/bin/xcodebuild build"}}
        {"type":"command_finished","payload":{"command":"/usr/bin/xcodebuild build","exit_code":0}}
        {"type":"agent_output","payload":{"text":"command_finished"}}
        {"type":"command_finished","payload":{"command":"xcrun simctl launch booted app"}}
        not json at all
        """
        // A started command is not a command that ran, and agent output that
        // happens to contain the word must never be counted as one.
        let commands = TrajectoryGrader.commands(in: log)
        #expect(commands == ["/usr/bin/xcodebuild build", "xcrun simctl launch booted app"])
    }

    @Test("An empty log yields nothing rather than failing")
    func emptyLog() {
        #expect(TrajectoryGrader.commands(in: "").isEmpty)
    }
}
