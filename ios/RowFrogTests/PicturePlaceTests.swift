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

    func testTheWidgetSquareIsCutAroundTheClub() {
        let tall = UIGraphicsImageRenderer(size: picture, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { context in UIColor.blue.setFill(); context.fill(CGRect(origin: .zero, size: picture)) }
        let part = BackgroundLibrary.square(of: tall, around: CGPoint(x: 0.5, y: 0.3))
        XCTAssertEqual(part.cgImage?.width, 400)
        XCTAssertEqual(part.cgImage?.height, 400)
        let top = BackgroundLibrary.square(of: tall, around: CGPoint(x: 0.5, y: 0.01))
        XCTAssertEqual(top.cgImage?.height, 400, "moved inwards at the picture's edge, not made smaller")
    }
}
