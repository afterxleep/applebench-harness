import Foundation
import Testing
@testable import AppleBenchAgents
@testable import AppleBenchCore

@Suite("Tart VM adapter")
struct TartAdapterTests {
    @Test("Shell quoting neutralizes hostile input")
    func shellQuoting() {
        #expect(shellQuote("simple") == "'simple'")
        #expect(shellQuote("with space") == "'with space'")
        #expect(shellQuote("a'b") == #"'a'\''b'"#)
        #expect(shellQuote("$(rm -rf /); `id`") == #"'$(rm -rf /); `id`'"#)
        #expect(shellQuote("") == "''")
    }

    @Test("Remote command quotes the prompt and pins the hermetic config")
    func remoteCommand() {
        let task = BenchmarkTask(
            id: "t-001",
            title: "T",
            repository: RepositorySpecification(url: "/tmp/repo", commit: "HEAD"),
            prompt: "Fix the crash; don't touch tests. Use `xcodebuild`.",
            environment: EnvironmentRequirements(platform: .ios)
        )
        let command = TartOpenCodeAdapter.remoteCommand(
            task: task,
            model: "anthropic/claude-sonnet-5",
            effort: "high",
            additionalArguments: [],
            environmentAllowlist: []
        )
        #expect(command.hasPrefix("cd '/Volumes/My Shared Files/workspace' &&"))
        #expect(command.contains("OPENCODE_CONFIG='/Volumes/My Shared Files/benchconfig/opencode.json'"))
        #expect(command.contains("opencode run --format json --pure --auto"))
        #expect(command.contains("--model 'anthropic/claude-sonnet-5'"))
        #expect(command.contains("--variant 'high'"))
        // Prompt must be a single quoted argument at the end.
        #expect(command.hasSuffix("'Fix the crash; don'\\''t touch tests. Use `xcodebuild`.'"))
    }

    @Test("SSH invocation targets the guest with host-key checking off")
    func sshInvocation() {
        let vm = TartVM(configuration: TartConfiguration(image: "bench-image"))
        let invocation = vm.sshInvocation(remoteCommand: "true", ip: "192.168.64.5")
        #expect(invocation.executable == "sshpass")
        #expect(invocation.arguments.contains("admin@192.168.64.5"))
        #expect(invocation.arguments.contains("StrictHostKeyChecking=no"))
        #expect(invocation.arguments.last == "true")
    }

    @Test("Booting the VM denies every destination when nothing is allowed")
    func defaultEgressDenied() {
        let arguments = TartVM.runArguments(
            configuration: TartConfiguration(image: "bench-image"),
            workspaceURL: URL(fileURLWithPath: "/tmp/ws"),
            configDirectoryURL: URL(fileURLWithPath: "/tmp/cfg")
        )
        #expect(arguments.contains("--net-softnet"))
        #expect(arguments.contains("--net-softnet-block=0.0.0.0/0"))
        #expect(!arguments.contains { $0.hasPrefix("--net-softnet-allow") })
    }

    @Test("An allowed range opens only itself and never lifts the block")
    func allowedRangeNarrowsTheDenial() {
        let arguments = TartVM.runArguments(
            configuration: TartConfiguration(image: "img", allowedCIDRs: ["10.0.0.0/8", "192.0.2.1/32"]),
            workspaceURL: URL(fileURLWithPath: "/tmp/ws"),
            configDirectoryURL: URL(fileURLWithPath: "/tmp/cfg")
        )
        #expect(arguments.contains("--net-softnet-block=0.0.0.0/0"))
        #expect(arguments.contains("--net-softnet-allow=10.0.0.0/8,192.0.2.1/32"))
    }

    @Test("The guest mounts the workspace writable and the harness config read-only")
    func mountsAreScoped() {
        let arguments = TartVM.runArguments(
            configuration: TartConfiguration(image: "img"),
            workspaceURL: URL(fileURLWithPath: "/tmp/ws"),
            configDirectoryURL: URL(fileURLWithPath: "/tmp/cfg")
        )
        #expect(arguments.contains("--dir=workspace:/tmp/ws"))
        #expect(arguments.contains("--dir=benchconfig:/tmp/cfg:ro"))
        // Anything else on the host would be reachable if it were mounted.
        #expect(arguments.filter { $0.hasPrefix("--dir=") }.count == 2)
    }

    @Test("Allowed CIDRs are optional and default empty")
    func configurationDefaults() {
        let configuration = TartConfiguration(image: "img")
        #expect(configuration.allowedCIDRs.isEmpty)
        #expect(configuration.sshUser == "admin")
        #expect(configuration.sshPassword == "admin")
    }
}
