import XCTest
@testable import RowerWeather

final class SafetyNoticeTests: XCTestCase {
    private var saved: (Any?, Any?)

    override func setUp() {
        saved = (UserDefaults.standard.object(forKey: SafetyNotice.versionKey), UserDefaults.standard.object(forKey: SafetyNotice.dateKey))
        UserDefaults.standard.removeObject(forKey: SafetyNotice.versionKey)
        UserDefaults.standard.removeObject(forKey: SafetyNotice.dateKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved.0, forKey: SafetyNotice.versionKey)
        UserDefaults.standard.set(saved.1, forKey: SafetyNotice.dateKey)
    }

    func testNeededUntilAccepted() {
        XCTAssertTrue(SafetyNotice.needsAcceptance)
        XCTAssertFalse(SafetyNotice.changedSinceAcceptance)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        SafetyNotice.accept(at: date)
        XCTAssertFalse(SafetyNotice.needsAcceptance)
        XCTAssertEqual(SafetyNotice.acceptedVersion, SafetyNotice.version)
        XCTAssertEqual(SafetyNotice.acceptedAt, date)
    }

    func testAnOlderVersionAsksAgain() {
        UserDefaults.standard.set(SafetyNotice.version - 1, forKey: SafetyNotice.versionKey)
        XCTAssertTrue(SafetyNotice.needsAcceptance)
        XCTAssertEqual(SafetyNotice.changedSinceAcceptance, SafetyNotice.version > 1)
    }

    func testFactoryResetKeepsTheAcceptance() {
        SafetyNotice.accept()
        AppSettings.shared.resetToFactorySettings()
        XCTAssertFalse(SafetyNotice.needsAcceptance)
    }

    func testUnder18LineIsPartOfTheNotice() {
        XCTAssertTrue(SafetyNotice.points.contains { $0.symbol == "figure.and.child.holdinghands" })
    }
}
