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
                    "temperatureC": 7.0, "cloudCoverPct": 80}]}
        """
        let forecast = try APIClient.decoder.decode(ClubForecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.hours.first?.light, .red)
        XCTAssertEqual(forecast.hours.first?.reasons.first?.label, "Waves")
    }

    func testLightOrdering() {
        XCTAssertLessThan(Light.green, Light.amber)
        XCTAssertEqual([Light.amber, .red, .green].max(), .red)
    }
}
