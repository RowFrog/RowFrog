import XCTest
@testable import RowFrog

/// Reads testdata/rules/cold-water.json, the table the website's tests
/// (web/tests/coldwater.test.mjs) read too, so the cold-water badge and the
/// cold shore on the lake maps are the same in the app and on rowfrog.com.
final class ColdWaterTableTests: XCTestCase {
    private struct Table: Decodable {
        struct BoatRow: Decodable {
            let id, type, boatClass: String
            private enum CodingKeys: String, CodingKey { case id, type, boatClass = "class" }
        }
        struct Case: Decodable {
            let boat: BoatRow
            let ownLifeJacket: Double?
            let waterC: Double?
            let kit: String?
            let shore: String?
        }
        let cases: [Case]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/rules/cold-water.json")
        return try! JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
    }()

    private func name(_ kit: ColdWaterKit?) -> String? {
        switch kit {
        case .lifeJacket: "lifeJacket"
        case .partnerBoat: "partnerBoat"
        case .nearShore: "nearShore"
        case nil: nil
        }
    }

    private func name(_ shore: ColdShore?) -> String? {
        switch shore {
        case .cool: "cool"
        case .cold: "cold"
        case nil: nil
        }
    }

    func testBadgeAndShoreMatchTheTable() throws {
        for c in Self.table.cases {
            let boat = c.boat.id == Boat.small.id ? Boat.small : Boat(
                id: c.boat.id, name: "",
                type: try XCTUnwrap(BoatType(rawValue: c.boat.type), "no boat type \(c.boat.type)"),
                boatClass: try XCTUnwrap(BoatClass(rawValue: c.boat.boatClass), "no boat class \(c.boat.boatClass)")
            )
            var limits = RowingLimits(boat: boat)
            if let own = c.ownLifeJacket { limits.custom[.lifeJacket] = own }
            let what = "\(c.boat.id) \(c.boat.type) \(c.boat.boatClass), \(String(describing: c.waterC)) °C, own \(String(describing: c.ownLifeJacket))"
            XCTAssertEqual(name(ColdWaterKit(waterC: c.waterC, limits: limits)), c.kit, what)
            XCTAssertEqual(name(ColdShore(waterC: c.waterC, limits: limits)), c.shore, what)
        }
    }
}
