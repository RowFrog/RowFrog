import SwiftUI
import XCTest
@testable import RowFrog

final class PicturePlaceTests: XCTestCase {
    /// A tall, slim lake picture on a wide screen: it fills the width and runs past the top and bottom.
    private let picture = CGSize(width: 400, height: 1600)
    private let screen = CGSize(width: 1200, height: 800)

    func testWithoutFocusThePictureIsCentred() {
        let place = PicturePlace.rect(for: picture, filling: screen, focus: nil)
        XCTAssertEqual(place.width, 1200)
        XCTAssertEqual(place.height, 4800)
        XCTAssertEqual(place.minY, -2000)
    }

    func testAClubAtTheTopShowsTheTopOfThePicture() {
        let place = PicturePlace.rect(for: picture, filling: screen, focus: UnitPoint(x: 0.5, y: 0.02))
        XCTAssertEqual(place.minY, 0, "as near the club as the picture's top edge allows")
    }

    func testAClubPartWayDownSitsInTheMiddle() {
        let place = PicturePlace.rect(for: picture, filling: screen, focus: UnitPoint(x: 0.5, y: 0.3))
        XCTAssertEqual(place.minY + 0.3 * place.height, screen.height / 2, accuracy: 0.001)
    }
}
