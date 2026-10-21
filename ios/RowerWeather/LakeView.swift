import CoreGraphics
import CoreLocation
import Foundation
import Observation

/// Conditions across a whole lake, hour by hour (backend: /lakes/{id}/view,
/// see backend/rowerweather/lake_view.py). The lake is covered by a grid of
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
    let hours: [LakeHour]

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
    let lakeWide: LakeWide
    /// Per water cell, from the conditions at the cell only.
    let lights: [Light]
    let wavesCm: [Int]
    /// Per forecast point.
    let wind: [LakeWind]
    /// Per part of the lake: the worst light and the highest waves in it.
    let zones: [LakeZone]

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
    let light: Light
    let reasons: [Reason]
}

struct LakeWind: Decodable, Hashable {
    let speedMs: Double?
    let gustMs: Double?
    let fromDeg: Double?
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
}

/// Caches lake views; they change with the forecast, every half hour.
@MainActor
@Observable
final class LakeViewStore {
    static let shared = LakeViewStore(api: .fromBundle())

    private(set) var views: [String: LakeView] = [:]
    private(set) var failed: Set<String> = []
    private let api: APIClient

    nonisolated init(api: APIClient) { self.api = api }

    func load(_ lakeID: String, force: Bool = false) async {
        if !force, let view = views[lakeID], view.generatedAt > .now.addingTimeInterval(-30 * 60) { return }
        do {
            views[lakeID] = try await api.lakeView(lakeID: lakeID)
            failed.remove(lakeID)
        } catch {
            failed.insert(lakeID)
        }
    }
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

    /// Wave limits as in the backend's score.py: amber from 0.15 m, red above 0.30 m.
    static func waveColor(_ m: Double) -> RGB { ramp(m, amber: 0.15, red: 0.30) }
    /// Wind limits: amber from 5.5 m/s (Bft 4), red above 8 m/s (Bft 5).
    static func windColor(_ ms: Double) -> RGB { ramp(ms, amber: 5.5, red: 8.0) }

    static func image(_ view: LakeView, hour: LakeHour, layer: LakeLayer) -> CGImage? {
        let grid = view.grid
        let w = grid.cols, h = grid.rows
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var water = [Bool](repeating: false, count: w * h)
        for (i, flat) in grid.cells.enumerated() where i < hour.lights.count {
            let color: RGB
            switch layer {
            case .light: color = Self.color(hour.lights[i])
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
