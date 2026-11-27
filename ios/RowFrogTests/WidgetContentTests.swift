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
        XCTAssertEqual(stormy.shortTitle, tr("Stay ashore", key: "Stay ashore (short)"))
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
        let already = snapshot([hour(0), hour(1), hour(2, .red)], at: start.addingTimeInterval(60)).days(1).first
        XCTAssertEqual(already?.good, "\(tr("Now"))–\(Format.time(start.addingTimeInterval(2 * 3600)))")
        XCTAssertNil(snapshot([hour(0, .red), hour(1, .amber)]).days(1).first?.good)
    }

    /// The forecast ends in the morning of its last day (owner, 13 Nov 2026: the
    /// widget called the whole Sunday "Not good" from its 07:00 hour alone).
    func testADayPastTheForecastsEndKeepsItsMissingHoursOpen() {
        let sun = [SunDay(sunrise: start.addingTimeInterval(-1200), sunset: start.addingTimeInterval(9.5 * 3600))]
        let cut = snapshot([hour(0, .red)], daylight: sun).days(1).first
        XCTAssertEqual(cut?.lights, [.red])
        XCTAssertEqual(cut?.missing, 9, "up to the sunset hour, as on the days the forecast covers")
        XCTAssertNil(cut?.good)
        let whole = snapshot((0..<10).map { hour($0) }, daylight: sun).days(1).first
        XCTAssertEqual(whole?.missing, 0)
    }

    /// Every day has the same boxes, from the sunrise hour to the sunset hour (owner, 23 Nov
    /// 2026: the last day alone had the 16:00 box). The sunrise and sunset hours show their
    /// daylight minutes in colour and the rest as night (owner's pick C, 27 Nov 2026): with
    /// sunrise 07:37 and sunset 16:24, 07:00 is 37 minutes night then green, 16:00 is 24
    /// minutes amber (the last hour before sunset) then night, though the forecast calls both red.
    func testSunriseAndSunsetHoursShowTheirDaylightPartOnEveryDay() {
        let sun = [SunDay(sunrise: start.addingTimeInterval(-23 * 60), sunset: start.addingTimeInterval(8 * 3600 + 25 * 60))]
        let dawn = hour(-1, .red, reasons: [Reason(condition: "daylight", light: .red)], sunUp: false)
        let dusk = hour(8, .red, reasons: [Reason(condition: "daylight", light: .red)], sunUp: false)
        let early = start.addingTimeInterval(-2 * 3600)
        let whole = snapshot([dawn] + (0..<8).map { hour($0) } + [dusk], at: early, daylight: sun).days(1).first
        XCTAssertEqual(whole?.lights.first, .green)
        XCTAssertEqual(whole?.lights.last, .amber)
        XCTAssertEqual(whole?.earlier, 0)
        XCTAssertEqual(whole?.missing, 0)
        XCTAssertEqual(whole?.slots, 10)
        XCTAssertEqual(whole?.nightBefore ?? 0, 37.0 / 60, accuracy: 0.001)
        XCTAssertEqual(whole?.nightAfter ?? 0, 35.0 / 60, accuracy: 0.001)
        XCTAssertEqual(whole?.good, "\(Format.time(start))–\(Format.time(start.addingTimeInterval(8 * 3600)))",
                       "the good stretch keeps to whole hours")
        let cut = snapshot([dawn] + (0..<5).map { hour($0) }, at: early, daylight: sun).days(1).first
        XCTAssertEqual(cut?.missing, 4)
        XCTAssertEqual(cut?.slots, 10)
        XCTAssertEqual(cut?.firstHour, whole?.firstHour)
        let later = snapshot((4..<8).map { hour($0) } + [dusk], at: start.addingTimeInterval(4.5 * 3600), daylight: sun).days(1).first
        XCTAssertEqual(later?.earlier, 5)
        XCTAssertEqual(later?.slots, 10)
        XCTAssertEqual(later?.firstHour, whole?.firstHour)
        // Weather worse than the daylight still shows in the daylight part.
        let windy = hour(8, .red, reasons: [Reason(condition: "daylight", light: .red), Reason(condition: "wind", light: .red)], sunUp: false)
        XCTAssertEqual(snapshot([dawn] + (0..<8).map { hour($0) } + [windy], at: early, daylight: sun).days(1).first?.lights.last, .red)
    }

    /// At 14:56 the green 14:00 hour still counts whole, as the light at the top says
    /// "Good, until 15:00" (owner, 15 Nov 2026: the bar said "Not good").
    func testARunningGreenHourCountsAsGood() {
        let late = snapshot([hour(0), hour(1, .amber), hour(2, .red)], at: start.addingTimeInterval(56 * 60))
        XCTAssertEqual(late.days(1).first?.good, "\(tr("Now"))–\(Format.time(start.addingTimeInterval(3600)))")
    }

    /// Today's hours gone before the forecast starts keep their place, faint, so the
    /// bar keeps its length; all days share one clock axis (owner's pick B, 15 Nov 2026).
    func testTodaysGoneHoursKeepTheirPlaceOnTheClockAxis() {
        let sun = [SunDay(sunrise: start.addingTimeInterval(-3 * 3600 + 600), sunset: start.addingTimeInterval(2.5 * 3600))]
        let day = snapshot([hour(0), hour(1), hour(2)], at: start.addingTimeInterval(1800), daylight: sun).days(1).first
        XCTAssertEqual(day?.earlier, 3)
        XCTAssertEqual(day?.slots, 6)
        let first = Calendar.current.component(.hour, from: start.addingTimeInterval(-3 * 3600))
        XCTAssertEqual(day?.firstHour, first)
        let now = Calendar.current.dateComponents([.hour, .minute], from: start.addingTimeInterval(1800))
        XCTAssertEqual(day?.now, Double(now.hour ?? 0) + Double(now.minute ?? 0) / 60)
    }

    func testAnOutOfDateForecastHasNoGoodStretch() {
        let late = snapshot((0..<8).map { hour($0) }, at: start.addingTimeInterval(4 * 3600))
        XCTAssertNil(late.days(1).first?.good)
    }

    // MARK: Night hours

    func testTheNightFoldsIntoOneColumnUpToSunrise() {
        // 01:00 to 12:00, dark until the sunrise at 06:22 (owner pick B, 15 Nov 2026).
        let sunrise = start.addingTimeInterval(6 * 3600 + 22 * 60)
        let sun = [SunDay(sunrise: sunrise, sunset: start.addingTimeInterval(15 * 3600))]
        let hours = (0..<12).map { hour($0, $0 < 7 ? .red : .green, sunUp: $0 >= 7) }
        let columns = snapshot(hours, daylight: sun).hourColumns(6)
        XCTAssertEqual(columns.count, 6)
        guard case let .hour(now) = columns[0], case let .night(night, until) = columns[1] else {
            return XCTFail("Now, then the rest of the night")
        }
        XCTAssertEqual(now.time, start, "Now keeps its own column")
        XCTAssertEqual(night.hours.map(\.time), (1...5).map { start.addingTimeInterval(Double($0) * 3600) })
        XCTAssertEqual(until, sunrise, "the night ends at sunrise")
        let after = columns.dropFirst(2).compactMap { if case let .hour(hour) = $0 { hour.time } else { nil } }
        XCTAssertEqual(after, (6...9).map { start.addingTimeInterval(Double($0) * 3600) }, "the sunrise hour, then the morning")
    }

    func testDaytimeHoursStayAsTheyAre() {
        let sun = [SunDay(sunrise: start.addingTimeInterval(-3 * 3600), sunset: start.addingTimeInterval(12 * 3600))]
        let columns = snapshot((0..<8).map { hour($0) }, daylight: sun).hourColumns(6)
        XCTAssertEqual(columns.map(\.id), (0..<6).map { start.addingTimeInterval(Double($0) * 3600) })
    }

    // MARK: Lock screen

    func testLockScreenLineNamesLightAndTemperatureWithoutTheClub() {
        let red = hour(0, .red, reasons: [Reason(condition: "wind", light: .red)])
        XCTAssertEqual(snapshot([red]).inlineText, "\(tr("Stay ashore", key: "Stay ashore (short)")) · \(Format.degrees(15))")
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
        let night = snapshot((0..<14).map { hour($0, $0 < 7 ? .red : .green, sunUp: $0 >= 7) },
                             daylight: [SunDay(sunrise: start.addingTimeInterval(6.4 * 3600), sunset: start.addingTimeInterval(15 * 3600))])
        let sizes: [(WidgetFamily, CGSize)] = [
            (.systemSmall, CGSize(width: 170, height: 170)), (.systemMedium, CGSize(width: 364, height: 170)),
            (.systemLarge, CGSize(width: 364, height: 382)), (.systemExtraLarge, CGSize(width: 715, height: 382)),
            (.accessoryCircular, CGSize(width: 72, height: 72)), (.accessoryRectangular, CGSize(width: 172, height: 76)),
            (.accessoryInline, CGSize(width: 234, height: 26)),
        ]
        for (family, size) in sizes {
            for snap in [full, night, empty] {
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

    /// The widget gallery draws each phone's own sizes (owner's C1, 14 Nov 2026), so the small iPhones' shots show the fit.
    /// The large widget makes room in steps before it leaves values out (owner, 14 Nov 2026):
    /// each step is at most as tall as the one before, and step 3 drops a day.
    func testFitStepsOnlyEverTighten() {
        let steps = [WidgetFit.regular, .tight, .tightTwoDays]
        XCTAssertEqual(steps.map(\.step), [1, 2, 3])
        for (a, b) in zip(steps, steps.dropFirst()) {
            XCTAssertLessThanOrEqual(b.gap, a.gap)
            XCTAssertLessThanOrEqual(b.rowGap, a.rowGap)
            XCTAssertLessThanOrEqual(b.skyHeight, a.skyHeight)
            XCTAssertLessThanOrEqual(b.dayGap, a.dayGap)
            XCTAssertLessThanOrEqual(b.days, a.days)
        }
        XCTAssertEqual(WidgetFit.tight.gap, 6)
        XCTAssertEqual(WidgetFit.tight.rowGap, 3)
        XCTAssertEqual(WidgetFit.tightTwoDays.days, 2)
    }

    func testGallerySizesFollowTheScreen() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone table")
        XCTAssertEqual(WidgetSizes.forScreen(CGSize(width: 375, height: 667)).large, CGSize(width: 321, height: 324))
        XCTAssertEqual(WidgetSizes.forScreen(CGSize(width: 375, height: 812)).large, CGSize(width: 329, height: 345))
        XCTAssertEqual(WidgetSizes.forScreen(CGSize(width: 390, height: 844)).medium, CGSize(width: 338, height: 158))
        XCTAssertEqual(WidgetSizes.forScreen(CGSize(width: 402, height: 874)).large, CGSize(width: 364, height: 382))
        XCTAssertEqual(WidgetSizes.forScreen(CGSize(width: 440, height: 956)).small, CGSize(width: 170, height: 170))
    }
}
