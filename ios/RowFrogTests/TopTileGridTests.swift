import XCTest
@testable import RowFrog

/// The top tile's values keep three columns while their titles and values fit side by
/// side; at large text sizes two, else one, so no word breaks or gets cut (German at
/// XXXL broke "Gefüh|lt" and cut "Ni…lag", 12 Nov 2026). The website does the same
/// (fitGreyLines in app.js, checked by the smoke test at every width and a large text size).
final class TopTileGridTests: XCTestCase {
    func testThreeColumnsWhileTheyFit() {
        XCTAssertEqual(TopTileGrid.columnCount(width: 330, core: [60, 100, 90], widest: 100, gap: 8), 3)
    }

    func testTwoColumnsWhenThreeAreTooWide() {
        XCTAssertEqual(TopTileGrid.columnCount(width: 330, core: [110, 170, 150], widest: 160, gap: 8), 2)
    }

    func testOneColumnWhenTwoAreTooWide() {
        XCTAssertEqual(TopTileGrid.columnCount(width: 300, core: [150, 200, 180], widest: 200, gap: 8), 1)
    }
}
