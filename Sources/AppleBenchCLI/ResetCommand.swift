import AppleBenchCore
import ArgumentParser
import Foundation

struct ResetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Remove AppleBench caches, build products, DerivedData, and previous runs."
    )

    func run() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let removed = try HarnessReset(rootURL: root).run()
        if removed.isEmpty {
            print("AppleBench is already clean.")
        } else {
            print("Removed generated state:")
            for path in removed {
                print("  \(path)")
            }
        }
        print("Preserved source, configuration, Data, Reports, and published site data.")
    }
}
