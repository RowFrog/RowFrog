import XCTest
@testable import RowFrog

/// The night after the 48 hours comes from ICON-EU (owner's option B, 12 Nov 2026):
/// those hours are marked in the table, the 48 hours before them are not.
final class CoarserModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func hour(_ offset: Int) -> ForecastHour {
        ForecastHour(
            time: start.addingTimeInterval(Double(offset) * 3600), light: .red, reasons: [],
            windSpeedMs: 2, windGustMs: 4, windFromDeg: 180, waveHeightM: 0.1, fetchM: nil,
            visibilityM: 20_000, temperatureC: 5, cloudCoverPct: 20, sunUp: false
        )
    }

    private func part(_ model: String, _ km: Double, _ from: Int, _ to: Int) -> ForecastSource.Part {
        ForecastSource.Part(model: model, provider: "Deutscher Wetterdienst (DWD)", resolutionKm: km, fromHour: from, toHour: to)
    }

    private func forecast(_ parts: [ForecastSource.Part]) -> ClubForecast {
        var forecast = ClubForecast(
            clubId: "mrc-1880", lakeId: "starnberger-see", generatedAt: start.addingTimeInterval(20 * 60),
            waterTemperature: nil, attribution: [], daylight: nil, hours: (0..<60).map(hour)
        )
        forecast.forecastSource = ForecastSource(region: "germany", parts: parts)
        return forecast
    }

    func testHoursAfterTheFirstModelAreCoarser() {
        let f = forecast([part("ICON-D2", 2.2, 0, 48), part("ICON-EU", 7, 48, 60)])
        XCTAssertNil(f.coarserModel(for: hour(0)))
        XCTAssertNil(f.coarserModel(for: hour(47)))
        XCTAssertEqual(f.coarserModel(for: hour(48))?.model, "ICON-EU")
        XCTAssertEqual(f.coarserModel(for: hour(59))?.model, "ICON-EU")
    }

    func testOneModelMarksNothing() {
        let f = forecast([part("ICON-D2", 2.2, 0, 48)])
        XCTAssertNil(f.coarserModel(for: hour(50)))
    }

    func testTheHintNamesTimeModelAndGrid() {
        let text = NightRow.coarserText(from: hour(48).time, part: part("ICON-EU", 7, 48, 60))
        XCTAssertTrue(text.hasPrefix("≈ "))
        XCTAssertTrue(text.contains("ICON-EU"))
        XCTAssertTrue(text.contains("7"))
    }
}
