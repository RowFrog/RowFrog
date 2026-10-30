import XCTest
@testable import RowFrog

final class MapAppTests: XCTestCase {
    func testGoogleMapsLinksPointAtTheLaunchPointAndTheClub() {
        XCTAssertEqual(MapApp.googleSearch("47.99812,11.34567")?.absoluteString,
                       "https://www.google.com/maps/search/?api=1&query=47.99812,11.34567")
        XCTAssertEqual(MapApp.googleDirections(to: "MRC 1880, Seestraße 1, Starnberg")?.absoluteString,
                       "https://www.google.com/maps/dir/?api=1&destination=MRC%201880,%20Seestra%C3%9Fe%201,%20Starnberg")
        XCTAssertEqual(MapApp.googleAppSearch("47.99812,11.34567")?.absoluteString, "comgooglemaps://?q=47.99812,11.34567")
        XCTAssertEqual(MapApp.googleAppDirections(to: "MRC 1880, Starnberg")?.absoluteString, "comgooglemaps://?daddr=MRC%201880,%20Starnberg")
    }

    func testAppleMapsIsTheDefault() {
        let defaults = UserDefaults(suiteName: "MapAppTests")!
        defaults.removePersistentDomain(forName: "MapAppTests")
        XCTAssertEqual(AppSettings(defaults: defaults).mapApp, .apple)
    }
}
