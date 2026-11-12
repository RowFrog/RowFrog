import XCTest
@testable import RowFrog

/// The iPad page's top buttons stay level with the list's top buttons, at the top of
/// the page and while it scrolls (owner, 12 Nov 2026: they sat 40 pt lower at the top,
/// beside the big name, and 4 pt higher once scrolled). The small name in the bar
/// sits on the same line.
@MainActor
final class PageTopButtonsTests: XCTestCase {
    func testTheButtonsFollowTheListButtonsWhereMeasured() {
        XCTAssertEqual(PageTopButtons.midY(statusBar: 24, listButtonsMidY: 61), 61)
    }

    func testWithoutAListTheyGoWhereTheListPutsItsButtons() {
        // The list's header: 4 pt gap, then a row of 44 pt buttons.
        XCTAssertEqual(PageTopButtons.midY(statusBar: 24, listButtonsMidY: nil), 24 + 4 + 22)
    }

    func testWithoutAListBesideTheBarIsJustTheName() {
        XCTAssertEqual(InlineClubTitle.barHeight(statusBar: 59, besideList: false), InlineClubTitle.height)
    }

    func testTheIPadBarCentresTheNameOnTheButtonLine() {
        let bar = InlineClubTitle.barHeight(statusBar: 24, besideList: true)
        let mid = PageTopButtons.midY(statusBar: 24, listButtonsMidY: PageScroll.shared.listButtonsMidY)
        XCTAssertEqual(24 + bar - InlineClubTitle.height / 2, mid)
    }
}
