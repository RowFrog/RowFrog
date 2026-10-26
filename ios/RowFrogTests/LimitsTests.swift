import XCTest
@testable import RowFrog

final class LimitsTests: XCTestCase {
    private func hour(wind: Double, gust: Double, waves: Double, reasons: [Reason] = []) -> ForecastHour {
        ForecastHour(
            time: Date(timeIntervalSince1970: 1_800_000_000), light: reasons.map(\.light).max() ?? .green, reasons: reasons,
            windSpeedMs: wind, windGustMs: gust, windFromDeg: 180, waveHeightM: waves, fetchM: nil,
            visibilityM: 20_000, temperatureC: 15, cloudCoverPct: 20, sunUp: true
        )
    }

    func testStandardLimitsMatchTheBackend() {
        let limits = RowingLimits.standard
        let calm = hour(wind: 3, gust: 5, waves: 0.05).applying(limits, waterC: 18)
        XCTAssertEqual(calm.light, .green)
        let windy = hour(wind: 6, gust: 9, waves: 0.35).applying(limits, waterC: 12)
        XCTAssertEqual(windy.light, .red)
        XCTAssertEqual(Set(windy.reasons.map(\.condition)), ["wind", "gusts", "waves"])
        XCTAssertNil(windy.notes)
    }

    func testBigBoatsAllowMore() {
        let h = hour(wind: 6, gust: 9, waves: 0.2).applying(RowingLimits(boat: .big), waterC: nil)
        XCTAssertEqual(h.light, .green)
        XCTAssertNil(h.notes, "the app's own big-boat limits need no note")
    }

    func testOwnLimitIsMarkedAndTheAppStillAdvises() {
        let limits = RowingLimits(custom: [.gustAmber: 14, .gustRed: 16, .windAmber: 3])
        let h = hour(wind: 4, gust: 13, waves: 0.05).applying(limits, waterC: nil)
        XCTAssertEqual(h.reasons, [Reason(condition: "wind", light: .amber, mine: true)])
        XCTAssertEqual(h.notes, [Reason(condition: "gusts", light: .red)])
    }

    func testEveryBoatTypeIsAtLeastAsLenientAsSmallRacingBoats() {
        for type in BoatType.allCases {
            for boatClass in BoatClass.allCases {
                let limits = RowingLimits(boat: Boat(id: type.rawValue, name: "", type: type, boatClass: boatClass))
                XCTAssertFalse(RowingLimits.standard.allowsMore(than: limits), "\(type.rawValue) \(boatClass.rawValue)")
                for (amber, red) in [(RowingLimit.windAmber, RowingLimit.windRed), (.gustAmber, .gustRed), (.waveAmber, .waveRed)] {
                    XCTAssertLessThan(limits.value(amber), limits.value(red), "\(type.rawValue) \(boatClass.rawValue) \(amber.rawValue)")
                }
            }
        }
    }

    func testOwnBoatWithTheSmallBoatLimitsChangesNothing() {
        let single = RowingLimits(boat: Boat(id: "x", name: "Flash", type: .racing, boatClass: .single))
        XCTAssertTrue(single.matchesStandard)
        let double = RowingLimits(boat: Boat(id: "d", name: "", type: .racing, boatClass: .double))
        XCTAssertFalse(double.matchesStandard, "same limits, but no partner-boat hint for a double")
        XCTAssertFalse(RowingLimits(boat: .big).matchesStandard)
        let quad = RowingLimits(boat: Boat(id: "q", name: "", type: .racing, boatClass: .quad))
        XCTAssertEqual(quad.value(.waveRed), RowingLimits(boat: .big).value(.waveRed), "a racing quad gets the big-boat limits")
    }

    func testSuggestsASteadierBoatOfYourOwn() {
        let defaults = UserDefaults(suiteName: "LimitsTests")!
        defaults.removePersistentDomain(forName: "LimitsTests")
        let settings = AppSettings(defaults: defaults)
        let rough = hour(wind: 6, gust: 9, waves: 0.28).applying(settings.limits, waterC: nil)
        XCTAssertEqual(rough.light, .red)
        XCTAssertNil(SteadierBoat.suggestion(for: rough, water: nil, settings: settings), "no boats of your own, no suggestion")

        let gig = settings.addBoat(type: .gig, boatClass: .quad)
        settings.addBoat(type: .training, boatClass: .single)
        XCTAssertEqual(SteadierBoat.suggestion(for: rough, water: nil, settings: settings), SteadierBoat(boat: gig, light: .green))

        let dark = rough.with(reasons: rough.reasons + [Reason(condition: "daylight", light: .red)], sunUp: false)
        XCTAssertNil(SteadierBoat.suggestion(for: dark, water: nil, settings: settings), "no boat helps in the dark")
    }

    func testColdWaterLowersTheAppsWindLimitsButNotTheUsers() {
        let warm = hour(wind: 5, gust: 7.5, waves: 0.05).applying(RowingLimits.standard, waterC: 12)
        XCTAssertEqual(warm.reasons, [], "cool water shows as the life-jacket badge, not in the light")
        let cold = hour(wind: 5, gust: 7.5, waves: 0.05).applying(RowingLimits(boat: .big), waterC: 8)
        XCTAssertEqual(cold.light, .green)
        XCTAssertFalse(cold.reasons.contains { $0.condition == "wind" }, "7 m/s is still fine for big boats")
        let small = hour(wind: 5, gust: 7.5, waves: 0.05).applying(RowingLimits(boat: Boat(id: "s", name: "", type: .racing, boatClass: .double)), waterC: 8)
        XCTAssertEqual(Set(small.reasons.map(\.condition)), ["wind", "gusts"], "the limits are 1 m/s lower in cold water")

        let mine = RowingLimits(custom: [.windAmber: 5.2])
        let h = hour(wind: 5, gust: 2, waves: 0.05).applying(mine, waterC: 8)
        XCTAssertFalse(h.reasons.contains { $0.condition == "wind" }, "your own limit stays as you set it")
        XCTAssertEqual(h.notes?.map(\.condition), ["wind", "cold_margin"])
    }

    func testOnlyNearFreezingWaterChangesTheLight() {
        let quad = RowingLimits(boat: Boat(id: "q", name: "", type: .gig, boatClass: .quad))
        let h = hour(wind: 1, gust: 2, waves: 0).applying(quad, waterC: 3)
        XCTAssertEqual(h.reasons.map(\.condition), ["freezing_water"])
        XCTAssertEqual(h.light, .amber, "near-freezing water is a strong warning, not red for all")
        let single = hour(wind: 1, gust: 2, waves: 0).applying(RowingLimits(boat: .small), waterC: 9)
        XCTAssertEqual(single.light, .green)
    }

    func testColdWaterKitSaysWhatToBring() {
        let single = RowingLimits(boat: .small)
        let quad = RowingLimits(boat: Boat(id: "q", name: "", type: .gig, boatClass: .quad))
        XCTAssertNil(ColdWaterKit(waterC: 16, limits: single))
        XCTAssertNil(ColdWaterKit(waterC: nil, limits: single))
        XCTAssertEqual(ColdWaterKit(waterC: 12, limits: single), .lifeJacket)
        XCTAssertEqual(ColdWaterKit(waterC: 8, limits: single), .partnerBoat)
        XCTAssertEqual(ColdWaterKit(waterC: 8, limits: quad), .nearShore)
        // The badge follows the user's own life-jacket limit.
        XCTAssertNil(ColdWaterKit(waterC: 12, limits: RowingLimits(custom: [.lifeJacket: 11])))
        XCTAssertEqual(ColdWaterKit(waterC: 15.5, limits: RowingLimits(custom: [.lifeJacket: 16])), .lifeJacket)
    }

    func testStrongWindLightIsRedOnlyForSmallRacingAndTrainingBoats() {
        let strong = Reason(condition: "lake_strong_wind", light: .red)
        let base = hour(wind: 1, gust: 2, waves: 0, reasons: [strong])
        XCTAssertEqual(base.applying(RowingLimits(boat: .big), waterC: nil).light, .amber)
        let training = RowingLimits(boat: Boat(id: "t", name: "", type: .training, boatClass: .single))
        XCTAssertEqual(training.strongWindLight, .red)
        XCTAssertEqual(base.applying(training, waterC: nil).light, .red)
        let gig = RowingLimits(boat: Boat(id: "g", name: "", type: .gig, boatClass: .double))
        XCTAssertEqual(base.applying(gig, waterC: nil).light, .amber)
        let storm = Reason(condition: "lake_warning", light: .red)
        XCTAssertEqual(hour(wind: 1, gust: 2, waves: 0, reasons: [storm]).applying(RowingLimits(boat: .big), waterC: nil).light, .red)
    }

    func testOtherReasonsStay() {
        let dark = Reason(condition: "daylight", light: .red)
        let h = hour(wind: 1, gust: 2, waves: 0, reasons: [dark, Reason(condition: "wind", light: .amber)])
            .applying(RowingLimits(boat: .big), waterC: nil)
        XCTAssertEqual(h.reasons, [dark])
        XCTAssertEqual(h.light, .red)
    }
}
