import AppleBenchCore
import ArgumentParser
import Foundation

/// Checks that a task is well-formed and this machine can run it, without
/// launching any agent.
struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a task definition and the local environment without launching an agent."
    )

    @Argument(help: "Task id or path to a task YAML file.")
    var task: String

    @Option(name: .long, help: "Directory to resolve bare task ids in.")
    var tasksDir: String?

    @Option(name: .long, help: "Path to a separate evaluation YAML supplying the graders.")
    var evaluation: String?

    func run() async throws {
        var problems: [String] = []
        var checks: [(String, Bool, String?)] = []

        // 1. YAML parses and is structurally sound.
        let taskURL = try ReferenceResolver.resolveTask(task, tasksDirectory: tasksDir)
        let benchmarkTask: BenchmarkTask
        do {
            benchmarkTask = try TaskLoader.loadTask(
                from: taskURL,
                evaluation: evaluation.map { URL(fileURLWithPath: $0) }
            )
            checks.append(("Task YAML", true, benchmarkTask.id))
        } catch {
            print("Task YAML            FAIL  \(error)")
            throw ExitCode.failure
        }

        // Category and difficulty define the shape of the task set, so a
        // shipped task that omits them is a defect worth surfacing here.
        if let category = benchmarkTask.category {
            checks.append(("Category", true, category.rawValue))
        } else {
            checks.append(("Category", false, "not declared"))
            problems.append("Task declares no category (one of: \(BenchmarkCategory.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        if let difficulty = benchmarkTask.difficulty {
            checks.append(("Difficulty", true, "\(difficulty)/\(BenchmarkTask.difficultyRange.upperBound)"))
        } else {
            checks.append(("Difficulty", false, "not declared"))
            problems.append("Task declares no difficulty (\(BenchmarkTask.difficultyRange.lowerBound)–\(BenchmarkTask.difficultyRange.upperBound))")
        }
        if !benchmarkTask.tags.isEmpty {
            checks.append(("Tags", true, benchmarkTask.tags.joined(separator: ", ")))
        }

        if benchmarkTask.graders.isEmpty {
            problems.append("Task has no graders (supply --evaluation for split distributions)")
            checks.append(("Graders", false, "none configured"))
        } else {
            checks.append(("Graders", true, benchmarkTask.graders.map(\.type.rawValue).joined(separator: ", ")))
        }

        // 2. Repository reachable and commit resolvable.
        let processRunner = ProcessRunner()
        let repository = benchmarkTask.repository
        let isLocal = repository.url.hasPrefix("/") || repository.url.hasPrefix("./")
            || repository.url.hasPrefix("../") || repository.url.hasPrefix("~")
        if isLocal {
            let path = (repository.url as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                checks.append(("Repository", true, path))
                if repository.commit.uppercased() != "HEAD" {
                    let result = try? await processRunner.run(
                        ProcessCommand(
                            executable: "/usr/bin/git",
                            arguments: ["cat-file", "-e", "\(repository.commit)^{commit}"],
                            workingDirectory: URL(fileURLWithPath: path)
                        ),
                        timeout: .seconds(30),
                        outputHandler: nil
                    )
                    let exists = result?.exitCode == 0
                    checks.append(("Commit", exists, repository.commit))
                    if !exists { problems.append("Commit \(repository.commit) not found in \(path)") }
                }
            } else {
                checks.append(("Repository", false, path))
                problems.append("Local repository does not exist: \(path)")
            }
        } else {
            let result = try? await processRunner.run(
                ProcessCommand(executable: "/usr/bin/git", arguments: ["ls-remote", repository.url, "HEAD"]),
                timeout: .seconds(120),
                outputHandler: nil
            )
            let reachable = result?.exitCode == 0
            checks.append(("Repository", reachable, repository.url))
            if !reachable {
                problems.append("Repository unreachable: \(repository.url)")
            }
            // Commit existence for remote repositories is verified at clone
            // time; ls-remote cannot check arbitrary SHAs.
            checks.append(("Commit", true, "\(repository.commit) (verified at clone time)"))
        }

        // 3. Machine environment.
        do {
            let environment = XcodeEnvironment(processRunner: processRunner)
            let snapshot = try await environment.snapshot()
            checks.append(("Xcode", true, "\(snapshot.xcodeVersion) (\(snapshot.xcodeBuildNumber))"))
            do {
                try environment.validate(task: benchmarkTask, against: snapshot)
                if let simulator = benchmarkTask.environment.simulator {
                    checks.append(("Simulator", true, "\(simulator.device) · \(simulator.runtime)"))
                }
            } catch {
                checks.append(("Environment", false, "\(error)"))
                problems.append("\(error)")
            }
        } catch {
            checks.append(("Environment", false, "\(error)"))
            problems.append("Could not inspect environment: \(error)")
        }

        print("AppleBench · validate \(benchmarkTask.id)\n")
        for (name, passed, detail) in checks {
            let status = passed ? "OK  " : "FAIL"
            print("  \(Format.pad(name, 12)) \(status)  \(detail ?? "")")
        }
        print("")
        if problems.isEmpty {
            print("Task '\(benchmarkTask.id)' is runnable on this machine.")
        } else {
            print("\(problems.count) problem(s) found.")
            throw ExitCode.failure
        }
    }
}
