import XCTest
@testable import RowFrog

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

    func testDaysLeaveOutNightHours() {
        let hours = [hour(0, .green), hour(1, .green), hour(2, .amber), hour(3, .green, sunUp: false), hour(4, .green, sunUp: false)]
        XCTAssertEqual(snapshot(hours, at: start).days(1).first?.lights, [.green, .green, .amber])
    }

    func testCurrentMovesOnWithTheEntryDate() {
        let hours = [hour(0, .green), hour(1, .red), hour(2, .amber)]
        let later = snapshot(hours, at: start.addingTimeInterval(3600 + 600))
        XCTAssertEqual(later.current?.light, .red)
        XCTAssertEqual(later.hours.count, 2)
    }

    func testOutOfDateForecastShowsNoGoodStretch() {
        let hours = (0..<8).map { hour($0, .green) }
        XCTAssertFalse(snapshot(hours, at: start.addingTimeInterval(2 * 3600)).isStale)
        let late = snapshot(hours, at: start.addingTimeInterval(3 * 3600 + 60))
        XCTAssertTrue(late.isStale)
        XCTAssertNil(late.days(1).first?.good)
    }

    func testHourLinesShowTheNumbersAloneForTheLegend() {
        let shown = hour(0, .green)
        XCTAssertEqual(RowingWidgetView.HourLine.allCases, [.wind, .waves, .visibility])
        for line in RowingWidgetView.HourLine.allCases {
            let text = line.text(shown)
            XCTAssertFalse(text.contains(line.unit), "\(line) shows its unit: \(text)")
            XCTAssertNotEqual(text, "–")
        }
        XCTAssertFalse(Format.temperatureNumber(15).contains("°"))
        XCTAssertEqual(Format.temperatureNumber(nil), "–")
    }
}
