import XCTest
@testable import RowFrog

/// The iPad page's top buttons stay level with the list's top buttons, at the top of
/// the page and while it scrolls (owner, 12 Nov 2026: they sat 40 pt lower at the top,
/// beside the big name, and 4 pt higher once scrolled). The small name in the bar
/// sits on the same line, and the page starts below it.
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
        XCTAssertEqual(InlineClubTitle.barHeight(statusBar: 59, topButtons: false), InlineClubTitle.height)
    }

    func testTheIPadBarCentresTheNameOnTheButtonLine() {
        let bar = InlineClubTitle.barHeight(statusBar: 24, topButtons: true)
        let mid = PageTopButtons.midY(statusBar: 24, listButtonsMidY: PageScroll.shared.listButtonsMidY)
        XCTAssertEqual(24 + bar - InlineClubTitle.height / 2, mid)
    }

    func testThePageStartsBelowTheButtonsLevelWithTheListSearchField() {
        // Owner's shot, 12 Nov 2026: a long name's header card reached under the cog and the boat.
        // The list: 4 pt gap, 44 pt buttons, 10 pt, then its search field.
        let top = 24 + InlineClubTitle.barHeight(statusBar: 24, topButtons: true) + PageTopButtons.gapBelow
        XCTAssertEqual(top, 24 + 4 + 44 + 10)
    }
}
