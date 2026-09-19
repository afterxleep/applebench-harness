import XCTest

/// Benchmark verification: the profile card must match the design reference
/// (Design/expected-ui.png) — title, element order, and the Follow button.
final class ProfileCardTests: XCTestCase {
    @MainActor
    func testProfileMatchesDesign() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Profile"].waitForExistence(timeout: 10),
            "The screen title must be 'Profile' as in the design"
        )

        let name = app.staticTexts["name"]
        let bio = app.staticTexts["bio"]
        XCTAssertTrue(name.exists, "The name label must exist")
        XCTAssertTrue(bio.exists, "The bio label must exist")
        XCTAssertEqual(name.label, "Ada Lovelace")
        XCTAssertLessThan(
            name.frame.minY, bio.frame.minY,
            "The name must appear above the bio, as in the design"
        )

        let follow = app.buttons["Follow"]
        XCTAssertTrue(follow.exists, "The Follow button from the design is missing")
    }
}
