import CoreLocation
import Foundation
import simd

/// Natural neighbour (Sibson) blending between a lake's forecast points, as
/// the backend does it (backend/rowfrog/interpolate.py): a spot's weights are
/// the shares of its own Voronoi cell it would take from each point's cell.
/// They are never negative and add up to 1, so a blended value always stays
/// between the points around it (owner's pick, 6 Nov 2026).
struct NaturalNeighbours {
    typealias Point = SIMD2<Double>
    private typealias Plane = (a: Double, b: Double, c: Double)

    let points: [Point]
    private let box: [Point]
    private let cells: [[Point]]
    private let planes: [[Plane]]

    init(points: [Point], west: Double, south: Double, east: Double, north: Double) {
        self.points = points
        box = [Point(west, south), Point(east, south), Point(east, north), Point(west, north)]
        planes = points.map { p in points.filter { $0 != p }.map { Self.closer(to: p, than: $0) } }
        cells = planes.map { Self.cut(box: [Point(west, south), Point(east, south), Point(east, north), Point(west, north)], by: $0) }
    }

    /// Point index and weight, only points with a share.
    func weights(at spot: Point) -> [(Int, Double)] {
        if let i = points.firstIndex(where: { simd_distance_squared($0, spot) < 1e-12 }) { return [(i, 1)] }
        let own = Self.cut(box: box, by: points.map { Self.closer(to: spot, than: $0) })
        let total = Self.area(own)
        guard total > 0, let lo = own.min(by: { $0.x < $1.x }), let hi = own.max(by: { $0.x < $1.x }),
              let bottom = own.min(by: { $0.y < $1.y }), let top = own.max(by: { $0.y < $1.y }) else {
            return nearest(spot).map { [($0, 1)] } ?? []
        }
        var out: [(Int, Double)] = []
        for (i, cell) in cells.enumerated() where !cell.isEmpty {
            // Cells that cannot overlap are skipped.
            if (cell.map(\.x).max() ?? 0) < lo.x || (cell.map(\.x).min() ?? 0) > hi.x
                || (cell.map(\.y).max() ?? 0) < bottom.y || (cell.map(\.y).min() ?? 0) > top.y { continue }
            let part = Self.cut(box: own, by: planes[i])
            let share = part.count >= 3 ? Self.area(part) : 0
            if share > 1e-9 * total { out.append((i, share)) }
        }
        let sum = out.reduce(0) { $0 + $1.1 }
        guard sum > 0 else { return nearest(spot).map { [($0, 1)] } ?? [] }
        return out.map { ($0.0, $0.1 / sum) }
    }

    private func nearest(_ spot: Point) -> Int? {
        points.indices.min { simd_distance_squared(points[$0], spot) < simd_distance_squared(points[$1], spot) }
    }

    /// The spots at least as close to p as to q: a*x + b*y <= c.
    private static func closer(to p: Point, than q: Point) -> Plane {
        (q.x - p.x, q.y - p.y, (simd_length_squared(q) - simd_length_squared(p)) / 2)
    }

    private static func cut(box: [Point], by planes: [Plane]) -> [Point] {
        var poly = box
        for plane in planes {
            poly = clip(poly, plane)
            if poly.isEmpty { break }
        }
        return poly
    }

    private static func clip(_ poly: [Point], _ plane: Plane) -> [Point] {
        var out: [Point] = []
        out.reserveCapacity(poly.count + 1)
        for i in poly.indices {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let fp = plane.a * p.x + plane.b * p.y - plane.c
            let fq = plane.a * q.x + plane.b * q.y - plane.c
            if fp <= 0 { out.append(p) }
            if (fp < 0 && fq > 0) || (fq < 0 && fp > 0) {
                out.append(p + (q - p) * (fp / (fp - fq)))
            }
        }
        return out
    }

    private static func area(_ poly: [Point]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var s = 0.0
        for i in poly.indices {
            let p = poly[i], q = poly[(i + poly.count - 1) % poly.count]
            s += p.x * q.y - q.x * p.y
        }
        return abs(s) / 2
    }
}

/// A lake's blending: flat metres around its middle, a box 4.4 km around the
/// cells and points, and the weights of every water cell, worked out once.
final class LakeInterpolation {
    static let boxMarginM = 4400.0
    private static let earthRadiusM = 6_371_000.0

    let cellWeights: [[(Int, Double)]]
    private let nn: NaturalNeighbours
    private let lat0: Double, lon0: Double, k: Double

    init(grid: LakeGrid, points: [Coordinate]) {
        let cells = grid.cells.indices.map { grid.coordinate(ofCell: $0) }
        let lats = cells.map(\.latitude) + points.map(\.lat)
        let lons = cells.map(\.longitude) + points.map(\.lon)
        lat0 = ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2
        lon0 = ((lons.min() ?? 0) + (lons.max() ?? 0)) / 2
        k = cos(lat0 * .pi / 180)
        let flatLat0 = lat0, flatLon0 = lon0, flatK = k
        func flat(_ lat: Double, _ lon: Double) -> NaturalNeighbours.Point {
            NaturalNeighbours.Point((lon - flatLon0) * .pi / 180 * Self.earthRadiusM * flatK, (lat - flatLat0) * .pi / 180 * Self.earthRadiusM)
        }
        let pts = points.map { flat($0.lat, $0.lon) }
        let sq = cells.map { flat($0.latitude, $0.longitude) }
        let all = pts + sq
        let m = Self.boxMarginM
        nn = NaturalNeighbours(points: pts,
                               west: (all.map(\.x).min() ?? 0) - m, south: (all.map(\.y).min() ?? 0) - m,
                               east: (all.map(\.x).max() ?? 0) + m, north: (all.map(\.y).max() ?? 0) + m)
        cellWeights = pts.count < 2 ? sq.map { _ in pts.isEmpty ? [] : [(0, 1.0)] } : sq.map { nn.weights(at: $0) }
    }

    /// Weights at any spot, such as where the water was tapped.
    func weights(at c: CLLocationCoordinate2D) -> [(Int, Double)] {
        guard nn.points.count >= 2 else { return nn.points.isEmpty ? [] : [(0, 1)] }
        let p = NaturalNeighbours.Point((c.longitude - lon0) * .pi / 180 * Self.earthRadiusM * k, (c.latitude - lat0) * .pi / 180 * Self.earthRadiusM)
        return nn.weights(at: p)
    }

    // The weights depend only on the grid and the points, so each lake works them out once.
    private static var cache: [String: LakeInterpolation] = [:]
    private static let lock = NSLock()

    static func of(_ view: LakeView) -> LakeInterpolation {
        let key = "\(view.lakeId)|\(view.grid.cells.count)|\(view.grid.south)|\(view.grid.west)|\(view.points.count)"
        lock.lock()
        defer { lock.unlock() }
        if let found = cache[key] { return found }
        let made = LakeInterpolation(grid: view.grid, points: view.points)
        if cache.count > 40 { cache.removeAll() }
        cache[key] = made
        return made
    }
}

extension LakeWind {
    /// The wind at a spot, blended from the forecast points around it: speed,
    /// gusts and rain as they are, visibility on a log scale, the direction from
    /// the wind arrows. Thunderstorms and hail are yes or no and come from `near`.
    static func blended(_ weights: [(Int, Double)], of winds: [LakeWind], near: LakeWind?) -> LakeWind? {
        let used = weights.filter { $0.0 < winds.count }
        guard used.count > 1 else { return used.first.map { winds[$0.0] } ?? near }
        func blend(_ value: (LakeWind) -> Double?) -> Double? {
            var s = 0.0
            for (i, w) in used {
                guard let v = value(winds[i]) else { return near.flatMap(value) }
                s += w * v
            }
            return s
        }
        var direction = near?.fromDeg
        if used.allSatisfy({ winds[$0.0].fromDeg != nil }) {
            var u = 0.0, v = 0.0
            for (i, w) in used {
                let speed = winds[i].speedMs ?? 0, rad = (winds[i].fromDeg ?? 0) * .pi / 180
                u += w * speed * sin(rad)
                v += w * speed * cos(rad)
            }
            if abs(u) > 1e-9 || abs(v) > 1e-9 {
                let deg = atan2(u, v) * 180 / .pi
                direction = deg < 0 ? deg + 360 : deg
            }
        }
        let vis = blend { $0.visM.map { log(max($0, 1)) } }.map { exp($0) }
        let rain = blend(\.rainMm)
        var other = near?.other
        // With the new backend fields, the point's light from fog, storms,
        // rain and hail is worked out again with the blended visibility and rain.
        if let near, let storm = near.storm {
            var light = storm
            if near.hail == true { light = .red }
            if let rain, rain >= 4 { light = max(light, .amber) }
            if let vis { light = max(light, vis < 500 ? .red : vis <= 1000 ? .amber : .green) }
            other = light
        }
        return LakeWind(speedMs: blend(\.speedMs), gustMs: blend(\.gustMs), fromDeg: direction, other: other,
                        visM: vis, storm: near?.storm, rainMm: rain, hail: near?.hail)
    }
}

extension LakeView {
    /// The wind at a water cell, blended from the forecast points around it.
    func cellWind(_ i: Int, in hour: LakeHour) -> LakeWind? {
        let p = i < grid.cellPoint.count ? grid.cellPoint[i] : 0
        let near = p < hour.wind.count ? hour.wind[p] : nil
        let weights = LakeInterpolation.of(self).cellWeights
        guard i < weights.count else { return near }
        return LakeWind.blended(weights[i], of: hour.wind, near: near)
    }

    /// The wind at any spot on the water, such as where it was tapped.
    func wind(at c: CLLocationCoordinate2D, cell i: Int, in hour: LakeHour) -> LakeWind? {
        let p = i < grid.cellPoint.count ? grid.cellPoint[i] : 0
        let near = p < hour.wind.count ? hour.wind[p] : nil
        return LakeWind.blended(LakeInterpolation.of(self).weights(at: c), of: hour.wind, near: near)
    }
}
