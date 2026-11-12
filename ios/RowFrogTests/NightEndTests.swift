import XCTest
@testable import RowFrog

/// The table's last night is finished up to sunrise (owner's option B): it reads "17–07",
/// not "17–", even where it ends the table. The 12 Nov evening shot read "17–" because
/// that night ended the table, though the forecast ran to the sunrise hour.
final class NightEndTests: XCTestCase {
    private let sunrise = Date(timeIntervalSince1970: 1_800_000_000 + 21 * 60)
    private var days: [SunDay] { [SunDay(sunrise: sunrise, sunset: sunrise.addingTimeInterval(9 * 3600))] }

    func testANightUpToTheSunriseHourIsWhole() {
        XCTAssertTrue(NightFold.endsAtSunrise(Date(timeIntervalSince1970: 1_800_000_000), days: days))
    }

    func testANightCutOffInTheDarkIsNot() {
        XCTAssertFalse(NightFold.endsAtSunrise(Date(timeIntervalSince1970: 1_800_000_000 - 3 * 3600), days: days))
        XCTAssertFalse(NightFold.endsAtSunrise(Date(timeIntervalSince1970: 1_800_000_000), days: []))
    }
}
