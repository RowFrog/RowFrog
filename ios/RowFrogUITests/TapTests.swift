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
    private func launchClubPage(_ extra: [String] = []) -> XCUIApplication {
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
        ] + extra
        app.launch()
        return app
    }

    /// Current conditions sits inside the top tile: its grip opens the tiles,
    /// and a tile opens its detail view (no card below covers it).
    func testConditionTileOpensItsDetailView() {
        let app = launchClubPage()
        let grip = app.buttons["top-tile-handle"]
        // The page waits for the published forecast. On the Intel runners of the
        // information-only jobs that took more than 60 s three times (#246, #272),
        // with the spinner still showing, so the wait is long; a fast run is no slower.
        XCTAssertTrue(grip.waitForExistence(timeout: 180), "No All values grip; the page shows:\n\(app.debugDescription)")
        grip.tap()
        let tile = app.buttons["condition-wind"]
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "The grip did not open the tiles; the page shows:\n\(app.debugDescription)")
        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["condition-detail"].waitForExistence(timeout: 30),
                      "Tapping the wind tile opened nothing; the page shows:\n\(app.debugDescription)")
    }

    /// The first start of a new install: the safety notice, the tour with the
    /// home base picked by search, then the home base's page.
    func testFirstStartLeadsToTheHomeBasePage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-RWFreshStart", "YES", "-RWNoTips", "YES",
            "-RWAPIBaseURL", "https://api.rowfrog.com/v1",
            "-RWLanguage", "en",
        ]
        app.launch()

        // The safety notice: agreeing needs the tick, the tick needs reading to the end.
        let agree = app.buttons["safety-agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 30), "No safety notice; the app shows:\n\(app.debugDescription)")
        XCTAssertFalse(agree.isEnabled, "Agree works before the notice was read")
        let tick = app.buttons["safety-tick"]
        for _ in 0..<15 where !tick.isEnabled { app.swipeUp() }
        XCTAssertTrue(tick.isEnabled, "Scrolling to the end did not enable the tick; the app shows:\n\(app.debugDescription)")
        tick.tap()
        XCTAssertTrue(agree.isEnabled, "The tick did not enable Agree")
        agree.tap()

        // The tour: welcome, then the home base, which needs a club before Next works.
        let next = app.buttons["tour-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 30), "No tour after the safety notice; the app shows:\n\(app.debugDescription)")
        next.tap()
        answerLocationQuestion()
        let search = app.textFields["tour-search-1"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "No home base search; the app shows:\n\(app.debugDescription)")
        XCTAssertFalse(next.isEnabled, "Next works without a home base")
        search.tap()
        search.typeText("MRC 1880")
        let club = app.buttons["tour-club-mrc-1880"]
        // The club list comes from the backend.
        XCTAssertTrue(club.waitForExistence(timeout: 60), "MRC 1880 not found by search; the app shows:\n\(app.debugDescription)")
        club.tap()
        XCTAssertTrue(next.isEnabled, "Picking the home base did not enable Next")
        next.tap()
        // More clubs is optional; the page after it can be skipped.
        next.tap()
        let skip = app.buttons["tour-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 30) && skip.isEnabled, "No Skip after the club pages; the app shows:\n\(app.debugDescription)")
        skip.tap()

        // The home base's page, with its forecast (see the wait in the test above).
        XCTAssertTrue(app.buttons["top-tile-handle"].waitForExistence(timeout: 180),
                      "The home base's page did not show; the app shows:\n\(app.debugDescription)")
    }

    /// The settings and the club list open from a club page and close again.
    func testSettingsAndClubListOpenFromTheClubPage() {
        let app = launchClubPage()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "No settings button; the page shows:\n\(app.debugDescription)")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30),
                      "Settings did not open; the app shows:\n\(app.debugDescription)")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 30), "Done did not close the settings")

        let list = app.buttons["All locations"]
        XCTAssertTrue(list.waitForExistence(timeout: 30), "No list button; the page shows:\n\(app.debugDescription)")
        list.tap()
        let row = app.buttons["list-club-mrc-1880"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The list does not show MRC 1880; the app shows:\n\(app.debugDescription)")
        row.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 30), "Picking the club did not close the list")
        XCTAssertTrue(app.buttons["Settings"].firstMatch.exists, "Not back on the club page")
    }

    /// Apple's accessibility audit of the club page: every control has a
    /// name VoiceOver can read, the right traits, a large enough tap area, and
    /// nothing that should be an element is hidden from VoiceOver. Contrast,
    /// clipped text and Dynamic Type are left out: they depend on the picture
    /// behind the cards and are checked on the screenshots instead.
    func testClubPagePassesTheAccessibilityAudit() throws {
        // Opened, so the audit sees the grip and every tile.
        let app = launchClubPage(["-RWTopTileOpen", "YES"])
        XCTAssertTrue(app.buttons["condition-wind"].waitForExistence(timeout: 180),
                      "No wind tile; the page shows:\n\(app.debugDescription)")
        // Small text links inside a card, known and kept on purpose: the boat
        // line already has a 44 pt touch area (tapArea), which the audit cannot
        // see; the warnings line, the daylight line and Feels like are one text
        // line each, and a taller target would push the card apart. A new small
        // target fails.
        let smallOnPurpose = ["For ", "No DWD warning", "No official warning", "Feels like", "Rowing until", "Rowing again"]
        var issues: [String] = []
        // Without .elementDetection: it reads text off the screen picture and names
        // no element, so a finding can't be traced (it flagged text with nothing
        // to point at once the background picture was hidden from VoiceOver).
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .trait]) { issue in
            if issue.auditType == .hitRegion, let label = issue.element?.label,
               smallOnPurpose.contains(where: { label.hasPrefix($0) }) {
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) id='\($0.identifier)' label='\($0.label)' at \($0.frame)" } ?? "no element"
            issues.append("\(issue.auditType): \(issue.compactDescription) [\(element)]")
            return true  // collected, reported together below
        }
        XCTAssertTrue(issues.isEmpty, "Accessibility audit of the club page:\n" + issues.joined(separator: "\n")
                      + "\n\nThe page shows:\n\(app.debugDescription)")
    }

    /// The tour asks for the location on the home base page; the answer does
    /// not matter to the test, so it is no.
    private func answerLocationQuestion() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let no = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don'")).firstMatch
        if no.waitForExistence(timeout: 30) { no.tap() }
    }
}
