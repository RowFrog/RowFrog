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
        XCTAssertEqual(wet.detailLine(green), tr("%@ from %@", tr("Light rain"), Format.time(start.addingTimeInterval(30 * 60))))
    }

    func testOutOfDateForecastSaysHowOld() {
        let hours = (0..<8).map { hour($0) }
        let late = snapshot(hours, at: start.addingTimeInterval(4 * 3600))
        let now = late.current!
        XCTAssertEqual(late.detailLine(now), tr("As of %@", Format.dayTime(start)))
        XCTAssertEqual(late.noWindowsText, tr("Forecast out of date. Open Row Frog to update."))
        XCTAssertEqual(snapshot(hours).noWindowsText, tr("No green hours in the forecast."))
    }

    // MARK: Short words

    func testShortWordsSayUntilWhenOrBetterFromWhen() {
        let wind = Reason(condition: "wind", light: .amber)
        let calm = snapshot([hour(0), hour(1), hour(2, .amber, reasons: [wind])])
        XCTAssertEqual(calm.shortTitle, tr("Good"))
        XCTAssertEqual(calm.shortWhy, tr("Until %@", Format.time(start.addingTimeInterval(2 * 3600))))
        XCTAssertEqual(calm.lockTitle, tr("Good until %@", Format.time(start.addingTimeInterval(2 * 3600))))

        let gusty = snapshot([hour(0, .amber, reasons: [wind]), hour(1, .amber, reasons: [wind]), hour(2)])
        XCTAssertEqual(gusty.shortTitle, tr("Caution"))
        XCTAssertEqual(gusty.shortWhy, tr("Better from %@", Format.time(start.addingTimeInterval(2 * 3600))))

        let stormy = snapshot([hour(0, .red, reasons: [Reason(condition: "wind", light: .red)])])
        XCTAssertEqual(stormy.shortTitle, tr("Stay ashore"))
        XCTAssertEqual(stormy.shortWhy, Reason(condition: "wind", light: .red).label)
    }

    func testOutOfDateShortWords() {
        let late = snapshot((0..<8).map { hour($0) }, at: start.addingTimeInterval(4 * 3600))
        XCTAssertEqual(late.shortTitle, tr("Out of date"))
        XCTAssertEqual(late.shortWhy, tr("As of %@", Format.dayTime(start)))
        XCTAssertNil(late.goodUntil)
    }

    // MARK: Values

    func testValuesAreSymbolAndValueWithTheCauseMarked() {
        let s = snapshot([hour(0, .amber, reasons: [Reason(condition: "gusts", light: .amber)])],
                         water: WaterTemperature(celsius: 16.24, measuredAt: start))
        XCTAssertEqual(s.value(.wind).text, Format.windRange(3, 6))
        XCTAssertEqual(s.value(.wind).light, .amber)
        XCTAssertNil(s.value(.waves).light)
        XCTAssertEqual(s.value(.waves).text, Format.waves(0.1))
        XCTAssertEqual(s.value(.visibility).text, Format.distance(20_000))
        XCTAssertEqual(s.value(.waterTemperature).text, Format.degrees(16.24, digits: 1))
        XCTAssertEqual(snapshot([hour(0)], waterModelC: 9).value(.waterTemperature).text, "≈ " + Format.degrees(9))
        XCTAssertEqual(snapshot([hour(0)]).value(.waterTemperature).text, "–")
    }

    func testTheWorstNearbyValueShowsWhileItSetsTheLight() {
        var h = hour(0, .red, reasons: [Reason(condition: "nearby_water", light: .red, topic: "wind", value: 9)])
        h.nearby = NearbyWater(light: .red, windMs: 9, gustMs: 12, waveM: 0.3, other: .green)
        let s = snapshot([h])
        XCTAssertEqual(s.value(.wind).text, Format.windRange(9, 12))
        XCTAssertEqual(s.value(.wind).light, .red)
        XCTAssertEqual(s.value(.wind).note, tr("Nearby"))
    }

    func testRainComesFromTheRadarElseTheForecast() {
        XCTAssertEqual(snapshot([hour(0)]).rainValue.text, tr("Dry"))
        var wet = hour(0)
        wet.precipitationMm = 1.2
        XCTAssertEqual(snapshot([wet]).rainValue.text, Format.rain(1.2))

        let coming = RainRadar(reference: start, steps: stride(from: 0, through: 120, by: 15).map {
            RadarStep(time: start.addingTimeInterval(Double($0) * 60), mmPerHour: $0 >= 30 ? 1.2 : 0)
        })
        XCTAssertEqual(snapshot([hour(0)], radar: coming).rainValue.text, tr("From %@", Format.time(start.addingTimeInterval(30 * 60))))
        let stopping = RainRadar(reference: start, steps: stride(from: 0, through: 120, by: 15).map {
            RadarStep(time: start.addingTimeInterval(Double($0) * 60), mmPerHour: $0 < 45 ? 1.2 : 0)
        })
        XCTAssertEqual(snapshot([hour(0)], radar: stopping).rainValue.text, tr("Until %@", Format.time(start.addingTimeInterval(45 * 60))))
    }

    func testAThunderstormThatSetsTheLightTakesTheRainsPlace() {
        let storm = Reason(condition: "thunderstorm", light: .red)
        let s = snapshot([hour(0), hour(1), hour(2, .red, reasons: [storm])])
        XCTAssertEqual(s.rainValue.condition, .thunderstorm)
        XCTAssertEqual(s.rainValue.text, tr("From %@", Format.time(start.addingTimeInterval(2 * 3600))))
        XCTAssertEqual(s.rainValue.light, .red)
        XCTAssertEqual(s.lockDetail, tr("%@ from %@", tr("Thunderstorm"), Format.time(start.addingTimeInterval(2 * 3600))))
    }

    // MARK: Good rowing times

    func testDaysShowTheirLightsAndTheFirstGoodStretch() {
        let hours = [hour(0, .amber), hour(1), hour(2), hour(3, .red), hour(4), hour(5), hour(6)]
        let day = snapshot(hours, at: start.addingTimeInterval(1800)).days(1).first
        XCTAssertEqual(day?.lights, hours.map(\.light))
        XCTAssertEqual(day?.past, [false, false, false, false, false, false, false])
        XCTAssertEqual(day?.good, "\(Format.time(start.addingTimeInterval(3600)))–\(Format.time(start.addingTimeInterval(3 * 3600)))")
        XCTAssertEqual(snapshot(hours, at: start.addingTimeInterval(3600 + 600)).days(1).first?.past.first, true)
        XCTAssertNil(snapshot([hour(0, .red), hour(1, .amber)]).days(1).first?.good)
    }

    func testAnOutOfDateForecastHasNoGoodStretch() {
        let late = snapshot((0..<8).map { hour($0) }, at: start.addingTimeInterval(4 * 3600))
        XCTAssertNil(late.days(1).first?.good)
    }

    // MARK: Lock screen

    func testLockScreenLineNamesLightAndTemperatureWithoutTheClub() {
        let red = hour(0, .red, reasons: [Reason(condition: "wind", light: .red)])
        XCTAssertEqual(snapshot([red]).inlineText, "\(tr("Stay ashore")) · \(Format.degrees(15))")
        let none = RowingSnapshot(date: start, clubName: "MRC 1880", isHome: true, forecast: nil)
        XCTAssertEqual(none.inlineText, "– · \(Format.degrees(nil))")
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
                    for layout in WidgetLayout.allCases {
                        for (plain, marks) in [(false, true), (true, false)] {
                            let view = RowingWidgetView(snapshot: snap, family: family, focus: focus, plain: plain, layout: layout, marks: marks)
                            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
                            renderer.scale = 1
                            XCTAssertNotNil(renderer.uiImage, "\(family) \(focus) \(layout) plain=\(plain) data=\(snap.forecast != nil)")
                        }
                    }
                }
            }
        }
    }
}
