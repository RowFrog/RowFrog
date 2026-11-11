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

    func testAServerThatDoesNotTakeTheCallIsAKnownCause() {
        XCTAssertEqual(RefreshFailure(URLError(.cannotConnectToHost)), .unreachable)
        XCTAssertEqual(RefreshFailure(URLError(.cannotConnectToHost), ownPlace: true), .placeService)
        XCTAssertEqual(RefreshFailure(URLError(.notConnectedToInternet)), .offline)
    }

    func testNoTextPromisesAForecastThatMayNotBeShown() {
        // The same words show under "No forecast", where nothing is shown.
        let all: [RefreshFailure] = [.offline, .timeout, .notFound, .server(500), .refused(403), .unreachable, .unreadable, .placeService, .other("x")]
        for failure in all {
            XCTAssertFalse(failure.explanation.contains("forecast shown stays"), "\(failure)")
        }
    }
}
