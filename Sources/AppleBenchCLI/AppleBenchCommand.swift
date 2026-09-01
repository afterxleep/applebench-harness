import ArgumentParser
import Foundation

@main
struct AppleBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "applebench",
        abstract: "A neutral benchmark harness for evaluating AI coding agents on real Apple-platform engineering tasks.",
        discussion: """
        AppleBench runs an agent against an isolated checkout of a task repository, \
        records the full trajectory, then independently grades the resulting \
        workspace with fresh xcodebuild/test/runtime invocations. Agents never \
        grade themselves.
        """,
        version: "0.1.0",
        subcommands: [
            ValidateCommand.self,
            RunCommand.self,
            SuiteCommand.self,
            ResultsCommand.self,
        ]
    )
}
