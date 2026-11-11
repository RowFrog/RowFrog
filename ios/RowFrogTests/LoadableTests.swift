import XCTest
@testable import RowFrog

/// The moves of the shared load state (Loadable), which the forecast and the
/// lake view stores take; ForecastLoadTests checks the same with a forecast.
final class LoadableTests: XCTestCase {
    private typealias Load = Loadable<String, String>
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    func testAFirstLoadWaitsThenShowsOrFails() {
        let start = Load.started(from: nil)
        XCTAssertTrue(start.isLoading)
        XCTAssertFalse(start.hasFailed)
        XCTAssertNil(start.value)
        let done = Load.loaded("view", at: at)
        XCTAssertEqual(done.value, "view")
        XCTAssertEqual(done.loadedAt, at)
        XCTAssertFalse(done.isLoading)
        XCTAssertFalse(done.hasFailed)
        let failed = start.failing(with: "offline")
        XCTAssertTrue(failed.hasFailed)
        XCTAssertFalse(failed.isLoading)
        XCTAssertNil(failed.value)
    }

    func testARetryAfterAFailureStillCountsAsFailed() {
        // The lake view tile stays away while it tries again, as it did before.
        let retry = Load.started(from: .failed("offline"))
        XCTAssertTrue(retry.isLoading)
        XCTAssertTrue(retry.hasFailed)
        XCTAssertEqual(retry.failure, "offline")
    }

    func testAFailedUpdateKeepsWhatIsShown() {
        let updating = Load.started(from: .loaded("view", at: at))
        XCTAssertTrue(updating.isLoading)
        XCTAssertEqual(updating.value, "view")
        let failed = updating.failing(with: "timeout")
        XCTAssertEqual(failed.value, "view")
        XCTAssertEqual(failed.loadedAt, at)
        XCTAssertEqual(failed.failure, "timeout")
        XCTAssertFalse(failed.isLoading)
        let again = Load.started(from: failed)
        XCTAssertEqual(again.failure, "timeout", "the reason stays until a load works")
    }

    func testCalledOffGoesBackToWhereItWas() {
        XCTAssertNil(Load.started(from: nil).calledOff())
        XCTAssertEqual(Load.started(from: .failed("x")).calledOff()?.failure, "x")
        let shown = Load.started(from: .loaded("view", at: at)).calledOff()
        XCTAssertEqual(shown?.value, "view")
        XCTAssertEqual(shown?.isLoading, false)
    }
}
