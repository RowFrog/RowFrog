import CoreGraphics
import CoreLocation
import Foundation
import Observation

/// Conditions across a whole lake, hour by hour (backend: /lakes/{id}/view,
/// see backend/rowfrog/lake_view.py). The lake is covered by a grid of
/// square cells; each water cell has its own light and waves every hour.
struct LakeView: Decodable, Hashable {
    let lakeId: String
    let name: String
    let generatedAt: Date
    /// The wind was replaced by a made-up sample, for the screenshots.
    let sample: Bool
    let attribution: [String]
    let grid: LakeGrid
    /// The lake's parts, northern (or western) end first: "north", "middle", "south" ... or "whole".
    let zones: [String]
    /// Shore and islands as [lon, lat] pairs, simplified for drawing.
    let outline: [[[Double]]]
    /// The forecast points the wind comes from.
    let points: [Coordinate]
    let clubs: [LakeClub]
    var hours: [LakeHour]
    /// The measured water the lights used; missing without a lake station or from older backends.
    var waterC: Double? = nil

    /// Older than a club forecast may be: the lights then turn grey instead of green.
    var isStale: Bool {
        UserDefaults.standard.bool(forKey: "RWStaleForecast") || Date.now.timeIntervalSince(generatedAt) > ClubForecast.staleAfter
    }

    /// The hour that is running at `date`, else the first one.
    func hourIndex(at date: Date = .now) -> Int {
        hours.lastIndex { $0.time <= date } ?? 0
    }
}

struct LakeGrid: Decodable, Hashable {
    /// Latitude of the centre of the bottom row and longitude of the centre of the left column.
    let south: Double
    let west: Double
    let dLat: Double
    let dLon: Double
    let cols: Int
    let rows: Int
    let cellM: Int
    /// row * cols + col of every water cell; row 0 is the south.
    let cells: [Int]
    /// The forecast point (index into `points`) each water cell takes its wind from.
    let cellPoint: [Int]
    /// The part of the lake (index into `zones`) each water cell lies in.
    let cellZone: [Int]

    func coordinate(ofCell i: Int) -> CLLocationCoordinate2D {
        let flat = cells[i]
        return CLLocationCoordinate2D(latitude: south + Double(flat / cols) * dLat, longitude: west + Double(flat % cols) * dLon)
    }

    /// The water cell at a coordinate, or nil on land.
    func cell(at c: CLLocationCoordinate2D) -> Int? {
        let col = Int(((c.longitude - west) / dLon).rounded())
        let row = Int(((c.latitude - south) / dLat).rounded())
        guard (0..<cols).contains(col), (0..<rows).contains(row) else { return nil }
        return cells.firstIndex(of: row * cols + col)
    }

    /// The area the cells cover, edges included.
    var north: Double { south + Double(rows - 1) * dLat + dLat / 2 }
    var southEdge: Double { south - dLat / 2 }
    var westEdge: Double { west - dLon / 2 }
    var east: Double { west + Double(cols - 1) * dLon + dLon / 2 }
}

struct LakeClub: Decodable, Hashable, Identifiable {
    let id: String
    let shortName: String
    let launchPoint: Coordinate
}

struct LakeHour: Decodable, Hashable, Identifiable {
    let time: Date
    /// What holds for the whole lake: DWD warnings, dark, cold water.
    var lakeWide: LakeWide
    /// Per water cell, from the conditions at the cell only.
    var lights: [Light]
    let wavesCm: [Int]
    /// Per forecast point.
    let wind: [LakeWind]
    /// Per part of the lake: the worst light and the highest waves in it.
    var zones: [LakeZone]

    var id: Date { time }

    private enum CodingKeys: String, CodingKey {
        case time, lakeWide, lights, wavesCm, wind, zones
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decode(Date.self, forKey: .time)
        lakeWide = try c.decode(LakeWide.self, forKey: .lakeWide)
        // One digit per cell: 0 green, 1 amber, 2 red.
        lights = try c.decode(String.self, forKey: .lights).map { (c: Character) -> Light in c == "2" ? .red : c == "1" ? .amber : .green }
        wavesCm = try c.decode([Int].self, forKey: .wavesCm)
        wind = try c.decode([LakeWind].self, forKey: .wind)
        zones = try c.decode([LakeZone].self, forKey: .zones)
    }

    func wave(ofCell i: Int) -> Double { Double(wavesCm[i]) / 100 }

    /// Share of the water that is green, amber and red.
    var shares: [Light: Double] {
        let total = Double(max(lights.count, 1))
        return Dictionary(grouping: lights, by: { $0 }).mapValues { Double($0.count) / total }
    }

    /// Weakest and strongest mean wind over the lake, and the strongest gust.
    var windRange: (min: Double, max: Double, gust: Double)? {
        let speeds = wind.compactMap(\.speedMs)
        guard let lo = speeds.min(), let hi = speeds.max() else { return nil }
        return (lo, hi, wind.compactMap(\.gustMs).max() ?? hi)
    }

    /// The mean direction the wind comes from, averaged as vectors.
    var windFromDeg: Double? {
        let vectors = wind.compactMap { w -> (Double, Double)? in
            guard let d = w.fromDeg, let s = w.speedMs else { return nil }
            let r = d * .pi / 180
            return (sin(r) * s, cos(r) * s)
        }
        guard !vectors.isEmpty else { return nil }
        let x = vectors.map(\.0).reduce(0, +), y = vectors.map(\.1).reduce(0, +)
        return (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

struct LakeWide: Decodable, Hashable {
    var light: Light
    var reasons: [Reason]
}

struct LakeWind: Decodable, Hashable {
    let speedMs: Double?
    let gustMs: Double?
    let fromDeg: Double?
    /// The light from fog and thunderstorms at the point; missing from older backends.
    let other: Light?

    private enum CodingKeys: String, CodingKey { case speedMs, gustMs, fromDeg, other }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speedMs = try c.decodeIfPresent(Double.self, forKey: .speedMs)
        gustMs = try c.decodeIfPresent(Double.self, forKey: .gustMs)
        fromDeg = try c.decodeIfPresent(Double.self, forKey: .fromDeg)
        // 0 green, 1 amber, 2 red.
        other = try c.decodeIfPresent(Int.self, forKey: .other).map { $0 >= 2 ? .red : $0 == 1 ? .amber : .green }
    }
}

extension LakeView {
    /// The lake coloured for a boat's wind, gust and wave limits; unchanged
    /// with the app's own, or when the backend does not send fog per point.
    func applying(_ limits: RowingLimits) -> LakeView {
        guard !limits.matchesStandard,
              hours.allSatisfy({ $0.wind.allSatisfy { $0.other != nil } }) else { return self }
        var copy = self
        copy.hours = hours.map { original in
            var hour = original
            // In cold water the app's wind limits drop, as on the backend.
            let cold = waterC.map { $0 < RowingLimits.coldWaterC }
                ?? original.lakeWide.reasons.contains { $0.condition == "cold_water" }  // older backends
            let forBoat = limits.forWater(cold ? 0 : nil)
            hour.lakeWide.reasons = forBoat.boatReasons(original.lakeWide.reasons).sorted { $0.light > $1.light }
            hour.lakeWide.light = hour.lakeWide.reasons.map(\.light).max() ?? .green
            var zoneLights = [Light](repeating: .green, count: hour.zones.count)
            hour.lights = hour.lights.indices.map { i in
                let p = i < grid.cellPoint.count ? grid.cellPoint[i] : 0
                let wind = p < hour.wind.count ? hour.wind[p] : nil
                let light = max(wind?.other ?? .green,
                                forBoat.light(wind?.speedMs, .windAmber, .windRed),
                                forBoat.light(wind?.gustMs, .gustAmber, .gustRed),
                                forBoat.light(i < hour.wavesCm.count ? hour.wave(ofCell: i) : nil, .waveAmber, .waveRed))
                let z = i < grid.cellZone.count ? grid.cellZone[i] : 0
                if z < zoneLights.count { zoneLights[z] = max(zoneLights[z], light) }
                return light
            }
            hour.zones = zip(hour.zones, zoneLights).map { LakeZone(light: $1, maxWaveM: $0.maxWaveM) }
            return hour
        }
        return copy
    }
}

struct LakeZone: Decodable, Hashable {
    let light: Light
    let maxWaveM: Double
}

/// What the lake map colours the water by.
enum LakeLayer: String, CaseIterable, Identifiable {
    case light, waves, wind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: tr("Rowing light")
        case .waves: tr("Waves")
        case .wind: tr("Wind")
        }
    }
}

/// Names of the lake's parts.
enum LakeZoneName {
    static func title(_ key: String) -> String {
        switch key {
        case "north": tr("North")
        case "northeast": tr("Northeast")
        case "east": tr("East")
        case "southeast": tr("Southeast")
        case "south": tr("South")
        case "southwest": tr("Southwest")
        case "west": tr("West")
        case "northwest": tr("Northwest")
        case "middle": tr("Middle")
        default: tr("Whole lake")
        }
    }

    /// For sentences: "in the north", "in the middle".
    static func phrase(_ key: String) -> String {
        switch key {
        case "north": tr("in the north")
        case "northeast": tr("in the northeast")
        case "east": tr("in the east")
        case "southeast": tr("in the southeast")
        case "south": tr("in the south")
        case "southwest": tr("in the southwest")
        case "west": tr("in the west")
        case "northwest": tr("in the northwest")
        case "middle": tr("in the middle")
        default: tr("on the whole lake")
        }
    }
}

extension LakeView {
    /// One line for the hour, such as "Calmest in the south, roughest in the north".
    func headline(for hour: LakeHour) -> String {
        if hour.lakeWide.light == .red { return tr("Stay ashore on the whole lake") }
        let ranked = zip(zones, hour.zones).sorted { ($0.1.light, $0.1.maxWaveM) < ($1.1.light, $1.1.maxWaveM) }
        guard let best = ranked.first, let worst = ranked.last else { return "" }
        if best.1.light == worst.1.light || zones.count < 2 {
            switch worst.1.light {
            case .green: return tr("Good to row on the whole lake")
            case .amber: return tr("Row with care on the whole lake")
            case .red: return tr("Stay ashore on the whole lake")
            }
        }
        return tr("Calmest %@, roughest %@", LakeZoneName.phrase(best.0), LakeZoneName.phrase(worst.0))
    }

    /// "4–5 m/s from S, gusts up to 8 m/s".
    func windSummary(for hour: LakeHour) -> String? {
        guard let range = hour.windRange else { return nil }
        let speed = Format.windNumber(range.min) == Format.windNumber(range.max)
            ? Format.wind(range.max) : Format.windRange(range.min, range.max)
        let from = hour.windFromDeg.map { " " + tr("from %@", Format.compass($0)) } ?? ""
        return speed + from + ", " + tr("gusts up to %@", Format.wind(range.gust))
    }

    /// The highest waves anywhere on the lake this hour.
    func waveSummary(for hour: LakeHour) -> String? {
        guard let cm = hour.wavesCm.max() else { return nil }
        return tr("Waves up to %@", Format.waves(Double(cm) / 100))
    }
}

/// Caches lake views; they change with the forecast, every half hour.
@MainActor
@Observable
final class LakeViewStore {
    static let shared = LakeViewStore(api: .fromBundle())

    /// As the backend sent them, coloured for small boats.
    private var raw: [String: LakeView] = [:]
    /// Coloured for the boat chosen in the settings, worked out once per change.
    var views: LakeViews { LakeViews(store: self) }
    @ObservationIgnored private var applied: [String: (limits: RowingLimits, view: LakeView)] = [:]
    private(set) var failed: Set<String> = []
    private let api: APIClient

    nonisolated init(api: APIClient) { self.api = api }

    func load(_ lakeID: String, force: Bool = false) async {
        if !force, let view = raw[lakeID], view.generatedAt > .now.addingTimeInterval(-30 * 60) { return }
        do {
            let view = try await api.lakeView(lakeID: lakeID)
            applied[lakeID] = nil
            raw[lakeID] = view
            failed.remove(lakeID)
        } catch {
            failed.insert(lakeID)
        }
    }

    /// The lake for the map's boat.
    func view(_ lakeID: String) -> LakeView? {
        guard let base = raw[lakeID] else { return nil }
        let limits = AppSettings.shared.mapLimits
        if let cached = applied[lakeID], cached.limits == limits { return cached.view }
        let view = base.applying(limits)
        applied[lakeID] = (limits, view)
        return view
    }
}

@MainActor
struct LakeViews {
    let store: LakeViewStore

    subscript(lakeID: String) -> LakeView? { store.view(lakeID) }
}

/// The lake's cells as a small picture, one pixel per cell, north up. Drawn
/// scaled up with smooth interpolation and clipped to the shore, it gives a
/// soft map of the conditions.
enum LakeRaster {
    typealias RGB = (r: Double, g: Double, b: Double)

    static let green: RGB = (52, 199, 89)
    static let amber: RGB = (255, 149, 0)
    static let red: RGB = (255, 59, 48)
    private static let calm: RGB = (120, 205, 255)
    private static let yellow: RGB = (255, 204, 0)
    private static let purple: RGB = (175, 82, 222)

    static func color(_ light: Light) -> RGB {
        switch light {
        case .green: green
        case .amber: amber
        case .red: red
        }
    }

    /// When the whole lake is red (dark, a warning), the squares stay readable
    /// but faded to grey; the map draws red stripes over them.
    static func greyed(_ c: RGB) -> RGB {
        let grey = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
        return (grey + (c.r - grey) * 0.25, grey + (c.g - grey) * 0.25, grey + (c.b - grey) * 0.25)
    }

    /// Calm blue, yellow at the amber limit, red at the red limit, purple beyond.
    static func ramp(_ value: Double, amber: Double, red: Double) -> RGB {
        let stops: [(Double, RGB)] = [(0, calm), (amber, yellow), (red, LakeRaster.red), (red * 1.6, purple)]
        guard value > 0 else { return calm }
        for (a, b) in zip(stops, stops.dropFirst()) where value <= b.0 {
            let t = (value - a.0) / (b.0 - a.0)
            return (a.1.r + (b.1.r - a.1.r) * t, a.1.g + (b.1.g - a.1.g) * t, a.1.b + (b.1.b - a.1.b) * t)
        }
        return purple
    }

    /// The wave and wind limits of the boat the map is coloured for; for
    /// small boats amber from 0.15 m and 5.5 m/s, red above 0.30 m and 8 m/s.
    static func waveColor(_ m: Double) -> RGB {
        let limits = AppSettings.shared.mapLimits
        return ramp(m, amber: limits.value(.waveAmber), red: limits.value(.waveRed))
    }
    static func windColor(_ ms: Double) -> RGB {
        let limits = AppSettings.shared.mapLimits
        return ramp(ms, amber: limits.value(.windAmber), red: limits.value(.windRed))
    }

    /// The picture for an hour, kept once drawn: pages and maps ask for it on
    /// every redraw, and drawing it means smoothing a thousand cells.
    static func image(_ view: LakeView, hour: LakeHour, layer: LakeLayer) -> CGImage? {
        let key = "\(view.lakeId)|\(view.generatedAt.timeIntervalSince1970)|\(hour.hashValue)|\(layer)|\(AppSettings.shared.mapLimits)" as NSString
        if let cached = cache.object(forKey: key) { return (cached as! CGImage) }
        let image = render(view, hour: hour, layer: layer)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static let cache: NSCache<NSString, AnyObject> = {
        let cache = NSCache<NSString, AnyObject>()
        cache.countLimit = 200
        return cache
    }()

    private static func render(_ view: LakeView, hour: LakeHour, layer: LakeLayer) -> CGImage? {
        let grid = view.grid
        let w = grid.cols, h = grid.rows
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var water = [Bool](repeating: false, count: w * h)
        for (i, flat) in grid.cells.enumerated() where i < hour.lights.count {
            let color: RGB
            switch layer {
            case .light: color = hour.lakeWide.light == .red ? Self.greyed(Self.color(hour.lights[i])) : Self.color(hour.lights[i])
            case .waves: color = waveColor(hour.wave(ofCell: i))
            case .wind:
                let p = grid.cellPoint[i]
                color = windColor(p < hour.wind.count ? hour.wind[p].speedMs ?? 0 : 0)
            }
            let pixel = (h - 1 - flat / w) * w + flat % w  // north up
            water[pixel] = true
            pixels[pixel * 4] = UInt8(color.r)
            pixels[pixel * 4 + 1] = UInt8(color.g)
            pixels[pixel * 4 + 2] = UInt8(color.b)
            pixels[pixel * 4 + 3] = 255
        }
        // Spread the colours two cells onto the land, so the smoothing does not
        // fade the water towards the shore; the shore line clips it again.
        for _ in 0..<2 {
            let filled = water
            for y in 0..<h {
                for x in 0..<w where !filled[y * w + x] {
                    var sum = (0.0, 0.0, 0.0), n = 0.0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nx = x + dx, ny = y + dy
                        guard (0..<w).contains(nx), (0..<h).contains(ny), filled[ny * w + nx] else { continue }
                        let j = (ny * w + nx) * 4
                        sum.0 += Double(pixels[j]); sum.1 += Double(pixels[j + 1]); sum.2 += Double(pixels[j + 2])
                        n += 1
                    }
                    guard n > 0 else { continue }
                    let j = (y * w + x) * 4
                    pixels[j] = UInt8(sum.0 / n); pixels[j + 1] = UInt8(sum.1 / n); pixels[j + 2] = UInt8(sum.2 / n)
                    pixels[j + 3] = 255
                    water[y * w + x] = true
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
