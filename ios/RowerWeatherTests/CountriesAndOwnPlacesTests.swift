import XCTest
@testable import RowerWeather

final class CountriesAndOwnPlacesTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "CountriesAndOwnPlacesTests")
        defaults.removePersistentDomain(forName: "CountriesAndOwnPlacesTests")
    }

    private func club(_ id: String, _ name: String, country: String, at point: Coordinate, region: String? = nil) -> Club {
        Club(id: id, name: name, shortName: nil, address: "", website: nil, launchPoint: point,
             launchPointVerified: false, country: country, region: region)
    }

    private func country(_ code: String, south: Double, west: Double, north: Double, east: Double) -> Country {
        Country(code: code, name: code, nameDe: code, clubs: 1, bounds: .init(south: south, west: west, north: north, east: east))
    }

    private var austria: [Lake] {
        [Lake(id: "river-donau", name: "Donau", center: Coordinate(lat: 48.2, lon: 16.4), clubs: [
            club("argonauten", "Wiener Ruderklub Argonauten", country: "at", at: Coordinate(lat: 48.24, lon: 16.43), region: "Wien"),
        ])]
    }

    private var switzerland: [Lake] {
        [Lake(id: "zurichsee", name: "Zürichsee", center: Coordinate(lat: 47.25, lon: 8.7), clubs: [
            club("seeclub-zurich", "Seeclub Zürich", country: "ch", at: Coordinate(lat: 47.36, lon: 8.54)),
            club("rc-zurich", "Ruderclub Zürich", country: "ch", at: Coordinate(lat: 47.35, lon: 8.55)),
        ])]
    }

    func testCountriesLoadOneByOneAndSearchFiltersByCountry() {
        let store = LocationStore(defaults: defaults)
        store.addCountry("at", lakes: austria)
        store.addCountry("ch", lakes: switzerland)
        XCTAssertEqual(store.loadedCountries, ["at", "ch"])
        XCTAssertEqual(Set(store.search("zurich").map(\.id)), ["seeclub-zurich", "rc-zurich"])  // "Zurich" finds "Zürich"
        XCTAssertEqual(store.search("wien").map(\.id), ["argonauten"])  // by state
        XCTAssertEqual(store.search("zurich", country: "at"), [])
        // A name starting with the search comes before one that only contains it.
        XCTAssertEqual(store.search("ruder").first?.id, "rc-zurich")

        store.addCountry("ch", lakes: [])  // loading a country again replaces its clubs
        XCTAssertEqual(store.catalog.map(\.id), ["argonauten"])
    }

    func testStartLoadsSavedCountriesThePhonesAndNearbyOnes() {
        let store = LocationStore(defaults: defaults)
        store.setCountries([
            country("de", south: 47.3, west: 6, north: 55, east: 15),
            country("at", south: 46.4, west: 9.5, north: 49, east: 17),
            country("ch", south: 45.8, west: 6, north: 47.8, east: 10.5),
        ])
        XCTAssertEqual(store.countriesToLoad(near: nil, region: "AT"), ["at"])
        XCTAssertEqual(store.countriesToLoad(near: nil, region: "US"), ["de"])  // nothing covered: the first
        // In Konstanz, Switzerland is a few km away.
        XCTAssertEqual(store.countriesToLoad(near: Coordinate(lat: 47.66, lon: 9.18), region: "DE"), ["de", "at", "ch"])

        store.addCountry("ch", lakes: switzerland)
        store.add(switzerland[0].clubs[0])
        let reopened = LocationStore(defaults: defaults)
        reopened.setCountries(store.countries)
        XCTAssertEqual(reopened.countriesToLoad(near: nil, region: "DE"), ["de", "ch"])
    }

    func testOwnPlaceStaysOnTheDeviceAndIsDeletedWhenRemoved() {
        let store = LocationStore(defaults: defaults)
        store.addCountry("ch", lakes: switzerland)
        store.add(switzerland[0].clubs[0])
        let place = OwnPlace(name: "Our jetty", kind: .water, website: nil,
                             coordinate: Coordinate(lat: 47.3, lon: 8.6), waterName: "Zürichsee", shared: false)
        store.addOwnPlace(place)
        XCTAssertEqual(store.saved.map(\.id), ["seeclub-zurich", place.id])
        XCTAssertTrue(store.saved[1].isOwnPlace)
        XCTAssertEqual(store.lake(of: store.saved[1])?.name, "Zürichsee")
        XCTAssertFalse(place.shared)

        let reopened = LocationStore(defaults: defaults)
        reopened.addCountry("ch", lakes: switzerland)
        XCTAssertEqual(reopened.saved.map(\.id), ["seeclub-zurich", place.id])
        reopened.remove(reopened.saved[1])
        XCTAssertTrue(reopened.ownPlaces.isEmpty)
        XCTAssertEqual(LocationStore(defaults: defaults).ownPlaces, [])
    }

    func testSuggestionLinkCarriesThePlaceButNothingPrivate() throws {
        let place = OwnPlace(name: "Bootshaus Nord", kind: .boathouse, website: URL(string: "https://example.org"),
                             coordinate: Coordinate(lat: 47.123456, lon: 8.5), waterName: nil, shared: true)
        let url = try XCTUnwrap(place.suggestionURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.host(), "github.com")
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "Place suggestion: Bootshaus Nord")
        XCTAssertTrue(items.first { $0.name == "body" }?.value?.contains("47.12346, 8.50000") == true)
    }

    func testSuggestionGoesToTheRowFrogService() throws {
        let place = OwnPlace(name: "Bootshaus Nord", kind: .boathouse, website: nil,
                             coordinate: Coordinate(lat: 47.5, lon: 9.7), waterName: "Bodensee", shared: true)
        let api = APIClient(baseURL: URL(string: "https://api.rowfrog.com/v1")!)
        let request = try place.suggestionRequest(api: api, country: "at")
        XCTAssertEqual(request.url?.absoluteString, "https://api.rowfrog.com/v1/suggestions")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "Bootshaus Nord")
        XCTAssertEqual(body["kind"] as? String, "boathouse")
        XCTAssertEqual(body["country"] as? String, "at")
        XCTAssertEqual(body["water"] as? String, "Bodensee")
        XCTAssertNil(body["id"])  // the place's id on the phone stays there
    }

    func testPhoneForecastAppliesTheRowingLightRules() throws {
        let json = """
        {"hourly": {"time": ["2026-10-23T10:00", "2026-10-23T11:00", "2026-10-23T22:00"],
          "temperature_2m": [12, 13, 8], "wind_speed_10m": [3, 9, 2], "wind_gusts_10m": [5, 14, 3],
          "wind_direction_10m": [200, 210, 220], "cloud_cover": [50, 80, 10], "visibility": [20000, 800, 20000],
          "precipitation": [0, 2, 0], "weather_code": [2, 95, 0], "apparent_temperature": [11, 10, 6],
          "relative_humidity_2m": [70, 90, 80], "dew_point_2m": [6, 11, 5], "pressure_msl": [1015, 1009, 1012],
          "cape": [0, 1200, 0], "is_day": [1, 1, 0]}}
        """
        let place = Club(id: "own-x", name: "X", shortName: nil, address: "", website: nil,
                         launchPoint: Coordinate(lat: 47.9, lon: 11.3), launchPointVerified: true, source: "own")
        let forecast = try PlaceForecaster.forecast(place, openMeteo: Data(json.utf8))
        XCTAssertEqual(forecast.hours.map(\.light), [.green, .red, .red])
        let stormy = Set(forecast.hours[1].reasons.map(\.condition))
        XCTAssertEqual(stormy, ["wind", "gusts", "thunderstorm", "fog"])
        XCTAssertEqual(forecast.hours[2].reasons.map(\.condition), ["daylight"])  // 22:00 UTC is dark in Bavaria
        XCTAssertNil(forecast.hours[0].waveHeightM)
        XCTAssertFalse(forecast.daylight?.isEmpty ?? true)
    }

    func testSunTimesMatchTheBackend() throws {
        // backend/rowerweather/sun.py gives 05:37 and 16:21 UTC for Starnberg on 18 Oct 2026.
        let day = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!
        let sun = try XCTUnwrap(Sun.day(day, lat: 47.99667, lon: 11.34745))
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        XCTAssertEqual(formatter.string(from: sun.sunrise), "05:37")
        XCTAssertEqual(formatter.string(from: sun.sunset), "16:21")
    }

    func testFlagFromCountryCode() {
        XCTAssertEqual(Country.flag("ch"), "🇨🇭")
    }
}
