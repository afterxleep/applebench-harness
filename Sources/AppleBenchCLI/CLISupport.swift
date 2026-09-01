import AppleBenchAgents
import AppleBenchCore
import AppleBenchGraders
import ArgumentParser
import Foundation

/// Resolution of task/suite references: an argument may be a YAML file path
/// or a bare identifier searched in conventional directories.
enum ReferenceResolver {
    static let taskSearchDirectories = ["Examples/Tasks", "Tasks", "tasks"]
    static let suiteSearchDirectories = ["Examples/Suites", "Suites", "suites"]

    static func resolveTask(_ reference: String, tasksDirectory: String?) throws -> URL {
        try resolve(
            reference,
            explicitDirectory: tasksDirectory,
            searchDirectories: taskSearchDirectories,
            fileNames: ["\(reference).yaml", "\(reference)/task.yaml"],
            kind: "task"
        )
    }

    static func resolveSuite(_ reference: String) throws -> URL {
        try resolve(
            reference,
            explicitDirectory: nil,
            searchDirectories: suiteSearchDirectories,
            fileNames: ["\(reference).yaml"],
            kind: "suite"
        )
    }

    private static func resolve(
        _ reference: String,
        explicitDirectory: String?,
        searchDirectories: [String],
        fileNames: [String],
        kind: String
    ) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: reference) {
            return URL(fileURLWithPath: reference)
        }
        var candidates: [String] = []
        let directories = (explicitDirectory.map { [$0] } ?? []) + searchDirectories
        for directory in directories {
            for fileName in fileNames {
                candidates.append("\(directory)/\(fileName)")
            }
        }
        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        throw ValidationError(
            "Cannot resolve \(kind) '\(reference)'. Tried the literal path and: \(candidates.joined(separator: ", "))"
        )
    }

    /// Locates a split evaluation file for a task id, when distributed
    /// separately from the task prompt.
    static func resolveEvaluation(taskID: String, evaluationsDirectory: String?) -> URL? {
        guard let evaluationsDirectory else { return nil }
        let candidates = [
            "\(evaluationsDirectory)/\(taskID)/evaluation.yaml",
            "\(evaluationsDirectory)/\(taskID).yaml",
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }
}

/// Shared factory wiring for commands that execute runs.
enum Wiring {
    static func makeRunner() -> BenchmarkRunner {
        let processRunner = ProcessRunner()
        return BenchmarkRunner(
            environment: XcodeEnvironment(processRunner: processRunner),
            workspaceManager: WorkspaceManager(processRunner: processRunner),
            simulatorManager: SimulatorManager(processRunner: processRunner),
            processRunner: processRunner,
            graderRegistry: GraderCatalog.defaultRegistry()
        )
    }

    struct VMOptions {
        var image: String
        var allowedCIDRs: [String]
        var sshUser: String
        var sshPassword: String
    }

    static func makeAdapter(
        agent: String,
        model: String?,
        effort: String?,
        agentArguments: [String],
        vm: VMOptions?
    ) throws -> any AgentAdapter {
        let options = AgentRegistry.Options(model: model, effort: effort, additionalArguments: agentArguments)
        if let vm {
            guard agent == "opencode" else {
                throw ValidationError("--vm applies to the opencode agent")
            }
            return TartOpenCodeAdapter(
                options: options,
                tart: TartConfiguration(
                    image: vm.image,
                    sshUser: vm.sshUser,
                    sshPassword: vm.sshPassword,
                    allowedCIDRs: vm.allowedCIDRs
                )
            )
        }
        return try AgentCatalog.defaultRegistry().makeAdapter(identifier: agent, options: options)
    }

    static func defaultRunsRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".applebench/runs", isDirectory: true)
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 {
            return "\(total / 60)m \(total % 60)s"
        }
        return "\(total)s"
    }

    static func passFail(_ passed: Bool) -> String {
        passed ? "PASS" : "FAIL"
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    static func cost(_ usd: Double) -> String {
        String(format: "$%.4f", usd)
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
