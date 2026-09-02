import Foundation
import Testing
@testable import AppleBenchCore

@Suite("Simulator device state")
struct SimulatorDeviceStateTests {
    private let udid = "1234-ABCD"

    private func argv(_ commands: [ProcessCommand]) -> [[String]] {
        commands.map { [$0.executable] + $0.arguments }
    }

    @Test("An empty state issues no commands at all")
    func emptyStateIsInert() {
        let state = SimulatorDeviceState()
        #expect(state.isEmpty)
        #expect(state.applyCommands(udid: udid).isEmpty)
        #expect(state.resetCommands(udid: udid).isEmpty)
    }

    @Test("Orientation is set through FlowDeck, which confirms it rather than sleeping")
    func orientation() {
        // `simctl` has no orientation primitive at all; this is the reason the
        // grader shells to FlowDeck rather than to xcrun.
        let state = SimulatorDeviceState(orientation: "landscape-left")
        #expect(argv(state.applyCommands(udid: udid)) == [
            ["flowdeck", "simulator", "orientation", "set", "landscape-left", "-S", udid]
        ])
        #expect(argv(state.resetCommands(udid: udid)) == [
            ["flowdeck", "simulator", "orientation", "set", "portrait", "-S", udid]
        ])
    }

    @Test("Language carries its locale when one is given, and resets by removing both")
    func language() {
        let bare = SimulatorDeviceState(language: "ar")
        #expect(argv(bare.applyCommands(udid: udid)) == [
            ["flowdeck", "simulator", "language", "set", "ar", "-S", udid]
        ])

        let located = SimulatorDeviceState(language: "ar", locale: "ar_SA")
        #expect(argv(located.applyCommands(udid: udid)) == [
            ["flowdeck", "simulator", "language", "set", "ar", "--locale", "ar_SA", "-S", udid]
        ])
        #expect(argv(located.resetCommands(udid: udid)) == [
            ["flowdeck", "simulator", "language", "reset", "-S", udid]
        ])
    }

    @Test("A locale with no language is rejected rather than silently ignored")
    func localeWithoutLanguageIsInvalid() {
        let state = SimulatorDeviceState(locale: "ar_SA")
        #expect(throws: BenchmarkFailure.self) { try state.validate() }
    }

    @Test("Appearance, content size and contrast each reset to the documented iOS default")
    func uiSettings() {
        let state = SimulatorDeviceState(
            appearance: "dark",
            contentSize: "accessibility-extra-extra-extra-large",
            increaseContrast: "enabled"
        )
        #expect(argv(state.applyCommands(udid: udid)) == [
            ["flowdeck", "simulator", "appearance", "set", "dark", "-S", udid],
            ["flowdeck", "simulator", "content-size", "set", "accessibility-extra-extra-extra-large", "-S", udid],
            ["flowdeck", "simulator", "increase-contrast", "set", "enabled", "-S", udid],
        ])
        #expect(argv(state.resetCommands(udid: udid)) == [
            ["flowdeck", "simulator", "appearance", "reset", "-S", udid],
            ["flowdeck", "simulator", "content-size", "reset", "-S", udid],
            ["flowdeck", "simulator", "increase-contrast", "reset", "-S", udid],
        ])
    }

    @Test("Disconnecting the hardware keyboard is what makes the software keyboard appear")
    func hardwareKeyboard() {
        let state = SimulatorDeviceState(hardwareKeyboard: "off")
        #expect(argv(state.applyCommands(udid: udid)) == [
            ["flowdeck", "simulator", "keyboard", "hardware", "off", "-S", udid]
        ])
        #expect(argv(state.resetCommands(udid: udid)) == [
            ["flowdeck", "simulator", "keyboard", "hardware", "on", "-S", udid]
        ])
    }

    @Test("Status bar overrides become one invocation with kebab flags in a stable order")
    func statusBar() {
        // Dictionary iteration order is not stable, and an unstable argv makes
        // a grader's recorded command unreproducible.
        let state = SimulatorDeviceState(statusBar: [
            "operator-name": "Telefónica Móviles España",
            "battery-level": "5",
            "battery-state": "discharging",
        ])
        #expect(argv(state.applyCommands(udid: udid)) == [
            [
                "flowdeck", "simulator", "status-bar", "override",
                "--battery-level", "5",
                "--battery-state", "discharging",
                "--operator-name", "Telefónica Móviles España",
                "-S", udid,
            ]
        ])
        #expect(argv(state.resetCommands(udid: udid)) == [
            ["flowdeck", "simulator", "status-bar", "clear", "-S", udid]
        ])
    }

    @Test("An unknown status bar key is rejected at validation, not passed through")
    func unknownStatusBarKeyIsInvalid() {
        let state = SimulatorDeviceState(statusBar: ["batteryLevel": "5"])
        #expect(throws: BenchmarkFailure.self) { try state.validate() }
    }

    @Test("Reset undoes only what was applied")
    func resetIsScopedToWhatWasSet() {
        let state = SimulatorDeviceState(orientation: "landscape-right")
        let reset = argv(state.resetCommands(udid: udid))
        #expect(reset.count == 1)
        #expect(reset.allSatisfy { !$0.contains("appearance") })
    }

    @Test("Every applied setting is named in the summary the run records")
    func describesItself() {
        let state = SimulatorDeviceState(orientation: "landscape-left", language: "ar", locale: "ar_SA")
        let description = state.summary
        #expect(description.contains("orientation=landscape-left"))
        #expect(description.contains("language=ar"))
        #expect(description.contains("locale=ar_SA"))
    }

    @Test("A state decodes from the snake_case a task file writes")
    func decodesFromTaskYAMLKeys() throws {
        let json = """
        {
          "orientation": "landscape-left",
          "content_size": "accessibility-extra-large",
          "increase_contrast": "enabled",
          "hardware_keyboard": "off",
          "status_bar": { "battery-level": "5" }
        }
        """
        let state = try JSONDecoder().decode(SimulatorDeviceState.self, from: Data(json.utf8))
        #expect(state.orientation == "landscape-left")
        #expect(state.contentSize == "accessibility-extra-large")
        #expect(state.increaseContrast == "enabled")
        #expect(state.hardwareKeyboard == "off")
        #expect(state.statusBar?["battery-level"] == "5")
    }
}
