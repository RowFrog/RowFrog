import CoreLocation
import XCTest
@testable import RowFrog

/// Reads testdata/rules/routes.json, the table the website's tests
/// (web/tests/routerules.test.mjs) read too, so a route is edited, measured
/// and timed alike in the app and on rowfrog.com.
final class RouteRulesTableTests: XCTestCase {
    private struct Table: Decodable {
        struct Between: Decodable { let from, to: String; let m, deg: Double? }
        struct Relation: Decodable { let heading, windFrom: Double; let relation: String }
        struct Pace: Decodable { let seconds: Double; let text: String }
        struct Step: Decodable { let op: String; let point: String?; let index: Int? }
        struct Edit: Decodable { let `case`: String; let start: [String]; let ops: [Step]; let points: [String]; let loop: Bool }
        struct Current: Decodable { let at: String; let heading: Double; let flow: [[String]]; let cosine: Double }
        let points: [String: [Double]]
        let distance, heading: [Between]
        let windRelation: [Relation]
        let pace: [Pace]
        let edits: [Edit]
        let withCurrent: [Current]
    }

    private static let table: Table = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "testdata/rules/routes.json")
        return try! JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
    }()

    private func at(_ name: String) -> CLLocationCoordinate2D {
        let p = Self.table.points[name]!
        return CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
    }

    private func names(_ points: [CLLocationCoordinate2D]) -> [String] {
        points.map { c in
            Self.table.points.first { $0.value[0] == c.latitude && $0.value[1] == c.longitude }?.key ?? "?"
        }
    }

    func testDistancesMatchTheTable() throws {
        for c in Self.table.distance {
            let expected = try XCTUnwrap(c.m)
            XCTAssertEqual(RoutePlanner.distance(at(c.from), at(c.to)), expected, accuracy: expected * 0.005, "\(c.from)→\(c.to)")
        }
    }

    func testHeadingsMatchTheTable() throws {
        for c in Self.table.heading {
            XCTAssertEqual(RoutePlanner.heading(at(c.from), at(c.to)), try XCTUnwrap(c.deg), accuracy: 0.01, "\(c.from)→\(c.to)")
        }
    }

    func testWindRelationsMatchTheTable() {
        for c in Self.table.windRelation {
            XCTAssertEqual(WindRelation(heading: c.heading, windFrom: c.windFrom).rawValue, c.relation, "\(c.heading)/\(c.windFrom)")
        }
    }

    func testPacesMatchTheTable() {
        for c in Self.table.pace {
            XCTAssertEqual(Format.pace(c.seconds), c.text, "\(c.seconds)")
        }
    }

    func testEditsMatchTheTable() throws {
        for c in Self.table.edits {
            var points = c.start.map(at)
            for step in c.ops {
                switch step.op {
                case "add": points = RouteEdit.add(at(try XCTUnwrap(step.point)), to: points)
                case "close": points = RouteEdit.close(points)
                case "open": points = RouteEdit.open(points)
                case "remove": points = RouteEdit.remove(at: try XCTUnwrap(step.index), from: points)
                case "insert": points = RouteEdit.insert(at(try XCTUnwrap(step.point)), at: try XCTUnwrap(step.index), in: points)
                case "move": points = RouteEdit.move(at: try XCTUnwrap(step.index), to: at(try XCTUnwrap(step.point)), in: points)
                default: XCTFail("unknown step \(step.op)")
                }
            }
            XCTAssertEqual(names(points), c.points, c.case)
            XCTAssertEqual(RouteEdit.isLoop(points), c.loop, "\(c.case): loop")
        }
    }

    func testCurrentMatchesTheTable() {
        for c in Self.table.withCurrent {
            let flow = c.flow.map { (at($0[0]), at($0[1])) }
            XCTAssertEqual(RoutePlanner.withCurrent(at: at(c.at), heading: c.heading, flow: flow), c.cosine, accuracy: 0.001, "\(c.at) \(c.heading)°")
        }
    }
}
