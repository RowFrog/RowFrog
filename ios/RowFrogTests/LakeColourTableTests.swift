import XCTest
@testable import RowFrog

/// Reads testdata/rules/lake-colours.json, the table the website's tests
/// (web/tests/lakecolours.test.mjs) read too, so the app and rowfrog.com
/// colour the lake view alike.
final class LakeColourTableTests: XCTestCase {
    private struct Table: Decodable {
        struct RampCase: Decodable {
            let layer: String
            let value, amber, red: Double
            let rgb: [Double]
        }
        struct GreyedCase: Decodable {
            let light: String
            let rgb: [Double]
        }
        let lights: [String: [Double]]
        let ramp: [RampCase]
        let greyed: [GreyedCase]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/rules/lake-colours.json")
        return try! JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
    }()

    private func assertClose(_ c: LakeRaster.RGB, _ expected: [Double], _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(expected.count, 3, what, file: file, line: line)
        for (actual, want) in zip([c.r, c.g, c.b], expected) {
            XCTAssertEqual(actual, want, accuracy: 0.01, "\(what): \(c) instead of \(expected)", file: file, line: line)
        }
    }

    func testLightColoursMatchTheTable() throws {
        for (name, rgb) in Self.table.lights {
            let light = try XCTUnwrap(Light(rawValue: name), "no light \(name)")
            assertClose(LakeRaster.color(light), rgb, name)
        }
    }

    func testWavesAndWindAreColouredAsInTheTable() {
        for c in Self.table.ramp {
            assertClose(LakeRaster.ramp(c.value, amber: c.amber, red: c.red), c.rgb, "\(c.layer) \(c.value) (\(c.amber)/\(c.red))")
        }
    }

    func testALakeWideRedFadesAsInTheTable() throws {
        for c in Self.table.greyed {
            let light = try XCTUnwrap(Light(rawValue: c.light), "no light \(c.light)")
            assertClose(LakeRaster.greyed(LakeRaster.color(light)), c.rgb, c.light)
        }
    }
}
