import CoreLocation
import XCTest
@testable import RowerWeather

final class LakeViewTests: XCTestCase {
    /// A 2 x 3 grid with four water cells, two forecast points and two parts.
    private let json = """
    {"lakeId": "test-see", "name": "Test See", "generatedAt": "2026-10-20T12:00:00+00:00", "sample": false,
     "attribution": [],
     "grid": {"south": 47.80, "west": 11.30, "dLat": 0.01, "dLon": 0.01, "cols": 2, "rows": 3, "cellM": 1000,
              "cells": [0, 1, 3, 5], "cellPoint": [1, 1, 0, 0], "cellZone": [1, 1, 0, 0]},
     "zones": ["north", "south"],
     "outline": [[[11.295, 47.795], [11.315, 47.795], [11.315, 47.825], [11.295, 47.825]]],
     "points": [{"lat": 47.82, "lon": 11.31}, {"lat": 47.80, "lon": 11.305}],
     "clubs": [{"id": "c", "shortName": "Club", "launchPoint": {"lat": 47.80, "lon": 11.30}}],
     "hours": [{"time": "2026-10-20T12:00:00+00:00",
                "lakeWide": {"light": "green", "reasons": []},
                "lights": "0012", "wavesCm": [3, 5, 20, 34],
                "wind": [{"speedMs": 5.0, "gustMs": 7.5, "fromDeg": 180}, {"speedMs": 4.0, "gustMs": 6.0, "fromDeg": 190}],
                "zones": [{"light": "red", "maxWaveM": 0.34}, {"light": "green", "maxWaveM": 0.05}]}]}
    """

    private func decode() throws -> LakeView {
        try APIClient.decoder.decode(LakeView.self, from: Data(json.utf8))
    }

    func testDecodesCellLightsAndWaves() throws {
        let view = try decode()
        let hour = try XCTUnwrap(view.hours.first)
        XCTAssertEqual(hour.lights, [.green, .green, .amber, .red])
        XCTAssertEqual(hour.wave(ofCell: 3), 0.34, accuracy: 0.001)
        XCTAssertEqual(hour.shares[.green] ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(hour.windRange?.max, 5.0)
        XCTAssertEqual(hour.windRange?.gust, 7.5)
    }

    func testFindsTheCellAtACoordinate() throws {
        let grid = try decode().grid
        // Cell 5 is row 2, column 1.
        XCTAssertEqual(grid.cell(at: CLLocationCoordinate2D(latitude: 47.821, longitude: 11.309)), 3)
        XCTAssertEqual(grid.coordinate(ofCell: 3).latitude, 47.82, accuracy: 1e-9)
        // Row 1, column 0 is land.
        XCTAssertNil(grid.cell(at: CLLocationCoordinate2D(latitude: 47.81, longitude: 11.30)))
    }

    func testHeadlineNamesTheCalmestAndRoughestPart() throws {
        let view = try decode()
        XCTAssertEqual(view.headline(for: view.hours[0]), "Calmest in the south, roughest in the north")
    }

    func testRasterHasOnePixelPerCell() throws {
        let view = try decode()
        let image = try XCTUnwrap(LakeRaster.image(view, hour: view.hours[0], layer: .light))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 3)
    }

    func testWaveColoursRiseWithTheLimits() {
        XCTAssertGreaterThan(LakeRaster.waveColor(0.3).r, LakeRaster.waveColor(0).r)
        XCTAssertEqual(LakeRaster.waveColor(0.30).g, LakeRaster.red.g, accuracy: 0.5)
    }
}
