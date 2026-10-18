import XCTest
@testable import RowerWeather

final class ModelDecodingTests: XCTestCase {
    func testDecodesBackendForecast() throws {
        let json = """
        {"clubId": "mrc-1880", "lakeId": "starnberger-see",
         "generatedAt": "2026-10-18T11:20:00+00:00",
         "attribution": ["Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0"],
         "hours": [{"time": "2026-10-18T07:00:00+00:00", "light": "red",
                    "reasons": [{"condition": "waves", "light": "red"}],
                    "windSpeedMs": 9.0, "windGustMs": 14.0, "windFromDeg": 0,
                    "waveHeightM": 0.45, "fetchM": 9900, "visibilityM": 20000,
                    "temperatureC": 7.0, "cloudCoverPct": 80, "sunUp": true}],
         "daylight": [{"date": "2026-10-18", "sunrise": "2026-10-18T05:35:00+00:00",
                       "sunset": "2026-10-18T16:21:00+00:00"}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.hours.first?.light, .red)
        XCTAssertEqual(forecast.hours.first?.reasons.first?.label, "Waves")
        XCTAssertEqual(forecast.hours.first?.sunUp, true)

        let noon = ISO8601DateFormatter().date(from: "2026-10-18T10:00:00Z")!
        let evening = ISO8601DateFormatter().date(from: "2026-10-18T19:00:00Z")!
        guard case let .up(_, sunset) = forecast.sunState(at: noon) else { return XCTFail("sun should be up") }
        XCTAssertEqual(Format.time(sunset).count, 5)  // 24-hour "HH:mm"
        XCTAssertNil(forecast.sunState(at: evening))  // no next sunrise in the data
    }

    func testCurrentHourUsesTheSunNowNotTheWholeHour() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T16:00:00+00:00", "attribution": [],
         "daylight": [{"date": "2026-10-18", "sunrise": "2026-10-18T05:35:00+00:00", "sunset": "2026-10-18T16:21:00+00:00"},
                      {"date": "2026-10-19", "sunrise": "2026-10-19T05:37:00+00:00", "sunset": "2026-10-19T16:19:00+00:00"}],
         "hours": [{"time": "2026-10-18T16:00:00+00:00", "light": "amber",
                    "reasons": [{"condition": "twilight", "light": "amber"}]}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        let before = ISO8601DateFormatter().date(from: "2026-10-18T16:10:00Z")!
        let after = ISO8601DateFormatter().date(from: "2026-10-18T16:40:00Z")!
        XCTAssertEqual(forecast.current(at: before)?.light, .green)
        XCTAssertEqual(forecast.current(at: after)?.light, .red)
        XCTAssertEqual(forecast.current(at: after)?.reasons.first?.label, "Sun down")
    }

    func testDecodesForecastWithoutDaylight() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [],
         "hours": [{"time": "2026-10-18T07:00:00+00:00", "light": "green", "reasons": []}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertNil(forecast.daylight)
        XCTAssertNil(forecast.hours.first?.sunUp)
    }

    func testDecodesWarnings() throws {
        let json = """
        {"clubId": "x", "lakeId": "y", "generatedAt": "2026-10-18T11:20:00+00:00", "attribution": [], "hours": [],
         "warnings": {"status": "ok", "lakeArea": "Starnberger See",
                      "items": [{"kind": "lake", "area": "Starnberger See", "event": "STURM", "severity": "severe",
                                 "headline": "Sturmwarnung", "description": "Sturmböen um 65 km/h.", "instruction": null,
                                 "onset": "2026-10-18T12:00:00+00:00", "expires": null, "sample": false}]}}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        let warning = try XCTUnwrap(forecast.warnings?.items.first)
        XCTAssertTrue(warning.isLake)
        XCTAssertNil(warning.expires)
        XCTAssertEqual(warning.shortLabel, "DWD lake warning")
        XCTAssertEqual(Reason(condition: "lake_warning", light: .red).label, "DWD lake warning")
    }

    func testLightOrdering() {
        XCTAssertLessThan(Light.green, Light.amber)
        XCTAssertEqual([Light.amber, .red, .green].max(), .red)
    }
}
