import XCTest
@testable import RowFrog

/// The daylight light to the minute and the half-and-half dots (owner's pick D, 6 Nov 2026).
final class DaylightRuleTests: XCTestCase {
    private func at(_ hm: String) -> Date { ISO8601DateFormatter().date(from: "2026-11-06T\(hm):00Z")! }
    private func days(sunset: String) -> [SunDay] { [SunDay(sunrise: at("06:00"), sunset: at(sunset))] }

    func testAmberInTheLastHourBeforeSunset() {
        let days = days(sunset: "16:49")
        XCTAssertEqual(DaylightRule.light(at: at("15:48"), days: days), .green)
        XCTAssertEqual(DaylightRule.light(at: at("15:49"), days: days), .amber)
        XCTAssertEqual(DaylightRule.light(at: at("16:48"), days: days), .amber)
        XCTAssertEqual(DaylightRule.light(at: at("16:49"), days: days), .red)
        XCTAssertEqual(DaylightRule.light(at: at("05:59"), days: days), .red)
    }

    func testAnHourThatChangesIsHalfAndHalf() {
        let days = days(sunset: "16:49")
        XCTAssertEqual(DaylightRule.halves(from: at("15:00"), days: days, floor: .green), DotHalves(start: .green, end: .amber))
        XCTAssertEqual(DaylightRule.halves(from: at("16:00"), days: days, floor: .green), DotHalves(start: .amber, end: .red))
        XCTAssertNil(DaylightRule.halves(from: at("14:00"), days: days, floor: .green))
        // Other conditions set a floor: under an amber wind the 15:00 hour is amber all through.
        XCTAssertNil(DaylightRule.halves(from: at("15:00"), days: days, floor: .amber))
    }

    func testAFewRelaxedMinutesAtTheEdgeDoNotShowButStricterOnesDo() {
        // Sunset 17:01: the 16:00 hour is green for one minute, then amber: one colour.
        XCTAssertNil(DaylightRule.halves(from: at("16:00"), days: days(sunset: "17:01"), floor: .green))
        // The 17:00 hour is amber for one minute, then dark: plain red.
        XCTAssertNil(DaylightRule.halves(from: at("17:00"), days: days(sunset: "17:01"), floor: .green))
        // Sunset 17:55: the 17:00 hour ends with five dark minutes, and they show.
        XCTAssertEqual(DaylightRule.halves(from: at("17:00"), days: days(sunset: "17:55"), floor: .green), DotHalves(start: .amber, end: .red))
        // Sunset on the hour: one whole amber hour, then red.
        XCTAssertNil(DaylightRule.halves(from: at("16:00"), days: days(sunset: "17:00"), floor: .green))
    }

    func testSunriseHour() {
        XCTAssertEqual(DaylightRule.halves(from: at("05:00"), days: [SunDay(sunrise: at("05:37"), sunset: at("16:49"))], floor: .green),
                       DotHalves(start: .red, end: .green))
    }

    func testOwnPlacesUseTheSameRule() {
        let days = days(sunset: "16:49")
        XCTAssertEqual(PlaceForecaster.daylight(start: at("15:00"), days: days, isDay: true).1, .amber)
        XCTAssertEqual(PlaceForecaster.daylight(start: at("16:00"), days: days, isDay: true).1, .red)
        XCTAssertEqual(PlaceForecaster.daylight(start: at("14:00"), days: days, isDay: true).1, .green)
    }
}
