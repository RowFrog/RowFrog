import XCTest
@testable import RowFrog

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

    func testWhatFallsNowAndWhereTheNowcastEnds() {
        XCTAssertNil(radar([0, 0, 1.2]).rainNow)
        XCTAssertEqual(radar([0.5, 0.8, 0]).rainNow, "Light rain")
        XCTAssertEqual(radar([12, 3, 0]).rainNow, "Heavy rain")
        let r = radar([0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(r.end, r.steps.last?.time)
        XCTAssertEqual(r.end.timeIntervalSince(r.reference), 2 * 3600)
    }

    private func hours(code: Int, mm: [Double]) -> [ForecastHour] {
        let start = ISO8601DateFormatter().date(from: "2026-10-20T20:00:00Z")!
        return mm.enumerated().map { i, v in
            var hour = ForecastHour(
                time: start.addingTimeInterval(Double(i) * 3600), light: .green, reasons: [],
                windSpeedMs: 2, windGustMs: 4, windFromDeg: 180, waveHeightM: 0, fetchM: nil,
                visibilityM: 20_000, temperatureC: 1, cloudCoverPct: 100, sunUp: true
            )
            hour.weatherCode = code
            hour.precipitationMm = v
            return hour
        }
    }

    func testTheOutlookNamesSnowFromTheForecast() {
        let outlook = RainOutlook(radar: radar([0, 0, 1.2, 1.5]), hours: hours(code: 73, mm: [0, 1, 1]))
        XCTAssertNil(outlook.now)
        XCTAssertTrue(outlook.next!.text.hasPrefix("Snow from "), outlook.next!.text)
        XCTAssertTrue(outlook.next!.fromRadar)
    }

    func testWhileItRainsTheOutlookSaysWhatComesNext() {
        let rain = hours(code: 61, mm: [1, 1, 1, 1, 0])
        // Ends within the radar's reach.
        let ends = RainOutlook(radar: radar([0.5, 0.8, 0, 0]), hours: rain)
        XCTAssertEqual(ends.now, "Light rain")
        XCTAssertTrue(ends.next!.text.hasPrefix("Dry from "))
        // Gets heavier first.
        let heavier = RainOutlook(radar: radar([0.5, 4, 4, 0]), hours: rain)
        XCTAssertTrue(heavier.next!.text.hasPrefix("Heavier from "))
        // Outlasts the radar: the forecast's end, not marked as radar.
        let long = RainOutlook(radar: radar([0.5, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8]), hours: rain)
        XCTAssertTrue(long.next!.text.hasPrefix("Until about "), long.next!.text)
        XCTAssertFalse(long.next!.fromRadar)
    }

    func testTheHeadlineFollowsTheRadarLikeTheRainTile() {
        func data(code: Int, mm: Double, radar values: [Double]) -> ConditionData {
            let hours = hours(code: code, mm: [mm, mm, mm])
            let forecast = ClubForecast(
                clubId: "mrc-1880", lakeId: "starnberger-see", generatedAt: hours[0].time, waterTemperature: nil,
                attribution: [], daylight: nil, hours: hours
            )
            return ConditionData(forecast: forecast, now: hours[0], radar: radar(values))
        }
        // The model says rain, the radar sees none: cloudy, as the rain tile says dry.
        let dry = data(code: 61, mm: 0.3, radar: [0, 0, 0, 1.2])
        XCTAssertEqual(dry.rainLines.value, "Dry")
        XCTAssertEqual(dry.sky, .cloudy)
        // The model is dry, the radar sees rain: rain (snow when it freezes; these hours are at 1 °C).
        XCTAssertEqual(data(code: 3, mm: 0, radar: [0.8, 0.8, 0]).sky, .rain)
        // Both agree: the model's own word stays.
        XCTAssertEqual(data(code: 73, mm: 1, radar: [0.8, 0.8, 0]).sky, .snow)
        XCTAssertEqual(data(code: 2, mm: 0, radar: [0, 0, 0]).sky, .partlyCloudy)
    }

    @MainActor
    func testAFailedRadarReadIsTriedAgainSoonThenAtTheUsualPace() {
        XCTAssertEqual(RadarStore.retryDelay(after: 1), 30)
        XCTAssertEqual(RadarStore.retryDelay(after: 2), 60)
        XCTAssertEqual(RadarStore.retryDelay(after: 3), 120)
        XCTAssertEqual(RadarStore.retryDelay(after: 4), RadarStore.refresh)
    }
}
