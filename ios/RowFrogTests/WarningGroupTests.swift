import XCTest
@testable import RowFrog

/// Reads testdata/states/warning-groups.json, the table the website's tests read
/// too, so the warnings card merges the same warnings on the iPhone and on rowfrog.com.
final class WarningGroupTests: XCTestCase {
    private struct Table: Decodable {
        struct Item: Decodable {
            let kind: String
            let area: String
            let event: String
            let onset: Date?
            let expires: Date?
            let source: String?
            let links: [String: String]?
        }
        struct Case: Decodable { let name: String; let warnings: [Item]; let blocks: [[String]] }
        let cases: [Case]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/states/warning-groups.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(Table.self, from: Data(contentsOf: url))
    }()

    func testEveryCaseGivesTheBlocksInTheSharedTable() {
        XCTAssertFalse(Self.table.cases.isEmpty)
        for item in Self.table.cases {
            let warnings = item.warnings.map {
                DWDWarning(kind: $0.kind, area: $0.area, event: $0.event, severity: "minor", headline: $0.event,
                           description: "", instruction: nil, onset: $0.onset, expires: $0.expires,
                           source: $0.source, links: $0.links)
            }
            let blocks = WarningGroup.groups(warnings).map { $0.warnings.map(\.event) }
            XCTAssertEqual(blocks, item.blocks, item.name)
        }
    }

    func testTheWorstLevelColoursTheBlock() {
        let minor = DWDWarning(kind: "weather", area: "Stadt Starnberg", event: "FROST", severity: "minor",
                               headline: "", description: "", instruction: nil, onset: nil, expires: nil)
        let moderate = DWDWarning(kind: "weather", area: "Stadt Starnberg", event: "GLÄTTE", severity: "moderate",
                                  headline: "", description: "", instruction: nil, onset: nil, expires: nil)
        let groups = WarningGroup.groups([minor, moderate])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].worst.event, "GLÄTTE")
        XCTAssertTrue(groups[0].sharedNote)
    }
}
