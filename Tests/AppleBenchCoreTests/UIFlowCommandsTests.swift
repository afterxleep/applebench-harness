import Foundation
import Testing
@testable import AppleBenchCore

@Suite("UI flow commands")
struct UIFlowCommandsTests {
    private let udid = "1234-ABCD"
    private let bundle = "com.applebench.Fixture"

    private func argv(_ command: ProcessCommand) -> [String] {
        [command.executable] + command.arguments
    }

    @Test("Granting and revoking a service always name the app")
    func privacyNamesTheApp() {
        let revoke = UIFlowCommands.privacy(
            .init(action: "revoke", service: "photos"), bundleIdentifier: bundle, udid: udid
        )
        #expect(argv(revoke) == [
            "flowdeck", "simulator", "privacy", "revoke", "photos", "--bundle-id", bundle, "-S", udid,
        ])
    }

    @Test("Resetting every service takes no bundle id, because it targets none")
    func privacyResetAll() {
        let reset = UIFlowCommands.privacy(
            .init(action: "reset", service: "all"), bundleIdentifier: bundle, udid: udid
        )
        #expect(argv(reset) == ["flowdeck", "simulator", "privacy", "reset", "all", "-S", udid])
    }

    @Test("An unknown privacy action is rejected at validation")
    func privacyActionIsChecked() {
        #expect(throws: BenchmarkFailure.self) {
            try UIFlowCommands.validate(privacy: [.init(action: "allow", service: "photos")])
        }
        #expect(throws: Never.self) {
            try UIFlowCommands.validate(privacy: [.init(action: "grant", service: "camera")])
        }
    }

    @Test("Push, clear-state, open-url, memory warning and buttons map to their commands")
    func remainingCommands() {
        #expect(argv(UIFlowCommands.push(payload: "Payloads/shipped.json", bundleIdentifier: bundle, udid: udid))
            == ["flowdeck", "simulator", "push", "Payloads/shipped.json", "--bundle-id", bundle, "-S", udid])
        #expect(argv(UIFlowCommands.clearState(bundleIdentifier: bundle, udid: udid))
            == ["flowdeck", "ui", "simulator", "clear-state", "--bundle-id", bundle, "-S", udid])
        #expect(argv(UIFlowCommands.openURL("fixture://orders/4471", udid: udid))
            == ["flowdeck", "ui", "simulator", "open-url", "fixture://orders/4471", "-S", udid])
        #expect(argv(UIFlowCommands.memoryWarning(udid: udid))
            == ["flowdeck", "simulator", "memory-warning", "-S", udid])
        #expect(argv(UIFlowCommands.button("home", udid: udid))
            == ["flowdeck", "simulator", "button", "home", "-S", udid])
    }
}
