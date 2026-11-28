import XCTest

/// Benchmark verification: the profile screen must survive being shown before
/// the account service has answered, and must show the profile once it has.
final class ProfileLoadTests: XCTestCase {
    @MainActor
    func testProfileAppearsAfterLoading() {
        let app = XCUIApplication()
        app.launch()

        let name = app.staticTexts["name"]
        XCTAssertTrue(
            name.waitForExistence(timeout: 15),
            "The profile name must appear once the account service answers"
        )
        XCTAssertEqual(name.label, "Ada Lovelace")
        XCTAssertEqual(app.staticTexts["role"].label, "Analyst")
        // The follower count is formatted for the device's locale, so assert
        // that it is populated rather than pinning a digit grouping.
        XCTAssertTrue(
            app.staticTexts["followers"].label.hasSuffix("followers"),
            "The follower count must be shown"
        )
        XCTAssertFalse(
            app.staticTexts["loading"].exists,
            "The loading placeholder must be gone once the profile has arrived"
        )

        XCTAssertEqual(
            app.state, .runningForeground,
            "The app must still be running after the profile loads"
        )
    }
}
