import XCTest
@testable import RowFrog

/// The lake map's panel (owner's option B, 12 Nov 2026): full width on an upright iPhone,
/// a card at the bottom left on every wider screen. The website copies these numbers.
final class LakePanelLayoutTests: XCTestCase {
    func testUprightIPhonesKeepTheFullWidthPanel() {
        for width: CGFloat in [320, 375, 390, 402, 440] {
            XCTAssertFalse(LakePanelLayout.usesCard(width: width), "\(width)")
        }
    }

    func testWiderScreensGetTheCard() {
        // iPhone sideways (inside the safe area), iPad upright and sideways, a Mac window.
        for width: CGFloat in [600, 734, 744, 834, 1024, 1366] {
            XCTAssertTrue(LakePanelLayout.usesCard(width: width), "\(width)")
        }
    }

    func testTheNumbersTheWebsiteCopies() {
        XCTAssertEqual(LakePanelLayout.cardFromWidth, 600)
        XCTAssertEqual(LakePanelLayout.cardWidth, 360)
        XCTAssertEqual(LakePanelLayout.inset, 16)
        XCTAssertEqual(LakePanelLayout.cornerRadius, 22)
    }

    func testTheCardScrollsWithinTheScreen() {
        XCTAssertEqual(LakePanelLayout.scrollHeight(screenHeight: 1000), 700)
        // A phone turned sideways still gets a usable scrolling part.
        XCTAssertEqual(LakePanelLayout.scrollHeight(screenHeight: 350), LakePanelLayout.minScroll)
    }
}
