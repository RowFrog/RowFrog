import XCTest
@testable import RowFrog

/// The reason under "Could not update" names the true cause (owner, 11 Nov 2026).
final class RefreshFailureTests: XCTestCase {
    func testARefusedDownloadIsNotCalledAPassingServerError() {
        XCTAssertEqual(RefreshFailure(HTTPStatusError(code: 403)), .refused(403))
        XCTAssertEqual(RefreshFailure(HTTPStatusError(code: 401)), .refused(401))
        XCTAssertFalse(RefreshFailure.refused(403).explanation.contains("fixes itself"))
    }

    func testOtherServerAnswersKeepTheirMeaning() {
        XCTAssertEqual(RefreshFailure(HTTPStatusError(code: 404)), .notFound)
        XCTAssertEqual(RefreshFailure(HTTPStatusError(code: 503)), .server(503))
        XCTAssertEqual(RefreshFailure(HTTPStatusError(code: 403), ownPlace: true), .placeService)
    }

    func testAMissingClubFileNamesTheSixHourRun() {
        XCTAssertTrue(RefreshFailure.notFound.explanation.contains("6"))
        XCTAssertFalse(RefreshFailure.notFound.explanation.contains("30 minutes"))
    }
}
