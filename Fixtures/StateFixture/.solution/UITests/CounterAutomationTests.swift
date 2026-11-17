import XCTest

/// Reference automation for the fixture, authored the way the task asks:
/// accessibility identifiers rather than coordinates, and assertions on what
/// the user can see.

final class CounterAutomationTests: XCTestCase {
    func testTheCounterAdvancesByEveryTap() {
        let app = XCUIApplication()
        app.launch()

        let increment = app.buttons["increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 10))
        for _ in 0..<3 { increment.tap() }

        XCTAssertTrue(app.buttons["goDetail"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
