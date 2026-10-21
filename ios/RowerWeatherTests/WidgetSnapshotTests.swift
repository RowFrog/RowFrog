import XCTest
@testable import RowerWeather

final class WidgetSnapshotTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func hour(_ offset: Int, _ light: Light, sunUp: Bool = true) -> ForecastHour {
        ForecastHour(
            time: start.addingTimeInterval(Double(offset) * 3600), light: light, reasons: [],
            windSpeedMs: 2, windGustMs: 4, windFromDeg: 180, waveHeightM: 0.1, fetchM: nil,
            visibilityM: 20_000, temperatureC: 15, cloudCoverPct: 20, sunUp: sunUp
        )
    }

    private func snapshot(_ hours: [ForecastHour], at date: Date) -> RowingSnapshot {
        let forecast = ClubForecast(
            clubId: "mrc-1880", lakeId: "starnberger-see", generatedAt: start, waterTemperature: nil,
            attribution: [], daylight: nil, hours: hours
        )
        return RowingSnapshot(date: date, clubName: "MRC 1880", isHome: true, forecast: forecast)
    }

    func testRowingWindowsJoinGreenDaylightHours() {
        let hours = [hour(0, .green), hour(1, .green), hour(2, .amber), hour(3, .green), hour(4, .green, sunUp: false), hour(5, .green), hour(6, .green)]
        let windows = snapshot(hours, at: start).rowingWindows
        XCTAssertEqual(windows.map(\.lowerBound), [start, start.addingTimeInterval(3 * 3600), start.addingTimeInterval(5 * 3600)])
        XCTAssertEqual(windows.map(\.upperBound), [start.addingTimeInterval(2 * 3600), start.addingTimeInterval(4 * 3600), start.addingTimeInterval(7 * 3600)])
    }

    func testCurrentMovesOnWithTheEntryDate() {
        let hours = [hour(0, .green), hour(1, .red), hour(2, .amber)]
        let later = snapshot(hours, at: start.addingTimeInterval(3600 + 600))
        XCTAssertEqual(later.current?.light, .red)
        XCTAssertEqual(later.hours.count, 2)
    }
}
