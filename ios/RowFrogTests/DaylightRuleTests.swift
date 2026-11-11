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

    /// Owner's pick B: the better half is held to the weather of the hour it touches.
    func testTheBetterHalfLooksAtItsNeighbour() {
        let days = days(sunset: "16:49")
        // A red hour before: the amber half before sunset turns red, so the dot is one colour.
        XCTAssertNil(DaylightRule.halves(from: at("16:00"), days: days, floor: .green, before: .red))
        // An amber hour before leaves the split as it is.
        XCTAssertEqual(DaylightRule.halves(from: at("16:00"), days: days, floor: .green, before: .amber), DotHalves(start: .amber, end: .red))
        // The hour after does not touch the better half at sunset.
        XCTAssertEqual(DaylightRule.halves(from: at("15:00"), days: days, floor: .green, after: .red), DotHalves(start: .green, end: .amber))
        // Never stricter than the other half: red before a green-then-amber hour gives plain amber.
        XCTAssertNil(DaylightRule.halves(from: at("15:00"), days: days, floor: .green, before: .red))
        // Sunrise: the green half is held to the hour after.
        let morning = [SunDay(sunrise: at("06:09"), sunset: at("16:49"))]
        XCTAssertNil(DaylightRule.halves(from: at("06:00"), days: morning, floor: .green, after: .red))
        XCTAssertEqual(DaylightRule.halves(from: at("06:00"), days: morning, floor: .green, after: .amber), DotHalves(start: .red, end: .amber))
    }

    /// Every sunrise and sunset minute with every weather in, before and after the hour
    /// (owner, 6 Nov 2026); the same loops run on the website (daylight-combos.test.mjs).
    func testEveryCombination() {
        let lights: [Light] = [.green, .amber, .red]
        var splits = 0
        for minute in 0..<60 {
            let sunsetDays = [SunDay(sunrise: at("06:09"), sunset: at("15:00").addingTimeInterval(Double(minute) * 60))]
            let sunriseDays = [SunDay(sunrise: at("06:00").addingTimeInterval(Double(minute) * 60), sunset: at("15:49"))]
            for (days, hours) in [(sunsetDays, ["13:00", "14:00", "15:00", "16:00"]), (sunriseDays, ["05:00", "06:00", "07:00"])] {
                for hm in hours {
                    let start = at(hm)
                    let sun = DaylightRule.parts(from: start, days: days).map(\.light).max()!
                    for floor in lights { for before in lights { for after in lights {
                        let row = max(sun, floor)
                        let label = "\(hm) minute \(minute) floor \(floor) before \(before) after \(after)"
                        guard let h = DaylightRule.halves(from: start, days: days, floor: floor, before: before, after: after) else { continue }
                        splits += 1
                        XCTAssertNotEqual(h.start, h.end, label)
                        XCTAssertEqual(max(h.start, h.end), row, label)
                        XCTAssertTrue(h.start >= floor && h.end >= floor, label)
                        if h.start < h.end { XCTAssertTrue(h.start >= before, label) } else { XCTAssertTrue(h.end >= after, label) }
                        XCTAssertTrue(h.start >= DaylightRule.light(at: start, days: days), label)
                        XCTAssertTrue(h.end >= DaylightRule.light(at: start.addingTimeInterval(3540), days: days), label)
                    } } }
                }
            }
        }
        XCTAssertGreaterThan(splits, 0)
    }
}
