import XCTest
@testable import RowerWeather

final class LimitsTests: XCTestCase {
    private func hour(wind: Double, gust: Double, waves: Double, reasons: [Reason] = []) -> ForecastHour {
        ForecastHour(
            time: Date(timeIntervalSince1970: 1_800_000_000), light: reasons.map(\.light).max() ?? .green, reasons: reasons,
            windSpeedMs: wind, windGustMs: gust, windFromDeg: 180, waveHeightM: waves, fetchM: nil,
            visibilityM: 20_000, temperatureC: 15, cloudCoverPct: 20, sunUp: true
        )
    }

    func testStandardLimitsMatchTheBackend() {
        let limits = RowingLimits.standard
        let calm = hour(wind: 3, gust: 5, waves: 0.05).applying(limits, waterC: 18)
        XCTAssertEqual(calm.light, .green)
        let windy = hour(wind: 6, gust: 9, waves: 0.35).applying(limits, waterC: 12)
        XCTAssertEqual(windy.light, .red)
        XCTAssertEqual(Set(windy.reasons.map(\.condition)), ["wind", "gusts", "waves", "cool_water"])
        XCTAssertNil(windy.notes)
    }

    func testBigBoatsAllowMore() {
        let h = hour(wind: 6, gust: 9, waves: 0.2).applying(RowingLimits(boat: .big), waterC: nil)
        XCTAssertEqual(h.light, .green)
        XCTAssertEqual(h.notes?.map(\.condition), ["wind", "gusts", "waves"])
    }

    func testOwnLimitIsMarkedAndTheAppStillAdvises() {
        let limits = RowingLimits(custom: [.gustAmber: 14, .gustRed: 16, .windAmber: 3])
        let h = hour(wind: 4, gust: 13, waves: 0.05).applying(limits, waterC: nil)
        XCTAssertEqual(h.reasons, [Reason(condition: "wind", light: .amber, mine: true)])
        XCTAssertEqual(h.notes, [Reason(condition: "gusts", light: .red)])
    }

    func testOtherReasonsStay() {
        let dark = Reason(condition: "daylight", light: .red)
        let h = hour(wind: 1, gust: 2, waves: 0, reasons: [dark, Reason(condition: "wind", light: .amber)])
            .applying(RowingLimits(boat: .big), waterC: nil)
        XCTAssertEqual(h.reasons, [dark])
        XCTAssertEqual(h.light, .red)
    }
}
