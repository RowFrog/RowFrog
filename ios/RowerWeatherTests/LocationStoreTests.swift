import XCTest
@testable import RowerWeather

final class LocationStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "LocationStoreTests")
        defaults.removePersistentDomain(forName: "LocationStoreTests")
    }

    private func club(_ id: String, _ name: String, verified: Bool = true, address: String = "Seestraße 1, 82319 Starnberg",
                      at launchPoint: Coordinate = Coordinate(lat: 48, lon: 11.3)) -> Club {
        Club(id: id, name: name, shortName: nil, address: address, website: nil,
             launchPoint: launchPoint, launchPointVerified: verified)
    }

    private var lakes: [Lake] {
        [
            Lake(id: "starnberger-see", name: "Starnberger See", center: Coordinate(lat: 47.9, lon: 11.3), clubs: [
                club("tutzinger-rv", "Tutzinger Ruderverein", address: "Seestraße 22, 82327 Tutzing"),
                club("mrc-1880", "Münchener Ruder-Club von 1880"),
            ]),
            Lake(id: "ammersee", name: "Ammersee", center: Coordinate(lat: 48, lon: 11.1), clubs: [
                club("rc-diessen", "Ruderclub Dießen", verified: false, address: "Seeweg 1, 86911 Dießen am Ammersee"),
            ]),
        ]
    }

    func testFirstLaunchStartsEmptyAndFirstClubBecomesHomeBase() {
        let store = LocationStore(defaults: defaults)
        store.setCatalog(lakes)
        XCTAssertEqual(store.saved.map(\.id), [])
        XCTAssertNil(store.homeID)
        XCTAssertEqual(Set(store.suggestions(near: nil).map(\.id)), ["tutzinger-rv", "mrc-1880", "rc-diessen"])
        store.add(lakes[0].clubs[0])
        XCTAssertEqual(store.homeID, "tutzinger-rv")
    }

    func testSuggestionsNearALocationComeNearestFirst() {
        let store = LocationStore(defaults: defaults)
        store.setCatalog([Lake(id: "x", name: "X", center: Coordinate(lat: 48, lon: 11), clubs: [
            club("far", "Far", at: Coordinate(lat: 49, lon: 11)),
            club("near", "Near", at: Coordinate(lat: 48.01, lon: 11)),
        ])])
        XCTAssertEqual(store.suggestions(near: Coordinate(lat: 48, lon: 11)).map(\.id), ["near", "far"])
    }

    func testReplacingTheHomeBaseDropsTheOldOne() {
        let store = LocationStore(defaults: defaults)
        store.setCatalog(lakes)
        store.replaceHome(with: lakes[0].clubs[0])
        store.replaceHome(with: lakes[0].clubs[1])
        store.add(lakes[1].clubs[0])
        XCTAssertEqual(store.saved.map(\.id), ["mrc-1880", "rc-diessen"])
    }

    func testSearchMatchesLakeAndTownIgnoringAccents() {
        let store = LocationStore(defaults: defaults)
        store.setCatalog(lakes)
        XCTAssertEqual(store.search("ammer").map(\.id), ["rc-diessen"])
        XCTAssertEqual(store.search("diessen").map(\.id), ["rc-diessen"])
        XCTAssertEqual(store.search("Dießen ruder").map(\.id), ["rc-diessen"])
        XCTAssertEqual(store.search("tutzing").map(\.id), ["tutzinger-rv"])
    }

    func testAddRemoveAndHomeBasePersist() {
        let store = LocationStore(defaults: defaults)
        store.setCatalog(lakes)
        store.add(lakes[0].clubs[1])  // the first club becomes the home base
        store.add(lakes[0].clubs[0])
        let diessen = lakes[1].clubs[0]
        store.add(diessen)
        store.remove(lakes[0].clubs[1])  // the home base cannot be removed
        XCTAssertEqual(store.saved.map(\.id), ["mrc-1880", "tutzinger-rv", "rc-diessen"])
        store.makeHome(diessen)

        let reopened = LocationStore(defaults: defaults)
        reopened.setCatalog(lakes)
        XCTAssertEqual(reopened.saved.map(\.id), ["rc-diessen", "mrc-1880", "tutzinger-rv"])
    }

    func testTownFromAddress() {
        XCTAssertEqual(club("x", "X", address: "Seestraße 22, 82327 Tutzing").town, "Tutzing")
        XCTAssertNil(club("x", "X", address: "").town)
    }
}
