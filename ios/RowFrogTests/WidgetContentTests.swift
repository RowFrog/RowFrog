import SwiftUI
import WidgetKit
import XCTest
@testable import RowFrog

/// What the widget says: the line under the light, the conditions grid, the
/// sun, the lock screen line, and that every size draws for every choice.
final class WidgetContentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func hour(_ offset: Int, _ light: Light = .green, reasons: [Reason] = [], sunUp: Bool = true) -> ForecastHour {
        ForecastHour(
            time: start.addingTimeInterval(Double(offset) * 3600), light: light, reasons: reasons,
            windSpeedMs: 3, windGustMs: 6, windFromDeg: 180, waveHeightM: 0.1, fetchM: nil,
            visibilityM: 20_000, temperatureC: 15, cloudCoverPct: 20, sunUp: sunUp, precipitationMm: 0
        )
    }

    private func snapshot(_ hours: [ForecastHour], at date: Date? = nil, water: WaterTemperature? = nil,
                          waterModelC: Double? = nil, daylight: [SunDay]? = nil, radar: RainRadar? = nil) -> RowingSnapshot {
        var forecast = ClubForecast(
            clubId: "mrc-1880", lakeId: "starnberger-see", generatedAt: start, waterTemperature: water,
            attribution: [], daylight: daylight, hours: hours
        )
        forecast.waterModelC = waterModelC
        forecast.radar = radar
        return RowingSnapshot(date: date ?? start, clubName: "MRC 1880", isHome: true, forecast: forecast)
    }

    // MARK: The line under the light

    func testLineUnderTheLightGivesTheReasonForAmberOrRed() {
        let wind = Reason(condition: "wind", light: .red)
        let red = hour(0, .red, reasons: [Reason(condition: "waves", light: .amber), wind])
        XCTAssertEqual(snapshot([red]).detailLine(red), wind.label)
    }

    func testLineUnderTheLightShowsRainAheadElseWind() {
        let green = hour(0)
        let dry = snapshot([green])
        XCTAssertEqual(dry.detailLine(green), "\(tr("Wind")) \(Format.windRange(3, 6))")

        let radar = RainRadar(reference: start, steps: stride(from: 0, through: 120, by: 15).map {
            RadarStep(time: start.addingTimeInterval(Double($0) * 60), mmPerHour: $0 >= 30 && $0 <= 90 ? 1.2 : 0)
        })
        let wet = snapshot([green], radar: radar)
        let summary = try? XCTUnwrap(wet.rainAhead?.summary)
        XCTAssertEqual(wet.detailLine(green), summary)
    }

    func testOutOfDateForecastSaysHowOld() {
        let hours = (0..<8).map { hour($0) }
        let late = snapshot(hours, at: start.addingTimeInterval(4 * 3600))
        let now = late.current!
        XCTAssertEqual(late.detailLine(now), tr("As of %@", Format.dayTime(start)))
        XCTAssertEqual(late.noWindowsText, tr("Forecast out of date. Open Row Frog to update."))
        XCTAssertEqual(snapshot(hours).noWindowsText, tr("No green hours in the forecast."))
    }

    // MARK: Conditions grid

    func testConditionsInTheTopTilesOrder() {
        let sun = [SunDay(sunrise: start.addingTimeInterval(-2 * 3600), sunset: start.addingTimeInterval(5 * 3600))]
        let s = snapshot([hour(0)], water: WaterTemperature(celsius: 16.24, measuredAt: start), daylight: sun)
        XCTAssertEqual(s.conditionTiles(rows: 1).map(\.condition), [.waterTemperature, .wind, .waves])
        let two = s.conditionTiles(rows: 2)
        XCTAssertEqual(two.map(\.condition), [.waterTemperature, .wind, .waves, .precipitation, .visibility, .daylight])
        XCTAssertEqual(two[0].value, Format.temperature(16.24, digits: 1))
        XCTAssertEqual(two[1].value, Format.windRange(3, 6))
        XCTAssertEqual(two[2].value, Format.waves(0.1))
        XCTAssertEqual(two[3].value, tr("None"))
        XCTAssertEqual(two[4].value, Format.distance(20_000))
        XCTAssertEqual(two[5].value, "↓ \(Format.time(sun[0].sunset))")
    }

    func testEstimatedWaterIsMarkedAndMissingWaterIsADash() {
        XCTAssertEqual(snapshot([hour(0)], waterModelC: 9).conditionTiles(rows: 1)[0].value, "≈ " + Format.temperature(9))
        XCTAssertEqual(snapshot([hour(0)]).conditionTiles(rows: 1)[0].value, "–")
    }

    func testIceJoinsBeforeDaylightInColdWater() {
        let cold = snapshot([hour(0)], water: WaterTemperature(celsius: 3, measuredAt: start))
        let tiles = cold.conditionTiles(rows: 2)
        XCTAssertEqual(tiles.map(\.condition).suffix(2), [.ice, .daylight])
        XCTAssertEqual(tiles.first { $0.condition == .ice }?.value, tr("No data yet"))
        XCTAssertFalse(snapshot([hour(0)], water: WaterTemperature(celsius: 12, measuredAt: start))
            .conditionTiles(rows: 2).contains { $0.condition == .ice })
    }

    func testSunsetWhileUpAndSunriseAtNight() {
        let sun = [SunDay(sunrise: start.addingTimeInterval(-10 * 3600), sunset: start.addingTimeInterval(-3600)),
                   SunDay(sunrise: start.addingTimeInterval(14 * 3600), sunset: start.addingTimeInterval(23 * 3600))]
        XCTAssertEqual(snapshot([hour(0, sunUp: false)], daylight: sun).sunText, "↑ \(Format.time(sun[1].sunrise))")
        XCTAssertEqual(snapshot([hour(0)], at: start.addingTimeInterval(15 * 3600), daylight: sun).sunText,
                       "↓ \(Format.time(sun[1].sunset))")
        XCTAssertEqual(snapshot([hour(0)]).sunText, "–")
    }

    // MARK: Lock screen

    func testLockScreenLineNamesClubLightAndTemperature() {
        let red = hour(0, .red, reasons: [Reason(condition: "wind", light: .red)])
        XCTAssertEqual(snapshot([red]).inlineText, "MRC 1880 · \(Light.red.title) · \(Format.degrees(15))")
        let none = RowingSnapshot(date: start, clubName: "MRC 1880", isHome: true, forecast: nil)
        XCTAssertEqual(none.inlineText, "MRC 1880 · – · \(Format.degrees(nil))")
    }

    // MARK: Every size draws

    @MainActor
    func testEverySizeDrawsForEveryChoice() {
        let sun = [SunDay(sunrise: start.addingTimeInterval(-2 * 3600), sunset: start.addingTimeInterval(5 * 3600))]
        let full = snapshot((0..<12).map { hour($0, $0 % 4 == 3 ? .amber : .green) },
                            water: WaterTemperature(celsius: 6, measuredAt: start), daylight: sun)
        let empty = RowingSnapshot(date: start, clubName: "MRC 1880", isHome: false, forecast: nil)
        let sizes: [(WidgetFamily, CGSize)] = [
            (.systemSmall, CGSize(width: 170, height: 170)), (.systemMedium, CGSize(width: 364, height: 170)),
            (.systemLarge, CGSize(width: 364, height: 382)), (.systemExtraLarge, CGSize(width: 715, height: 382)),
            (.accessoryCircular, CGSize(width: 72, height: 72)), (.accessoryRectangular, CGSize(width: 172, height: 76)),
            (.accessoryInline, CGSize(width: 234, height: 26)),
        ]
        for (family, size) in sizes {
            for snap in [full, empty] {
                for focus in WidgetFocus.allCases {
                    for plain in [false, true] {
                        let renderer = ImageRenderer(content: RowingWidgetView(snapshot: snap, family: family, focus: focus, plain: plain)
                            .frame(width: size.width, height: size.height))
                        renderer.scale = 1
                        XCTAssertNotNil(renderer.uiImage, "\(family) \(focus) plain=\(plain) data=\(snap.forecast != nil)")
                    }
                }
            }
        }
    }
}
