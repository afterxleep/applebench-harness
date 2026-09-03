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

@Suite("Trajectory and the reference agents")
struct TrajectoryReferenceAgentTests {
    @Test("fake and solution are the only agents exempt from a process check")
    func referenceAgents() {
        // They exist to prove a task is sound, and neither reaches its result
        // by doing the work: one changes nothing, the other applies a patch.
        #expect(TrajectoryGrader.referenceAgents == ["fake", "solution"])
        #expect(!TrajectoryGrader.referenceAgents.contains("opencode"))
        #expect(!TrajectoryGrader.referenceAgents.contains("claude"))
    }
}
