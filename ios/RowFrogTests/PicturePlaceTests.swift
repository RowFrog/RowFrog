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

    // The widget's satellite picture: a square cut around the club.

    func testAClubsPlaceFollowsItsLaunchPoint() {
        let box = [11.25, 47.80, 11.45, 48.00]
        let spot = BackgroundLibrary.place(of: Coordinate(lat: 47.95, lon: 11.30), in: box)
        XCTAssertEqual(spot?.x ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(spot?.y ?? 0, 0.25, accuracy: 0.0001, "north is at the top")
        XCTAssertNil(BackgroundLibrary.place(of: Coordinate(lat: 47.95, lon: 11.30), in: nil))
    }

    func testAClubAtALakesEndSitsAtTheTopOfTheMediumWidget() {
        // Starnberger See's picture (435 × 1280) with MRC 1880's Steg near its top right,
        // in the medium widget (364 × 170): the full width, the picture's top at the widget's top.
        let lake = CGSize(width: 435, height: 1280), medium = CGSize(width: 364, height: 170)
        let steg = UnitPoint(x: 0.82, y: 0.075)
        let place = PicturePlace.rect(for: lake, filling: medium, focus: steg)
        XCTAssertEqual(place.width, medium.width, accuracy: 0.001, "fills the whole width")
        XCTAssertEqual(place.minY, 0, "the picture's top edge, as near the club as it allows")
        let clubY = place.minY + steg.y * place.height
        XCTAssertTrue((0...medium.height).contains(clubY), "the club is in the widget")
        // Without the club's place, the widget showed the picture's middle and missed the club.
        let middle = PicturePlace.rect(for: lake, filling: medium, focus: nil)
        XCTAssertFalse((0...medium.height).contains(middle.minY + steg.y * middle.height))
    }

    func testThePictureFileKeepsItsOwnClubPlace() {
        // The satellite key stays as it was; the club page picture's place has its own.
        XCTAssertEqual(WidgetPictures.focusKey("mrc-1880"), "RWWidgetPictureFocus-mrc-1880")
        XCTAssertNotEqual(WidgetPictures.focusKey("mrc-1880", .picture), WidgetPictures.focusKey("mrc-1880"))
    }
}
