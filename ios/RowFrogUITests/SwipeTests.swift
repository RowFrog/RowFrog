import XCTest

/// Quick swipes between club pages. Build 1024 aborted on the iPhone after a few fast
/// swipes (21 Nov 2026): with a navigation stack in each page, the paged TabView made
/// UIKit lay out one page's bar with a neighbouring page's item. In the Simulator,
/// bursts of three quick swipes brought the abort within 6 to 59 swipes; the club
/// pager (ClubPager) went 415 swipes without one.
final class SwipeTests: XCTestCase {
    /// Four clubs as in the iPhone crash, plus one.
    static let clubs = ["mrc-1880", "rudergesellschaft-muenchen-1972", "mrsv-bayern",
                        "der-hamburger-und-germania-ruder-club", "berliner-ruder-club"]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-RWSavedClubs", "(" + Self.clubs.joined(separator: ",") + ")", "-RWHomeClub", "mrc-1880",
            "-RWTutorialSeen", "YES", "-RWNoTips", "YES",
            "-RWSafetyAccepted", "YES", "-RWWhatsNewSeen", "1000",
            "-RWOpenClub", "mrc-1880",
            "-RWAPIBaseURL", "https://api.rowfrog.com/v1",
            "-RWLanguage", "en",
        ]
        app.launch()
        // The first page; no forecast is needed for swiping.
        _ = app.buttons["top-tile-handle"].waitForExistence(timeout: 60)
        return app
    }

    /// The selected page dot's label: which club is shown.
    private func shown(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(NSPredicate(format: "isSelected == true"))
            .allElementsBoundByIndex.map(\.label).joined(separator: "|")
    }

    private func swipe(_ app: XCUIApplication, left: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.5))
        from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// A swipe goes to the next club, and back.
    func testSwipeChangesTheClub() {
        let app = launch()
        let first = shown(app)
        swipe(app, left: true)
        Thread.sleep(forTimeInterval: 1.5)
        let second = shown(app)
        XCTAssertNotEqual(first, second, "A swipe to the left did not change the club")
        swipe(app, left: false)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(shown(app), first, "A swipe back did not return to the first club")
    }

    /// Bursts of three quick swipes, then half a second's pause (the iPhone aborted about
    /// half a second after such swipes), back and forth over all pages, with taps on the
    /// page dots now and then. The app must still run after each burst.
    func testQuickSwipesKeepTheAppRunning() {
        let app = launch()
        let end = Date().addingTimeInterval(8 * 60)
        var swipes = 0
        var burst = 0
        while swipes < 90, Date() < end {
            let left = burst % 2 == 0
            for _ in 0..<3 { swipe(app, left: left) }
            swipes += 3
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertEqual(app.state, .runningForeground, "The app quit after \(swipes) quick swipes")
            if burst % 4 == 1 {
                // The dots sit in the middle of the bar at the bottom.
                for dx in [0.42, 0.58, 0.45, 0.55] {
                    app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.945)).tap()
                }
                XCTAssertEqual(app.state, .runningForeground, "The app quit after taps on the page dots")
            }
            burst += 1
        }
        print("Quick swipes: \(swipes) without the app quitting")
    }
}
