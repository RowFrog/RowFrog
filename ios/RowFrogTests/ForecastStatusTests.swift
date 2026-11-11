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
