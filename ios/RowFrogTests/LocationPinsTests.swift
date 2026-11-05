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

    func testAClubhouseAtTheLaunchPointGetsNoPinOfItsOwn() {
        let near = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.99677, longitude: 11.34745)))
        let away = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34745)))
        XCTAssertNil(ClubMarks.clubhouse(of: near, launch: launch, verified: true))
        XCTAssertNil(ClubMarks.clubhouse(of: nil, launch: launch, verified: true))
        XCTAssertNotNil(ClubMarks.clubhouse(of: away, launch: launch, verified: true))
    }

    func testAClubWithNoLaunchPointSetKeepsOnePin() {
        // Its one point is the club itself, so there is nothing to split from.
        let away = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.99766, longitude: 11.34745)))
        XCTAssertNil(ClubMarks.clubhouse(of: away, launch: launch, verified: false))
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
