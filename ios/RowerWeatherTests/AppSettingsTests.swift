import XCTest
@testable import RowerWeather

final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "AppSettingsTests")
        defaults.removePersistentDomain(forName: "AppSettingsTests")
    }

    func testFactoryDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.appearance, .device)
        XCTAssertEqual(settings.language, .device)
        XCTAssertEqual(settings.windUnit, .metersPerSecond)
        XCTAssertEqual(settings.allPagesBackground, .noPicture)
        XCTAssertEqual(settings.background(for: .clubPages, clubID: "mrc-1880"), .noPicture)
    }

    func testChoicesAreKept() {
        let settings = AppSettings(defaults: defaults)
        settings.windUnit = .knots
        settings.language = .german
        settings.allPagesBackground = .sample("lake-waves")
        settings.pageBackgrounds[.list] = .noPicture
        settings.clubBackgrounds["tutzinger-rv"] = .sample("alpine-lake")

        let again = AppSettings(defaults: defaults)
        XCTAssertEqual(again.windUnit, .knots)
        XCTAssertEqual(again.language, .german)
        XCTAssertEqual(again.allPagesBackground, .sample("lake-waves"))
        XCTAssertEqual(again.pageBackgrounds[.list], .noPicture)
        XCTAssertEqual(again.clubBackgrounds["tutzinger-rv"], .sample("alpine-lake"))
    }

    func testClubPictureBeatsPagePictureBeatsAllPages() {
        let settings = AppSettings(defaults: defaults)
        settings.allPagesBackground = .sample("lake-waves")
        XCTAssertEqual(settings.background(for: .settings), .sample("lake-waves"))

        settings.pageBackgrounds[.clubPages] = .sample("sunny-day")
        XCTAssertEqual(settings.background(for: .clubPages, clubID: "mrc-1880"), .sample("sunny-day"))
        XCTAssertEqual(settings.background(for: .list), .sample("lake-waves"))

        settings.clubBackgrounds["tutzinger-rv"] = .noPicture
        XCTAssertEqual(settings.background(for: .clubPages, clubID: "tutzinger-rv"), .noPicture)
        XCTAssertEqual(settings.background(for: .clubPages, clubID: "mrc-1880"), .sample("sunny-day"))
    }

    func testRemoveAllBackgroundsAndFactoryReset() {
        let settings = AppSettings(defaults: defaults)
        settings.allPagesBackground = .sample("lake-waves")
        settings.clubBackgrounds["mrc-1880"] = .sample("alpine-lake")
        settings.temperatureUnit = .fahrenheit
        settings.removeAllBackgrounds()
        XCTAssertEqual(settings.background(for: .clubPages, clubID: "mrc-1880"), .noPicture)
        XCTAssertEqual(settings.temperatureUnit, .fahrenheit)

        settings.appearance = .dark
        settings.boatClass = .big
        settings.customLimits[.windAmber] = 7
        settings.resetToFactorySettings()
        XCTAssertEqual(settings.limits, .standard)
        XCTAssertEqual(AppSettings(defaults: defaults).limits, .standard)
        XCTAssertEqual(settings.appearance, .device)
        XCTAssertEqual(settings.temperatureUnit, .celsius)
        XCTAssertNil(defaults.object(forKey: AppSettings.Keys.appearance))
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .device)
    }

    func testLandscapeIsOnUntilTurnedOff() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.allowsLandscape)
        settings.allowsLandscape = false
        XCTAssertFalse(AppSettings(defaults: defaults).allowsLandscape)
        settings.resetToFactorySettings()
        XCTAssertTrue(AppSettings(defaults: defaults).allowsLandscape)
    }

    func testBackgroundChoiceRawValues() {
        for choice in [BackgroundChoice.noPicture, .sample("night-lake"), .custom("user-1.jpg")] {
            XCTAssertEqual(BackgroundChoice(rawValue: choice.rawValue), choice)
        }
        XCTAssertNil(BackgroundChoice(rawValue: "nonsense"))
    }

    func testEverySampleIsInTheBundle() {
        for sample in BackgroundLibrary.samples {
            XCTAssertNotNil(BackgroundLibrary.image(for: sample.choice, thumbnail: true), sample.id)
        }
    }

    func testUnitConversions() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(10), 50, accuracy: 0.001)
        XCTAssertEqual(SpeedUnit.kilometersPerHour.convert(10), 36, accuracy: 0.001)
        XCTAssertEqual(SpeedUnit.knots.convert(10), 19.438, accuracy: 0.001)
        XCTAssertEqual(SpeedUnit.beaufort(0.2), 0)
        XCTAssertEqual(SpeedUnit.beaufort(5.0), 3)
        XCTAssertEqual(SpeedUnit.beaufort(8.0), 5)
        XCTAssertEqual(SpeedUnit.beaufort(40), 12)
        XCTAssertEqual(WaveUnit.centimeters.convert(0.12), 12, accuracy: 0.001)
        XCTAssertEqual(RainUnit.inches.convert(25.4), 1, accuracy: 0.001)
        XCTAssertEqual(DistanceUnit.nauticalMiles.convert(1852), 1, accuracy: 0.001)
    }

    func testTimeAndDateFormats() {
        let date = ISO8601DateFormatter().date(from: "2026-10-19T13:05:00Z")!
        XCTAssertNotNil(TimeFormat.hours24.string(from: date).range(of: #"^\d\d:05$"#, options: .regularExpression))
        XCTAssertNotNil(TimeFormat.hours12.string(from: date).range(of: #"^\d{1,2}:05 (AM|PM)$"#, options: .regularExpression))
        let english = Locale(identifier: "en_GB")
        XCTAssertTrue(DateFormat.iso.string(from: date, locale: english).hasSuffix("2026-10-19"))
        XCTAssertTrue(DateFormat.dayMonthYear.string(from: date, locale: english).hasSuffix("19.10.2026"))
        XCTAssertTrue(DateFormat.monthDayYear.string(from: date, locale: english).hasSuffix("10/19/2026"))
    }
}
