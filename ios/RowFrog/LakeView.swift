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
    /// Set by the app: the measured water, else the estimate of the club page that showed the lake.
    var shoreWaterC: Double? = nil
    /// "lake" or "river"; missing from older backends.
    var kind: String? = nil
    /// River sections only: where the stretch ends each way and the river line.
    var section: RiverSection? = nil
    /// Set by the app on rivers: the current of the club page that showed the
    /// stretch (gauge, m/s mid-river), for the route planner.
    var currentMs: Double? = nil

    var water: WaterKind { WaterKind(kind: kind, waterway: section?.waterway) }

    /// Cold water draws the shore blue on the maps, for the map's boat.
    var coldShore: ColdShore? { ColdShore(waterC: shoreWaterC, limits: AppSettings.shared.mapLimits) }
    /// Whether the whole-lake stripes run from top left to bottom right instead
    /// of bottom left to top right, so they cross the lake's long side.
    var stripesFall: Bool { Self.stripesFall(outline) }

    /// A long lake lying along the usual diagonal, like a regatta course, would
    /// get stripes along its length that hardly show; such lakes get the other
    /// diagonal. Round lakes keep the usual one.
    static func stripesFall(_ outline: [[[Double]]]) -> Bool {
        guard let first = outline.first?.first, first.count > 1 else { return false }
        let squeeze = cos(first[1] * .pi / 180)
        // The shore's spread, each stretch weighted by its length, in degrees of latitude.
        var sum = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
        for ring in outline where ring.count > 1 {
            for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) where a.count > 1 && b.count > 1 {
                let ax = a[0] * squeeze, ay = a[1], bx = b[0] * squeeze, by = b[1]
                let w = hypot(bx - ax, by - ay), x = (ax + bx) / 2, y = (ay + by) / 2
                sum += w; sx += w * x; sy += w * y
                sxx += w * x * x; syy += w * y * y; sxy += w * x * y
            }
        }
        guard sum > 0 else { return false }
        let mx = sx / sum, my = sy / sum
        let vxx = sxx / sum - mx * mx, vyy = syy / sum - my * my, vxy = sxy / sum - mx * my
        let half = (vxx + vyy) / 2, spread = (((vxx - vyy) / 2) * ((vxx - vyy) / 2) + vxy * vxy).squareRoot()
        guard half + spread > 1.5 * max(half - spread, 0) else { return false }
        // The long side's angle, north up, and how far it lies from the usual stripes at 45°;
        // a lake lying north-south or east-west keeps the usual ones.
        let along = atan2(2 * vxy, vxx - vyy) / 2
        return abs(remainder(along - .pi / 4, .pi)) < .pi / 4 - 0.05
    }

    /// What to bring in cold water, for the map's boat.
    var coldWaterKit: ColdWaterKit? { ColdWaterKit(waterC: shoreWaterC, limits: AppSettings.shared.mapLimits) }

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
    /// The middle of the grid.
    var centre: Coordinate { Coordinate(lat: (north + southEdge) / 2, lon: (westEdge + east) / 2) }
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

/// The shore on the lake maps while the water is cold: light blue from the
/// life-jacket limit down, deeper blue below 10 °C. The whole lake reads as
/// cold without colouring the squares, which keep showing where to row
/// (owner's pick, 2026-10-26).
enum ColdShore: Equatable {
    case cool, cold

    init?(waterC: Double?, limits: RowingLimits) {
        guard let kit = ColdWaterKit(waterC: waterC, limits: limits) else { return nil }
        self = kit == .lifeJacket ? .cool : .cold
    }

    /// Line width in screen points on the full map and on the club page's tile.
    var mapWidth: CGFloat { self == .cool ? 2.5 : 3.5 }
    var tileWidth: CGFloat { self == .cool ? 1.6 : 2.2 }
}

struct LakeWide: Decodable, Hashable {
    var light: Light
    var reasons: [Reason]

    /// The stripes the maps draw over the squares: red while the whole lake is
    /// red, amber in the sunrise or sunset hour or under an amber warning. Cold
    /// water stays in the panel only: it lasts for months and is the same all
    /// over the lake, so it never tells where to row.
    var stripes: Light? {
        if light == .red { return .red }
        let cold = Condition.waterTemperature.reasonNames
        return reasons.contains { $0.light == .amber && !cold.contains($0.condition) } ? .amber : nil
    }
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

    /// The same for a river section's single part.
    static func title(_ key: String, water: WaterKind) -> String {
        water == .lake || key != "whole" ? title(key) : tr("Whole stretch")
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
        let lake = water == .lake
        if hour.lakeWide.light == .red { return lake ? tr("Stay ashore on the whole lake") : tr("Stay ashore on the whole stretch") }
        let ranked = zip(zones, hour.zones).sorted { ($0.1.light, $0.1.maxWaveM) < ($1.1.light, $1.1.maxWaveM) }
        guard let best = ranked.first, let worst = ranked.last else { return "" }
        if best.1.light == worst.1.light || zones.count < 2 {
            switch worst.1.light {
            case .green: return lake ? tr("Good to row on the whole lake") : tr("Good to row on the whole stretch")
            case .amber: return lake ? tr("Row with care on the whole lake") : tr("Row with care on the whole stretch")
            case .red: return lake ? tr("Stay ashore on the whole lake") : tr("Stay ashore on the whole stretch")
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
    /// The water of the club page that last showed each lake, for lakes without a station.
    private var clubWater: [String: Double] = [:]
    /// The current of the club page that last showed each river stretch.
    private var clubCurrent: [String: Double] = [:]
    private let api: APIClient

    nonisolated init(api: APIClient) { self.api = api }

    func load(_ lakeID: String, force: Bool = false) async {
        if !force, let view = raw[lakeID], view.generatedAt > .now.addingTimeInterval(-30 * 60) { return }
        do {
            var view = try await api.lakeView(lakeID: lakeID)
            // Screenshots: -RWLakeWide twilight|cold|dark sets the whole-lake light of every hour.
            if let wide = UserDefaults.standard.string(forKey: "RWLakeWide") {
                let reasons: [Reason] = switch wide {
                case "dark": [Reason(condition: "daylight", light: .red)]
                case "cold": [Reason(condition: "cold_water", light: .amber)]
                default: [Reason(condition: "twilight", light: .amber), Reason(condition: "cold_water", light: .amber)]
                }
                for i in view.hours.indices {
                    view.hours[i].lakeWide = LakeWide(light: reasons.map(\.light).max() ?? .green, reasons: reasons)
                }
            }
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
        var view: LakeView
        if let cached = applied[lakeID], cached.limits == limits {
            view = cached.view
        } else {
            view = base.applying(limits)
            applied[lakeID] = (limits, view)
        }
        view.shoreWaterC = view.waterC ?? clubWater[lakeID]
        view.currentMs = view.section == nil ? nil : clubCurrent[lakeID]
        return view
    }

    /// The water a club page shows (measured or estimated), for the cold shore.
    func noteWater(_ celsius: Double?, lake lakeID: String) {
        if let celsius, clubWater[lakeID] != celsius { clubWater[lakeID] = celsius }
    }

    /// The current a river club page shows, for the route planner.
    func noteCurrent(_ ms: Double?, lake lakeID: String) {
        if let ms, clubCurrent[lakeID] != ms { clubCurrent[lakeID] = ms }
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

/// Wind arrows on an even grid, as the lake map and the satellite picture draw
/// them: worked out between the lake's forecast points, more of them as the view
/// zooms in, the same size on screen, and on land up to `ashoreM` from the shore.
enum WindArrows {
    /// A forecast point's wind, in the drawing's own coordinates.
    struct Sample {
        let point: CGPoint
        let towardDeg: Double
        let speedMs: Double
    }

    /// An arrow to draw, and whether it stands on land.
    struct Arrow {
        let at: CGPoint
        let towardDeg: Double
        let speedMs: Double
        let ashore: Bool
    }

    /// Screen points between arrows: more arrows as the view zooms in, fewer out.
    static let spacing: CGFloat = 60
    /// Over this much land past the shore the lake's wind fades into the land's,
    /// so the two forecasts meet without a step.
    static let blendM = 1000.0

    /// The shore as line pieces, to tell how far a point on land lies from it.
    struct Shore {
        let segments: [(CGPoint, CGPoint)]
        let bounds: CGRect

        init(rings: [[CGPoint]]) {
            segments = rings.flatMap { ring in zip(ring, ring.dropFirst() + ring.prefix(1)).map { ($0, $1) } }
            bounds = segments.reduce(CGRect.null) { $0.union(CGRect(origin: $1.0, size: .zero)).union(CGRect(origin: $1.1, size: .zero)) }
        }

        /// How far `p` is from the shore, or nil when farther than `limit`.
        func distance(to p: CGPoint, within limit: CGFloat) -> CGFloat? {
            guard bounds.insetBy(dx: -limit, dy: -limit).contains(p) else { return nil }
            var best = limit * limit
            var found = false
            for (a, b) in segments {
                let dx = b.x - a.x, dy = b.y - a.y
                let length = dx * dx + dy * dy
                let t = length > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1) : 0
                let ex = a.x + t * dx - p.x, ey = a.y + t * dy - p.y
                let d = ex * ex + ey * ey
                if d <= best { best = d; found = true }
            }
            return found ? best.squareRoot() : nil
        }
    }

    /// Arrow length on screen: longer in stronger wind.
    static func length(_ speedMs: Double) -> CGFloat { 14 + CGFloat(min(max(speedMs, 0), 15)) * 1.6 }

    /// The arrows in `area`, `spacing` apart in the drawing's units and fixed to
    /// its coordinates, so map tiles and redraws agree; every other row is
    /// shifted by half, so the arrows don't line up in columns. On the water the
    /// wind comes from the lake's forecast points, on land from `land` (the wind
    /// map's forecast); without it, land gets no arrows. Within `blend` of the
    /// `shore` the land's wind fades in from the lake's.
    static func arrows(in area: CGRect, spacing: CGFloat, water: CGPath, from samples: [Sample],
                       land: ((CGPoint) -> (towardDeg: Double, speedMs: Double)?)? = nil,
                       shore: Shore? = nil, blend: CGFloat = 0) -> [Arrow] {
        guard !samples.isEmpty, !area.isNull, !area.isEmpty, spacing > 0 else { return [] }
        var out: [Arrow] = []
        var y = (area.minY / spacing).rounded(.down) * spacing + spacing / 2
        while y < area.maxY {
            let shift: CGFloat = Int((y / spacing).rounded(.down)) % 2 == 0 ? 0 : spacing / 2
            var x = ((area.minX - shift) / spacing).rounded(.down) * spacing + shift + spacing / 2
            while x < area.maxX {
                let p = CGPoint(x: x, y: y)
                let onWater = water.contains(p, using: .evenOdd)
                if let wind = onWater ? wind(at: p, from: samples) : landWind(at: p, land, shore, blend, samples) {
                    out.append(Arrow(at: p, towardDeg: wind.towardDeg, speedMs: wind.speedMs, ashore: !onWater))
                }
                x += spacing
            }
            y += spacing
        }
        return out
    }

    /// The land's wind at `p`, faded in from the lake's over `blend` from the shore.
    private static func landWind(at p: CGPoint, _ land: ((CGPoint) -> (towardDeg: Double, speedMs: Double)?)?,
                                 _ shore: Shore?, _ blend: CGFloat, _ samples: [Sample]) -> (towardDeg: Double, speedMs: Double)? {
        guard let far = land?(p) else { return nil }
        guard blend > 0, let d = shore?.distance(to: p, within: blend), let lake = wind(at: p, from: samples) else { return far }
        return mix(lake, far, Double(d / blend))
    }

    /// `a` and `b` mixed, `t` of the way to `b`: directions as east and north parts, speeds in between.
    static func mix(_ a: (towardDeg: Double, speedMs: Double), _ b: (towardDeg: Double, speedMs: Double), _ t: Double)
        -> (towardDeg: Double, speedMs: Double) {
        let ra = a.towardDeg * .pi / 180, rb = b.towardDeg * .pi / 180
        let east = sin(ra) * (1 - t) + sin(rb) * t, north = cos(ra) * (1 - t) + cos(rb) * t
        let toward = east == 0 && north == 0 ? b.towardDeg : atan2(east, north) * 180 / .pi
        return ((toward + 360).truncatingRemainder(dividingBy: 360), a.speedMs * (1 - t) + b.speedMs * t)
    }

    /// The wind on the lake, from the forecast points weighted by
    /// distance (nearer counts more), averaged as east and north parts so
    /// opposite directions don't add up to a wrong one.
    static func wind(at p: CGPoint, from samples: [Sample]) -> (towardDeg: Double, speedMs: Double)? {
        guard !samples.isEmpty else { return nil }
        var east = 0.0, north = 0.0, speed = 0.0, total = 0.0
        for s in samples {
            let dx = Double(s.point.x - p.x), dy = Double(s.point.y - p.y)
            let w = 1 / max(dx * dx + dy * dy, 1)
            let r = s.towardDeg * .pi / 180
            east += sin(r) * w
            north += cos(r) * w
            speed += s.speedMs * w
            total += w
        }
        let toward = atan2(east, north) * 180 / .pi
        return ((toward + 360).truncatingRemainder(dividingBy: 360), speed / total)
    }
}
