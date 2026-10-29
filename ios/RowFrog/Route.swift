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

    /// The whole outing in metres, back to the start when rowed out and back.
    var lengthM: Double {
        let c = coordinates
        let oneWay = zip(c, c.dropFirst()).reduce(0) { $0 + RoutePlanner.distance($1.0, $1.1) }
        return outAndBack ? oneWay * 2 : oneWay
    }

    var isLoop: Bool { RouteEdit.isLoop(coordinates) }

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

    func rename(_ route: Route, to name: String) {
        guard let i = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[i].name = name
        persist()
    }

    /// A copy right after the route, named "… (copy)".
    @discardableResult
    func duplicate(_ route: Route) -> Route {
        var copy = route
        copy.id = UUID()
        copy.name = tr("%@ (copy)", route.name)
        let i = routes.firstIndex(where: { $0.id == route.id }).map { $0 + 1 } ?? routes.endIndex
        routes.insert(copy, at: i)
        persist()
        return copy
    }

    /// Moves routes within one lake's list; other lakes' routes keep their places.
    func move(on lakeID: String, from source: IndexSet, to destination: Int) {
        let all = routes(on: lakeID)
        let moving = source.map { all[$0] }
        var lake = all.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        lake.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        var next = lake.makeIterator()
        routes = routes.map { $0.lakeId == lakeID ? next.next() ?? $0 : $0 }
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

    /// Adds a turning point on the stretch before the point at `index`; not before the start.
    static func insert(_ point: CLLocationCoordinate2D, at index: Int, in points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard index > 0, index < points.count else { return points }
        var out = points
        out.insert(point, at: index)
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
    /// On rivers: the current the times count with (mid-river, m/s), and
    /// whether some stretch runs against a current faster than the boat.
    var currentMs: Double? = nil
    var noHeadway = false


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
        /// The length of route this point stands for.
        let stepM: Double
        /// How much of the current runs along the route here: 1 downstream, -1 upstream.
        let withCurrent: Double
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
        let flow = Self.flowPieces(view.section?.flow)
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
                    headingDeg: heading,
                    stepM: length / Double(steps),
                    withCurrent: Self.withCurrent(at: mid, heading: heading, flow: flow)
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
    /// On rivers the current at the club's gauge speeds the boat up downstream
    /// and slows it down upstream (over ground: still-water speed ± current).
    func plan(start: Date, paceSecondsPer500: Double) -> RoutePlan {
        let speed = 500 / max(paceSecondsPer500, 60)
        let current = view.currentMs ?? 0
        let hours = view.hours
        var beyond = false, noHeadway = false
        var stops: [RoutePlan.Stop] = []
        var elapsed = 0.0
        for p in points {
            var ground = speed + current * p.withCurrent
            if ground < Self.minGroundMs {
                noHeadway = true
                ground = Self.minGroundMs
            }
            let time = start.addingTimeInterval(elapsed + p.stepM / 2 / ground)
            elapsed += p.stepM / ground
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
        let end = start.addingTimeInterval(elapsed)
        return RoutePlan(start: start, end: end, distanceM: distanceM, stops: stops, segments: segments(stops), beyondForecast: beyond,
                         currentMs: view.currentMs, noHeadway: noHeadway)
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

    /// Slowest speed over ground counted where the current is about as fast as the boat.
    static let minGroundMs = 0.2
    /// The river line farther than this from a point of the route says nothing about its current.
    static let flowNearM = 300.0

    /// The river line (pointing downstream) as pieces from one point to the next.
    private static func flowPieces(_ flow: [[[Double]]]?) -> [(CLLocationCoordinate2D, CLLocationCoordinate2D)] {
        (flow ?? []).flatMap { line in
            let points = line.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil }
            return Array(zip(points, points.dropFirst()))
        }
    }

    /// The cosine between the route's heading and the river's flow at the
    /// nearest piece of the river line; 0 away from the river line.
    static func withCurrent(at c: CLLocationCoordinate2D, heading: Double, flow: [(CLLocationCoordinate2D, CLLocationCoordinate2D)]) -> Double {
        let nearest = flow.map { ($0, distance(c, interpolate($0.0, $0.1, 0.5))) }.min { $0.1 < $1.1 }
        guard let nearest, nearest.1 < flowNearM + distance(nearest.0.0, nearest.0.1) / 2 else { return 0 }
        return cos((heading - Self.heading(nearest.0.0, nearest.0.1)) * .pi / 180)
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
