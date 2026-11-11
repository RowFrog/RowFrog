import XCTest
@testable import RowFrog

/// Reads testdata/states/forecast-status.json, the table the website's tests
/// read too, so the club page says the same on the iPhone and on rowfrog.com.
final class ForecastStatusTests: XCTestCase {
    private struct Table: Decodable {
        struct Row: Decodable { let hasForecast, outOfDate, loading, failed: Bool; let status: String }
        let states: [String: String]
        let rows: [Row]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/states/forecast-status.json")
        return try! JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
    }()

    func testEveryCombinationGivesTheStateInTheSharedTable() {
        XCTAssertEqual(Self.table.rows.count, 16, "every combination of the four inputs")
        for row in Self.table.rows {
            let status = ForecastStatus.of(hasForecast: row.hasForecast, outOfDate: row.outOfDate,
                                           loading: row.loading, failure: row.failed ? .offline : nil)
            XCTAssertEqual(status.name, row.status, "\(row)")
            XCTAssertNotNil(Self.table.states[status.name], "\(status.name) is described in the table")
        }
    }

    func testOutOfDateShowsWithAFailedUpdate() {
        let status = ForecastStatus.of(hasForecast: true, outOfDate: true, loading: false, failure: .refused(403))
        XCTAssertEqual(status, .updateFailed(.refused(403), outOfDate: true))
        XCTAssertTrue(status.isOutOfDate)
        XCTAssertFalse(ForecastStatus.of(hasForecast: true, outOfDate: false, loading: false, failure: .offline).isOutOfDate)
    }
}

/// The steps of one club's load (ForecastLoad), as ForecastStore.load takes them.
final class ForecastLoadTests: XCTestCase {
    private let forecast = try! APIClient.decoder.decode(ClubForecast.self, from: Data("""
    {"clubId": "a", "lakeId": "starnberger-see", "generatedAt": "2026-10-28T13:51:00+00:00",
     "attribution": [], "hours": [], "daylight": []}
    """.utf8))
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    func testAFirstLoadWaitsThenShowsOrFails() {
        let start = ForecastLoad.started(from: nil)
        XCTAssertTrue(start.isLoading)
        XCTAssertNil(start.forecast)
        XCTAssertEqual(start.failing(with: .offline).failure, .offline)
        XCTAssertNil(start.failing(with: .offline).forecast)
        XCTAssertNil(start.calledOff(), "called off before anything came: as if never asked")
    }

    func testARetryKeepsNoForecastUpWithItsReason() {
        let retry = ForecastLoad.started(from: .failed(.timeout))
        XCTAssertTrue(retry.isLoading)
        XCTAssertEqual(retry.failure, .timeout)
        XCTAssertEqual(retry.calledOff()?.failure, .timeout)
    }

    func testAnUpdateKeepsTheForecastAndItsTime() {
        let shown = ForecastLoad.shown(forecast, loadedAt: at, updating: false, failure: nil)
        let updating = ForecastLoad.started(from: shown)
        XCTAssertTrue(updating.isLoading)
        XCTAssertNotNil(updating.forecast)
        XCTAssertEqual(updating.loadedAt, at)
        let failed = updating.failing(with: .refused(403))
        XCTAssertFalse(failed.isLoading)
        XCTAssertNotNil(failed.forecast, "a failed update keeps the forecast")
        XCTAssertEqual(failed.failure, .refused(403))
        XCTAssertEqual(failed.loadedAt, at)
        let off = ForecastLoad.started(from: failed).calledOff()
        XCTAssertEqual(off?.failure, .refused(403))
        XCTAssertEqual(off?.isLoading, false)
    }
}

/// `-RWForecastFailure` names every reason, so screenshots can show each one.
final class ForecastFailureNameTests: XCTestCase {
    func testEveryReasonHasAName() {
        let names = ["offline", "timeout", "notFound", "server", "refused", "unreachable", "unreadable", "placeService", "other"]
        XCTAssertEqual(names.compactMap(RefreshFailure.init(name:)).count, names.count)
        XCTAssertEqual(RefreshFailure(name: "refused"), .refused(403))
        XCTAssertNil(RefreshFailure(name: "nonsense"))
    }
}
