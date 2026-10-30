import XCTest

/// Taps the app as a rower would. The unit tests check the logic and the
/// screenshots the looks; neither notices a view that takes the taps meant
/// for the cards around it, as the frosted cards' picture did after #220.
final class TapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// MRC 1880's page, as the only club, over a background picture with
    /// frosted cards, with the published forecasts (the Debug build otherwise asks the backend on the Mac).
    private func launchClubPage() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            // MRC 1880 alone: with the demo's three clubs the pages beside it
            // made the page's accessibility tree too big to read in time on CI.
            "-RWSavedClubs", "(mrc-1880)", "-RWHomeClub", "mrc-1880",
            "-RWTutorialSeen", "YES", "-RWNoTips", "YES",
            "-RWSafetyAccepted", "YES", "-RWWhatsNewSeen", "1000",
            "-RWOpenClub", "mrc-1880",
            "-RWBackground", "sample:alpine-lake", "-RWTileStyle", "frosted",
            "-RWAPIBaseURL", "https://api.rowfrog.com/v1",
            "-RWLanguage", "en",
        ]
        app.launch()
        return app
    }

    /// The current conditions card is the page's first card, so every card
    /// below it could cover it.
    func testConditionTileOpensItsDetailView() {
        let app = launchClubPage()
        let tile = app.buttons["condition-wind"]
        XCTAssertTrue(tile.waitForExistence(timeout: 60), "No wind tile; the page shows:\n\(app.debugDescription)")
        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["condition-detail"].waitForExistence(timeout: 10),
                      "Tapping the wind tile opened nothing; the page shows:\n\(app.debugDescription)")
    }
}
