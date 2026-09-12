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
