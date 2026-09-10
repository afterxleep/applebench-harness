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
}

private enum TestError: Error {
    case commandFailed(String)
}
