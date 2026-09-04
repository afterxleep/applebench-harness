import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

/// The sandbox stops a wrapper running; this notices if one ran anyway.
///
/// Denial is a list of paths resolved when the run starts, so it cannot see a
/// wrapper reached some way that list does not describe — an interpreter, a
/// shell function, a path that appeared mid-run. The command record is written
/// by the harness and is the one part of a run the agent cannot author, so it
/// is where that shows up.
@Suite("Trajectory: wrapper detection")
struct TrajectoryWrapperTests {
    @Test("A wrapper invocation is spotted in the recorded commands")
    func spotsAWrapper() {
        let found = TrajectoryGrader.wrappersUsed(in: [
            "/usr/bin/xcodebuild -scheme App build",
            "bundle exec fastlane beta",
        ])
        #expect(found == ["fastlane"])
    }

    @Test("Apple's own tools are never mistaken for one")
    func applesToolsAreClean() {
        #expect(TrajectoryGrader.wrappersUsed(in: [
            "/usr/bin/xcodebuild -scheme App test",
            "/usr/bin/xcrun simctl list devices --json",
            "/bin/sh -c 'sips -g pixelWidth shot.png'",
        ]).isEmpty)
    }

    @Test("A wrapper named inside a path or a word is not a match")
    func noSubstringFalsePositives() {
        // `--derivedDataPath /tmp/pod-cache` is not CocoaPods, and a report
        // that mentions a tool is not the same as running it.
        #expect(TrajectoryGrader.wrappersUsed(in: [
            "/usr/bin/xcodebuild -derivedDataPath /tmp/pod-cache build",
            "/bin/echo 'we could have used fastlane here' > notes.md",
            "/usr/bin/grep -r xcodegen .",
        ]).isEmpty)
    }

    @Test("Invocation through an interpreter still counts")
    func interpreterInvocationCounts() {
        // The sandbox cannot see this one: ruby is allowed and the gem is data.
        #expect(TrajectoryGrader.wrappersUsed(in: ["/usr/bin/ruby -S fastlane gym"]) == ["fastlane"])
    }
}

/// Which commands count as "what the agent did".
@Suite("Trajectory: whose commands")
struct TrajectoryCommandSourceTests {
    private func log(_ events: [String]) -> String { events.joined(separator: "\n") }

    @Test("The agent's own shell commands are read")
    func readsAgentToolCalls() {
        // The agent runs its work through its own bash tool, which the harness
        // never spawns. Reading only the commands the harness spawned meant
        // reading everything except the work.
        let bash = #"""
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"input":{"command":"xcodebuild -list"}}}}}}
        """#
        #expect(TrajectoryGrader.commands(in: log([bash])) == ["xcodebuild -list"])
    }

    @Test("The graders' own commands are not the agent's")
    func ignoresHarnessCommands() {
        // Every task builds during grading, so counting those would satisfy
        // "the agent built the project" on a run where it did nothing at all.
        let grading = #"""
        {"type":"command_finished","payload":{"command":"/usr/bin/xcodebuild build"}}
        """#
        #expect(TrajectoryGrader.commands(in: log([grading])).isEmpty)
    }

    @Test("The sandbox wrapper that launches the agent is not a command it ran")
    func ignoresTheLaunchLine() {
        let launch = #"""
        {"type":"command_finished","payload":{"phase":"agent","command":"/usr/bin/sandbox-exec -f a.sb opencode run --model m"}}
        """#
        #expect(TrajectoryGrader.commands(in: log([launch])).isEmpty)
    }
}

extension TrajectoryWrapperTests {
    @Test("A Swift keyword in a heredoc is not a tool invocation")
    func heredocSourceIsNotATool() {
        // `struct` really is a project generator, and it is also how every
        // Swift file starts a type. Fifteen historical runs would have been
        // failed for writing Swift.
        #expect(TrajectoryGrader.wrappersUsed(in: [
            "cat > View.swift <<'EOF'\nstruct View: SwiftUI.View {\n}\nEOF",
            "/usr/bin/xcodebuild -scheme App test",
        ]).isEmpty)
    }

    @Test("Installing a tool mid-run is still caught")
    func installerIsCaught() {
        #expect(TrajectoryGrader.wrappersUsed(in: ["brew install xcodegen"]) == ["brew"])
    }
}
