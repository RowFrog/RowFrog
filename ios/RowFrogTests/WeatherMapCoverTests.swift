import XCTest
@testable import RowFrog

final class WeatherMapCoverTests: XCTestCase {
    /// Three published tiles as the backend cuts them (6° × 4°, every 3° × 2°).
    private func index() throws -> WeatherMapIndex {
        let tiles = [(9.0, 46.0), (12.0, 46.0), (6.0, 48.0)].map { west, south in
            #"{"id": "e\#(Int(west))n\#(Int(south))", "west": \#(west), "east": \#(west + 6), "south": \#(south), "north": \#(south + 4)}"#
        }
        let json = #"""
        {"run": "2026-10-26T12:00:00Z", "hours": [], "columns": 150, "rows": 130, "arrowStep": 5,
         "tiles": [\#(tiles.joined(separator: ","))], "values": {}, "credit": ""}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WeatherMapIndex.self, from: Data(json.utf8))
    }

    private let starnberg = Coordinate(lat: 47.9, lon: 11.3)

    func testStartAreaNeedsOnlyTheClubsTile() throws {
        let cover = try index().cover(MapArea(around: starnberg, km: 50))
        XCTAssertEqual(cover.map(\.tile.id), ["e9n46"])
    }

    func testZoomedOutAreaTakesMoreTilesWithoutDrawingTwice() throws {
        let cover = try index().cover(MapArea(west: 5, east: 17, south: 45, north: 51))
        XCTAssertEqual(Set(cover.map(\.tile.id)), ["e9n46", "e12n46", "e6n48"])
        let patches = cover.flatMap(\.patches)
        XCTAssertEqual(patches.count, Set(patches).count, "a patch drawn by two tiles")
        // Each tile draws only inside itself, and the club's patch is its own tile's.
        for (tile, patches) in cover {
            XCTAssertTrue(patches.allSatisfy { tile.holds($0) })
        }
        XCTAssertEqual(cover.first { $0.patches.contains { $0.west <= 11.3 && $0.east > 11.3 && $0.south <= 47.9 && $0.north > 47.9 } }?.tile.id, "e9n46")
    }

    func testMapStartZoomHalvesOrDoublesTheNormalSpan() {
        XCTAssertEqual(WeatherMapLayer.wind.normalSpanKm * MapStartZoom.close.factor, 25)
        XCTAssertEqual(WeatherMapLayer.rain.normalSpanKm * MapStartZoom.close.factor, 60)
        XCTAssertEqual(WeatherMapLayer.wind.normalSpanKm * MapStartZoom.wide.factor, 100)
        XCTAssertEqual(WeatherMapLayer.lightning.normalSpanKm * MapStartZoom.wide.factor, 240)
    }
}
