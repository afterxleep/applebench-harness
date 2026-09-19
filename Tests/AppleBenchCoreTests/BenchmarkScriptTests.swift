import Foundation
import Testing

@Suite("Benchmark wrapper")
struct BenchmarkScriptTests {
    @Test(
        "Provider model IDs select their native API key",
        arguments: [
            ("openai/gpt-5.3-codex", "OPENAI_API_KEY"),
            ("anthropic/claude-sonnet-5", "ANTHROPIC_API_KEY"),
            ("openrouter/anthropic/claude-sonnet-5", "OPENROUTER_API_KEY"),
            ("minimax/MiniMax-M3", "MINIMAX_API_KEY"),
        ]
    )
    func providerKeyEnvironment(model: String, expected: String) throws {
        #expect(try keyEnvironment(model: model) == expected)
    }

    @Test("An explicit API key environment variable overrides model inference")
    func explicitKeyEnvironment() throws {
        #expect(
            try keyEnvironment(
                model: "anthropic/claude-sonnet-5",
                override: "ANTHROPIC_BENCHMARK_KEY"
            ) == "ANTHROPIC_BENCHMARK_KEY"
        )
    }

    @Test("Wrapper help exposes the provider credential options")
    func helpIncludesCredentialOptions() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        let output = Pipe()
        process.executableURL = repository.appendingPathComponent("Scripts/run-benchmark.sh")
        process.arguments = ["--help"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(process.terminationStatus == 0)
        #expect(text.contains("--api-key-file"))
        #expect(text.contains("--api-key-env"))
        #expect(text.contains("defaults to max"))
        #expect(text.contains("Wrapper CLI stripping is always"))
    }

    @Test("Fixture verification can pick out the tasks modified since a given instant")
    func verificationSelectsRecentlyModifiedTasks() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repository.appendingPathComponent("Scripts/verify-fixtures.sh").path
        let tasks = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-verify-select-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tasks) }
        try "id: old-001\nmodified: 2026-09-03T08:48:15+02:00\n".write(to: tasks.appendingPathComponent("old-001.yaml"), atomically: true, encoding: .utf8)
        try "id: new-001\nmodified: 2026-09-15T09:55:00+02:00\n".write(to: tasks.appendingPathComponent("new-001.yaml"), atomically: true, encoding: .utf8)
        try "id: undated-001\n".write(to: tasks.appendingPathComponent("undated-001.yaml"), atomically: true, encoding: .utf8)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "source \"$1\"; tasks_modified_since \"$2\" \"$3\"", "test", script, tasks.path, "2026-09-15T00:00:00+02:00"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        #expect(text.split(separator: "\n").map(String.init) == ["new-001"])
    }

    @Test("Fixture verification only removes the simulators its own runs created")
    func verificationLeavesBenchmarkSimulatorsAlone() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repository.appendingPathComponent("Scripts/verify-tasks.sh").path
        let listing = """
        -- iOS 26.5 --
            AppleBench-2026-09-15T103703-g2-flow-003-opencode (31B37D45-01C9-4A39-882B-6E1617D4F097) (Booted)
            AppleBench-2026-09-15T103710-g2-flow-003-fake (AAAAAAAA-0000-0000-0000-000000000001) (Shutdown)
            AppleBench-2026-09-15T103900-g2-flow-003-solution (BBBBBBBB-0000-0000-0000-000000000002) (Booted)
            iPhone 17 (CCCCCCCC-0000-0000-0000-000000000003) (Shutdown)
        """
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "source \"$1\"; verification_device_udids", "test", script]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(listing.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(text.split(separator: "\n").map(String.init) == [
            "AAAAAAAA-0000-0000-0000-000000000001",
            "BBBBBBBB-0000-0000-0000-000000000002",
        ])
    }

    @Test("Scoring runs accept only Xcode 27")
    func onlyXcode27IsSupported() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repository.appendingPathComponent("Scripts/run-benchmark.sh").path

        for (version, expected) in [("27.0", 0), ("27.1.2", 0), ("26.5", 1), ("28.0", 1), ("", 1)] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "source \"$1\"; supported_xcode_version \"$2\"", "test", script, version]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == Int32(expected), "Xcode \(version)")
        }
    }

    @Test("Only successful and resumable suite exits may publish")
    func publishableSuiteStatuses() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repository.appendingPathComponent("Scripts/run-benchmark.sh").path

        for (status, expected) in [(0, 0), (1, 0), (2, 1), (3, 1), (64, 1)] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "source \"$1\"; publishable_suite_status \"$2\"", "test", script, "\(status)"]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == Int32(expected))
        }
    }

    @Test("Changed selection prefers the complete published model report")
    func changedSelectionPrefersPublishedReport() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-pending-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let reports = root.appendingPathComponent("Reports", isDirectory: true)
        let raw = reports.appendingPathComponent("newer-partial", isDirectory: true)
        let tasks = root.appendingPathComponent("Examples/Tasks", isDirectory: true)
        let suites = root.appendingPathComponent("Examples/Suites", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: suites, withIntermediateDirectories: true)

        let model = "openrouter/example/model"
        let published = report(model: model, tasks: ["done-001", "done-002"])
        let partial = report(model: model, tasks: ["done-001"])
        try JSONSerialization.data(withJSONObject: published).write(
            to: reports.appendingPathComponent("model.json")
        )
        let partialURL = raw.appendingPathComponent("summary.json")
        try JSONSerialization.data(withJSONObject: partial).write(to: partialURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: partialURL.path
        )

        for task in ["done-001", "done-002", "new-001"] {
            try "modified: 2026-09-01T00:00:00Z\n".write(
                to: tasks.appendingPathComponent("\(task).yaml"),
                atomically: true,
                encoding: .utf8
            )
        }
        try "tasks:\n  - done-001\n  - done-002\n  - new-001\n".write(
            to: suites.appendingPathComponent("gold.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let process = Process()
        let output = Pipe()
        process.executableURL = repository.appendingPathComponent("Scripts/pending-tasks.py")
        process.arguments = [
            "--model", model,
            "--reports-dir", reports.path,
            "--suite", suites.appendingPathComponent("gold.yaml").path,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["APPLEBENCH_TASKSET": root.path],
            uniquingKeysWith: { _, new in new }
        )
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(process.terminationStatus == 0)
        #expect(text.contains("comparing against model.json"))
        #expect(text.split(separator: "\n").last == "new-001")
    }

    private func keyEnvironment(model: String, override: String = "") throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let wrapper = repository.appendingPathComponent("Scripts/run-benchmark.sh").path

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "source \"$1\"; provider_key_environment_variable \"$2\" \"$3\"",
            "applebench-test",
            wrapper,
            model,
            override,
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw TestError.commandFailed(text)
        }
        return text
    }

    private func report(model: String, tasks: [String]) -> [String: Any] {
        [
            "runs": tasks.enumerated().map { index, task in
                [
                    "task": task,
                    "run_id": "2026-09-10T1200\(index)0-\(task)-opencode",
                    "agent": ["model": model],
                ]
            }
        ]
    }
}

private enum TestError: Error {
    case commandFailed(String)
}
