import XCTest
@testable import RowerWeather

final class RainRadarTests: XCTestCase {
    private func radar(_ values: [Double]) -> RainRadar {
        let start = ISO8601DateFormatter().date(from: "2026-10-20T20:30:00Z")!
        let steps = values.enumerated().map { RadarStep(time: start.addingTimeInterval(Double($0.offset) * 900), mmPerHour: $0.element) }
        return RainRadar(reference: start, steps: steps)
    }

    func testDry() {
        XCTAssertNil(radar([0, 0, 0.05, 0]).firstRain)
        XCTAssertEqual(radar([0, 0, 0.05, 0]).summary, "No rain in the next 2 hours")
    }

    func testRainLater() {
        let r = radar([0, 0, 0, 0, 1.2, 3.0])
        XCTAssertFalse(r.rainingNow)
        XCTAssertEqual(r.firstRain?.mmPerHour, 1.2)
        XCTAssertTrue(r.summary.hasPrefix("Rain from "))
    }

    func testRainNowThenDry() {
        let r = radar([0.5, 0.8, 0, 0])
        XCTAssertTrue(r.rainingNow)
        XCTAssertNotNil(r.dryAgain)
        XCTAssertTrue(r.summary.hasPrefix("Light rain now, dry from "))
    }
}
