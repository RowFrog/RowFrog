import XCTest
@testable import RowFrog

final class NightFoldTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Hours from `start`, dark where `dark` says so.
    private func hours(_ dark: [Bool], temperature: (Int) -> Double = { _ in 5 }) -> [ForecastHour] {
        dark.enumerated().map { i, isDark in
            ForecastHour(
                time: start.addingTimeInterval(Double(i) * 3600), light: isDark ? .red : .green, reasons: [],
                windSpeedMs: Double(i), windGustMs: Double(i) * 2, windFromDeg: 180, waveHeightM: 0.1, fetchM: nil,
                visibilityM: 20_000 - Double(i), temperatureC: temperature(i), cloudCoverPct: 20, sunUp: !isDark,
                precipitationMm: i == 3 ? 0.4 : 0.2
            )
        }
    }

    func testTheDarkHoursFoldIntoOneNight() {
        let parts = NightFold.parts(hours([false, false, true, true, true, false]))
        XCTAssertEqual(parts.count, 4)
        guard case let .night(night) = parts[2] else { return XCTFail("the third part is the night") }
        XCTAssertEqual(night.hours.count, 3)
        XCTAssertEqual(night.start, start.addingTimeInterval(2 * 3600))
        XCTAssertEqual(night.end, start.addingTimeInterval(5 * 3600), "the night ends when its last hour does")
    }

    func testTheFirstHourKeepsItsRowAtNight() {
        let parts = NightFold.parts(hours([true, true, true, false]))
        guard case .hour = parts[0], case let .night(night) = parts[1] else { return XCTFail("now, then the rest of the night") }
        XCTAssertEqual(night.hours.count, 2)
    }

    func testOneDarkHourStaysARow() {
        let parts = NightFold.parts(hours([false, true, false]))
        XCTAssertEqual(parts.count, 3)
        XCTAssertFalse(parts.contains { if case .night = $0 { true } else { false } })
    }

    func testTheNightLineShowsTheWorstOfEachColumn() {
        let parts = NightFold.parts(hours([false, true, true, true, false], temperature: { [3, 2, -1, 1, 4][$0] }))
        guard case let .night(night) = parts[1] else { return XCTFail("the second part is the night") }
        XCTAssertEqual(night.lowestC, -1)
        XCTAssertTrue(night.frost)
        XCTAssertEqual(night.strongestWindMs, 3)
        XCTAssertEqual(night.strongestGustMs, 6)
        XCTAssertEqual(night.rainMm ?? 0, 0.8, accuracy: 0.001, "all the night's rain added up")
        XCTAssertEqual(night.poorestVisibilityM, 20_000 - 3)
        XCTAssertNil(night.fogLight)
    }

    func testTheHourTheSunSetsInKeepsItsRow() {
        var list = hours([false, true, true, true])
        list[1] = list[1].with(reasons: [Reason(condition: "twilight", light: .amber)], sunUp: false)
        let parts = NightFold.parts(list)
        guard case .hour = parts[1], case let .night(night) = parts[2] else { return XCTFail("dusk as a row, then the night") }
        XCTAssertEqual(night.hours.count, 2)
    }

    func testNoFrostAboveFreezing() {
        let parts = NightFold.parts(hours([false, true, true], temperature: { _ in 0.6 }))
        guard case let .night(night) = parts[1] else { return XCTFail("the second part is the night") }
        XCTAssertFalse(night.frost, "0.6 °C shows as 1°, so no snowflake")
    }
}
