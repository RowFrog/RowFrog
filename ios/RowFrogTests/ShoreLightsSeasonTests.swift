import XCTest
@testable import RowFrog

/// Reads testdata/states/shore-lights-season.json, the table the website's tests
/// read too, so the warnings card says the same on the iPhone and on rowfrog.com.
final class ShoreLightsSeasonTests: XCTestCase {
    private struct Table: Decodable {
        struct Row: Decodable { let season: String?; let at: Date; let state: String }
        let states: [String: String]
        let rows: [Row]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/states/shore-lights-season.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(Table.self, from: Data(contentsOf: url))
    }()

    func testEveryRowGivesTheStateInTheSharedTable() {
        XCTAssertFalse(Self.table.rows.isEmpty)
        for row in Self.table.rows {
            let state = ShoreLightsSeason(row.season).state(at: row.at)
            XCTAssertEqual(state.rawValue, row.state, "\(row)")
            XCTAssertNotNil(Self.table.states[state.rawValue])
        }
    }

    func testTheSeasonComesFromTheForecastFile() throws {
        let json = #"{"status":"ok","lakeArea":"Starnberger See","items":[],"shoreLights":true,"shoreLightsSeason":"apr-oct"}"#
        let warnings = try JSONDecoder().decode(Warnings.self, from: Data(json.utf8))
        XCTAssertEqual(ShoreLightsSeason(warnings.shoreLightsSeason), .aprilToOctober)
        let older = try JSONDecoder().decode(Warnings.self, from: Data(#"{"status":"ok","lakeArea":null,"items":[]}"#.utf8))
        XCTAssertEqual(ShoreLightsSeason(older.shoreLightsSeason), .unknown)
    }
}
