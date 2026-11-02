import XCTest
@testable import RowFrog

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
        let gig = settings.addBoat(type: .gig)
        settings.boatID = gig.id
        settings.boatLimits[gig.id] = [.windAmber: 7]
        settings.boatLimits[Boat.small.id] = [.waveRed: 0.5]
        settings.resetToFactorySettings()
        XCTAssertEqual(settings.limits, .standard)
        XCTAssertEqual(AppSettings(defaults: defaults).limits, .standard)
        XCTAssertEqual(AppSettings(defaults: defaults).myBoats, [gig], "the user's boats stay, like the locations")
        XCTAssertEqual(AppSettings(defaults: defaults).limits(for: gig).custom, [:])
        XCTAssertEqual(settings.appearance, .device)
        XCTAssertEqual(settings.temperatureUnit, .celsius)
        XCTAssertNil(defaults.object(forKey: AppSettings.Keys.appearance))
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .device)
    }

    func testBoatsAndTheirLimitsAreKept() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.selectedBoat, .small, "small boats, the strictest limits, at first start")
        var anna = settings.addBoat(type: .gig)
        anna.name = "Anna"
        settings.myBoats[0] = anna
        settings.boatID = anna.id
        settings.boatLimits[anna.id] = [.waveAmber: 0.4]
        settings.boatLimits[Boat.big.id] = [.windAmber: 9]

        let again = AppSettings(defaults: defaults)
        XCTAssertEqual(again.selectedBoat, anna, "the last boat picked stays ticked")
        XCTAssertEqual(again.limits.value(.waveAmber), 0.4)
        XCTAssertEqual(again.limits.value(.waveRed), 0.5, "the gig's own limit where the user changed nothing")
        XCTAssertEqual(again.limits(for: .big).value(.windAmber), 9)
        XCTAssertEqual(again.limits(for: .small), .standard)
    }

    func testTheOldLakeMapBoatIsCleared() {
        defaults.set(Boat.big.id, forKey: AppSettings.Keys.mapBoat)
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: AppSettings.Keys.mapBoat), "the lake maps follow the ticked boat now")
        XCTAssertEqual(settings.selectedBoat, .small)
    }

    func testBoatsShowOnlyAtTheClubsWhereTheyAreKept() throws {
        let settings = AppSettings(defaults: defaults)
        let gig = settings.addBoat(type: .gig, at: "mrc-1880")
        settings.boatID = gig.id
        XCTAssertEqual(settings.boat(at: "mrc-1880"), gig)
        XCTAssertEqual(settings.boat(at: "tutzinger-rv"), .small, "elsewhere small boats, the strictest limits")
        XCTAssertEqual(settings.limits(at: "tutzinger-rv"), .standard)
        XCTAssertEqual(settings.boat(at: nil), gig, "the settings show the ticked boat")
        XCTAssertEqual(settings.boats(keptAt: "tutzinger-rv"), [])

        settings.keep(gig.id, at: "tutzinger-rv")
        XCTAssertEqual(settings.boat(at: "tutzinger-rv").id, gig.id, "taken along to the regatta")
        XCTAssertEqual(AppSettings(defaults: defaults).myBoats[0].clubs, ["mrc-1880", "tutzinger-rv"])

        settings.unkeep(gig.id, at: "mrc-1880")
        settings.unkeep(gig.id, at: "tutzinger-rv")
        XCTAssertEqual(settings.myBoats[0].clubs, ["tutzinger-rv"], "the last club stays")
        settings.boatID = Boat.big.id
        XCTAssertEqual(settings.boat(at: "tutzinger-rv"), .big, "small and big boats are everywhere")
    }

    func testAClubUsesABoatKeptThereBeforeSmallBoats() {
        let settings = AppSettings(defaults: defaults)
        let anna = settings.addBoat(type: .gig, at: "mrc-1880")
        let flash = settings.addBoat(type: .training, boatClass: .single, at: "tutzinger-rv")
        let berta = settings.addBoat(type: .gig, at: "tutzinger-rv")
        settings.pick(anna.id, at: "mrc-1880")
        XCTAssertEqual(settings.boat(at: "tutzinger-rv"), flash, "a boat kept there, not small boats")
        XCTAssertEqual(settings.boat(at: "seeclub-starnberg"), .small, "no boat kept there")

        settings.pick(berta.id, at: "tutzinger-rv")
        settings.pick(anna.id, at: "mrc-1880")
        XCTAssertEqual(settings.boat(at: "tutzinger-rv"), berta, "the boat last picked there")
        XCTAssertEqual(AppSettings(defaults: defaults).boat(at: "tutzinger-rv"), berta)

        settings.removeBoat(berta.id)
        XCTAssertEqual(settings.boat(at: "tutzinger-rv"), flash)
    }

    func testOlderBoatsGoToTheHomeBase() throws {
        let old = try JSONDecoder().decode([Boat].self, from: Data(#"[{"id":"b1","name":"Anna","type":"gig","class":"4x"}]"#.utf8))
        XCTAssertEqual(old[0].clubs, [])
        defaults.set(try JSONEncoder().encode(old), forKey: AppSettings.Keys.myBoats)
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.isKept(settings.myBoats[0], at: "anywhere"), "until there is a home base")
        settings.keepUnplacedBoats(at: "mrc-1880")
        XCTAssertEqual(AppSettings(defaults: defaults).myBoats[0].clubs, ["mrc-1880"])
    }

    func testRemovingTheTickedBoatFallsBackToSmallBoats() {
        let settings = AppSettings(defaults: defaults)
        let gig = settings.addBoat()
        settings.boatID = gig.id
        settings.removeBoat(gig.id)
        XCTAssertEqual(settings.selectedBoat, .small)
        XCTAssertTrue(settings.myBoats.isEmpty)
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

    func testSmallNegativeValuesRoundToZeroWithoutAMinus() {
        XCTAssertFalse(Format.number(-0.3).contains("-"))
        XCTAssertFalse(Format.number(-0.04, digits: 1).contains("-"))
        XCTAssertTrue(Format.number(-0.6).hasPrefix("-") || Format.number(-0.6).hasPrefix("−"))
    }
}
