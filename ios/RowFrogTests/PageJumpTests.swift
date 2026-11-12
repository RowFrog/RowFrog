import XCTest
@testable import RowFrog

/// The page dots as Weather's (owner, 12 Nov 2026): a tap moves one club towards the tapped dot.
final class PageJumpTests: XCTestCase {
    private let ids = ["a", "b", "c", "d"]

    func testATapOnALaterDotMovesOneClubForward() {
        XCTAssertEqual(PageJump.step(towards: "d", from: "a", in: ids), "b")
    }

    func testATapOnAnEarlierDotMovesOneClubBack() {
        XCTAssertEqual(PageJump.step(towards: "a", from: "d", in: ids), "c")
    }

    func testTheCurrentDotDoesNothing() {
        XCTAssertNil(PageJump.step(towards: "b", from: "b", in: ids))
        XCTAssertNil(PageJump.step(towards: "x", from: "b", in: ids))
    }
}
