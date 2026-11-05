import MapKit
import XCTest
@testable import RowFrog

/// The Location map: one pin zoomed out, the clubhouse and the launch point
/// apart once they are far enough from each other on screen.
final class LocationPinsTests: XCTestCase {
    private let launch = CLLocationCoordinate2D(latitude: 47.99667, longitude: 11.34745)
    private let size = CGSize(width: 360, height: 320)

    func testPinsSplitOnlyWhenZoomedInFarEnough() {
        // About 110 m north of the launch point.
        let clubhouse = CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34745)
        let wide = MKCoordinateSpan(latitudeDelta: 0.0135, longitudeDelta: 0.02)   // ~1.5 km
        let close = MKCoordinateSpan(latitudeDelta: 0.00225, longitudeDelta: 0.0033)  // ~250 m
        XCTAssertFalse(LaunchPointDetails.shouldSplit(clubhouse, from: launch, span: wide, size: size, now: false))
        XCTAssertTrue(LaunchPointDetails.shouldSplit(clubhouse, from: launch, span: close, size: size, now: false))
    }

    func testPinsDontFlickerBetweenSplitAndJoined() {
        // 44 points apart on screen: not enough to split, not little enough to join.
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let clubhouse = CLLocationCoordinate2D(latitude: launch.latitude + 0.01 * 44 / 320, longitude: launch.longitude)
        XCTAssertFalse(LaunchPointDetails.shouldSplit(clubhouse, from: launch, span: span, size: size, now: false))
        XCTAssertTrue(LaunchPointDetails.shouldSplit(clubhouse, from: launch, span: span, size: size, now: true))
    }

    private func club(set: Bool, verified: Bool = false, house: Coordinate?) -> Club {
        var club = Club(id: "rc", name: "RC", shortName: nil, address: "", website: nil,
                        launchPoint: Coordinate(lat: launch.latitude, lon: launch.longitude), launchPointVerified: verified)
        club.launchPointSet = set
        club.clubhouse = house
        return club
    }

    func testAClubhouseAtTheLaunchPointGetsNoPinOfItsOwn() {
        XCTAssertNil(ClubMarks.clubhouse(of: club(set: true, house: Coordinate(lat: 47.99677, lon: 11.34745))))  // 11 m
        XCTAssertNil(ClubMarks.clubhouse(of: club(set: true, house: nil)))
        XCTAssertNotNil(ClubMarks.clubhouse(of: club(set: true, house: Coordinate(lat: 47.99766, lon: 11.34745))))  // 110 m
        XCTAssertNotNil(ClubMarks.clubhouse(of: club(set: false, verified: true, house: Coordinate(lat: 47.99766, lon: 11.34745))))
    }

    func testTheHandCheckedClubhouseComesBeforeTheMapsPlace() {
        let place = CLLocationCoordinate2D(latitude: 47.99700, longitude: 11.34900)
        let checked = Coordinate(lat: 47.99766, lon: 11.34745)
        // No hand-checked point: the club's Apple Maps place.
        XCTAssertEqual(ClubMarks.clubhouse(of: club(set: true, house: nil), place: place)?.longitude, place.longitude)
        // Checked by hand: that point, wherever the map app puts the club.
        XCTAssertEqual(ClubMarks.clubhouse(of: club(set: true, house: checked), place: place)?.latitude, checked.lat)
        // No launch point set: one pin, whatever the map app knows.
        XCTAssertNil(ClubMarks.clubhouse(of: club(set: false, house: nil), place: place))
    }

    func testAClubWithNoLaunchPointSetKeepsOnePin() {
        // Its one point is the club itself, so there is nothing to split from.
        XCTAssertNil(ClubMarks.clubhouse(of: club(set: false, house: Coordinate(lat: 47.99766, lon: 11.34745))))
    }

    func testMapsFindTheClubhouseByID() {
        let checked = club(set: true, house: Coordinate(lat: 47.99766, lon: 11.34745))
        ClubMarks.register([checked])
        XCTAssertNotNil(ClubMarks.clubhouse(forID: "rc"))
        XCTAssertNil(ClubMarks.clubhouse(forID: "other"))
        ClubMarks.register([])
    }

    func testEveryMapUsesTheSameThresholds() {
        XCTAssertFalse(ClubMarks.shouldSplit(apart: 47, now: false))
        XCTAssertTrue(ClubMarks.shouldSplit(apart: 48, now: false))
        XCTAssertTrue(ClubMarks.shouldSplit(apart: 40, now: true))
        XCTAssertFalse(ClubMarks.shouldSplit(apart: 39, now: true))
    }

    func testNoSplitBeforeTheMapHasASize() {
        let clubhouse = CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34745)
        let span = MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        XCTAssertFalse(LaunchPointDetails.shouldSplit(clubhouse, from: launch, span: span, size: .zero, now: false))
    }
}
