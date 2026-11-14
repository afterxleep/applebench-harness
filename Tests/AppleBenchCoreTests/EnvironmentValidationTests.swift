import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Environment validation")
struct EnvironmentValidationTests {
    @Test("A screen-recording task is rejected before the agent runs when permission is absent")
    func screenRecordingPermissionIsPreflighted() throws {
        let environment = XcodeEnvironment(screenCaptureAllowed: { false })
        let task = BenchmarkTask(
            id: "screen-001",
            title: "Capture",
            repository: RepositorySpecification(url: "/tmp", commit: "HEAD"),
            prompt: "Capture the screen.",
            environment: EnvironmentRequirements(
                platform: .macos,
                screenRecording: true
            )
        )
        let snapshot = EnvironmentSnapshot(
            macosVersion: "26.5",
            architecture: "arm64",
            xcodePath: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "27.0",
            xcodeBuildNumber: "27A0000"
        )

        #expect(throws: BenchmarkFailure.self) {
            try environment.validate(task: task, against: snapshot)
        }
    }
}
