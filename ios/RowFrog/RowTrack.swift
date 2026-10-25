import CoreLocation
import Foundation
import UniformTypeIdentifiers

/// A row recorded by another app: its GPS points with their times, from Apple
/// Health or from a GPX, TCX or FIT file. Read on the phone only.
struct RowTrack: Equatable {
    struct Point: Equatable {
        var lat: Double
        var lon: Double
        var time: Date?

        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    }

    enum Source: String, Codable { case health, file }

    var points: [Point]
    var source: Source

    var start: Date? { points.first?.time }

    var distanceM: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + RoutePlanner.distance($1.0.coordinate, $1.1.coordinate) }
    }

    /// Seconds per 500 m while the boat moved: stops (turning, waiting) leave
    /// out the stretches slower than `stoppedMs`. Nil without times.
    var paceSecondsPer500: Double? {
        var metres = 0.0, seconds = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            guard let ta = a.time, let tb = b.time else { continue }
            let dt = tb.timeIntervalSince(ta), d = RoutePlanner.distance(a.coordinate, b.coordinate)
            guard dt > 0, d / dt >= Self.stoppedMs else { continue }
            metres += d
            seconds += dt
        }
        return metres >= 200 ? seconds / metres * 500 : nil
    }

    /// Slower than this (8:20 per 500 m) the boat is taken to stand still.
    static let stoppedMs = 1.0
    /// Faster than this between two points is a GPS jump, not rowing.
    static let jumpMs = 12.0

    /// Without GPS jumps and without points closer than 2 m to the one before.
    var cleaned: RowTrack {
        var out: [Point] = []
        for p in points {
            guard let last = out.last else { out.append(p); continue }
            let d = RoutePlanner.distance(last.coordinate, p.coordinate)
            if d < 2 { continue }
            if let ta = last.time, let tb = p.time, tb.timeIntervalSince(ta) > 0, d / tb.timeIntervalSince(ta) > Self.jumpMs { continue }
            out.append(p)
        }
        return RowTrack(points: out, source: source)
    }
}

// MARK: - Files

/// GPX, TCX and FIT files, as exported by CrewNerd, Garmin Connect, Strava and
/// other apps. The types are declared in the app's Info.plist (project.yml).
enum TrackFile {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
    static let tcx = UTType(importedAs: "com.garmin.tcx", conformingTo: .xml)
    static let fit = UTType(importedAs: "com.garmin.fit", conformingTo: .data)
    static let types: [UTType] = [gpx, tcx, fit]

    enum Failure: Error { case unknownFormat, noPoints }

    /// The file's track: FIT by its header, else GPX or TCX by their XML.
    static func read(_ data: Data) throws -> RowTrack {
        let points = isFIT(data) ? try FITReader.points(data) : try XMLTrackReader.points(data)
        guard points.count >= 2 else { throw Failure.noPoints }
        return RowTrack(points: points, source: .file)
    }

    static func read(contentsOf url: URL) throws -> RowTrack {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try read(Data(contentsOf: url))
    }

    static func isFIT(_ data: Data) -> Bool {
        data.count >= 12 && data[data.startIndex + 8 ..< data.startIndex + 12].elementsEqual(Array(".FIT".utf8))
    }

    static func isTrackFile(_ url: URL) -> Bool {
        ["gpx", "tcx", "fit"].contains(url.pathExtension.lowercased())
    }
}

/// GPX (`trkpt`, or `rtept` when there is no track) and TCX (`Trackpoint`) points.
private final class XMLTrackReader: NSObject, XMLParserDelegate {
    private var track: [RowTrack.Point] = []
    private var route: [RowTrack.Point] = []
    private var current: (lat: Double?, lon: Double?, time: Date?, kind: String)?
    private var text = ""

    static func points(_ data: Data) throws -> [RowTrack.Point] {
        let reader = XMLTrackReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() || !reader.track.isEmpty || !reader.route.isEmpty else { throw TrackFile.Failure.unknownFormat }
        return reader.track.isEmpty ? reader.route : reader.track
    }

    /// Without a namespace prefix such as "gpx:".
    private static func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let name = Self.local(elementName)
        text = ""
        switch name {
        case "trkpt", "rtept":
            current = (attributes["lat"].flatMap(Double.init), attributes["lon"].flatMap(Double.init), nil, name)
        case "Trackpoint":
            current = (nil, nil, nil, name)
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = Self.local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != nil else { return }
        switch name {
        case "time", "Time": current?.time = Self.date(value)
        case "LatitudeDegrees": current?.lat = Double(value)
        case "LongitudeDegrees": current?.lon = Double(value)
        case "trkpt", "rtept", "Trackpoint":
            if let c = current, let lat = c.lat, let lon = c.lon, abs(lat) <= 90, abs(lon) <= 180 {
                let point = RowTrack.Point(lat: lat, lon: lon, time: c.time)
                if name == "rtept" { route.append(point) } else { track.append(point) }
            }
            current = nil
        default: break
        }
    }

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ text: String) -> Date? { withFraction.date(from: text) ?? plain.date(from: text) }
}

/// Reads the positions and times of a FIT file's record messages (Garmin's
/// binary activity format, also written by CrewNerd and others).
enum FITReader {
    /// FIT times count seconds from 1989-12-31 00:00 UTC.
    static let epoch = Date(timeIntervalSince1970: 631_065_600)
    private static let recordMessage = 20

    private struct Field { let number: UInt8; let size: Int }
    private struct Definition { let global: Int; let bigEndian: Bool; let fields: [Field]; let developerBytes: Int }

    static func points(_ file: Data) throws -> [RowTrack.Point] {
        let data = [UInt8](file)
        guard data.count >= 12 else { throw TrackFile.Failure.unknownFormat }
        let headerSize = Int(data[0])
        let dataSize = Int(UInt32(data[4]) | UInt32(data[5]) << 8 | UInt32(data[6]) << 16 | UInt32(data[7]) << 24)
        let end = min(headerSize + dataSize, data.count)
        var i = headerSize
        var definitions: [Int: Definition] = [:]
        var lastTimestamp: UInt32?
        var points: [RowTrack.Point] = []

        func uint(_ at: Int, _ size: Int, bigEndian: Bool) -> UInt32? {
            guard size <= 4, at + size <= data.count else { return nil }
            var value: UInt32 = 0
            for k in 0..<size {
                let byte = UInt32(data[at + (bigEndian ? k : size - 1 - k)])
                value = value << 8 | byte
            }
            return value
        }

        while i < end {
            let header = data[i]
            i += 1
            if header & 0x80 == 0, header & 0x40 != 0 {
                // Definition message: which fields the data messages of this local type carry.
                guard i + 5 <= end else { break }
                let bigEndian = data[i + 1] == 1
                let global = Int(uint(i + 2, 2, bigEndian: bigEndian) ?? 0)
                let count = Int(data[i + 4])
                i += 5
                guard i + count * 3 <= end else { break }
                let fields = (0..<count).map { Field(number: data[i + $0 * 3], size: Int(data[i + $0 * 3 + 1])) }
                i += count * 3
                var developerBytes = 0
                if header & 0x20 != 0 {
                    guard i < end else { break }
                    let devCount = Int(data[i])
                    i += 1
                    guard i + devCount * 3 <= end else { break }
                    developerBytes = (0..<devCount).reduce(0) { $0 + Int(data[i + $1 * 3 + 1]) }
                    i += devCount * 3
                }
                definitions[Int(header & 0x0F)] = Definition(global: global, bigEndian: bigEndian, fields: fields, developerBytes: developerBytes)
            } else {
                // Data message, with a normal header or a compressed timestamp header.
                let compressed = header & 0x80 != 0
                let local = compressed ? Int((header >> 5) & 0x03) : Int(header & 0x0F)
                // Without its definition the message's length is unknown: keep what was read.
                guard let definition = definitions[local] else { break }
                var lat: Int32?, lon: Int32?, timestamp: UInt32?
                if compressed, let last = lastTimestamp {
                    let offset = UInt32(header & 0x1F)
                    var t = (last & ~0x1F) + offset
                    if offset < last & 0x1F { t += 0x20 }
                    timestamp = t
                }
                for field in definition.fields {
                    defer { i += field.size }
                    guard i + field.size <= end else { break }
                    switch field.number {
                    case 253 where field.size == 4:
                        timestamp = uint(i, 4, bigEndian: definition.bigEndian)
                    case 0 where definition.global == recordMessage && field.size == 4:
                        lat = uint(i, 4, bigEndian: definition.bigEndian).map { Int32(bitPattern: $0) }
                    case 1 where definition.global == recordMessage && field.size == 4:
                        lon = uint(i, 4, bigEndian: definition.bigEndian).map { Int32(bitPattern: $0) }
                    default: break
                    }
                }
                i += definition.developerBytes
                if let timestamp, timestamp != UInt32.max { lastTimestamp = timestamp }
                if definition.global == recordMessage, let lat, let lon, lat != Int32.max, lon != Int32.max {
                    points.append(RowTrack.Point(lat: degrees(lat), lon: degrees(lon),
                                                 time: timestamp.map { epoch.addingTimeInterval(TimeInterval($0)) }))
                }
            }
        }
        return points
    }

    /// FIT positions are in semicircles: 2^31 of them make 180°.
    static func degrees(_ semicircles: Int32) -> Double { Double(semicircles) * 180 / 2_147_483_648 }
}

// MARK: - From a track to a route

/// Turns a rowed track into a route that plans and edits like one drawn by hand.
enum RouteImport {
    /// The turning points keep the route within this of the track.
    static let toleranceM = 15.0
    static let maxTurningPoints = 40
    /// The track kept for showing on the map.
    static let trackToleranceM = 4.0
    static let maxTrackPoints = 1500
    /// A start this close to a club's launch point starts there.
    static let launchSnapM = 200.0
    /// An end this close to the start ends the row where it began.
    static let backAtStartM = 150.0
    /// Out and back when this share of the way back runs within `retraceM` of the way out.
    static let retraceShare = 0.8
    static let retraceM = 75.0
    /// Shorter rows are taken for a recording mistake.
    static let shortestM = 200.0

    /// The share of the track's points on the lake's water cells.
    static func shareOnWater(_ track: RowTrack, grid: LakeGrid) -> Double {
        guard !track.points.isEmpty else { return 0 }
        // Every point is too slow for long tracks, and a sample tells as much.
        let step = max(track.points.count / 200, 1)
        let sample = stride(from: 0, to: track.points.count, by: step).map { track.points[$0] }
        return Double(sample.filter { grid.cell(at: $0.coordinate) != nil }.count) / Double(sample.count)
    }

    static func route(from track: RowTrack, lakeId: String, launchPoints: [Coordinate], now: Date = .now) -> Route? {
        let clean = track.cleaned
        var coordinates = clean.points.map(\.coordinate)
        guard coordinates.count >= 2, clean.distanceM >= shortestM, let first = coordinates.first, let last = coordinates.last else { return nil }
        // Start at the club when the row started there.
        if let launch = launchPoints.map({ CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
            .min(by: { RoutePlanner.distance($0, first) < RoutePlanner.distance($1, first) }),
           RoutePlanner.distance(launch, first) <= launchSnapM {
            coordinates[0] = launch
        }
        let start = coordinates[0]
        let backAtStart = RoutePlanner.distance(start, last) <= backAtStartM
        var outAndBack = false
        var turning: [CLLocationCoordinate2D]
        if backAtStart, let far = farthest(from: start, in: coordinates), retraces(coordinates, turnAt: far) {
            outAndBack = true
            turning = turningPoints(Array(coordinates[...far]))
        } else {
            turning = turningPoints(coordinates)
            if backAtStart, turning.count >= 3 {
                // A loop ends exactly at the start.
                turning[turning.count - 1] = start
                if turning.count < 4 {
                    // Start, one point, start: that is rowing out and back.
                    turning = Array(turning.dropLast())
                    outAndBack = true
                }
            }
        }
        let date = track.start ?? now
        let name = tr("Rowed %@, %@", date.formatted(.dateTime.day().month(.abbreviated).locale(AppSettings.shared.locale)), Format.distance(clean.distanceM))
        return Route(name: name, lakeId: lakeId,
                     points: turning.map { Coordinate(lat: $0.latitude, lon: $0.longitude) },
                     outAndBack: outAndBack,
                     track: keptTrack(coordinates).map { Coordinate(lat: $0.latitude, lon: $0.longitude) },
                     rowedAt: track.start,
                     importedFrom: track.source)
    }

    /// Route planning goes on at the pace the crew really rowed.
    static func usePace(_ secondsPer500: Double) {
        UserDefaults.standard.set(min(max((secondsPer500 / 5).rounded() * 5, 90), 240), forKey: "RWRoutePace")
    }

    /// The turning points, fewer the longer the row, never more than `maxTurningPoints`.
    static func turningPoints(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        thinned(points, tolerance: toleranceM, max: maxTurningPoints)
    }

    static func keptTrack(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        thinned(points, tolerance: trackToleranceM, max: maxTrackPoints)
    }

    private static func thinned(_ points: [CLLocationCoordinate2D], tolerance: Double, max count: Int) -> [CLLocationCoordinate2D] {
        var t = tolerance
        var out = simplify(points, toleranceM: t)
        while out.count > count {
            t *= 1.5
            out = simplify(points, toleranceM: t)
        }
        return out
    }

    /// Douglas–Peucker: keeps the points the line strays furthest from, until
    /// none of the others is more than `toleranceM` away from it.
    static func simplify(_ points: [CLLocationCoordinate2D], toleranceM: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        let xy = local(points)
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var worst = a, worstD = 0.0
            for k in (a + 1)..<b {
                let d = segmentDistance(xy[k], xy[a], xy[b])
                if d > worstD { worst = k; worstD = d }
            }
            if worstD > toleranceM {
                keep[worst] = true
                stack.append((a, worst))
                stack.append((worst, b))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// The point furthest from the start, where an out-and-back row turned.
    static func farthest(from start: CLLocationCoordinate2D, in points: [CLLocationCoordinate2D]) -> Int? {
        points.indices.max { RoutePlanner.distance(points[$0], start) < RoutePlanner.distance(points[$1], start) }
    }

    /// Whether the way back from `turn` runs along the way out.
    static func retraces(_ points: [CLLocationCoordinate2D], turnAt turn: Int) -> Bool {
        guard turn > 0, turn < points.count - 1 else { return false }
        let xy = local(points)
        let out = Array(xy[...turn]), back = xy[turn...]
        let near = back.filter { p in
            zip(out, out.dropFirst()).contains { segmentDistance(p, $0, $1) <= retraceM }
        }
        return Double(near.count) / Double(back.count) >= retraceShare
    }

    /// Metres east and north of the first point.
    private static func local(_ points: [CLLocationCoordinate2D]) -> [SIMD2<Double>] {
        guard let origin = points.first else { return [] }
        let k = cos(origin.latitude * .pi / 180) * 111_320
        return points.map { SIMD2(($0.longitude - origin.longitude) * k, ($0.latitude - origin.latitude) * 110_540) }
    }

    private static func segmentDistance(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let ab = b - a
        let length = (ab * ab).sum()
        guard length > 0 else { return ((p - a) * (p - a)).sum().squareRoot() }
        let t = min(max(((p - a) * ab).sum() / length, 0), 1)
        let q = a + ab * t
        return ((p - q) * (p - q)).sum().squareRoot()
    }

    /// Screenshot hook: a made-up row along `points`, wandering a few metres
    /// either side as a real boat does, at 2:20 per 500 m, a week ago.
    static func sampleTrack(along points: [CLLocationCoordinate2D], outAndBack: Bool, now: Date = .now) -> RowTrack {
        let legs = outAndBack ? points + points.reversed().dropFirst() : points
        var out: [RowTrack.Point] = []
        var time = now.addingTimeInterval(-7 * 86_400)
        for (a, b) in zip(legs, legs.dropFirst()) {
            let d = RoutePlanner.distance(a, b)
            let steps = max(Int(d / 10), 1)
            for s in 0..<steps {
                let t = Double(s) / Double(steps)
                let wobble = sin(Double(out.count) / 9) * 0.00008
                out.append(RowTrack.Point(lat: a.latitude + (b.latitude - a.latitude) * t + wobble,
                                          lon: a.longitude + (b.longitude - a.longitude) * t + wobble,
                                          time: time))
                time.addTimeInterval(d / Double(steps) / 500 * 140)
            }
        }
        if let last = legs.last { out.append(RowTrack.Point(lat: last.latitude, lon: last.longitude, time: time)) }
        return RowTrack(points: out, source: .health)
    }
}
