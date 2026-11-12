import XCTest
@testable import RowFrog

/// The club page's column rule B (owner, 12 Nov 2026), the same as the website's.
final class ClubPageColumnsTests: XCTestCase {
    /// Every iPad, upright and on its side, list shown and hidden: always two
    /// columns, because the count follows the width beside the list (400 pt).
    func testEveryIPadKeepsTwoColumnsWithTheListShownOrHidden() {
        let ipads: [(String, CGFloat, CGFloat)] = [
            ("mini", 744, 1133), ("iPad", 820, 1180), ("Air/Pro 11", 834, 1194),
            ("Pro 11 M4", 834, 1210), ("Air 13", 1024, 1366), ("Pro 13 M4", 1032, 1376),
        ]
        for (name, short, long) in ipads {
            for (width, height) in [(short, long), (long, short)] {
                let wide = width >= 860 && height >= 560
                let countWidth = wide ? width - 400 : width
                XCTAssertEqual(ClubPageColumns.count(width: countWidth), 2, "\(name) \(width)×\(height)")
            }
        }
    }

    func testThreeColumnsWithABufferAgainstFlicker() {
        // Room = width − 32 padding. Three from 1,200, back to two below 1,172.
        XCTAssertEqual(ClubPageColumns.count(width: 1231), 2)
        XCTAssertEqual(ClubPageColumns.count(width: 1232), 3)
        XCTAssertEqual(ClubPageColumns.count(width: 1204, current: 3), 3)
        XCTAssertEqual(ClubPageColumns.count(width: 1203, current: 3), 2)
        XCTAssertEqual(ClubPageColumns.count(width: 1200, current: 2), 2)
        XCTAssertEqual(ClubPageColumns.count(width: 599), 1)
        XCTAssertEqual(ClubPageColumns.count(width: 600), 2)
        // The third column's cards are never narrower than 380.
        let room = ClubPageColumns.threeUntil - 2 * ClubPageColumns.spacing
        XCTAssertGreaterThanOrEqual(room / 3, ClubPageColumns.narrowestCard)
    }

    func testThePageGrowsUntilEveryCardIs560Wide() {
        XCTAssertEqual(ClubPageColumns.pageWidth(columns: 1), 1000)
        XCTAssertEqual(ClubPageColumns.pageWidth(columns: 2), 2 * 560 + 16 + 32)
        XCTAssertEqual(ClubPageColumns.pageWidth(columns: 3), 3 * 560 + 32 + 32)
        // 13-inch iPad on its side, list hidden: 1,376 − 32 = 1,344 of room, cards stop at 560.
        XCTAssertEqual(BalancedColumns(columns: 2).columnWidth(1344), 560)
        // List shown: 976 − 32 = 944 of room.
        XCTAssertEqual(BalancedColumns(columns: 2).columnWidth(944), 464)
        XCTAssertEqual(BalancedColumns(columns: 3).columnWidth(1296), 421.33, accuracy: 0.01)
    }

    func testThreeColumnsFillShortestFirstAndLevelTheirMaps() {
        // Top to bottom: 300, 200, 500 (filler), 100 (filler), 100.
        let (columns, grow) = BalancedColumns.balance(sorted: [300, 200, 500, 100, 100],
                                                      fillers: [false, false, true, true, false],
                                                      columns: 3, spacing: 16, tallestCard: 1000)
        XCTAssertEqual(columns, [0, 1, 2, 1, 0])
        // Column 2 ends at 500, column 1 at 200+16+100 = 316, column 0 at 300+16+100 = 416.
        // Column 1's map grows by 184; column 0 has no map, so it stays short.
        XCTAssertEqual(grow[3], 184, accuracy: 0.01)
        XCTAssertEqual(grow[2], 0)
        XCTAssertEqual(grow.reduce(0, +), 184, accuracy: 0.01)
    }

    func testTwoColumnsStayAsBefore() {
        // 400 left; 300 (a map) and 50 right, ending at 366: the map grows by 34.
        let (columns, grow) = BalancedColumns.balance(sorted: [400, 300, 50], fillers: [false, true, false],
                                                      columns: 2, spacing: 16, tallestCard: 1000)
        XCTAssertEqual(columns, [0, 1, 1])
        XCTAssertEqual(grow[1], 400 - (300 + 16 + 50), accuracy: 0.01)
        XCTAssertEqual(grow[0], 0)
    }

    func testTheTopCardIsTheOneAtTheTopEdge() {
        let spots = CardSpots()
        spots.frames = [
            .conditions: CGRect(x: 16, y: -400, width: 400, height: 300),
            .hourly: CGRect(x: 432, y: -200, width: 400, height: 900),
            .lakeView: CGRect(x: 16, y: -84, width: 400, height: 300),
            .satellite: CGRect(x: 16, y: 232, width: 400, height: 300),
        ]
        // At the edge (60): the lake view (left) and the 48 hours both cut it; the leftmost wins.
        XCTAssertEqual(spots.topCard(below: 60), .lakeView)
        // Not scrolled past the first card yet: nothing to keep.
        spots.frames = [.conditions: CGRect(x: 16, y: 500, width: 400, height: 300)]
        XCTAssertNil(spots.topCard(below: 60))
    }
}
