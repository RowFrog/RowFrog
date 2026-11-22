import XCTest
@testable import RowFrog

/// Owner's picks of 22 Nov 2026: one line per thing when the launch point and the water
/// within 1 km both set the light for it (fog A), and the ice line only at or below the
/// backend's open-water mark or when the estimate reports ice (ice A).
final class NearbyAndIceLinesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func hour(visibility: Double?, reasons: [Reason]) -> ForecastHour {
        ForecastHour(
            time: start, light: reasons.map(\.light).max() ?? .green, reasons: reasons,
            windSpeedMs: 3, windGustMs: 5, windFromDeg: 45, waveHeightM: 0.01, fetchM: nil,
            visibilityM: visibility, temperatureC: 3, cloudCoverPct: 100, sunUp: true
        )
    }

    private let nearbyFog = Reason(condition: "nearby_water", light: .red, topic: "fog", value: 300)
    private let stegFog = Reason(condition: "fog", light: .amber)

    func testFogAtTheStegAndNearbyIsOneLine() {
        let h = hour(visibility: 700, reasons: [nearbyFog, stegFog, Reason(condition: "cool_water", light: .amber)])
        XCTAssertEqual(h.shownReasons, [nearbyFog, Reason(condition: "cool_water", light: .amber)])
        XCTAssertEqual(h.reasons.count, 3, "the hour's own reasons and light stay as they are")
        let line = h.nearbyWithLaunchPoint(nearbyFog)
        XCTAssertNotNil(line)
        XCTAssertNotEqual(line, nearbyFog.explanation)
    }

    func testWithoutAStegReasonTheNearbyLineStaysAsBefore() {
        let h = hour(visibility: 2_000, reasons: [nearbyFog])
        XCTAssertEqual(h.shownReasons, [nearbyFog])
        XCTAssertNil(h.nearbyWithLaunchPoint(nearbyFog))
    }

    func testAMissingStegValueFallsBackToTheNearbySentence() {
        let h = hour(visibility: nil, reasons: [nearbyFog, stegFog])
        XCTAssertEqual(h.shownReasons, [nearbyFog])
        XCTAssertNil(h.nearbyWithLaunchPoint(nearbyFog))
    }

    func testOtherTopicsJoinToo() {
        let wind = Reason(condition: "nearby_water", light: .red, topic: "wind", value: 9)
        let h = hour(visibility: 20_000, reasons: [wind, Reason(condition: "wind", light: .amber)])
        XCTAssertEqual(h.shownReasons, [wind])
        XCTAssertNotNil(h.nearbyWithLaunchPoint(wind))
        let storm = Reason(condition: "nearby_water", light: .red, topic: "thunderstorm")
        XCTAssertNotNil(hour(visibility: nil, reasons: [storm, Reason(condition: "thunderstorm", light: .amber)]).nearbyWithLaunchPoint(storm))
    }

    private func forecast(water: Double?, ice: IceEstimate?) -> ClubForecast {
        var f = ClubForecast(
            clubId: "mrc-1880", lakeId: "starnberger-see", generatedAt: start,
            waterTemperature: water.map { WaterTemperature(celsius: $0, measuredAt: start) }, attribution: [], daylight: nil, hours: []
        )
        f.ice = ice
        return f
    }

    func testTheIceLineFollowsTheBackendsOpenWaterMark() {
        XCTAssertEqual(IceSeason.openWaterC, 3, "OPEN_WATER_C in backend/rowfrog/ice.py")
        let open = IceEstimate(status: "open", light: .green, waterTemperatureC: 7.9, basis: "measured")
        XCTAssertNil(forecast(water: 7.9, ice: open).iceValue, "the screenshot of 22 Nov: no line saying too warm for ice")
        XCTAssertNil(forecast(water: 3.1, ice: open).iceValue)
        let cold = IceEstimate(status: "open", light: .green, waterTemperatureC: 2.6, basis: "model")
        XCTAssertEqual(forecast(water: 2.6, ice: cold).iceValue, cold.title)
        XCTAssertEqual(forecast(water: 3, ice: cold).iceValue, cold.title)
        let edges = IceEstimate(status: "edges", light: .amber, basis: "model")
        XCTAssertEqual(forecast(water: 10, ice: edges).iceValue, edges.title, "reported ice shows at any water temperature")
        XCTAssertEqual(forecast(water: 2, ice: nil).iceValue, tr("No data yet"))
        XCTAssertNil(forecast(water: 5, ice: nil).iceValue)
    }
}
