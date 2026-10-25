import CoreLocation
import Foundation
import Observation

/// A rowing route on a lake: the turning points from the start, rowed once
/// or out and back.
struct Route: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var lakeId: String
    var points: [Coordinate]
    var outAndBack: Bool
    /// For a row brought in from Apple Health or a file: the track as rowed
    /// (thinned to a few metres), when, and from where. Nil for drawn routes.
    var track: [Coordinate]? = nil
    var rowedAt: Date? = nil
    var importedFrom: RowTrack.Source? = nil

    var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var trackCoordinates: [CLLocationCoordinate2D] {
        (track ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
}

/// Saved routes, kept on the device.
@Observable
final class RouteStore {
    static let shared = RouteStore()

    private(set) var routes: [Route]
    private let defaults: UserDefaults
    private static let key = "RWRoutes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        routes = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Route].self, from: $0) } ?? []
    }

    func routes(on lakeID: String) -> [Route] { routes.filter { $0.lakeId == lakeID } }

    /// Adds the route, or replaces the saved one with the same id.
    func save(_ route: Route) {
        if let i = routes.firstIndex(where: { $0.id == route.id }) {
            routes[i] = route
        } else {
            routes.append(route)
        }
        persist()
    }

    func delete(_ route: Route) {
        routes.removeAll { $0.id == route.id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(routes), forKey: Self.key)
    }
}

/// Changes to a route's turning points. The first point is the launch point
/// and stays; a route that ends where it started is a loop.
enum RouteEdit {
    /// A new point this close to the start closes the loop.
    static let closeDistanceM = 50.0

    static func isLoop(_ points: [CLLocationCoordinate2D]) -> Bool {
        guard points.count >= 3, let first = points.first, let last = points.last else { return false }
        return RoutePlanner.distance(first, last) < 1
    }

    /// Adds a point; one near the start, after at least two turning points, closes the loop.
    /// A closed loop takes no more points.
    static func add(_ point: CLLocationCoordinate2D, to points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard !isLoop(points) else { return points }
        if points.count >= 3, RoutePlanner.distance(point, points[0]) <= closeDistanceM {
            return points + [points[0]]
        }
        return points + [point]
    }

    /// Ends the route at the start.
    static func close(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        points.count >= 3 && !isLoop(points) ? points + [points[0]] : points
    }

    /// Removes one turning point; the start stays. A loop left with one
    /// turning point opens again.
    static func remove(at index: Int, from points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard index > 0, points.indices.contains(index) else { return points }
        let loop = isLoop(points)
        var out = points
        out.remove(at: index)
        if loop, out.count < 4 { out.removeLast() }
        return out
    }

    /// Moves one turning point; the start stays where the club is.
    static func move(at index: Int, to point: CLLocationCoordinate2D, in points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard index > 0, points.indices.contains(index) else { return points }
        var out = points
        out[index] = point
        return out
    }
}

/// How the wind (or the waves it makes) meets the boat.
enum WindRelation: String, Hashable {
    case head, tail, cross

    /// The boat heading and where the wind comes from, both in degrees from north.
    init(heading: Double, windFrom: Double) {
        let off = abs((windFrom - heading + 540).truncatingRemainder(dividingBy: 360) - 180)
        self = off < 45 ? .head : off > 135 ? .tail : .cross
    }

    var wind: String {
        switch self {
        case .head: tr("headwind")
        case .tail: tr("tailwind")
        case .cross: tr("crosswind")
        }
    }

    var waves: String {
        switch self {
        case .head: tr("head sea")
        case .tail: tr("following sea")
        case .cross: tr("waves from the side")
        }
    }
}

/// What a route meets on the way when started at a given time at a given pace:
/// the conditions at every 150 m or so, at the time the boat gets there.
struct RoutePlan: Hashable {
    struct Stop: Hashable {
        let coordinate: Coordinate
        let distanceM: Double
        let time: Date
        let cell: Int
        let light: Light
        let waveM: Double
        let windMs: Double?
        let gustMs: Double?
        let relation: WindRelation?
    }

    /// A stretch of the route in one colour.
    struct Segment: Hashable {
        let points: [Coordinate]
        let light: Light
    }

    let start: Date
    let end: Date
    let distanceM: Double
    let stops: [Stop]
    let segments: [Segment]
    /// The trip runs past the end of the forecast.
    let beyondForecast: Bool


    var worstLight: Light { stops.map(\.light).max() ?? .green }
    var maxWaveM: Double { stops.map(\.waveM).max() ?? 0 }

    /// The stop with the worst light and, among those, the highest waves.
    var roughest: Stop? { stops.max { ($0.light, $0.waveM) < ($1.light, $1.waveM) } }
}

/// The route's geometry, worked out once; plans for different start times reuse it.
struct RoutePlanner {
    private struct Point {
        let coordinate: CLLocationCoordinate2D
        let distanceM: Double
        let cell: Int
        let headingDeg: Double
    }

    let view: LakeView
    let path: [CLLocationCoordinate2D]
    let distanceM: Double
    private let points: [Point]
    /// Where each stretch between two stops begins and ends, for drawing.
    private let pieces: [[CLLocationCoordinate2D]]

    static let stepM = 150.0

    /// `waypoints` from the start; out and back rows them again in reverse.
    init?(view: LakeView, waypoints: [CLLocationCoordinate2D], outAndBack: Bool) {
        guard waypoints.count >= 2, !view.grid.cells.isEmpty else { return nil }
        self.view = view
        path = outAndBack ? waypoints + waypoints.dropLast().reversed() : waypoints
        let grid = view.grid
        let byFlat = Dictionary(uniqueKeysWithValues: grid.cells.enumerated().map { ($1, $0) })
        var points: [Point] = [], pieces: [[CLLocationCoordinate2D]] = []
        var travelled = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            let length = Self.distance(a, b)
            guard length > 1 else { continue }
            let heading = Self.heading(a, b)
            let steps = max(1, Int((length / Self.stepM).rounded(.up)))
            for k in 0..<steps {
                let mid = Self.interpolate(a, b, (Double(k) + 0.5) / Double(steps))
                points.append(Point(
                    coordinate: mid,
                    distanceM: travelled + length * (Double(k) + 0.5) / Double(steps),
                    cell: Self.cell(at: mid, grid: grid, byFlat: byFlat),
                    headingDeg: heading
                ))
                pieces.append([Self.interpolate(a, b, Double(k) / Double(steps)), Self.interpolate(a, b, Double(k + 1) / Double(steps))])
            }
            travelled += length
        }
        guard !points.isEmpty else { return nil }
        self.points = points
        self.pieces = pieces
        distanceM = travelled
    }

    /// Pace in seconds per 500 m, as on an ergometer.
    func plan(start: Date, paceSecondsPer500: Double) -> RoutePlan {
        let speed = 500 / max(paceSecondsPer500, 60)
        let hours = view.hours
        var beyond = false
        var stops: [RoutePlan.Stop] = []
        for p in points {
            let time = start.addingTimeInterval(p.distanceM / speed)
            var h = hours.lastIndex { $0.time <= time } ?? 0
            if let last = hours.last, time >= last.time.addingTimeInterval(3600) { beyond = true }
            h = min(h, hours.count - 1)
            let hour = hours[h]
            let point = view.grid.cellPoint[p.cell]
            let wind = point < hour.wind.count ? hour.wind[point] : nil
            stops.append(RoutePlan.Stop(
                coordinate: Coordinate(lat: p.coordinate.latitude, lon: p.coordinate.longitude),
                distanceM: p.distanceM,
                time: time,
                cell: p.cell,
                light: max(hour.lights[p.cell], hour.lakeWide.light),
                waveM: hour.wave(ofCell: p.cell),
                windMs: wind?.speedMs,
                gustMs: wind?.gustMs,
                relation: wind?.fromDeg.map { WindRelation(heading: p.headingDeg, windFrom: $0) }
            ))
        }
        let end = start.addingTimeInterval(distanceM / speed)
        return RoutePlan(start: start, end: end, distanceM: distanceM, stops: stops, segments: segments(stops), beyondForecast: beyond)
    }

    /// The start time within the forecast that meets the best conditions:
    /// the best worst light, then the lowest waves, then the earliest.
    /// Hours that end the trip past the forecast are left out.
    func bestStart(paceSecondsPer500: Double, from: Date = .now) -> RoutePlan? {
        let starts = view.hours.map(\.time).filter { $0.addingTimeInterval(3600) > from }.map { max($0, from) }
        return starts
            .map { plan(start: $0, paceSecondsPer500: paceSecondsPer500) }
            .filter { !$0.beyondForecast }
            .min { ($0.worstLight, ($0.maxWaveM * 100).rounded(), $0.start) < ($1.worstLight, ($1.maxWaveM * 100).rounded(), $1.start) }
    }

    private func segments(_ stops: [RoutePlan.Stop]) -> [RoutePlan.Segment] {
        var out: [RoutePlan.Segment] = []
        var current: [CLLocationCoordinate2D] = []
        var light: Light?
        for (stop, piece) in zip(stops, pieces) {
            if stop.light != light, let light, !current.isEmpty {
                out.append(RoutePlan.Segment(points: current.map(Self.coordinate), light: light))
                current = [current[current.count - 1]]
            }
            if current.isEmpty { current = [piece[0]] }
            current.append(piece[1])
            light = stop.light
        }
        if let light, current.count > 1 { out.append(RoutePlan.Segment(points: current.map(Self.coordinate), light: light)) }
        return out
    }

    private static func coordinate(_ c: CLLocationCoordinate2D) -> Coordinate {
        Coordinate(lat: c.latitude, lon: c.longitude)
    }

    /// The water cell at the point, or the nearest one for a point on the shore.
    private static func cell(at c: CLLocationCoordinate2D, grid: LakeGrid, byFlat: [Int: Int]) -> Int {
        let col = Int(((c.longitude - grid.west) / grid.dLon).rounded())
        let row = Int(((c.latitude - grid.south) / grid.dLat).rounded())
        if (0..<grid.cols).contains(col), (0..<grid.rows).contains(row), let i = byFlat[row * grid.cols + col] {
            return i
        }
        let k = cos(c.latitude * .pi / 180)
        return grid.cells.indices.min { a, b in
            let pa = grid.coordinate(ofCell: a), pb = grid.coordinate(ofCell: b)
            let da = pow((pa.longitude - c.longitude) * k, 2) + pow(pa.latitude - c.latitude, 2)
            let db = pow((pb.longitude - c.longitude) * k, 2) + pow(pb.latitude - c.latitude, 2)
            return da < db
        } ?? 0
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Compass heading from a to b, degrees from north, clockwise.
    static func heading(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
        let dy = b.latitude - a.latitude
        return (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
}

extension Format {
    /// Pace per 500 m as on an ergometer, "2:15".
    static func pace(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
