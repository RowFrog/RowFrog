import CoreLocation
import XCTest
@testable import RowFrog

/// Natural neighbour blending between a lake's forecast points (owner's pick, 6 Nov 2026).
final class LakeInterpolationTests: XCTestCase {
    private let points: [NaturalNeighbours.Point] = [[0, 0], [2200, 300], [500, 2100], [2600, 2500], [1300, 4400], [-400, 3600]]

    private var nn: NaturalNeighbours {
        NaturalNeighbours(points: points, west: -3000, south: -3000, east: 5000, north: 7000)
    }

    func testWeightsAreNeverNegativeAndAddUpToOne() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let spot = NaturalNeighbours.Point(Double.random(in: -2500...4500, using: &generator), Double.random(in: -2500...6500, using: &generator))
            let w = nn.weights(at: spot)
            XCTAssertTrue(w.allSatisfy { $0.1 >= 0 })
            XCTAssertEqual(w.reduce(0) { $0 + $1.1 }, 1, accuracy: 1e-9)
        }
    }

    func testASpotOnAPointGetsThatPoint() {
        let w = nn.weights(at: points[3])
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w.first?.0, 3)
    }

    func testAnEvenSlopeIsReproducedInsideThePoints() {
        let values = points.map { 3 + 0.001 * $0.x - 0.0005 * $0.y }
        for spot: NaturalNeighbours.Point in [[1200, 1500], [1500, 3000], [800, 900]] {
            let v = nn.weights(at: spot).reduce(0) { $0 + $1.1 * values[$1.0] }
            XCTAssertEqual(v, 3 + 0.001 * spot.x - 0.0005 * spot.y, accuracy: 1e-6)
        }
    }

    func testBlendedWindStaysBetweenThePointsAndTakesTheArrowsDirection() throws {
        let a = LakeWind(speedMs: 4, gustMs: 6, fromDeg: 350, other: .green, visM: 300, storm: .green, rainMm: 0, hail: false)
        let b = LakeWind(speedMs: 8, gustMs: 11, fromDeg: 10, other: .green, visM: 15000, storm: .green, rainMm: 0, hail: false)
        let w = try XCTUnwrap(LakeWind.blended([(0, 0.5), (1, 0.5)], of: [a, b], near: a))
        XCTAssertEqual(w.speedMs ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(w.gustMs ?? 0, 8.5, accuracy: 1e-9)
        let from = try XCTUnwrap(w.fromDeg)
        XCTAssertLessThan(min(from, 360 - from), 5, "350° and 10° make about north, not south")
        XCTAssertEqual(w.visM ?? 0, (300.0 * 15000).squareRoot(), accuracy: 1, "visibility on a log scale")
        XCTAssertEqual(w.other, .green, "2.1 km is clear enough")
    }
}
