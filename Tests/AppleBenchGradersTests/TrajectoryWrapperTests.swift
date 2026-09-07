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

extension TrajectoryWrapperTests {
    @Test("A wrapper the shell could not find was not used")
    func commandNotFoundIsNotUse() {
        // ops-010 typed `xcbuild`, a tool that does not exist on the machine,
        // got "command not found", and was failed for having used a wrapper.
        // Typing a name is not the work being done by it; only an invocation
        // that ran counts.
        let ran = TrajectoryGrader.wrappersUsed(in: [
            ("xcbuild -project App.xcodeproj -scheme App", "zsh:1: command not found: xcbuild"),
            ("fastlane beta", "sandbox-exec: execvp() of 'fastlane' failed: Operation not permitted"),
        ])
        #expect(ran.isEmpty)
    }

    @Test("A wrapper that produced output did run")
    func wrapperWithOutputCounts() {
        let ran = TrajectoryGrader.wrappersUsed(in: [("fastlane beta", "[fastlane] Driving the lane 'beta'")])
        #expect(ran == ["fastlane"])
    }
}

@Suite("Mutation summaries")
struct MutationDescriptionTests {
    @Test("A pattern mutation is described as a pattern, not as nil")
    func patternIsDescribed() {
        let m = SourceMutation(path: "Sources/V.swift", pattern: #"\.accessibilityIdentifier\("([^"]+)"\)"#, with: ".accessibilityIdentifier(\"$1-mutated\")")
        let text = MutationGrader.describe(m)
        #expect(!text.contains("nil"))
        #expect(!text.contains("$1"))
        #expect(text.contains("every match"))
    }

    @Test("A literal mutation still shows what was swapped")
    func literalIsQuoted() {
        let m = SourceMutation(path: "Sources/CounterStore.swift", replace: "count += 1", with: "count += 2")
        #expect(MutationGrader.describe(m) == "Sources/CounterStore.swift: \"count += 1\" → \"count += 2\"")
    }
}

/// What the mutation grader does when some or none of its mutations apply.
@Suite("Mutation planning")
struct MutationPlanTests {
    private let literal = SourceMutation(path: "Sources/Store.swift", replace: "count += 1", with: "count += 2")
    private let quoted = SourceMutation(path: "Sources/View.swift", pattern: #"\.accessibilityIdentifier\("([^"]+)"\)"#, with: #".accessibilityIdentifier("$1-mutated")"#)
    private let expression = SourceMutation(path: "Sources/View.swift", pattern: #"\.accessibilityIdentifier\(([A-Za-z_][A-Za-z0-9_.]*(?:\([^()]*\))?)\)"#, with: #".accessibilityIdentifier(($1) + "-mutated")"#)

    @Test("A computed identifier is caught by the expression pattern when the quoted one finds nothing")
    func expressionFormApplies() throws {
        // MiniMax M3 rewrote `.accessibilityIdentifier("result-\(index)")` as
        // `.accessibilityIdentifier(Self.identifier(for: part))`. Its test still
        // drove the app by identifier; the quoted pattern just could not see it.
        let source = "Text(part)\n    .accessibilityIdentifier(Self.identifier(for: part))\n"
        let plan = try MutationGrader.plan([quoted, expression], sources: ["Sources/View.swift": source])
        guard case .apply(let applied, let skipped) = plan else { Issue.record("expected apply"); return }
        #expect(applied.count == 1 && skipped.count == 1)
        #expect(applied[0].mutated.contains(#".accessibilityIdentifier((Self.identifier(for: part)) + "-mutated")"#))
    }

    @Test("When every pattern finds nothing, the app has no identifiers and that is a failure")
    func noIdentifiersIsAFailure() throws {
        // The prompts on these tasks require the test to drive the app by
        // accessibility identifier. An app with none left is not an app the
        // grader cannot judge; it is an app the agent stripped of the thing
        // the task asked for.
        let plan = try MutationGrader.plan([quoted, expression], sources: ["Sources/View.swift": "Text(part)\n"])
        guard case .fail(let summary) = plan else { Issue.record("expected fail"); return }
        #expect(summary.contains("no accessibility identifier"))
    }

    @Test("A literal that no longer exists is the task's problem, not the agent's")
    func missingLiteralIsAnError() {
        #expect(throws: BenchmarkFailure.self) {
            _ = try MutationGrader.plan([literal], sources: ["Sources/Store.swift": "func increment() { total = total + 1 }"])
        }
    }

    @Test("A missing file is an error whatever the mutation kind")
    func missingFileIsAnError() {
        #expect(throws: BenchmarkFailure.self) {
            _ = try MutationGrader.plan([quoted], sources: [:])
        }
    }
}

extension TrajectoryWrapperTests {
    @Test("A wrapper's name inside a longer path is not that wrapper")
    func absolutePathToAnAppleToolIsNotAWrapper() {
        // M3 ran Xcode's own xcbuild, at its full path inside Xcode.app, while
        // investigating a build failure. The detector took the last path
        // component and saw the third-party tool of the same name. It also
        // read `gem list` as CocoaPods territory when the agent was only
        // asking what was installed.
        let ran = TrajectoryGrader.wrappersUsed(in: [
            ("/Applications/Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/Support/xcbuild help", "build clang-scan"),
            ("/Applications/Xcode-27.0.0-beta.6.app/Contents/Developer/usr/bin/xcodebuild -list", "Information about project"),
        ])
        #expect(ran.isEmpty)
    }

    @Test("A wrapper on the machine's own path still counts")
    func installedWrapperCounts() {
        #expect(TrajectoryGrader.wrappersUsed(in: [("/opt/homebrew/bin/xcodegen generate", "Loaded project.yml")]) == ["xcodegen"])
        #expect(TrajectoryGrader.wrappersUsed(in: [("xcbuild -project App.xcodeproj", "Build succeeded")]) == ["xcbuild"])
    }
}
