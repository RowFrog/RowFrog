import XCTest
@testable import RowFrog

final class ClubPageLayoutTests: XCTestCase {
    func testEveryCardOnceAndNewCardsAtTheEnd() {
        let layout = PageLayout(order: [.hourly, .radar, .hourly])
        XCTAssertEqual(layout.order, [.hourly, .radar, .conditions, .lakeView, .launchPoint, .satellite])
        XCTAssertEqual(PageLayout(list: "satellite, radar").order.prefix(2), [.satellite, .radar])
    }

    func testUnknownCardsFromANewerVersionAreSkipped() throws {
        let json = #"{"order": ["radar", "webcam", "hourly"], "hidden": ["satellite", "webcam"]}"#
        let layout = try JSONDecoder().decode(PageLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.order.prefix(2), [.radar, .hourly])
        XCTAssertEqual(layout.order.count, PageCard.allCases.count)
        XCTAssertEqual(layout.hidden, [.satellite])
        XCTAssertFalse(layout.visible.contains(.satellite))
    }

    func testRoundTrip() throws {
        let layout = PageLayout(order: [.launchPoint, .conditions], hidden: [.radar])
        let back = try JSONDecoder().decode(PageLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(back, layout)
    }

    func testAClubsOwnOrderWinsAndResetFollowsAllClubs() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "ClubPageLayoutTests")!)
        settings.resetToFactorySettings()
        settings.pageLayout = PageLayout(order: [.hourly])
        settings.clubPageLayouts["a"] = PageLayout(order: [.satellite])
        XCTAssertEqual(settings.pageLayout(for: "a").order.first, .satellite)
        XCTAssertEqual(settings.pageLayout(for: "b").order.first, .hourly)
        settings.resetToFactorySettings()
        XCTAssertEqual(settings.pageLayout(for: "a"), .standard)
    }

    private func hours(_ pressures: [Double]) -> [ForecastHour] {
        pressures.enumerated().map { i, p in
            var hour = ForecastHour(
                time: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 3600), light: .green, reasons: [],
                windSpeedMs: 2, windGustMs: 4, windFromDeg: 180, waveHeightM: 0, fetchM: nil,
                visibilityM: 20_000, temperatureC: 15, cloudCoverPct: 20, sunUp: true
            )
            hour.pressureHpa = p
            return hour
        }
    }

    func testAPressureDipThatRecoversIsNotSteady() {
        // 1018 now, down to 1005, back to 1017 a day later: the old text said "steady".
        let text = ConditionDetail.pressureNext24(now: 1018, hours: hours([1018, 1012, 1005, 1010, 1017]))
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("1,005") || text!.contains("1.005") || text!.contains("1005"), text!)
        XCTAssertTrue(text!.hasSuffix("then rises"), text!)
        XCTAssertEqual(ConditionDetail.pressureNext24(now: 1013, hours: hours([1013, 1013.4, 1012.8])), "steady")
    }
}
