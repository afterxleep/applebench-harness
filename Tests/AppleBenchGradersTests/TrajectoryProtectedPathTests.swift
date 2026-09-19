import AppleBenchCore
import Foundation
import Testing
@testable import AppleBenchGraders

@Suite("Trajectory: protected benchmark paths")
struct TrajectoryProtectedPathTests {
    @Test("Reading harness material outside the workspace invalidates the trajectory")
    func rejectsHarnessRead() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"read","state":{"input":{"filePath":"\(harness.path)/docs/AUTHORING.md"}}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("protected benchmark material"))
    }

    @Test("Source the agent writes may name harness paths without accessing them")
    func permitsHarnessPathsInWrittenContent() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let workspace = context.workspaceURL.path
        let source = #"let snapshot = \"\#(harness.path)/.applebench/runs/\" + \"test/workspace/snapshot.txt\""#
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"write","state":{"input":{"filePath":"\(workspace)/UITests/SnapshotTests.swift","content":"\(source)"}}}}}}
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"edit","state":{"input":{"filePath":"\(workspace)/UITests/SnapshotTests.swift","oldString":"x","newString":"\(source)"}}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("Writing a file into harness material outside the workspace invalidates the trajectory")
    func rejectsHarnessWrite() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"write","state":{"input":{"filePath":"\(harness.path)/Reports/model.json","content":"{}"}}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("protected benchmark material"))
    }

    @Test("An attempt the sandbox refused reached nothing, so the trajectory holds")
    func permitsRefusedHarnessAccess() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"write","state":{"status":"error","error":"Unknown: FileSystem.writeFile (\(harness.path)/report.txt)","input":{"filePath":"\(harness.path)/report.txt","content":"x"}}}}}}
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"ls -la \(harness.path)/"},"metadata":{"exit":1},"output":"ls: \(harness.path)/: Operation not permitted\\ntotal 0\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("A shell tool error before launch reached nothing")
    func permitsShellToolErrorBeforeLaunch() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let missingDirectory = harness.appendingPathComponent(".applebench-runs/missing/workspace")
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"error","error":"NotFound: FileSystem.access (\(missingDirectory.path))","input":{"command":"xcrun simctl list devices","workdir":"\(missingDirectory.path)"},"metadata":{"output":""}}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("A file search reporting no matches disclosed nothing")
    func permitsEmptyProtectedFileSearch() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"glob","state":{"status":"completed","input":{"pattern":"**/*.pbxproj","path":"\(harness.path)"},"output":"No files found"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("A command that was refused one path but printed another still invalidates the trajectory")
    func rejectsPartlyRefusedHarnessAccess() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"cat \(harness.path)/a \(harness.path)/b"},"metadata":{"exit":1},"output":"cat: \(harness.path)/a: Operation not permitted\\nexpected_answer = 42\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("protected benchmark material"))
    }

    @Test("A refusal for one path does not excuse another path the command reached silently")
    func rejectsSilentHarnessAccessBesideARefusal() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let workspace = context.workspaceURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"cp \(harness.path)/answers.txt \(workspace)/a.txt; ls \(harness.path)/docs"},"metadata":{"exit":1},"output":"ls: \(harness.path)/docs: Operation not permitted\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
        #expect(result.summary.contains("protected benchmark material"))
    }

    @Test("A refused command that printed nothing reached nothing")
    func permitsSilentlyRefusedHarnessAccess() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"find \(harness.path) -name answers.md 2>/dev/null"},"metadata":{"exit":1},"output":""}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("A command that printed nothing but succeeded still counts as access")
    func rejectsSilentSuccessfulHarnessAccess() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let workspace = context.workspaceURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"cp \(harness.path)/answers.md \(workspace)/a.md"},"metadata":{"exit":0},"output":""}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
    }

    @Test("Reading the run's own agent configuration is not a benchmark access")
    func permitsReadingOwnAgentConfiguration() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let runDirectory = context.runDirectoryURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"read","state":{"status":"completed","input":{"filePath":"\(runDirectory)/opencode.json"}}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("Reading the run's own event log is still an access")
    func rejectsReadingOwnEventLog() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let runDirectory = context.runDirectoryURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"read","state":{"status":"completed","input":{"filePath":"\(runDirectory)/events.jsonl"}}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
    }

    @Test("Listing the run's own directory is not a benchmark access")
    func permitsListingOwnRunDirectory() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let runDirectory = context.runDirectoryURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"ls -la \(runDirectory)"},"metadata":{"exit":0},"output":"agent.sb\\nevents.jsonl\\nopencode.json\\nworkspace\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("A refusal piped through another command is still a refusal")
    func permitsRefusedHarnessAccessWithZeroExit() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"ls -la \(harness.path)/ 2>&1 | head -20"},"metadata":{"exit":0},"output":"ls: \(harness.path)/: Operation not permitted\\ntotal 0\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("Searching a protected path that returns nothing reached nothing")
    func permitsFruitlessSearchOfProtectedPaths() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let workspace = context.workspaceURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"cat \(workspace)/Sources/App.swift; find \(harness.path) -name 'Answers.swift' 2>/dev/null | grep -v workspace"},"metadata":{"exit":1},"output":"struct App { let title = \\"Dashboard\\" }\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("A search that printed a protected path found it")
    func rejectsSearchThatListedProtectedPaths() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"find \(harness.path) -name '*.patch'"},"metadata":{"exit":0},"output":"\(harness.path)/.applebench/solutions/CartFixture.patch\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
    }

    @Test("A silenced read that printed nothing came back with nothing")
    func permitsSilentlyRefusedRead() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"cat \(harness.path)/docs/AUTHORING.md 2>/dev/null; ls \(harness.path) 2>/dev/null"},"metadata":{"exit":0},"output":"total 0\\n"}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    @Test("Copying out of a protected path counts even when it says nothing")
    func rejectsSilentCopyOutOfProtectedPath() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let workspace = context.workspaceURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"cat \(harness.path)/answers.md > \(workspace)/a.md 2>/dev/null"},"metadata":{"exit":0},"output":""}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(!result.passed)
    }

    @Test("Workspace, Xcode, DerivedData, and temporary paths remain legitimate")
    func permitsRequiredExternalPaths() async throws {
        let (context, harness) = try await context()
        defer { try? FileManager.default.removeItem(at: harness) }
        let workspace = context.workspaceURL.path
        let log = """
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"read","state":{"input":{"filePath":"\(workspace)/Sources/App.swift"}}}}}}
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"bash","state":{"input":{"command":"/usr/bin/xcodebuild -derivedDataPath /Users/test/Library/Developer/Xcode/DerivedData/App build"}}}}}}
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"read","state":{"input":{"filePath":"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Info.plist"}}}}}}
        {"type":"agent_event","payload":{"data":{"part":{"type":"tool","tool":"read","state":{"input":{"filePath":"/private/tmp/build.log"}}}}}}
        """
        try log.write(
            to: context.runDirectoryURL.appendingPathComponent("events.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await TrajectoryGrader(
            configuration: TrajectoryGraderConfiguration()
        ).grade(task: defaultTask(), context: context)

        #expect(result.passed)
    }

    private func context() async throws -> (GradingContext, URL) {
        let harness = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-trajectory-\(UUID().uuidString)")
        let run = harness.appendingPathComponent(".applebench/runs/test")
        let workspace = run.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return (
            GradingContext(
                runID: "test",
                workspaceURL: workspace,
                runDirectoryURL: run,
                artifactsDirectoryURL: run.appendingPathComponent("artifacts"),
                derivedDataURL: run.appendingPathComponent("DerivedData"),
                simulatorUDID: nil,
                agent: "opencode",
                destination: nil,
                changedFiles: [],
                processRunner: FakeProcessRunner(),
                recorder: try EventRecorder(runID: "test", fileURL: nil)
            ),
            harness
        )
    }
}
