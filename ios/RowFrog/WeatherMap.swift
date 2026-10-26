import MapKit
import SwiftUI

/// The values the weather map can show. The model maps come from DWD's
/// ICON-D2 grid, which the publish job cuts into tiles around the clubs
/// (maps/index and maps/<tile>/<value>); lightning, fog and UV come live from
/// DWD's and EUMETSAT's map servers, like the rain radar.
enum WeatherMapLayer: String, CaseIterable, Identifiable {
    case wind, gust, temperature, feelsLike, humidity, pressure, visibility, rain, uv, lightning, fog
    var id: String { rawValue }

    var title: String {
        switch self {
        case .wind: tr("Wind")
        case .gust: tr("Gusts")
        case .temperature: tr("Air temperature")
        case .feelsLike: tr("Feels like")
        case .humidity: tr("Humidity")
        case .pressure: tr("Air pressure")
        case .visibility: tr("Visibility")
        case .rain: tr("Rain forecast")
        case .uv: tr("UV index")
        case .lightning: tr("Lightning")
        case .fog: tr("Fog and low cloud")
        }
    }

    var symbol: String {
        switch self {
        case .wind: Condition.wind.symbol
        case .gust: "wind.snow"
        case .temperature: Condition.temperature.symbol
        case .feelsLike: Condition.feelsLike.symbol
        case .humidity: Condition.humidity.symbol
        case .pressure: Condition.pressure.symbol
        case .visibility: Condition.visibility.symbol
        case .rain: Condition.precipitation.symbol
        case .uv: Condition.uvIndex.symbol
        case .lightning: Condition.thunderstorm.symbol
        case .fog: "cloud.fog"
        }
    }

    /// The file name of a model map; nil for the live layers.
    var modelValue: String? {
        switch self {
        case .wind, .gust, .temperature, .feelsLike, .humidity, .pressure, .visibility, .rain: rawValue
        case .uv, .lightning, .fog: nil
        }
    }

    /// How much map a view opens with, in km across: the lake and its shores for
    /// the values there; more for rain and lightning, to see them coming from upwind.
    var startSpanKm: Double {
        switch self {
        case .rain, .lightning: 120
        default: 50
        }
    }

    /// How the map follows a chart's time: the model maps hour by hour, UV by
    /// day; lightning and fog show the past and keep their own time.
    enum Link { case hour, day, none }

    var links: Link {
        switch self {
        case .uv: .day
        case .lightning, .fog: .none
        default: .hour
        }
    }

    /// Which of `frames` to show for a time: the nearest hour, or for UV the
    /// day the time falls in.
    func frame(in frames: [Date], for time: Date) -> Int? {
        if links == .day, let i = frames.lastIndex(where: { $0 <= time }) { return i }
        return frames.indices.min { abs(frames[$0].timeIntervalSince(time)) < abs(frames[$1].timeIntervalSince(time)) }
    }

    /// The map a detail view opens.
    init?(condition: Condition) {
        switch condition {
        case .wind: self = .wind
        case .temperature: self = .temperature
        case .feelsLike: self = .feelsLike
        case .humidity: self = .humidity
        case .pressure: self = .pressure
        case .visibility, .cloudCover: self = .visibility
        case .uvIndex: self = .uv
        case .thunderstorm: self = .lightning
        default: return nil
        }
    }

    /// Colours by value, in the backend's units (°C, m/s, %, hPa, km).
    var palette: MapPalette? {
        switch self {
        case .temperature, .feelsLike:
            MapPalette([(-20, 0x5B2A86, 0.75), (-10, 0x2F5DD8, 0.7), (0, 0x8EC5F2, 0.6), (5, 0x7FD3B8, 0.55),
                        (10, 0x9BD565, 0.55), (15, 0xE8E05A, 0.6), (20, 0xF5B341, 0.62), (25, 0xF07C2E, 0.66),
                        (30, 0xE0442B, 0.7), (38, 0x9E1B3B, 0.75)])
        case .wind, .gust:
            MapPalette([(0, 0xBFE6F5, 0.15), (2, 0x9FD9E8, 0.35), (4, 0x7FD3A2, 0.5), (6, 0xD8E05A, 0.6),
                        (8, 0xF5B341, 0.65), (10, 0xF07C2E, 0.7), (13, 0xE0442B, 0.75), (17, 0xB0306E, 0.8),
                        (24, 0x6A2C8F, 0.85)])
        case .humidity:
            MapPalette([(20, 0xD9A55B, 0.6), (40, 0xEBD9A0, 0.45), (60, 0xBFE0D8, 0.4), (80, 0x6FB7E0, 0.55),
                        (100, 0x2F6FC9, 0.65)])
        case .pressure:
            MapPalette([(975, 0x6A2C8F, 0.65), (990, 0x3D5FD0, 0.6), (1005, 0x7FC3E8, 0.5), (1013, 0xBFE6C8, 0.45),
                        (1020, 0xE8E05A, 0.5), (1030, 0xF5A341, 0.6), (1040, 0xE0602B, 0.65)])
        case .visibility:
            // Fog stands out; good visibility leaves the map clear.
            MapPalette([(0, 0xF2F2F2, 0.9), (0.5, 0xE0E0E6, 0.85), (1, 0xC8C8D4, 0.75), (3, 0xB4B8C8, 0.5),
                        (6, 0xA8B4C8, 0.25), (10, 0xA8B4C8, 0.0)])
        case .rain:
            MapPalette([(0, 0x9FD9F5, 0.0), (0.1, 0x9FD9F5, 0.35), (0.5, 0x5DB6EC, 0.55), (1, 0x2F7FD8, 0.65),
                        (2, 0x2F9E5C, 0.7), (4, 0xE8D23A, 0.75), (8, 0xF07C2E, 0.8), (15, 0xD8302B, 0.85),
                        (25, 0x9E1B6B, 0.9)])
        case .uv, .lightning, .fog: nil
        }
    }

    /// Values marked under the colour bar.
    var legendValues: [Double] {
        switch self {
        case .temperature, .feelsLike: [-10, 0, 10, 20, 30]
        case .wind, .gust: [0, 4, 8, 13, 17, 24]
        case .humidity: [20, 40, 60, 80, 100]
        case .pressure: [990, 1005, 1013, 1020, 1030]
        case .visibility: [0, 1, 3, 6, 10]
        case .rain: [0, 5, 10, 15, 25]
        case .uv, .lightning, .fog: []
        }
    }

    /// A value in the user's units, with or without the unit.
    func text(_ value: Double, unit: Bool = true) -> String {
        switch self {
        case .temperature, .feelsLike: unit ? Format.temperature(value) : Format.degrees(value)
        case .wind, .gust: unit ? Format.wind(value) : Format.windNumber(value)
        case .humidity: unit ? "\(Format.number(value)) %" : Format.number(value)
        case .pressure: unit ? Format.pressure(value) : Format.pressureNumber(value)
        case .visibility: unit ? Format.distance(value * 1000) : Format.distanceNumber(value * 1000)
        case .rain: unit ? Format.rain(value) + tr("/h") : Format.rainNumber(value)
        case .uv, .lightning, .fog: Format.number(value)
        }
    }

    var unitSymbol: String {
        let settings = AppSettings.shared
        return switch self {
        case .temperature, .feelsLike: settings.temperatureUnit.symbol
        case .wind, .gust: settings.windUnit.symbol
        case .humidity: "%"
        case .pressure: settings.pressureUnit.symbol
        case .visibility: settings.distanceUnit.symbol
        case .rain: settings.rainUnit.symbol + tr("/h")
        case .uv, .lightning, .fog: ""
        }
    }

    /// The live layers: map server, layer and the times to show.
    var live: (server: URL, layer: String)? {
        switch self {
        case .lightning: (RadarClient.wms, "dwd:Blitzdichte")
        case .uv: (RadarClient.wms, "dwd:UVIndex")
        case .fog: (URL(string: "https://view.eumetsat.int/geoserver/ows")!, "msg_fes:rgb_fog")
        default: nil
        }
    }

    /// For the live layers: the frames and the one shown first (the latest).
    func liveTimes(now: Date = .now) -> (times: [Date], first: Int) {
        func floored(_ date: Date, minutes: Double) -> Date {
            Date(timeIntervalSince1970: (date.timeIntervalSince1970 / (minutes * 60)).rounded(.down) * minutes * 60)
        }
        switch self {
        case .lightning:
            // NowCastMIX lightning every 5 minutes, about 10 minutes behind: the last hour.
            let last = floored(now.addingTimeInterval(-10 * 60), minutes: 5)
            return (stride(from: -55, through: 0, by: 5).map { last.addingTimeInterval(Double($0) * 60) }, 11)
        case .fog:
            // Meteosat every 15 minutes, about 25 minutes behind: the last 3 hours.
            let last = floored(now.addingTimeInterval(-25 * 60), minutes: 15)
            return (stride(from: -180, through: 0, by: 15).map { last.addingTimeInterval(Double($0) * 60) }, 12)
        default:
            // The day's highest UV index: today and the next two days, as DWD's maps are dated (midnight UTC).
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let today = calendar.startOfDay(for: now)
            return ((0..<3).map { today.addingTimeInterval(Double($0) * 86400) }, 0)
        }
    }

    var credit: String {
        switch self {
        case .fog: tr("Satellite: EUMETSAT, Meteosat")
        case .lightning, .uv: tr("Deutscher Wetterdienst (DWD), CC BY 4.0")
        default: tr("Deutscher Wetterdienst (DWD), ICON-D2, CC BY 4.0")
        }
    }

    var note: String? {
        switch self {
        case .lightning: tr("Lightning in the last 5 minutes, for the past hour.")
        case .fog: tr("Fog and low cloud from the satellite, for the past 3 hours.")
        case .uv: tr("The day's highest UV index under the expected clouds.")
        case .visibility: tr("Grey where fog or low cloud brings the visibility down.")
        case .rain: tr("Rain an hour from the weather model; after the first day, the average of every 3 hours.")
        default: nil
        }
    }
}

/// A colour ramp: values and colours (RGB with opacity), mixed in between.
struct MapPalette {
    struct Stop {
        let value: Double
        let r: Double, g: Double, b: Double, a: Double
    }

    let stops: [Stop]

    init(_ stops: [(Double, Int, Double)]) {
        self.stops = stops.map { value, rgb, alpha in
            Stop(value: value, r: Double((rgb >> 16) & 0xFF) / 255, g: Double((rgb >> 8) & 0xFF) / 255,
                 b: Double(rgb & 0xFF) / 255, a: alpha)
        }
    }

    func stop(at value: Double) -> Stop {
        guard let first = stops.first, let last = stops.last else { return Stop(value: 0, r: 0, g: 0, b: 0, a: 0) }
        if value <= first.value { return first }
        if value >= last.value { return last }
        let i = stops.firstIndex { $0.value >= value }!
        let lo = stops[i - 1], hi = stops[i]
        let f = (value - lo.value) / (hi.value - lo.value)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return Stop(value: value, r: mix(lo.r, hi.r), g: mix(lo.g, hi.g), b: mix(lo.b, hi.b), a: mix(lo.a, hi.a))
    }

    func color(at value: Double) -> Color {
        let s = stop(at: value)
        return Color(red: s.r, green: s.g, blue: s.b).opacity(max(s.a, 0.35))
    }
}

/// A part of the map between two longitudes and two latitudes.
struct MapArea: Hashable {
    var west: Double, east: Double, south: Double, north: Double

    init(west: Double, east: Double, south: Double, north: Double) {
        self.west = west; self.east = east
        // Mercator ends short of the poles.
        self.south = max(south, -85); self.north = min(north, 85)
    }

    /// What a map shows.
    init(_ region: MKCoordinateRegion) {
        self.init(west: region.center.longitude - region.span.longitudeDelta / 2,
                  east: region.center.longitude + region.span.longitudeDelta / 2,
                  south: region.center.latitude - region.span.latitudeDelta / 2,
                  north: region.center.latitude + region.span.latitudeDelta / 2)
    }

    /// About `km` across around a place.
    init(around p: Coordinate, km: Double) {
        let lat = km / 111 / 2, lon = km / (111 * max(cos(p.lat * .pi / 180), 0.2)) / 2
        self.init(west: p.lon - lon, east: p.lon + lon, south: p.lat - lat, north: p.lat + lat)
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2),
                           span: MKCoordinateSpan(latitudeDelta: north - south, longitudeDelta: east - west))
    }

    var mapRect: MKMapRect {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        return MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
    }
}

/// maps/index: the model run, its hours and the tiles.
struct WeatherMapIndex: Decodable {
    let run: Date
    let hours: [Date]
    let columns: Int
    let rows: Int
    let arrowStep: Int
    let tiles: [Tile]
    let values: [String: Encoding]
    let credit: String

    struct Tile: Decodable, Hashable {
        let id: String
        let west: Double, east: Double, south: Double, north: Double

        func contains(_ p: Coordinate) -> Bool { p.lon > west && p.lon < east && p.lat > south && p.lat < north }

        func holds(_ a: MapArea) -> Bool {
            west <= a.west + 1e-6 && east >= a.east - 1e-6 && south <= a.south + 1e-6 && north >= a.north - 1e-6
        }

        func distance(to p: Coordinate) -> Double {
            hypot((west + east) / 2 - p.lon, (south + north) / 2 - p.lat)
        }

        /// The pixel at a place: column from the west, row from the north (rows are even in mercator).
        func pixel(_ p: Coordinate, columns: Int, rows: Int) -> (row: Int, column: Int)? {
            guard contains(p) else { return nil }
            func y(_ lat: Double) -> Double { log(tan(.pi / 4 + lat * .pi / 360)) }
            let column = Int((p.lon - west) / (east - west) * Double(columns))
            let row = Int((y(north) - y(p.lat)) / (y(north) - y(south)) * Double(rows))
            return (min(max(row, 0), rows - 1), min(max(column, 0), columns - 1))
        }
    }

    struct Encoding: Decodable {
        let offset: Double
        let scale: Double
        let unit: String
    }

    /// The tile a place lies most central in.
    func tile(for p: Coordinate) -> Tile? {
        tiles.filter { $0.contains(p) }.min { $0.distance(to: p) < $1.distance(to: p) }
    }

    /// The tiles that draw a visible area, each with the patches it draws. The tiles
    /// overlap by half (6° × 4°, every 3° × 2°), so the area is cut into 1.5° × 1°
    /// patches and each goes to the tile, of those holding it whole, whose centre is
    /// nearest: nothing is drawn twice, and a patch with no tile stays empty. At most
    /// `limit` tiles, those nearest the middle, so zooming far out stays light.
    func cover(_ area: MapArea, limit: Int = 9) -> [(tile: Tile, patches: [MapArea])] {
        // Far out, only the middle 15° × 10° is filled.
        let mid = Coordinate(lat: (area.south + area.north) / 2, lon: (area.west + area.east) / 2)
        let west = max(area.west, mid.lon - 7.5), east = min(area.east, mid.lon + 7.5)
        let south = max(area.south, mid.lat - 5), north = min(area.north, mid.lat + 5)
        var patches: [String: [MapArea]] = [:]
        var lon = (west / 1.5).rounded(.down) * 1.5
        while lon < east {
            var lat = south.rounded(.down)
            while lat < north {
                let patch = MapArea(west: lon, east: lon + 1.5, south: lat, north: lat + 1)
                let centre = Coordinate(lat: lat + 0.5, lon: lon + 0.75)
                if let best = tiles.filter({ $0.holds(patch) }).min(by: { $0.distance(to: centre) < $1.distance(to: centre) }) {
                    patches[best.id, default: []].append(patch)
                }
                lat += 1
            }
            lon += 1.5
        }
        return tiles.filter { patches[$0.id] != nil }
            .sorted { $0.distance(to: mid) < $1.distance(to: mid) }
            .prefix(limit)
            .map { ($0, patches[$0.id] ?? []) }
    }
}

/// One value of one tile for every hour, as bytes.
struct ModelMapGrid {
    let columns: Int
    let rows: Int
    let encoding: WeatherMapIndex.Encoding
    let bytes: [UInt8]

    var hourCount: Int { bytes.count / max(columns * rows, 1) }

    func value(hour: Int, row: Int, column: Int) -> Double? {
        let i = hour * columns * rows + row * columns + column
        guard bytes.indices.contains(i), bytes[i] != 255 else { return nil }
        return encoding.offset + encoding.scale * Double(bytes[i])
    }

    /// The hour coloured, one pixel per grid point; the map smooths it when drawn.
    func image(hour: Int, palette: MapPalette) -> CGImage? {
        guard hour < hourCount else { return nil }
        // The 255 byte values as colours, worked out once.
        let table: [(UInt8, UInt8, UInt8, UInt8)] = (0..<256).map { byte in
            guard byte != 255 else { return (0, 0, 0, 0) }
            let s = palette.stop(at: encoding.offset + encoding.scale * Double(byte))
            // Premultiplied, as the bitmap context expects.
            return (UInt8(s.r * s.a * 255), UInt8(s.g * s.a * 255), UInt8(s.b * s.a * 255), UInt8(s.a * 255))
        }
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let start = hour * columns * rows
        for i in 0..<(columns * rows) {
            let c = table[Int(bytes[start + i])]
            pixels[i * 4] = c.0
            pixels[i * 4 + 1] = c.1
            pixels[i * 4 + 2] = c.2
            pixels[i * 4 + 3] = c.3
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage()
        }
    }
}

/// Loads the model maps: the index (for half an hour) and each value's file
/// for the club's tile, kept while the app runs so switching back never waits.
@Observable
@MainActor
final class ModelMapStore {
    static let shared = ModelMapStore(api: .published())

    private(set) var index: WeatherMapIndex?
    private(set) var grids: [String: ModelMapGrid] = [:]
    private(set) var failed: Set<String> = []
    private(set) var indexFailed = false
    @ObservationIgnored private var indexLoaded: Date?
    let api: APIClient

    nonisolated init(api: APIClient) { self.api = api }

    static func key(_ index: WeatherMapIndex, _ tile: String, _ value: String) -> String {
        "\(index.run.timeIntervalSince1970)|\(tile)|\(value)"
    }

    func loadIndex() async {
        if let indexLoaded, indexLoaded > .now.addingTimeInterval(-30 * 60), index != nil { return }
        do {
            index = try await api.weatherMapIndex()
            indexLoaded = .now
            indexFailed = false
        } catch {
            indexFailed = index == nil
        }
    }

    /// The times a layer has maps for: the model run's hours from the hour now
    /// on (hourly for a day, then every 3 hours), or the live layer's pictures.
    func frames(for layer: WeatherMapLayer, now: Date = .now) -> [Date] {
        if layer.modelValue != nil {
            return index?.hours.filter { $0 > now.addingTimeInterval(-3600) } ?? []
        }
        return layer.liveTimes(now: now).times
    }

    func grid(tile: String, value: String) -> ModelMapGrid? {
        guard let index else { return nil }
        return grids[Self.key(index, tile, value)]
    }

    /// Loads what a model layer needs for the area on screen: the index, the
    /// value's file of each tile there (the club's first) and, for wind and
    /// gusts, the arrows. Zooming out or moving loads the next tiles only then.
    func prepare(_ layer: WeatherMapLayer, at point: Coordinate, area: MapArea) async {
        await loadIndex()
        guard let value = layer.modelValue, let index else { return }
        var ids = index.cover(area).map(\.tile.id)
        if let own = index.tile(for: point)?.id {
            ids.removeAll { $0 == own }
            ids.insert(own, at: 0)
        }
        let values = layer == .wind || layer == .gust ? [value, "windDirection"] : [value]
        for id in ids {
            for v in values { await load(tile: id, value: v) }
        }
    }

    /// The tiles a model layer needs for an area, to load again when they change.
    func tileIDs(for area: MapArea) -> [String] { index?.cover(area).map(\.tile.id) ?? [] }

    /// What the map draws for a model layer at one of its hours: each loaded tile
    /// coloured over its patches and, for wind and gusts, the arrows.
    func overlays(_ layer: WeatherMapLayer, area: MapArea, time: Date) -> [WeatherMapOverlayContent] {
        guard let value = layer.modelValue, let palette = layer.palette, let index,
              let hour = index.hours.firstIndex(of: time) else { return [] }
        return index.cover(area).compactMap { tile, patches in
            guard let values = grid(tile: tile.id, value: value) else { return nil }
            var wind: WindField?
            if layer == .wind || layer == .gust, let directions = grid(tile: tile.id, value: "windDirection") {
                // The arrows' length follows the layer shown: wind, or gusts.
                wind = WindField(directions: directions, speeds: values, hour: hour)
            }
            return WeatherMapOverlayContent(id: "\(tile.id)|\(value)",
                                            northWest: CLLocationCoordinate2D(latitude: tile.north, longitude: tile.west),
                                            southEast: CLLocationCoordinate2D(latitude: tile.south, longitude: tile.east),
                                            image: values.image(hour: hour, palette: palette), smooth: true, wind: wind,
                                            clip: patches)
        }
    }

    func load(tile: String, value: String) async {
        guard let index else { return }
        let key = Self.key(index, tile, value)
        guard grids[key] == nil else { return }
        do {
            let packed = try await api.weatherMapData(tile: tile, value: value)
            let raw = try (packed as NSData).decompressed(using: .zlib) as Data
            guard let encoding = index.values[value] else { return }
            let arrows = value == "windDirection"
            let columns = arrows ? index.columns / index.arrowStep : index.columns
            let rows = arrows ? index.rows / index.arrowStep : index.rows
            grids[key] = ModelMapGrid(columns: columns, rows: rows, encoding: encoding, bytes: [UInt8](raw))
            failed.remove(key)
            // Older runs' files are not needed any more.
            let run = "\(index.run.timeIntervalSince1970)|"
            for old in grids.keys where !old.hasPrefix(run) { grids[old] = nil }
        } catch {
            failed.insert(key)
        }
    }
}

#if !WIDGET_EXTENSION
extension APIClient {
    func weatherMapIndex() async throws -> WeatherMapIndex {
        try Self.decoder.decode(WeatherMapIndex.self, from: try await data("maps/index"))
    }

    func weatherMapData(tile: String, value: String) async throws -> Data {
        try await data("maps/\(tile)/\(value)")
    }

    private func data(_ path: String) async throws -> Data {
        let request = URLRequest(url: url(path), cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPStatusError(code: http.statusCode)
        }
        return data
    }
}
#endif

/// The weather map, full screen: one value over the region around the club,
/// played or slid through time like the rain radar. The model maps go hour by
/// hour up to two days; lightning and fog show the last hours, UV three days.
struct WeatherMapScreen: View {
    let point: Coordinate
    var clubID: String?
    /// The time shown, from outside when a chart and the map follow each other;
    /// nil keeps the map's own time.
    var time: Binding<Date?>?
    @State private var layer: WeatherMapLayer
    @State private var index = 0
    @State private var playing = false
    @State private var live: RadarFrames?
    /// The same repeat switch as the rain radar's: on, playing goes round 3 times.
    @AppStorage("RWRadarLoop") private var loops = true
    @Environment(\.dismiss) private var dismiss
    private let store = ModelMapStore.shared
    private let start: Date?
    /// Shown above the map's controls, e.g. a slim chart that moves with the map.
    private let chart: AnyView?
    /// The area it opens with, and the area on screen now.
    private let startArea: MapArea
    @State private var area: MapArea

    init(point: Coordinate, clubID: String? = nil, layer: WeatherMapLayer, start: Date? = nil, time: Binding<Date?>? = nil,
         chart: AnyView? = nil) {
        self.point = point
        self.clubID = clubID
        self.start = start
        self.time = time
        self.chart = chart
        _layer = State(initialValue: layer)
        startArea = MapArea(around: point, km: layer.startSpanKm)
        _area = State(initialValue: startArea)
    }

    /// The hours or pictures the slider goes through.
    private var frames: [Date] {
        layer.modelValue != nil ? store.frames(for: layer) : live?.times ?? []
    }

    private var tile: WeatherMapIndex.Tile? { store.index?.tile(for: point) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WeatherMapView(point: point, clubID: clubID, overlays: overlays, start: startArea) { area = $0 }
                    .ignoresSafeArea(edges: .bottom)
                controls
            }
            .navigationTitle(layer.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { layerMenu }
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
            .task(id: layer) { await load() }
            // Zoomed out or moved: the tiles or the wider picture it needs now.
            .task(id: "\(layer.rawValue)|\(store.tileIDs(for: area))") {
                if layer.modelValue != nil { await store.prepare(layer, at: point, area: area) }
            }
            .task(id: area) { await widenLive() }
            .onChange(of: index) { _, i in
                if layer.links != .none, frames.indices.contains(i) { time?.wrappedValue = frames[i] }
            }
            .onChange(of: time?.wrappedValue) { _, date in
                guard layer.links != .none, let date, let i = nearest(to: date), i != index else { return }
                index = i
            }
            .task(id: playing) {
                guard playing else { return }
                if index >= frames.count - 1 { index = 0 }
                // With repeat on it goes round 3 times, as the rain radar does,
                // then stops on the hour it started from.
                let from = index
                var rounds = 0
                while playing, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(index == frames.count - 1 ? 1400 : 700))
                    guard playing, !Task.isCancelled else { return }
                    if index < frames.count - 1 {
                        index += 1
                    } else if loops, rounds < 2 {
                        rounds += 1
                        index = 0
                    } else {
                        playing = false
                        if loops { index = from }
                    }
                }
            }
        }
    }

    private func load() async {
        playing = false
        if layer.modelValue != nil {
            live = nil
            await store.loadIndex()
            index = nearest(to: time?.wrappedValue ?? start ?? .now) ?? 0
            await store.prepare(layer, at: point, area: area)
        } else if let source = layer.live {
            let (times, first) = layer.liveTimes()
            let frames = RadarFrames(point: point, times: times, layer: source.layer, server: source.server, nowIndex: first,
                                     region: RadarRegion.around(point, showing: area))
            live = frames
            index = first
            await frames.load()
        }
    }

    /// A live layer zoomed out or moved past its pictures: pictures of the area on screen.
    private func widenLive() async {
        guard let live, let source = layer.live, !live.region.covers(area) else { return }
        let frames = RadarFrames(point: point, times: live.times, layer: source.layer, server: source.server,
                                 nowIndex: live.nowIndex, region: RadarRegion(covering: area))
        self.live = frames
        await frames.load()
    }

    private func nearest(to date: Date) -> Int? { layer.frame(in: frames, for: date) }

    /// What the map draws: the coloured tiles and arrows, or the live picture.
    private var overlays: [WeatherMapOverlayContent] {
        guard frames.indices.contains(index) else { return [] }
        if layer.modelValue != nil { return store.overlays(layer, area: area, time: frames[index]) }
        return live.map { [$0.overlay(at: frames[index])] } ?? []
    }

    private var layerMenu: some View {
        Menu {
            Picker(tr("Show"), selection: $layer) {
                ForEach(WeatherMapLayer.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
        } label: {
            Label(tr("Show"), systemImage: "square.3.layers.3d")
        }
        .accessibilityLabel(tr("Choose what the map shows"))
    }

    /// The value at the club in the hour shown.
    private var valueAtClub: String? {
        guard let value = layer.modelValue, let tile, let index = store.index, frames.indices.contains(self.index),
              let grid = store.grid(tile: tile.id, value: value),
              let pixel = tile.pixel(point, columns: index.columns, rows: index.rows),
              let hour = index.hours.firstIndex(of: frames[self.index]),
              let v = grid.value(hour: hour, row: pixel.row, column: pixel.column) else { return nil }
        return layer.text(v)
    }

    private var loading: Bool {
        if layer.modelValue != nil {
            guard let tile, let value = layer.modelValue, store.index != nil else { return !store.indexFailed }
            return store.grid(tile: tile.id, value: value) == nil && !(store.index.map { store.failed.contains(ModelMapStore.key($0, tile.id, value)) } ?? false)
        }
        return !(live?.done ?? true)
    }

    private var problem: String? {
        if layer.modelValue != nil {
            if store.indexFailed { return tr("The map could not be loaded.") }
            if store.index != nil, tile == nil { return tr("No map for this place yet.") }
            if let tile, let value = layer.modelValue, let index = store.index,
               store.failed.contains(ModelMapStore.key(index, tile.id, value)) { return tr("The map could not be loaded.") }
            return nil
        }
        if let live, live.done, live.images.isEmpty { return tr("The map could not be loaded.") }
        return nil
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let chart { chart }
            HStack(alignment: .firstTextBaseline) {
                if frames.indices.contains(index) {
                    Text(layer == .uv ? Format.day(frames[index]) : Format.dayTime(frames[index]))
                        .font(.headline.monospacedDigit())
                }
                if let valueAtClub {
                    Label(valueAtClub, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(tr("At the club: %@", valueAtClub))
                }
                Spacer()
                if loading { ProgressView().accessibilityLabel(tr("Loading the map")) }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            if let palette = layer.palette {
                WeatherMapColourBar(layer: layer, palette: palette)
            }
            if let note = layer.note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            if frames.count > 1 {
                HStack(spacing: 12) {
                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.title3)
                    }
                    .accessibilityLabel(playing ? tr("Pause") : tr("Play"))
                    Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()); playing = false }),
                           in: 0...Double(frames.count - 1), step: 1)
                    Button {
                        loops.toggle()
                    } label: {
                        Image(systemName: "repeat")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(loops ? Color.accentColor : .secondary)
                            .padding(6)
                            .background(loops ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel(tr("Play 3 times"))
                    .accessibilityAddTraits(loops ? .isSelected : [])
                }
            }
            Text(layer.credit).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

extension RadarFrames {
    /// A live layer's picture at one of its times, for the weather map.
    func overlay(at time: Date) -> WeatherMapOverlayContent {
        // A wider picture is a new overlay.
        WeatherMapOverlayContent(id: "\(layer)|\(region.minX)|\(region.maxX)", northWest: region.northWest, southEast: region.southEast,
                                 image: images[time]?.cgImage, smooth: false)
    }
}

/// The weather map without controls, at the frame nearest a given time: for a
/// card whose chart moves the map. Model maps follow the hour, UV the day;
/// lightning and fog stay on their latest picture (`WeatherMapLayer.links`).
struct WeatherMapPanel: View {
    let point: Coordinate
    var clubID: String?
    let layer: WeatherMapLayer
    let time: Date
    @State private var live: RadarFrames?
    private let store = ModelMapStore.shared
    /// The area it opens with, and the area on screen now.
    private let startArea: MapArea
    @State private var area: MapArea

    init(point: Coordinate, clubID: String? = nil, layer: WeatherMapLayer, time: Date) {
        self.point = point
        self.clubID = clubID
        self.layer = layer
        self.time = time
        startArea = MapArea(around: point, km: layer.startSpanKm)
        _area = State(initialValue: startArea)
    }

    /// The frame shown: the one nearest `time`, or the latest for layers that do not follow it.
    private var shown: Date? {
        let frames = layer.modelValue != nil ? store.frames(for: layer) : live?.times ?? []
        if layer.links == .none, let live, live.times.indices.contains(live.nowIndex) { return live.times[live.nowIndex] }
        return layer.frame(in: frames, for: time).map { frames[$0] }
    }

    var body: some View {
        WeatherMapView(point: point, clubID: clubID, overlays: shown.map { date in
            layer.modelValue != nil ? store.overlays(layer, area: area, time: date) : live.map { [$0.overlay(at: date)] } ?? []
        } ?? [], start: startArea) { area = $0 }
        .task(id: layer) {
            if layer.modelValue != nil {
                live = nil
            } else if let source = layer.live {
                let (times, first) = layer.liveTimes()
                let frames = RadarFrames(point: point, times: times, layer: source.layer, server: source.server, nowIndex: first,
                                         region: RadarRegion.around(point, showing: area))
                live = frames
                await frames.load()
            }
        }
        // The club's tile first, then the tiles a zoom or move brings in.
        .task(id: "\(layer.rawValue)|\(store.tileIDs(for: area))") {
            if layer.modelValue != nil { await store.prepare(layer, at: point, area: area) }
        }
        .task(id: area) {
            // A live layer zoomed out or moved past its pictures: pictures of the area on screen.
            guard let live, let source = layer.live, !live.region.covers(area) else { return }
            let frames = RadarFrames(point: point, times: live.times, layer: source.layer, server: source.server,
                                     nowIndex: live.nowIndex, region: RadarRegion(covering: area))
            self.live = frames
            await frames.load()
        }
        .accessibilityLabel(layer.title)
    }
}

/// The colours and what they stand for, in the user's units.
private struct WeatherMapColourBar: View {
    let layer: WeatherMapLayer
    let palette: MapPalette

    var body: some View {
        let values = layer.legendValues
        VStack(spacing: 2) {
            LinearGradient(stops: stride(from: 0.0, through: 1.0, by: 0.05).map { f in
                let lo = values.first ?? 0, hi = values.last ?? 1
                return .init(color: palette.color(at: lo + (hi - lo) * f), location: f)
            }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(Capsule())
            GeometryReader { geo in
                let lo = values.first ?? 0, hi = values.last ?? 1
                ForEach(values, id: \.self) { v in
                    Text(layer.text(v, unit: false))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: min(max(geo.size.width * (v - lo) / (hi - lo), 10), geo.size.width - 10), y: 6)
                }
            }
            .frame(height: 12)
            HStack {
                Spacer()
                Text(layer.unitSymbol).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Colours from %@ to %@", layer.text(values.first ?? 0), layer.text(values.last ?? 0)))
    }
}

/// What lies on the map: one picture over its corners, and wind arrows.
struct WeatherMapOverlayContent {
    /// Changes when the area or value changes, so the overlay is laid anew.
    let id: String
    let northWest: CLLocationCoordinate2D
    let southEast: CLLocationCoordinate2D
    let image: CGImage?
    /// Smoothed between grid points (model maps), or sharp (pictures from a map server).
    let smooth: Bool
    var wind: WindField? = nil
    /// The patches drawn (where tiles overlap); empty draws the whole picture.
    var clip: [MapArea] = []
}

/// The wind of one hour over a tile, for arrows at any zoom: directions at the
/// arrow points (every arrowStep pixels) and speeds at every pixel, blended
/// between the grid points.
struct WindField {
    let directions: ModelMapGrid
    let speeds: ModelMapGrid
    let hour: Int

    /// Where the wind blows to (degrees) and its speed (m/s), at a share of the tile's width and height.
    func sample(x: Double, y: Double) -> (towards: Double, speed: Double)? {
        // Directions are blended as east and north parts, so opposite ones don't add up to a wrong one.
        let parts = blend(directions, x, y) { from in
            let r = (from + 180) * .pi / 180
            return (sin(r), cos(r))
        }
        guard let parts, parts.0 != 0 || parts.1 != 0,
              let speed = blend(speeds, x, y, { ($0, 0) })?.0 else { return nil }
        return (atan2(parts.0, parts.1) * 180 / .pi, speed)
    }

    private func blend(_ grid: ModelMapGrid, _ x: Double, _ y: Double, _ parts: (Double) -> (Double, Double)) -> (Double, Double)? {
        let gx = x * Double(grid.columns) - 0.5, gy = y * Double(grid.rows) - 0.5
        let c0 = Int(gx.rounded(.down)), r0 = Int(gy.rounded(.down))
        let tx = gx - Double(c0), ty = gy - Double(r0)
        var sum = (0.0, 0.0), total = 0.0
        for (dr, wy) in [(0, 1 - ty), (1, ty)] {
            for (dc, wx) in [(0, 1 - tx), (1, tx)] {
                let r = min(max(r0 + dr, 0), grid.rows - 1), c = min(max(c0 + dc, 0), grid.columns - 1)
                guard let value = grid.value(hour: hour, row: r, column: c) else { continue }
                let w = wx * wy, p = parts(value)
                sum.0 += w * p.0
                sum.1 += w * p.1
                total += w
            }
        }
        return total > 0 ? (sum.0 / total, sum.1 / total) : nil
    }
}

private struct WeatherMapView: UIViewRepresentable {
    let point: Coordinate
    var clubID: String?
    let overlays: [WeatherMapOverlayContent]
    /// The area it opens with (`WeatherMapLayer.startSpanKm` around the club).
    let start: MapArea
    /// The area on screen after each zoom or move, to load what it needs.
    var onArea: ((MapArea) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(start.region, animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        map.addAnnotation(pin)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onArea = onArea
        coordinator.pending = Dictionary(overlays.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A tile or picture no longer wanted goes; a new one gets its overlay;
        // one already there only changes its picture, so nothing flashes.
        for (id, area) in coordinator.areas where coordinator.pending[id] == nil {
            map.removeOverlay(area)
            coordinator.areas[id] = nil
            coordinator.renderers[id] = nil
        }
        for overlay in overlays {
            if let renderer = coordinator.renderers[overlay.id] {
                renderer.show(overlay)
            } else if coordinator.areas[overlay.id] == nil {
                let area = WeatherMapArea(id: overlay.id, northWest: overlay.northWest, southEast: overlay.southEast)
                coordinator.areas[overlay.id] = area
                map.addOverlay(area, level: .aboveRoads)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(symbol: LocationStore.markSymbol(for: clubID)) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let symbol: String
        var areas: [String: WeatherMapArea] = [:]
        var renderers: [String: WeatherMapRenderer] = [:]
        var pending: [String: WeatherMapOverlayContent] = [:]
        var onArea: ((MapArea) -> Void)?

        init(symbol: String) { self.symbol = symbol }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let overlay = overlay as? WeatherMapArea else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = WeatherMapRenderer(overlay: overlay)
            if let content = pending[overlay.id] { renderer.show(content) }
            renderers[overlay.id] = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            onArea?(MapArea(mapView.region))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.glyphImage = UIImage(systemName: symbol)
            view.markerTintColor = .systemBlue
            view.displayPriority = .required
            return view
        }
    }
}

/// Where a weather map's picture lies.
final class WeatherMapArea: NSObject, MKOverlay {
    let id: String
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(id: String, northWest: CLLocationCoordinate2D, southEast: CLLocationCoordinate2D) {
        self.id = id
        let nw = MKMapPoint(northWest), se = MKMapPoint(southEast)
        boundingMapRect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
    }
}

/// Draws the picture over its area and the wind arrows on top.
final class WeatherMapRenderer: MKOverlayRenderer {
    private var image: CGImage?
    private var smooth = false
    private var wind: WindField?
    private var clip: [MapArea] = []

    func show(_ content: WeatherMapOverlayContent) {
        clip = content.clip
        // A frame still loading keeps the last picture rather than an empty map.
        if content.image == nil, image != nil { setNeedsDisplay(); return }
        image = content.image
        smooth = content.smooth
        wind = content.wind
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let rect = self.rect(for: overlay.boundingMapRect)
        // Only its own patches, where tiles overlap.
        context.saveGState()
        defer { context.restoreGState() }
        if !clip.isEmpty {
            for patch in clip { context.addRect(self.rect(for: patch.mapRect)) }
            context.clip()
        }
        if let image {
            // Core Graphics draws images upside down in the map's flipped context.
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = smooth ? .high : .none
            context.setAlpha(smooth ? 1 : 0.75)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        }
        guard let wind else { return }
        // Arrows on an even grid fixed to the map, as on the lake map: more as the map
        // zooms in, fewer out, each from the wind blended between the model's points.
        let spacing = LakeRenderer.arrowSpacing / zoomScale
        let margin = LakeRenderer.arrowLength(15) / zoomScale
        let area = rect.intersection(self.rect(for: mapRect).insetBy(dx: -margin, dy: -margin))
        guard !area.isNull, rect.width > 0, rect.height > 0 else { return }
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(2 / zoomScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        var gx = (area.minX / spacing).rounded(.up) * spacing
        while gx <= area.maxX {
            var gy = (area.minY / spacing).rounded(.up) * spacing
            while gy <= area.maxY {
                defer { gy += spacing }
                guard let sample = wind.sample(x: (gx - rect.minX) / rect.width, y: (gy - rect.minY) / rect.height),
                      sample.speed >= 0.5 else { continue }
                // Longer in stronger wind, as on the lake map.
                let length = LakeRenderer.arrowLength(sample.speed) / zoomScale
                let angle = sample.towards * .pi / 180
                // North is up: the arrow points along (sin, −cos).
                let dx = sin(angle) * length / 2, dy = -cos(angle) * length / 2
                let tip = CGPoint(x: gx + dx, y: gy + dy)
                context.move(to: CGPoint(x: gx - dx, y: gy - dy))
                context.addLine(to: tip)
                let head = min(length * 0.35, 8 / zoomScale)
                for side in [-1.0, 1.0] {
                    let a = angle + .pi + side * 0.5
                    context.move(to: tip)
                    context.addLine(to: CGPoint(x: tip.x + sin(a) * head, y: tip.y - cos(a) * head))
                }
            }
            gx += spacing
        }
        context.strokePath()
    }
}
