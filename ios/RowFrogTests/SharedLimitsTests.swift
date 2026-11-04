import XCTest
@testable import RowFrog

/// Reads testdata/limits.json, the table the backend's and the website's tests
/// read too, so the app, rowfrog.com and the published light use the same limits.
final class SharedLimitsTests: XCTestCase {
    private struct Table: Decodable {
        struct BoatRow: Decodable {
            let type: String
            let boatClass: String
            let windAmber, windRed, gustAmber, gustRed, waveAmber, waveRed: Double
            private enum CodingKeys: String, CodingKey {
                case type, boatClass = "class", windAmber, windRed, gustAmber, gustRed, waveAmber, waveRed
            }
        }
        struct EveryBoat: Decodable { let currentAmber, currentRed, lifeJacket: Double }
        struct ColdWater: Decodable { let belowC, windMarginMs, freezingC: Double }
        struct StrongWind: Decodable {
            let type, boatClass, light: String
            private enum CodingKeys: String, CodingKey { case type, boatClass = "class", light }
        }
        let boats: [BoatRow]
        let everyBoat: EveryBoat
        let coldWater: ColdWater
        let strongWindLight: [StrongWind]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/limits.json")
        return try! JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
    }()

    private func boat(_ type: String, _ boatClass: String) throws -> Boat {
        Boat(
            id: "own", name: "",
            type: try XCTUnwrap(BoatType(rawValue: type), "no boat type \(type)"),
            boatClass: try XCTUnwrap(BoatClass(rawValue: boatClass), "no boat class \(boatClass)")
        )
    }

    func testBoatLimitsMatchTheSharedTable() throws {
        for row in Self.table.boats {
            let b = try boat(row.type, row.boatClass)
            let expected: [(RowingLimit, Double)] = [
                (.windAmber, row.windAmber), (.windRed, row.windRed), (.gustAmber, row.gustAmber),
                (.gustRed, row.gustRed), (.waveAmber, row.waveAmber), (.waveRed, row.waveRed),
                (.currentAmber, Self.table.everyBoat.currentAmber), (.currentRed, Self.table.everyBoat.currentRed),
                (.lifeJacket, Self.table.everyBoat.lifeJacket),
            ]
            for (limit, value) in expected {
                XCTAssertEqual(limit.standard(for: b), value, accuracy: 1e-9, "\(row.type) \(row.boatClass) \(limit.rawValue)")
            }
        }
    }

    func testEveryBoatTypeIsInTheTable() {
        let types = Set(Self.table.boats.map(\.type))
        XCTAssertEqual(types, Set(BoatType.allCases.map(\.rawValue)))
    }

    func testColdWaterMatchesTheSharedTable() throws {
        let cold = Self.table.coldWater
        XCTAssertEqual(RowingLimits.coldWaterC, cold.belowC)
        XCTAssertEqual(RowingLimits.coldWindMarginMs, cold.windMarginMs)
        XCTAssertEqual(RowingLimits.freezingWaterC, cold.freezingC)
    }

    func testStrongWindLightMatchesTheSharedTable() throws {
        for row in Self.table.strongWindLight {
            let limits = RowingLimits(boat: try boat(row.type, row.boatClass))
            XCTAssertEqual(limits.strongWindLight.rawValue, row.light, "\(row.type) \(row.boatClass)")
        }
    }
}
