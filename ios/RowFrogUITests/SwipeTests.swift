import XCTest

/// Quick swipes between club pages. Build 1024 aborted on the iPhone after a few fast
/// swipes (21 Nov 2026): with a navigation stack in each page, the paged TabView made
/// UIKit lay out one page's bar with a neighbouring page's item. In the Simulator,
/// bursts of three quick swipes brought the abort within 6 to 59 swipes; without a navigation
/// stack per page (decision 0063) 1,032 swipes went without one.
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

    /// One deliberate swipe across most of the screen, as a thumb does it: a short hold,
    /// then a drag at a moderate speed, above the middle where no card scrolls sideways.
    /// app.swipeLeft() and a fast drag left the page where it was on the GitHub runners
    /// with both the own pager and the standard TabView (21 and 22 Nov 2026), while the
    /// same pages swiped on the Mac's Simulators.
    private func pageSwipe(_ app: XCUIApplication, left: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.92 : 0.08, dy: 0.3))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.08 : 0.92, dy: 0.3))
        from.press(forDuration: 0.15, thenDragTo: to, withVelocity: 1200, thenHoldForDuration: 0)
    }

    /// Waits up to 10 s for the club shown to become (or stop being) `club`: on the Intel
    /// runners a gesture can take several seconds to arrive (CI on 21 Nov 2026).
    private func waitForShown(_ app: XCUIApplication, toBe club: String? = nil, notToBe other: String? = nil) -> String {
        let end = Date().addingTimeInterval(10)
        var now = shown(app)
        while Date() < end {
            if let club, now == club { break }
            if let other, now != other { break }
            Thread.sleep(forTimeInterval: 0.5)
            now = shown(app)
        }
        return now
    }

    /// A swipe goes to the next club, and back (the system's own swipe, as a rower's thumb).
    func testSwipeChangesTheClub() {
        let app = launch()
        let first = shown(app)
        pageSwipe(app, left: true)
        let second = waitForShown(app, notToBe: first)
        // The page tree tells whether the page moved but the dots did not follow, or the page stayed.
        XCTAssertNotEqual(first, second, "A swipe to the left did not change the club; the app shows:\n\(app.debugDescription)")
        pageSwipe(app, left: false)
        XCTAssertEqual(waitForShown(app, toBe: first), first, "A swipe back did not return to the first club")
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
