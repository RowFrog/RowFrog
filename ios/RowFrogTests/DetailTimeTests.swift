import XCTest
@testable import RowFrog

final class DetailTimeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DetailTime.linkKey)
        UserDefaults.standard.removeObject(forKey: "RWChartSelect")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DetailTime.linkKey)
        super.tearDown()
    }

    func testLinkedByDefaultAndTheMapFollowsTheChart() {
        let time = DetailTime()
        XCTAssertTrue(time.linked)
        time.setChart(5.4)
        XCTAssertEqual(time.hour, 5)
        XCTAssertEqual(time.shownMapHour, 5)
        time.setMap(9)
        XCTAssertEqual(time.hour, 9, "linked, the map's slider moves the chart")
    }

    func testUnlinkedEachKeepsItsOwnHourAndLinkingAgainMovesTheChart() {
        let time = DetailTime()
        time.setChart(3)
        time.setLinked(false)
        XCTAssertEqual(time.shownMapHour, 3, "the map stays where it was")
        time.setChart(10)
        time.setMap(20)
        XCTAssertEqual(time.hour, 10)
        XCTAssertEqual(time.shownMapHour, 20)
        time.setLinked(true)
        XCTAssertEqual(time.hour, 20)
        XCTAssertEqual(time.shownMapHour, 20)
    }

    func testTheLinkChoiceIsRemembered() {
        DetailTime().setLinked(false)
        XCTAssertFalse(DetailTime().linked)
    }

    func testBackMovesTheChartAndOnlyALinkedMap() {
        let linked = DetailTime()
        linked.setChart(7)
        linked.scrollX = 30
        linked.back()
        XCTAssertEqual(linked.hour, 0)
        XCTAssertEqual(linked.shownMapHour, 0)
        XCTAssertEqual(linked.scrollX, DetailTime.start)

        let own = DetailTime()
        own.setLinked(false)
        own.setMap(12)
        own.setChart(7)
        own.back()
        XCTAssertEqual(own.hour, 0)
        XCTAssertEqual(own.shownMapHour, 12)
    }

    func testTheMapShowsTheNearestHourAndKnowsWhenItRunsOut() {
        let time = DetailTime()
        XCTAssertNil(time.mapFrameHour, "no map, no green marker")
        time.mapHours = Array(stride(from: 0.0, through: 24, by: 1)) + [27, 30, 33, 36, 39, 42, 45, 48]
        time.setChart(28)
        XCTAssertEqual(time.mapFrameHour, 27)
        XCTAssertFalse(time.mapOutOfRange)
        time.setChart(60)
        XCTAssertEqual(time.mapFrameHour, 48)
        XCTAssertTrue(time.mapOutOfRange)
        time.setChart(-5)
        XCTAssertEqual(time.mapFrameHour, 0)
        XCTAssertTrue(time.mapOutOfRange)
    }

    func testTheBigNumberComesFromTheBlueLinesHour() {
        let hours = (-24..<48).map { i in
            ForecastHour(
                time: start.addingTimeInterval(Double(i) * 3600), light: .green, reasons: [],
                windSpeedMs: Double(i + 30), windGustMs: nil, windFromDeg: 180, waveHeightM: 0.1, fetchM: nil,
                visibilityM: 20_000, temperatureC: 15, cloudCoverPct: 20, sunUp: true
            )
        }
        let forecast = ClubForecast(
            clubId: "mrc-1880", lakeId: "starnberger-see", generatedAt: start, waterTemperature: nil,
            attribution: [], daylight: nil, hours: hours
        )
        let data = ConditionData(forecast: forecast, now: hours[24])
        XCTAssertEqual(data.at(0).now.time, start)
        XCTAssertEqual(data.at(5).now.windSpeedMs, 35)
        XCTAssertEqual(data.at(-3).now.time, start.addingTimeInterval(-3 * 3600))
        XCTAssertEqual(data.at(5).x(start), -5, "hours now count from the blue line's hour")
    }
}
