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

    func testThePinStandsOnTheMapAppsPlaceUnlessTheCheckedClubhouseIsFarFromIt() {
        let checked = Coordinate(lat: 47.99766, lon: 11.34745)  // 110 m from the launch point
        let near = CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34810)  // ~48 m from it
        let far = CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34950)  // ~150 m from it
        // No hand-checked point: the club's Apple Maps place.
        XCTAssertEqual(ClubMarks.clubhouse(of: club(set: true, house: nil), place: near)?.longitude, near.longitude)
        // Close to the checked clubhouse: Apple's place, so our pin covers its label.
        XCTAssertEqual(ClubMarks.clubhouse(of: club(set: true, house: checked), place: near)?.longitude, near.longitude)
        // Far from it (an entrance by the road): the checked clubhouse.
        XCTAssertEqual(ClubMarks.clubhouse(of: club(set: true, house: checked), place: far)?.longitude, checked.lon)
        // No map-app place: the checked clubhouse.
        XCTAssertEqual(ClubMarks.clubhouse(of: club(set: true, house: checked))?.longitude, checked.lon)
    }

    func testAClubWithNoLaunchPointSetMovesOntoItsPlaceWithoutOars() {
        let place = CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34810)
        let unset = club(set: false, house: nil)
        XCTAssertEqual(ClubMarks.clubhouse(of: unset, place: place)?.longitude, place.longitude)
        XCTAssertFalse(ClubMarks.showsOars(for: unset))
        XCTAssertTrue(ClubMarks.showsOars(for: club(set: true, house: nil)))
        XCTAssertTrue(ClubMarks.showsOars(for: club(set: false, verified: true, house: nil)))
        // Its place where its pin already stands: nothing moves.
        XCTAssertNil(ClubMarks.clubhouse(of: unset, place: launch))
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

    func testTheSheetKnowsItsScaleBeforeTheFirstMove() {
        // A square region on a wider map: the height sets the scale, the width shows more.
        let region = MKCoordinateRegion(center: launch, latitudinalMeters: 700, longitudinalMeters: 700)
        let span = LaunchPointDetails.fittedSpan(region, size: size)
        XCTAssertEqual(span.latitudeDelta, region.span.latitudeDelta, accuracy: 1e-9)
        XCTAssertEqual(span.longitudeDelta, region.span.longitudeDelta * 360 / 320, accuracy: 1e-9)
        // Kölner RG 1891's clubhouse, 204 m from its launch point, splits off at 700 m.
        let steg = CLLocationCoordinate2D(latitude: 50.89377, longitude: 7.00415)
        let house = CLLocationCoordinate2D(latitude: 50.892302, longitude: 7.002394)
        let wide = MKCoordinateRegion(center: steg, latitudinalMeters: 700, longitudinalMeters: 700)
        XCTAssertTrue(LaunchPointDetails.shouldSplit(house, from: steg, span: LaunchPointDetails.fittedSpan(wide, size: size), size: size, now: false))
    }

    func testNoSplitBeforeTheMapHasASize() {
        let clubhouse = CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34745)
        let span = MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        XCTAssertFalse(LaunchPointDetails.shouldSplit(clubhouse, from: launch, span: span, size: .zero, now: false))
    }
}
