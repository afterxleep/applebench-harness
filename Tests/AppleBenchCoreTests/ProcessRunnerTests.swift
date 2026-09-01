import Foundation
import Testing
@testable import AppleBenchCore

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    let runner = ProcessRunner(terminationGracePeriod: .milliseconds(200))

    @Test("Captures stdout and exit code")
    func stdoutCapture() async throws {
        let result = try await runner.run(
            ProcessCommand(executable: "/bin/echo", arguments: ["hello", "world"])
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "hello world\n")
        #expect(result.standardError.isEmpty)
        #expect(!result.timedOut)
        #expect(result.succeeded)
    }

    @Test("Arguments are never shell-interpreted")
    func noShellInterpretation() async throws {
        let hostile = "$(touch /tmp/pwned); echo injected; `id`"
        let result = try await runner.run(
            ProcessCommand(executable: "/bin/echo", arguments: [hostile])
        )
        #expect(result.standardOutput == hostile + "\n")
    }

    @Test("Captures stderr separately")
    func stderrCapture() async throws {
        let result = try await runner.run(
            ProcessCommand(executable: "/bin/sh", arguments: ["-c", "echo out; echo err >&2"])
        )
        #expect(result.standardOutput == "out\n")
        #expect(result.standardError == "err\n")
    }

    @Test("Non-zero exit codes are preserved")
    func exitCode() async throws {
        let result = try await runner.run(ProcessCommand(executable: "/usr/bin/false"))
        #expect(result.exitCode == 1)
        #expect(!result.succeeded)
    }

    @Test("Large output does not deadlock pipes")
    func largeOutput() async throws {
        // 4 MiB through a 64 KiB pipe buffer: hangs forever if the pipes are
        // not drained concurrently with the child's execution.
        let result = try await runner.run(
            ProcessCommand(executable: "/bin/dd", arguments: ["if=/dev/zero", "bs=65536", "count=64"]),
            timeout: .seconds(30)
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.utf8.count == 4_194_304)
    }

    @Test("Timeout terminates the process and its children")
    func timeout() async throws {
        let start = ContinuousClock.now
        let result = try await runner.run(
            ProcessCommand(executable: "/bin/sh", arguments: ["-c", "sleep 30 & sleep 30"]),
            timeout: .milliseconds(300)
        )
        let elapsed = start.duration(to: .now)
        #expect(result.timedOut)
        #expect(result.exitCode == nil)
        #expect(result.terminationSignal != nil)
        #expect(elapsed < .seconds(10))
    }

    @Test("Streaming handler receives chunks as they arrive")
    func streaming() async throws {
        let chunks = Chunks()
        _ = try await runner.run(
            ProcessCommand(executable: "/bin/echo", arguments: ["streamed"]),
            timeout: nil
        ) { stream, text in
            if stream == .stdout { chunks.append(text) }
        }
        #expect(chunks.joined().contains("streamed"))
    }

    @Test("Working directory is honored")
    func workingDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("applebench-cwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await runner.run(
            ProcessCommand(executable: "/bin/pwd", workingDirectory: directory)
        )
        let reported = URL(fileURLWithPath: result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            .resolvingSymlinksInPath().path
        #expect(reported == directory.resolvingSymlinksInPath().path)
    }

    @Test("Explicit environment replaces inherited environment")
    func environment() async throws {
        let result = try await runner.run(
            ProcessCommand(
                executable: "/usr/bin/env",
                environment: ["APPLEBENCH_TEST": "value-123"]
            )
        )
        #expect(result.standardOutput.contains("APPLEBENCH_TEST=value-123"))
        #expect(!result.standardOutput.contains("HOME="))
    }

    @Test("Missing executables throw a typed error")
    func missingExecutable() async throws {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(
                ProcessCommand(executable: "definitely-not-a-real-binary-applebench")
            )
        }
    }

    @Test("PATH lookup resolves bare executable names")
    func pathLookup() async throws {
        let result = try await runner.run(ProcessCommand(executable: "echo", arguments: ["via-path"]))
        #expect(result.standardOutput == "via-path\n")
    }

    @Test("A child that exits within the timeout is not marked as timed out")
    func fastExitNotMarkedTimedOut() async throws {
        // Regression: the watchdog's `try?` previously made `timedOut.set()`
        // fire on cancellation too, so a 4s child under a 30-minute timeout
        // was reported as timed out. Cancellation now means "the child
        // exited on its own; don't claim it timed out."
        let result = try await runner.run(
            ProcessCommand(executable: "/bin/sh", arguments: ["-c", "exit 65"]),
            timeout: .seconds(1800)
        )
        #expect(!result.timedOut)
        #expect(result.exitCode == 65)
    }
}

private final class Chunks: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.withLock { values.append(value) } }
    func joined() -> String { lock.withLock { values.joined() } }
}
