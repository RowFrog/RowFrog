import CoreGraphics
import CoreLocation
import XCTest
@testable import RowFrog

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
        XCTAssertEqual(LakeRaster.waveColor(0.25).g, LakeRaster.red.g, accuracy: 0.5)
    }

    func testWindRelationToTheBoat() {
        XCTAssertEqual(WindRelation(heading: 0, windFrom: 10), .head)
        XCTAssertEqual(WindRelation(heading: 0, windFrom: 180), .tail)
        XCTAssertEqual(WindRelation(heading: 350, windFrom: 80), .cross)
        XCTAssertEqual(WindRelation(heading: 270, windFrom: 100), .tail)
    }

    func testRoutePlanOutAndBack() throws {
        let view = try decode()
        let start = CLLocationCoordinate2D(latitude: 47.80, longitude: 11.30)
        let turn = CLLocationCoordinate2D(latitude: 47.82, longitude: 11.31)
        let once = try XCTUnwrap(RoutePlanner(view: view, waypoints: [start, turn], outAndBack: false))
        let both = try XCTUnwrap(RoutePlanner(view: view, waypoints: [start, turn], outAndBack: true))
        XCTAssertEqual(both.distanceM, 2 * once.distanceM, accuracy: 1)

        let plan = both.plan(start: view.hours[0].time, paceSecondsPer500: 150)
        // 500 m in 150 s is 3.33 m/s.
        XCTAssertEqual(plan.end.timeIntervalSince(plan.start), both.distanceM / (500.0 / 150), accuracy: 1)
        XCTAssertFalse(plan.beyondForecast)
        XCTAssertEqual(plan.worstLight, .red, "the route reaches the red cell at the turn")
        XCTAssertEqual(plan.maxWaveM, 0.34, accuracy: 0.001)
        XCTAssertEqual(plan.segments.first?.light, .green)
        XCTAssertGreaterThan(plan.segments.count, 1)
        // The way out heads north into a wind from the south: tailwind.
        XCTAssertEqual(plan.stops.first?.relation, .tail)
    }

    func testRouteNeedsTwoPoints() throws {
        let view = try decode()
        XCTAssertNil(RoutePlanner(view: view, waypoints: [CLLocationCoordinate2D(latitude: 47.8, longitude: 11.3)], outAndBack: true))
    }

    func testPaceFormat() {
        XCTAssertEqual(Format.pace(135), "2:15")
        XCTAssertEqual(Format.pace(90), "1:30")
    }

    func testRouteLegsSitSideBySide() {
        // Out east and back west: on screen (y down) the way out sits below, the way back above.
        let out = RouteLineRenderer.shifted([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)], by: 3)
        let back = RouteLineRenderer.shifted([CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 0)], by: 3)
        XCTAssertEqual(out.map(\.y), [3, 3])
        XCTAssertEqual(back.map(\.y), [-3, -3])
        XCTAssertEqual(out.map(\.x), [0, 10])
    }

    func testRouteLoopClosesNearTheStart() {
        let start = CLLocationCoordinate2D(latitude: 47.99, longitude: 11.34)
        var points = [start]
        points = RouteEdit.add(CLLocationCoordinate2D(latitude: 47.98, longitude: 11.34), to: points)
        // Only one turning point yet: a point near the start is just another point.
        points = RouteEdit.add(CLLocationCoordinate2D(latitude: 47.9901, longitude: 11.3401), to: points)
        XCTAssertFalse(RouteEdit.isLoop(points))
        points.removeLast()
        points = RouteEdit.add(CLLocationCoordinate2D(latitude: 47.98, longitude: 11.35), to: points)
        // 30 m from the start closes the loop on the start itself.
        points = RouteEdit.add(CLLocationCoordinate2D(latitude: 47.99027, longitude: 11.34), to: points)
        XCTAssertTrue(RouteEdit.isLoop(points))
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points.last?.latitude, start.latitude)
        // A closed loop takes no more points.
        XCTAssertEqual(RouteEdit.add(CLLocationCoordinate2D(latitude: 47.97, longitude: 11.34), to: points).count, 4)
    }

    func testRouteEditRemoveAndMove() {
        let s = CLLocationCoordinate2D(latitude: 47.99, longitude: 11.34)
        let a = CLLocationCoordinate2D(latitude: 47.98, longitude: 11.34)
        let b = CLLocationCoordinate2D(latitude: 47.98, longitude: 11.35)
        let loop = RouteEdit.close([s, a, b])
        XCTAssertEqual(loop.count, 4)
        // Removing a turning point from a triangle leaves an open route.
        let open = RouteEdit.remove(at: 1, from: loop)
        XCTAssertEqual(open.count, 2)
        XCTAssertFalse(RouteEdit.isLoop(open))
        // The start can't be removed or moved.
        XCTAssertEqual(RouteEdit.remove(at: 0, from: loop).count, 4)
        XCTAssertEqual(RouteEdit.move(at: 0, to: a, in: loop)[0].latitude, s.latitude)
        XCTAssertEqual(RouteEdit.move(at: 2, to: a, in: loop)[2].longitude, a.longitude)
    }

    func testWindArrowsOnWaterAndLand() {
        // A 100 x 100 lake in a 300 x 300 area, arrows 10 apart.
        let water = CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil)
        let samples = [WindArrows.Sample(point: CGPoint(x: 50, y: 50), towardDeg: 90, speedMs: 4)]
        let area = CGRect(x: -100, y: -100, width: 300, height: 300)
        // With the weather map's wind on land, the whole area gets arrows: the lake's on the water, the map's on land.
        let arrows = WindArrows.arrows(in: area, spacing: 10, water: water, from: samples, land: { _ in (0, 3) })
        XCTAssertEqual(arrows.count, 900)
        XCTAssertTrue(arrows.contains { a in a.at.x < -80 && a.at.y < -80 })
        for a in arrows {
            // Points right on the shore line could count either way.
            if a.at.x == 0 || a.at.x == 100 { continue }
            let inside = a.at.x > 0 && a.at.x < 100 && a.at.y > 0 && a.at.y < 100
            XCTAssertEqual(a.ashore, !inside)
            XCTAssertEqual(a.towardDeg, inside ? 90 : 0, accuracy: 0.001)
        }
        // Without it, only the water.
        XCTAssertTrue(WindArrows.arrows(in: area, spacing: 10, water: water, from: samples).allSatisfy { !$0.ashore })
        // Near the shore the land's wind fades in from the lake's: halfway at half the blend distance.
        let shore = WindArrows.Shore(rings: [[CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]])
        XCTAssertEqual(shore.distance(to: CGPoint(x: -10, y: 50), within: 20) ?? 0, 10, accuracy: 0.001)
        XCTAssertNil(shore.distance(to: CGPoint(x: -30, y: 50), within: 20))
        let half = WindArrows.mix((90, 4), (0, 2), 0.5)
        XCTAssertEqual(half.towardDeg, 45, accuracy: 0.001)
        XCTAssertEqual(half.speedMs, 3, accuracy: 0.001)
        let blended = WindArrows.arrows(in: area, spacing: 10, water: water, from: samples, land: { _ in (0, 3) },
                                        shore: shore, blend: 20)
        for a in blended where a.ashore {
            guard let d = shore.distance(to: a.at, within: 20) else { XCTAssertEqual(a.towardDeg, 0, accuracy: 0.001); continue }
            XCTAssertEqual(a.speedMs, 4 + (3 - 4) * Double(d / 20), accuracy: 0.001)
        }
        // Opposite winds of equal weight don't make a strong wind sideways.
        let two = [WindArrows.Sample(point: CGPoint(x: 0, y: 0), towardDeg: 0, speedMs: 5),
                   WindArrows.Sample(point: CGPoint(x: 10, y: 0), towardDeg: 10, speedMs: 5)]
        XCTAssertEqual(WindArrows.wind(at: CGPoint(x: 5, y: 0), from: two)?.towardDeg ?? 0, 5, accuracy: 0.01)
    }

    func testWholeLakeStripes() {
        func wide(_ reasons: [(String, Light)]) -> LakeWide {
            let r = reasons.map { Reason(condition: $0.0, light: $0.1) }
            return LakeWide(light: r.map(\.light).max() ?? .green, reasons: r)
        }
        XCTAssertNil(wide([]).stripes)
        XCTAssertEqual(wide([("daylight", .red)]).stripes, .red)
        XCTAssertEqual(wide([("twilight", .amber)]).stripes, .amber)
        XCTAssertEqual(wide([("lake_strong_wind", .amber)]).stripes, .amber)
        XCTAssertEqual(wide([("weather_warning", .amber), ("cold_water", .amber)]).stripes, .amber)
        // Cold water alone stays in the panel: no stripes for months on end.
        XCTAssertNil(wide([("cool_water", .amber)]).stripes)
        XCTAssertNil(wide([("cold_water", .amber), ("single_cold", .amber), ("freezing_water", .amber)]).stripes)
    }

    func testRouteEditInsertOnAStretch() {
        let s = CLLocationCoordinate2D(latitude: 47.99, longitude: 11.34)
        let a = CLLocationCoordinate2D(latitude: 47.98, longitude: 11.34)
        let b = CLLocationCoordinate2D(latitude: 47.98, longitude: 11.35)
        let mid = CLLocationCoordinate2D(latitude: 47.985, longitude: 11.34)
        let route = RouteEdit.insert(mid, at: 1, in: [s, a, b])
        XCTAssertEqual(route.map(\.latitude), [s.latitude, mid.latitude, a.latitude, b.latitude])
        // On a loop the stretch back to the start takes a point too, and it stays a loop.
        let loop = RouteEdit.insert(mid, at: 3, in: RouteEdit.close([s, a, b]))
        XCTAssertEqual(loop.count, 5)
        XCTAssertTrue(RouteEdit.isLoop(loop))
        // Nothing goes before the start or after the end.
        XCTAssertEqual(RouteEdit.insert(mid, at: 0, in: [s, a]).count, 2)
        XCTAssertEqual(RouteEdit.insert(mid, at: 2, in: [s, a]).count, 2)
        // The distance from a touch to a drawn stretch.
        XCTAssertEqual(LakeMapView.Coordinator.distance(from: CGPoint(x: 5, y: 3), toSegment: .zero, CGPoint(x: 10, y: 0)), 3, accuracy: 0.001)
        XCTAssertEqual(LakeMapView.Coordinator.distance(from: CGPoint(x: 14, y: 3), toSegment: .zero, CGPoint(x: 10, y: 0)), 5, accuracy: 0.001)
    }
}
