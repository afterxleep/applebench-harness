import Darwin
import Foundation

/// A command to execute, without shell interpretation.
///
/// Arguments are passed straight to `execve`-style spawning, so no quoting or
/// escaping is ever applied and task-supplied strings can never be interpreted
/// by a shell.
public struct ProcessCommand: Sendable, Equatable {
    /// Executable name (resolved against `PATH`) or a path containing `/`.
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: URL?
    /// Full child environment. `nil` inherits the parent environment.
    public var environment: [String: String]?

    public init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    /// Human-readable rendering for logs and events (never executed).
    public var displayString: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public enum ProcessOutputStream: String, Sendable {
    case stdout
    case stderr
}

public struct ProcessExecutionResult: Sendable {
    /// Exit code when the process exited normally; `nil` when signaled.
    public var exitCode: Int32?
    /// Terminating signal when the process was killed; `nil` when it exited.
    public var terminationSignal: Int32?
    public var standardOutput: String
    public var standardError: String
    public var duration: Duration
    /// The process was terminated by AppleBench because it exceeded the timeout.
    public var timedOut: Bool

    public init(
        exitCode: Int32? = nil,
        terminationSignal: Int32? = nil,
        standardOutput: String,
        standardError: String,
        duration: Duration,
        timedOut: Bool
    ) {
        self.exitCode = exitCode
        self.terminationSignal = terminationSignal
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.duration = duration
        self.timedOut = timedOut
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

public enum ProcessRunnerError: Error, Equatable, CustomStringConvertible {
    case executableNotFound(String)
    case spawnFailed(command: String, errno: Int32)
    case pipeCreationFailed

    public var description: String {
        switch self {
        case .executableNotFound(let name):
            "Executable not found: \(name)"
        case .spawnFailed(let command, let code):
            "Failed to spawn '\(command)': \(String(cString: strerror(code)))"
        case .pipeCreationFailed:
            "Failed to create pipe"
        }
    }
}

/// Executes external processes with streaming output capture, timeout
/// enforcement, cancellation, and process-group termination.
public protocol ProcessRunning: Sendable {
    func run(
        _ command: ProcessCommand,
        timeout: Duration?,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)?
    ) async throws -> ProcessExecutionResult
}

extension ProcessRunning {
    public func run(_ command: ProcessCommand, timeout: Duration? = nil) async throws -> ProcessExecutionResult {
        try await run(command, timeout: timeout, outputHandler: nil)
    }
}

/// Production `ProcessRunning` built on `posix_spawn`.
///
/// The child is placed in its own process group (`POSIX_SPAWN_SETPGROUP`) so a
/// timeout or cancellation can terminate the entire tree with `kill(-pid, …)`,
/// including grandchildren spawned by agent CLIs. Both output pipes are
/// drained concurrently with `DispatchIO`, so a full pipe buffer can never
/// deadlock the child.
public struct ProcessRunner: ProcessRunning {
    /// Grace period between SIGTERM and SIGKILL when tearing a process down.
    private let terminationGracePeriod: Duration

    public init(terminationGracePeriod: Duration = .seconds(3)) {
        self.terminationGracePeriod = terminationGracePeriod
    }

    public func run(
        _ command: ProcessCommand,
        timeout: Duration?,
        outputHandler: (@Sendable (ProcessOutputStream, String) -> Void)?
    ) async throws -> ProcessExecutionResult {
        let executablePath = try Self.resolveExecutable(command)
        let start = ContinuousClock.now

        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            [stdoutPipe[0], stdoutPipe[1], stderrPipe[0], stderrPipe[1]]
                .filter { $0 >= 0 }
                .forEach { close($0) }
            throw ProcessRunnerError.pipeCreationFailed
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], 1)
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], 2)
        if let workingDirectory = command.workingDirectory {
            posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory.path)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // New process group (pgid == child pid) so we can signal the whole
        // tree; CLOEXEC_DEFAULT so only the dup2'd descriptors survive exec.
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
        )
        posix_spawnattr_setpgroup(&attributes, 0)

        let argv = [executablePath] + command.arguments
        let environment = command.environment ?? ProcessInfo.processInfo.environment
        let envp = environment.map { "\($0.key)=\($0.value)" }

        var pid: pid_t = 0
        let spawnResult = withCStringArray(argv) { argvPointer in
            withCStringArray(envp) { envpPointer in
                posix_spawn(&pid, executablePath, &fileActions, &attributes, argvPointer, envpPointer)
            }
        }

        // Parent must close the write ends regardless of spawn outcome,
        // otherwise the read side never sees EOF.
        close(stdoutPipe[1])
        close(stderrPipe[1])

        guard spawnResult == 0 else {
            close(stdoutPipe[0])
            close(stderrPipe[0])
            throw ProcessRunnerError.spawnFailed(command: command.displayString, errno: spawnResult)
        }

        let childPID = pid
        let stdoutReadFD = stdoutPipe[0]
        let stderrReadFD = stderrPipe[0]
        let killProcessGroup: @Sendable (Int32) -> Void = { signal in
            kill(-childPID, signal)
        }

        // Not `try`: once the child is spawned every remaining step is
        // non-throwing, and the result is reported through the exit status
        // rather than by unwinding.
        return await withTaskCancellationHandler {
            let timedOut = LockedFlag()

            // Drain both pipes and wait for exit concurrently; a watchdog
            // enforces the timeout by killing the process group.
            async let stdoutData = Self.drain(fd: stdoutReadFD) { chunk in
                outputHandler?(.stdout, String(decoding: chunk, as: UTF8.self))
            }
            async let stderrData = Self.drain(fd: stderrReadFD) { chunk in
                outputHandler?(.stderr, String(decoding: chunk, as: UTF8.self))
            }

            let watchdog: Task<Void, Never>? = timeout.map { limit in
                let grace = terminationGracePeriod
                return Task {
                    // Wait for the timeout, but only act if we weren't
                    // cancelled (the parent cancelling the watchdog means
                    // the child exited on its own — setting `timedOut` then
                    // would lie about what happened).
                    do {
                        try await Task.sleep(for: limit)
                    } catch {
                        return
                    }
                    timedOut.set()
                    killProcessGroup(SIGTERM)
                    // The second sleep is best-effort: a cancellation
                    // arriving between SIGTERM and SIGKILL must not skip
                    // the kill, because children that ignore SIGTERM
                    // would then outlive the harness.
                    do {
                        try await Task.sleep(for: grace)
                    } catch {
                        // fall through
                    }
                    killProcessGroup(SIGKILL)
                }
            }

            let status = await Self.waitForExit(pid: childPID)
            watchdog?.cancel()

            let stdout = await stdoutData
            let stderr = await stderrData
            let duration = start.duration(to: .now)

            var exitCode: Int32?
            var signal: Int32?
            if status.exited {
                exitCode = status.exitCode
            } else {
                signal = status.signal
            }

            return ProcessExecutionResult(
                exitCode: exitCode,
                terminationSignal: signal,
                standardOutput: String(decoding: stdout, as: UTF8.self),
                standardError: String(decoding: stderr, as: UTF8.self),
                duration: duration,
                timedOut: timedOut.isSet
            )
        } onCancel: {
            killProcessGroup(SIGTERM)
        }
    }

    // MARK: - Internals

    public static func resolveExecutable(_ command: ProcessCommand) throws -> String {
        let name = command.executable
        if name.contains("/") {
            let path = (name as NSString).isAbsolutePath
                ? name
                : command.workingDirectory?.appendingPathComponent(name).path ?? name
            guard FileManager.default.isExecutableFile(atPath: path) else {
                throw ProcessRunnerError.executableNotFound(name)
            }
            return path
        }
        let searchPath = command.environment?["PATH"]
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in searchPath.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw ProcessRunnerError.executableNotFound(name)
    }

    private struct ExitStatus {
        var exited: Bool
        var exitCode: Int32
        var signal: Int32
    }

    private static func waitForExit(pid: pid_t) async -> ExitStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
                if (status & 0x7F) == 0 {
                    continuation.resume(returning: ExitStatus(exited: true, exitCode: (status >> 8) & 0xFF, signal: 0))
                } else {
                    continuation.resume(returning: ExitStatus(exited: false, exitCode: -1, signal: status & 0x7F))
                }
            }
        }
    }

    /// Reads a file descriptor to EOF using DispatchIO, invoking `onChunk`
    /// for each chunk as it arrives. Closes the descriptor when done.
    private static func drain(fd: Int32, onChunk: @escaping @Sendable (Data) -> Void) async -> Data {
        let queue = DispatchQueue(label: "applebench.process.pipe")
        return await withCheckedContinuation { continuation in
            let accumulated = LockedBuffer()
            let io = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue) { _ in
                close(fd)
            }
            io.setLimit(lowWater: 1)
            io.read(offset: 0, length: .max, queue: queue) { done, data, _ in
                if let data, !data.isEmpty {
                    let chunk = Data(data)
                    accumulated.append(chunk)
                    onChunk(chunk)
                }
                if done {
                    io.close()
                    continuation.resume(returning: accumulated.value)
                }
            }
        }
    }
}

/// Minimal locked flag/buffer helpers so the runner stays a value type while
/// sharing state with the watchdog and IO callbacks.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var isSet: Bool { lock.withLock { flag } }
}

private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    var value: Data { lock.withLock { data } }
}

/// Invokes `body` with a NULL-terminated array of C strings.
private func withCStringArray<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
    var cStrings: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    cStrings.append(nil)
    defer { cStrings.forEach { free($0) } }
    return body(&cStrings)
}
