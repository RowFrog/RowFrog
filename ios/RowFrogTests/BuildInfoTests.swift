import XCTest
@testable import RowFrog

/// Settings > About's "0.1.0 (723) · 22a69ce" (decision 0034).
final class BuildInfoTests: XCTestCase {
    func testTheAppCarriesTheCommitKey() throws {
        // The test host is the app, so Bundle.main is its Info.plist.
        let raw = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: BuildInfo.commitKey) as? String,
                                "RWCommit missing from the app's Info.plist (ios/project.yml)")
        XCTAssertFalse(raw.hasPrefix("$("), "RW_COMMIT not set: ios/BuildNumber.xcconfig not used")
        XCTAssertTrue(raw == "dev" || raw.range(of: "^[0-9a-f]{7,}$", options: .regularExpression) != nil, raw)
    }

    func testBuildNumberIsACount() {
        XCTAssertNotNil(Int(BuildInfo.build), BuildInfo.build)
        XCTAssertGreaterThanOrEqual(Int(BuildInfo.build) ?? 0, 1)
    }

    func testSummary() {
        XCTAssertEqual(BuildInfo.summary(version: "0.1.0", build: "723", commit: "22a69ce"), "0.1.0 (723) · 22a69ce")
        XCTAssertEqual(BuildInfo.summary, "\(BuildInfo.version) (\(BuildInfo.build)) · \(BuildInfo.commit)")
    }
}
