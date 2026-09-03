import Foundation
import Yams

/// Loads tasks, suites, and split evaluation files from YAML.
///
/// Task prompts and grader configuration are deliberately not welded into one
/// file format: a task may omit `graders`, with an evaluation file supplied
/// separately by the runner (`--evaluation`). This keeps hidden-evaluation
/// distribution possible without a server.
public enum TaskLoader {
    /// The grader half of a split task/evaluation distribution.
    public struct EvaluationFile: Sendable, Codable, Equatable {
        public var graders: [GraderSpecification]

        public init(graders: [GraderSpecification]) {
            self.graders = graders
        }
    }

    /// Overrides the simulator every task asks for.
    ///
    /// A task names the device and runtime it was authored against, which is
    /// also the reference environment for a published result. A host with a
    /// different Xcode has different runtimes available, and rewriting every
    /// task file to run there would lose that reference — so the target is
    /// overridable in one place instead.
    ///
    /// The substitution is recorded in each run's environment snapshot, so a
    /// result always says what it actually ran on.
    public static let simulatorDeviceEnvironmentKey = "APPLEBENCH_SIMULATOR_DEVICE"
    public static let simulatorRuntimeEnvironmentKey = "APPLEBENCH_SIMULATOR_RUNTIME"

    public static func loadTask(from url: URL, evaluation evaluationURL: URL? = nil) throws -> BenchmarkTask {
        var task: BenchmarkTask = try decode(from: url, describe: "task")
        if let evaluationURL {
            let evaluation: EvaluationFile = try decode(from: evaluationURL, describe: "evaluation")
            task.graders = evaluation.graders
        }
        applySimulatorOverride(to: &task)
        try validateShape(of: task)
        return task
    }

    static func applySimulatorOverride(to task: inout BenchmarkTask) {
        guard var simulator = task.environment.simulator else { return }
        let environment = ProcessInfo.processInfo.environment
        if let device = environment[simulatorDeviceEnvironmentKey], !device.isEmpty {
            simulator.device = device
        }
        if let runtime = environment[simulatorRuntimeEnvironmentKey], !runtime.isEmpty {
            simulator.runtime = runtime
        }
        task.environment.simulator = simulator
    }

    public static func loadSuite(from url: URL) throws -> BenchmarkSuite {
        let suite: BenchmarkSuite = try decode(from: url, describe: "suite")
        guard !suite.tasks.isEmpty else {
            throw BenchmarkFailure.invalidTask("Suite '\(suite.id)' contains no tasks")
        }
        return suite
    }

    private static func decode<T: Decodable>(from url: URL, describe kind: String) throws -> T {
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw BenchmarkFailure.invalidTask("Cannot read \(kind) file at \(url.path): \(error.localizedDescription)")
        }
        do {
            return try YAMLDecoder().decode(T.self, from: contents)
        } catch let error as DecodingError {
            throw BenchmarkFailure.invalidTask("Malformed \(kind) YAML at \(url.path): \(describe(error))")
        } catch {
            throw BenchmarkFailure.invalidTask("Malformed \(kind) YAML at \(url.path): \(error.localizedDescription)")
        }
    }

    /// Structural checks that do not require touching the machine environment.
    static func validateShape(of task: BenchmarkTask) throws {
        guard !task.id.isEmpty else {
            throw BenchmarkFailure.invalidTask("Task id must not be empty")
        }
        guard task.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw BenchmarkFailure.invalidTask("Task id '\(task.id)' may only contain letters, numbers, '-' and '_'")
        }
        guard !task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BenchmarkFailure.invalidTask("Task '\(task.id)' has an empty prompt")
        }
        guard !task.repository.url.isEmpty else {
            throw BenchmarkFailure.invalidTask("Task '\(task.id)' has an empty repository URL")
        }
        guard !task.repository.commit.isEmpty else {
            throw BenchmarkFailure.invalidTask("Task '\(task.id)' has an empty repository commit")
        }
        guard task.limits.timeoutSeconds > 0 else {
            throw BenchmarkFailure.invalidTask("Task '\(task.id)' has a non-positive timeout")
        }
        if let difficulty = task.difficulty, !BenchmarkTask.difficultyRange.contains(difficulty) {
            throw BenchmarkFailure.invalidTask(
                "Task '\(task.id)' has difficulty \(difficulty); it must be between "
                + "\(BenchmarkTask.difficultyRange.lowerBound) and \(BenchmarkTask.difficultyRange.upperBound)"
            )
        }
        for grader in task.graders {
            if case .runtime(let configuration) = grader, configuration.scheme == nil {
                throw BenchmarkFailure.invalidTask(
                    "Task '\(task.id)': runtime grader requires a 'scheme' to build the app it launches"
                )
            }
            if case .file(let configuration) = grader, configuration.assertions.isEmpty {
                throw BenchmarkFailure.invalidTask("Task '\(task.id)': file grader has no assertions")
            }
            if case .xcodeproj(let configuration) = grader, configuration.isEmpty {
                throw BenchmarkFailure.invalidTask(
                    "Task '\(task.id)': xcodeproj grader asserts nothing "
                    + "(needs build_settings, info_plist, or bundle_contains)"
                )
            }
            if case .trajectory(let configuration) = grader {
                do { try configuration.validate() } catch let failure as BenchmarkFailure {
                    throw BenchmarkFailure.invalidTask("Task '\(task.id)': \(failure)")
                }
            }
            if case .mutation(let configuration) = grader {
                do { try configuration.validate() } catch let failure as BenchmarkFailure {
                    throw BenchmarkFailure.invalidTask("Task '\(task.id)': \(failure)")
                }
            }
            if case .uiflow(let configuration) = grader {
                do { try configuration.validate() } catch let failure as BenchmarkFailure {
                    throw BenchmarkFailure.invalidTask("Task '\(task.id)': \(failure)")
                }
            }
        }
        let needsSimulator = task.graders.contains { specification in
            switch specification {
            case .xcuitest, .runtime, .uiflow, .mutation: true
            case .xcodeproj: task.environment.platform == .ios
            case .build, .xctest, .file, .trajectory: false
            }
        }
        if needsSimulator && task.environment.simulator == nil && task.environment.platform == .ios {
            throw BenchmarkFailure.invalidTask(
                "Task '\(task.id)' uses simulator-dependent graders but declares no simulator requirement"
            )
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "missing key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(_, let context):
            "type mismatch at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(_, let context):
            "missing value at \(path(context))"
        case .dataCorrupted(let context):
            context.debugDescription
        @unknown default:
            String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? "(root)" : joined
    }
}
