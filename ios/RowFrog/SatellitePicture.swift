import MapKit
import SwiftUI

/// Sentinel-2 pictures of a lake, published by the backend
/// (backend/rowfrog/sources/sentinel2.py, scripts/publish_static.py) next to
/// the lake view: lakes/<id>/satellite describes them, the pictures lie beside it.
struct SatellitePicture: Decodable, Hashable {
    /// One picture: the day of the pass and how much of the lake was under cloud.
    struct Shot: Decodable, Hashable {
        /// Calendar day, "yyyy-MM-dd".
        let date: String
        /// Share of the lake under cloud, 0...1.
        let lakeCloud: Double
        /// File name beside the description, e.g. "satellite-latest.jpg".
        let image: String
        /// Big lakes in use: the folder of this pass's 10 m tiles ("<row>-<col>.jpg").
        var tiles: String?
        /// The three biggest lakes: a 2500 px picture for the full view, before the tiles.
        var overview: String?

        var day: Date? { SatellitePicture.parser.date(from: date) }
    }

    /// Winter only: the satellite ice map of the lake, drawn over the picture.
    struct IceMap: Decodable, Hashable {
        let date: String
        let seenShare: Double
        let iceShare: Double
        /// West, south, east, north.
        let bbox: [Double]
        let image: String
    }

    /// Big lakes in use: the picture at Sentinel-2's own 10 m, as tiles over
    /// the same box, `tile` pixels square (smaller along the right and bottom).
    struct Sharp: Decodable, Hashable {
        let width: Int
        let height: Int
        let tile: Int
        let rows: Int
        let columns: Int

        /// Where tile (row, column) lies in a picture of `size`.
        func rect(row: Int, column: Int, in size: CGSize) -> CGRect {
            let x0 = CGFloat(column * tile) / CGFloat(width), x1 = CGFloat(min(width, (column + 1) * tile)) / CGFloat(width)
            let y0 = CGFloat(row * tile) / CGFloat(height), y1 = CGFloat(min(height, (row + 1) * tile)) / CGFloat(height)
            return CGRect(x: x0 * size.width, y: y0 * size.height, width: (x1 - x0) * size.width, height: (y1 - y0) * size.height)
        }
    }

    /// The area both pictures show: west, south, east, north.
    var bbox: [Double]?
    var width: Int?
    var height: Int?
    /// The newest pass, however cloudy.
    var latest: Shot?
    /// In cloudy weeks: a newer pass than the clearest with most of the lake free of cloud.
    var mostlyClear: Shot?
    /// The newest pass with the lake (nearly) free of cloud.
    var clearest: Shot?
    var ice: IceMap?
    var attribution: String?
    var sharp: Sharp?

    /// The picture's frame, short: it changes when the frame does (a small water
    /// shown wider, a corrected outline), so a copy kept for the same day but the
    /// old frame is never shown under the new frame's shore line.
    var frameKey: String? {
        guard let bbox, let width, let height else { return nil }
        let text = bbox.map { String(format: "%.5f", $0) }.joined(separator: ",") + "|\(width)x\(height)"
        // FNV-1a: the same on every run, unlike hashValue.
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(format: "%08x", hash)
    }

    var aspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 1.6 }
        return CGFloat(width) / CGFloat(height)
    }

    /// The pictures to choose from, each a different pass.
    var kinds: [Kind] {
        var dates: Set<String> = []
        return Kind.allCases.filter { kind in
            guard let shot = shot(kind, fallback: false) else { return false }
            return dates.insert(shot.date).inserted
        }
    }

    var hasChoice: Bool { kinds.count > 1 }

    func shot(_ kind: Kind, fallback: Bool = true) -> Shot? {
        let own: Shot? = switch kind {
        case .latest: latest
        case .mostlyClear: mostlyClear
        case .clearest: clearest
        }
        return fallback ? own ?? latest ?? clearest : own
    }

    enum Kind: String, CaseIterable, Identifiable {
        case latest, mostlyClear, clearest
        var id: String { rawValue }
    }

    fileprivate static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Satellite pictures change every few days at most, so one load per lake and app start is enough.
@MainActor
@Observable
final class SatellitePictureStore {
    static let shared = SatellitePictureStore(api: .published())

    private(set) var pictures: [String: SatellitePicture] = [:]
    private(set) var missing: Set<String> = []
    let api: APIClient

    nonisolated init(api: APIClient) { self.api = api }

    func load(_ lakeID: String) async {
        guard pictures[lakeID] == nil, !missing.contains(lakeID) else { return }
        await fetch(lakeID)
    }

    /// Pull to refresh: asks again for the lake's list of passes. Only the pictures
    /// of a new pass download; one already here keeps its address (its day) and so
    /// comes from memory or the cache folder.
    func refresh(_ lakeID: String) async {
        missing.remove(lakeID)
        await fetch(lakeID)
    }

    private func fetch(_ lakeID: String) async {
        do {
            let picture = try await api.satellitePicture(lakeID: lakeID)
            if picture.latest != nil || picture.clearest != nil {
                pictures[lakeID] = picture
                // Fetch all of them now, so switching between them never waits;
                // when saving data, only the one asked for (see `mayDownload`).
                for kind in picture.kinds where !DataSaver.shared.saving {
                    if let shot = picture.shot(kind), let url = url(lakeID, file: shot.image, date: shot.date) {
                        Task { await image(url) }
                    }
                }
            } else if pictures[lakeID] == nil {
                missing.insert(lakeID)
            }
        } catch let error as URLError where error.code != .badServerResponse {
            // Offline or a timeout: try again the next time the page opens. A lake
            // without pictures answers 404 (badServerResponse) and stays missing.
        } catch {
            // A refresh that fails keeps the pictures already shown.
            if pictures[lakeID] == nil { missing.insert(lakeID) }
        }
    }

    /// A file's address; the day it shows and the picture's frame keep caches
    /// from showing an older one.
    func url(_ lakeID: String, file: String, date: String) -> URL? {
        var components = URLComponents(url: api.url("lakes/\(lakeID)/\(file)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "d", value: date)]
        if let frame = pictures[lakeID]?.frameKey { components?.queryItems?.append(.init(name: "f", value: frame)) }
        return components?.url
    }

    /// Pictures already shown in this run of the app, by address.
    private(set) var images: [URL: UIImage] = [:]
    private var loading: Set<URL> = []
    /// Lakes whose pictures the user asked for while the app saves data.
    private(set) var allowedLakes: Set<String> = []

    /// How bright each part of a shown picture is, for marks that must stand out from it.
    @ObservationIgnored private var brightnessMaps: [URL: PictureBrightness] = [:]

    /// The brightness of a picture already in memory; nil until it has loaded.
    func brightness(_ url: URL) -> PictureBrightness? {
        if let map = brightnessMaps[url] { return map }
        guard let image = images[url], let map = PictureBrightness(image) else { return nil }
        brightnessMaps[url] = map
        return map
    }

    /// Decoded tiles, which take 4 MB each: only as many as the cache holds,
    /// so panning around Bodensee doesn't fill the memory.
    private let tiles: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 96 << 20
        return cache
    }()
    private var tileLoads: [URL: Task<UIImage?, Never>] = [:]

    /// A tile's address.
    func tileURL(_ lakeID: String, shot: SatellitePicture.Shot, row: Int, column: Int) -> URL? {
        guard let folder = shot.tiles else { return nil }
        return url(lakeID, file: "\(folder)/\(row)-\(column).jpg", date: shot.date)
    }

    /// A 10 m tile, from memory, the cache folder or the server, decoded for drawing.
    func tile(_ url: URL) async -> UIImage? {
        if let image = tiles.object(forKey: url as NSURL) { return image }
        if let load = tileLoads[url] { return await load.value }
        let file = Self.cacheFile(for: url)
        let load = Task<UIImage?, Never> {
            var data = try? Data(contentsOf: file)
            if data == nil, let (fetched, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                Self.store(fetched, at: file)
                data = fetched
            }
            guard let data, let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        tileLoads[url] = load
        let image = await load.value
        tileLoads[url] = nil
        if let image {
            tiles.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        }
        return image
    }

    /// Whether a picture may come from the server: always, unless the app saves
    /// data (DataSaver) and the user has not tapped to load this lake's pictures.
    func mayDownload(_ lakeID: String) -> Bool {
        !DataSaver.shared.saving || allowedLakes.contains(lakeID)
    }

    func allowDownloads(_ lakeID: String) { allowedLakes.insert(lakeID) }

    /// Whether the picture is here without a download: in memory or in the cache folder.
    func isKept(_ url: URL) -> Bool {
        images[url] != nil || FileManager.default.fileExists(atPath: Self.cacheFile(for: url).path)
    }

    /// A picture from memory, from the phone's cache folder or, the first time
    /// for that day's pass, from the server. A file's address names its day, so a
    /// kept copy never goes stale: a new pass has a new address.
    /// With `download` false only memory and the cache folder are looked at.
    @discardableResult
    func image(_ url: URL, download: Bool = true) async -> UIImage? {
        if let image = images[url] { return image }
        guard loading.insert(url).inserted else { return nil }
        defer { loading.remove(url) }
        let file = Self.cacheFile(for: url)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            images[url] = image
            return image
        }
        guard download else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        images[url] = image
        Self.store(data, at: file)
        return image
    }

    /// The picture for a background: the clearest pass (else the mostly clear
    /// or latest one). Until the lake's list has loaded, the copy kept from an
    /// earlier run, so a background shows at once. Starts the loading when
    /// needed; views that call this redraw once the picture is in.
    func backgroundImage(_ lakeID: String) -> UIImage? {
        if let picture = pictures[lakeID] {
            guard let shot = picture.clearest ?? picture.mostlyClear ?? picture.latest,
                  let url = url(lakeID, file: shot.image, date: shot.date) else { return nil }
            if let image = images[url] { return image }
            Task { await image(url) }
            return nil
        }
        if !missing.contains(lakeID) { Task { await load(lakeID) } }
        return Self.keptImage(lakeID)
    }

    /// The newest kept copy of a lake's clearest picture, from an earlier run.
    private static func keptImage(_ lakeID: String) -> UIImage? {
        let folder = URL.cachesDirectory.appending(path: "Satellite", directoryHint: .isDirectory)
        for file in ["satellite-clearest.jpg", "satellite-mostly-clear.jpg", "satellite-latest.jpg"] {
            let prefix = "\(lakeID)-\(file)-"
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasPrefix(prefix) } ?? []
            if let newest = names.max(), let image = UIImage(contentsOfFile: folder.appending(path: newest).path) { return image }
        }
        return nil
    }

    /// Caches/Satellite/<lake>-<file>-<day>-<frame>, a tile's as
    /// <lake>-<folder>-<row>-<col>.jpg-<day>-<frame>; the system may clear it when space runs low.
    private static func cacheFile(for url: URL) -> URL {
        let folder = URL.cachesDirectory.appending(path: "Satellite", directoryHint: .isDirectory)
        let path = url.pathComponents
        let parts = path[((path.lastIndex(of: "lakes") ?? path.count - 3) + 1)...].joined(separator: "-")
        let version = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap(\.value)
        return folder.appending(path: "\(parts)-\(version.joined(separator: "-"))")
    }

    /// Saves a picture and drops older passes of the same lake and file.
    private static func store(_ data: Data, at file: URL) {
        let folder = file.deletingLastPathComponent()
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // "<lake>-<file>-" without the day and frame, which have no dot: up to the
        // first "-" after the file's extension.
        let name = file.lastPathComponent
        if let dot = name.lastIndex(of: "."), let dash = name[dot...].firstIndex(of: "-") {
            let prefix = String(name[...dash])
            for old in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where old.hasPrefix(prefix) {
                try? manager.removeItem(at: folder.appending(path: old))
            }
        }
        try? data.write(to: file, options: .atomic)
    }
}

/// A satellite picture shrunk to a small grey grid, to tell white cloud (and snow)
/// from dark water and land under each mark drawn on it.
struct PictureBrightness {
    let width: Int
    let height: Int
    /// 0 (black) to 255 (white), row by row from the top.
    let values: [UInt8]

    init?(_ image: UIImage, longSide: Int = 128) {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        let scale = Double(longSide) / Double(max(cg.width, cg.height))
        let w = max(1, Int((Double(cg.width) * scale).rounded())), h = max(1, Int((Double(cg.height) * scale).rounded()))
        var values = [UInt8](repeating: 0, count: w * h)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        self.values = values
    }

    /// Mean brightness, 0...1, over `rect` in the picture's unit square (0...1, y down).
    func mean(in rect: CGRect) -> Double {
        let x0 = min(max(Int(rect.minX * CGFloat(width)), 0), width - 1)
        let x1 = min(max(Int(rect.maxX * CGFloat(width)), x0), width - 1)
        let y0 = min(max(Int(rect.minY * CGFloat(height)), 0), height - 1)
        let y1 = min(max(Int(rect.maxY * CGFloat(height)), y0), height - 1)
        var sum = 0, count = 0
        for y in y0...y1 {
            for x in x0...x1 {
                sum += Int(values[y * width + x])
                count += 1
            }
        }
        return Double(sum) / Double(count * 255)
    }

    /// Whether the picture is mostly white (cloud, snow) around `point`, in the unit square.
    func isBright(around point: CGPoint, radius: CGFloat) -> Bool {
        mean(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)) > 0.5
    }
}

/// A satellite picture or ice map through SatellitePictureStore's caches.
struct CachedSatelliteImage<Content: View>: View {
    let url: URL?
    /// False while the app saves data and the user has not asked for the picture.
    var download = true
    @ViewBuilder let content: (UIImage?) -> Content
    @MainActor private var store: SatellitePictureStore { .shared }

    var body: some View {
        content(url.flatMap { store.images[$0] })
            .task(id: "\(url?.absoluteString ?? "")|\(download)") {
                if let url { await store.image(url, download: download) }
            }
    }
}

/// What can be drawn over the picture.
enum SatelliteLayer: String, CaseIterable, Identifiable {
    // Shore, clubs and routes first, then as on the lake view: rowing light, waves, wind; ice last.
    case shore, clubs, routes, light, waves, wind, ice
    var id: String { rawValue }

    /// Waves and rowing light both colour the water, so only one is on at a time.
    var colorsWater: Bool { self == .waves || self == .light }

    var title: String {
        switch self {
        case .shore: tr("Shore")
        case .clubs: tr("Clubs")
        case .routes: tr("Routes")
        case .wind: tr("Wind")
        case .waves: tr("Waves")
        case .light: tr("Rowing light")
        case .ice: tr("Ice map")
        }
    }

    var symbol: String {
        switch self {
        case .shore: "scribble"
        case .clubs: "mappin"
        case .routes: "point.topleft.down.to.point.bottomright.curvepath"
        case .wind: "wind"
        case .waves: "water.waves"
        case .light: "light.beacon.max"
        case .ice: "snowflake"
        }
    }
}

/// The layers a person switched on, kept on the device.
@MainActor
@Observable
final class SatelliteLayers {
    static let shared = SatelliteLayers()
    private static let key = "RWSatelliteLayers"

    var on: Set<SatelliteLayer> {
        didSet { UserDefaults.standard.set(on.map(\.rawValue).sorted(), forKey: Self.key) }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        on = Set(saved.compactMap(SatelliteLayer.init(rawValue:)))
    }

    func toggle(_ layer: SatelliteLayer) {
        if on.contains(layer) {
            on.remove(layer)
        } else {
            if layer.colorsWater { on = on.filter { !$0.colorsWater } }
            on.insert(layer)
        }
    }
}

/// "Satellite picture": the lake from space. Shows the latest picture; when it
/// is cloudy, a switch offers the clearest one. Shore, clubs, saved routes, wind,
/// waves or the rowing light, and (in winter) the ice map can be drawn over it.
/// Tap for full screen.
/// Hidden when there is no picture; the page loads it (see LocationPageView).
struct SatellitePictureCard: View {
    let lakeID: String
    /// The page's club, marked like on the lake view.
    var clubID: String?
    /// Lake, river or canal, for the wording.
    var water: WaterKind = .lake
    /// A lake's picture covers the lake; a river section's or a club place's ("club-<id>") the area around the club.
    private var overLake: Bool { water == .lake && !lakeID.hasPrefix("club-") }
    @MainActor private var store: SatellitePictureStore { .shared }
    @State private var kind: SatellitePicture.Kind = .latest
    /// The page's visible height, which follows turning the device and resizing the window.
    @Environment(\.pageHeight) private var pageHeight
    /// The card's height without the picture: title, picker, caption and switches.
    /// Changed only by more than a point, as the picture's size follows it: two
    /// heights measured a fraction apart sent it back and forth for ever, which
    /// froze the app (most often on turning the phone or swiping between clubs).
    @State private var chromeHeight: CGFloat = 0
    /// The last measured heights of the card and its picture; kept out of the
    /// view's state, as only their difference matters.
    @State private var measured = MeasuredHeights()
    /// Screenshot hook: `-RWOpenSatellite YES` opens the picture full screen.
    @State private var showingFull = UserDefaults.standard.bool(forKey: "RWOpenSatellite")

    /// The tallest the picture may be so the card fits the page with a margin above and below.
    private var pictureLimit: CGFloat {
        guard let pageHeight, chromeHeight > 0 else { return max(300, UIScreen.main.bounds.height - 360) }
        return max(240, (pageHeight - chromeHeight - 32).rounded(.down))
    }

    private final class MeasuredHeights {
        var card: CGFloat = 0
        var picture: CGFloat = 0
    }

    private func measuredChrome() {
        let chrome = (measured.card - measured.picture).rounded()
        if measured.card > 0, abs(chrome - chromeHeight) > 1 { chromeHeight = chrome }
    }

    /// Where the page's visible height comes from (LocationPageView).
    struct PageHeightKey: EnvironmentKey {
        static let defaultValue: CGFloat? = nil
    }

    var body: some View {
        Group {
            if let picture = store.pictures[lakeID], let shot = picture.shot(kind) {
                Card(title: tr("Satellite picture"), symbol: "globe.europe.africa") {
                    if picture.hasChoice {
                        SatelliteKindPicker(picture: picture, kind: $kind)
                    }
                    Button {
                        // Saving data: the first tap loads the pictures, the next opens them.
                        if waitsForTap(picture, shot) { store.allowDownloads(lakeID) } else { showingFull = true }
                    } label: {
                        // The whole card fits on one screen: the picture takes what the page
                        // leaves after the picker, the caption and the switches, never wider
                        // than the card. Measured again on every turn or window resize.
                        SatelliteImage(lakeID: lakeID, picture: picture, shot: shot, clubID: clubID)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.picture = $0; measuredChrome() }
                            .frame(maxHeight: pictureLimit)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(overLake ? tr("Satellite picture of the lake") : tr("Satellite picture of the water around the club"))
                    SatelliteCaption(picture: picture, shot: shot, overLake: overLake)
                    SatelliteLayerChips(lakeID: lakeID, picture: picture, clubID: clubID)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.card = $0; measuredChrome() }
                .fullScreenCover(isPresented: $showingFull) {
                    SatellitePictureScreen(lakeID: lakeID, picture: picture, kind: kind, clubID: clubID, overLake: overLake)
                        .diagnosisNamed("satellite picture")
                }
            }
        }
        // Runs once the picture shows (LocationPageView loads the picture itself):
        // the overlays need the lake view.
        .task { await LakeViewStore.shared.load(lakeID) }
    }

    private func waitsForTap(_ picture: SatellitePicture, _ shot: SatellitePicture.Shot) -> Bool {
        guard !store.mayDownload(lakeID), let url = store.url(lakeID, file: shot.image, date: shot.date) else { return false }
        return !store.isKept(url)
    }
}

/// "Latest, 21 Oct" | "Clearest, 12 Oct".
struct SatelliteKindPicker: View {
    let picture: SatellitePicture
    @Binding var kind: SatellitePicture.Kind

    var body: some View {
        Picker(tr("Satellite picture"), selection: $kind) {
            ForEach(picture.kinds) { kind in
                Text(label(kind)).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    /// "Latest, 22 Oct"; with three pictures just "Latest", as the grey line below names the day.
    private func label(_ kind: SatellitePicture.Kind) -> String {
        if picture.kinds.count > 2 {
            switch kind {
            case .latest: return tr("Latest")
            // "Fast klar": the sky's "Überwiegend klar" didn't fit its third.
            case .mostlyClear: return tr("Mostly clear", key: "Mostly clear (picture)")
            case .clearest: return tr("Clearest")
            }
        }
        // Short, so both labels fit their halves: "Latest, 23 Oct".
        let day = picture.shot(kind)?.day.map { $0.formatted(.dateTime.day().month(.abbreviated).locale(Format.locale)) } ?? ""
        switch kind {
        case .latest: return tr("Latest, %@", day)
        case .mostlyClear: return tr("Mostly clear, %@", day)
        case .clearest: return tr("Clearest, %@", day)
        }
    }
}

/// "Sentinel-2 · 21 Oct · 35 % of the lake under cloud", the ice map's day when it is shown, and the credit.
struct SatelliteCaption: View {
    let picture: SatellitePicture
    let shot: SatellitePicture.Shot
    /// Whether the cloud share is the lake's; on rivers it is the picture's box around the club.
    var overLake = true
    @MainActor private var layers: SatelliteLayers { .shared }
    @State private var explaining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Always two lines high, so the picture above keeps its size when
                // switching between pictures whose line wraps and whose doesn't.
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                Button { explaining = true } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(tr("Why only every few days?"))
            }
            .alert(tr("Why only every few days?"), isPresented: $explaining) {
                Button(tr("OK"), role: .cancel) {}
            } message: {
                Text(tr("Sentinel-2 photographs each lake from about 800 km up, every 2 to 5 days in the late morning, as its two satellites circle the Earth. It takes pictures in daylight like a camera and cannot see through clouds, so the latest picture may be cloudy and the clearest one older."))
            }
            if layers.on.contains(.ice), let ice = picture.ice {
                Text(tr("Satellite ice map, %@", SatellitePicture.parser.date(from: ice.date).map { Format.day($0) } ?? ice.date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let attribution = picture.attribution {
                Text(attribution)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var line: String {
        let day = shot.day.map { Format.day($0) } ?? shot.date
        let cloud = (shot.lakeCloud * 100).rounded()
        if !overLake {
            if cloud < 1 { return tr("Sentinel-2 · %@ · no cloud", day) }
            return tr("Sentinel-2 · %@ · %@ %% under cloud", day, Format.number(cloud))
        }
        if cloud < 1 { return tr("Sentinel-2 · %@ · no cloud over the lake", day) }
        return tr("Sentinel-2 · %@ · %@ %% of the lake under cloud", day, Format.number(cloud))
    }
}

/// One small switch per layer that has something to show on this lake.
struct SatelliteLayerChips: View {
    let lakeID: String
    let picture: SatellitePicture
    var clubID: String? = nil
    @MainActor private var layers: SatelliteLayers { .shared }
    @State private var showingLegend = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showingLegend = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Legend"))
                ForEach(available) { layer in
                    let on = layers.on.contains(layer)
                    Button { layers.toggle(layer) } label: {
                        Label(layer.title, systemImage: layer.symbol)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(on ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .sheet(isPresented: $showingLegend) { SatelliteLegend(lakeID: lakeID, picture: picture, clubID: clubID) }
    }

    private var available: [SatelliteLayer] {
        let view = LakeViewStore.shared.views[lakeID, club: clubID]
        return SatelliteLayer.allCases.filter { layer in
            switch layer {
            case .shore: view != nil
            case .clubs: !(view?.clubs.isEmpty ?? true)
            case .routes: !RouteStore.shared.routes(on: lakeID).isEmpty
            case .wind, .waves, .light: !(view?.hours.isEmpty ?? true)
            case .ice: picture.ice != nil
            }
        }
    }
}

/// The picture with the switched-on layers drawn over it.
struct SatelliteImage: View {
    let lakeID: String
    let picture: SatellitePicture
    let shot: SatellitePicture.Shot
    var clubID: String?
    /// The full view draws shore, routes, clubs and wind on the screen above the zoomed picture.
    var marksOnScreen = false
    /// The full view's zoom, for the 10 m tiles of big lakes.
    var zoom: ZoomTracker?
    @MainActor private var store: SatellitePictureStore { .shared }
    @MainActor private var layers: SatelliteLayers { .shared }

    var body: some View {
        CachedSatelliteImage(url: store.url(lakeID, file: shot.image, date: shot.date), download: store.mayDownload(lakeID)) { image in
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if !store.mayDownload(lakeID) {
                // Saving data and not on the phone yet: the card's tap loads it.
                Color.secondary.opacity(0.15).overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle").font(.title)
                        Text(tr("Tap to load the picture")).font(.subheadline.weight(.semibold))
                        Text(tr("Saving data: satellite pictures load only when asked for."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else {
                Color.secondary.opacity(0.15).overlay { ProgressView() }
            }
        }
        .aspectRatio(picture.aspectRatio, contentMode: .fit)
        .overlay { sharpOverlay }
        .overlay { iceOverlay }
        .overlay {
            // The full view puts it on the screen, where it doesn't zoom.
            if !marksOnScreen { SatelliteColdBadge(lakeID: lakeID, picture: picture, clubID: clubID) }
        }
        .overlay {
            if !marksOnScreen {
                SatelliteOverlay(lakeID: lakeID, picture: picture, layers: layers.on, clubID: clubID, cloudy: shot.lakeCloud >= 0.5, shot: shot)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Full view only: the overview (the three biggest lakes), then the 10 m tiles
    /// in sight once zoomed in further than the picture below them is sharp.
    @ViewBuilder
    private var sharpOverlay: some View {
        if marksOnScreen, let zoom, let sharp = picture.sharp, shot.tiles != nil {
            ZStack {
                if let overview = shot.overview {
                    CachedSatelliteImage(url: store.url(lakeID, file: overview, date: shot.date)) { image in
                        if let image { Image(uiImage: image).resizable() }
                    }
                }
                // The overview is 2500 px on its longer side, the card's picture `width` wide.
                let overviewWidth = CGFloat(sharp.width) * 2500 / CGFloat(max(sharp.width, sharp.height, 1))
                SharpTiles(lakeID: lakeID, shot: shot, sharp: sharp, zoom: zoom,
                           below: shot.overview == nil ? CGFloat(picture.width ?? 0) : overviewWidth)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var iceOverlay: some View {
        if layers.on.contains(.ice), let ice = picture.ice, let box = picture.bbox, box.count == 4, ice.bbox.count == 4,
           let url = store.url(lakeID, file: ice.image, date: ice.date) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let x0 = (ice.bbox[0] - box[0]) / (box[2] - box[0]) * w
                let x1 = (ice.bbox[2] - box[0]) / (box[2] - box[0]) * w
                let y0 = (box[3] - ice.bbox[3]) / (box[3] - box[1]) * h
                let y1 = (box[3] - ice.bbox[1]) / (box[3] - box[1]) * h
                CachedSatelliteImage(url: url) { image in
                    if let image { Image(uiImage: image).resizable().interpolation(.none) }
                }
                .frame(width: x1 - x0, height: y1 - y0)
                .position(x: (x0 + x1) / 2, y: (y0 + y1) / 2)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Shore, clubs, routes and wind, from the lake view and the saved routes, in the picture's own lon/lat box.
struct SatelliteOverlay: View {
    let lakeID: String
    let picture: SatellitePicture
    let layers: Set<SatelliteLayer>
    var clubID: String?
    /// Over mostly white cloud the shore is drawn dark with a light edge, over a clear lake light with a dark edge.
    var cloudy = false
    /// The pass shown, so wind arrows can be dark where the picture under them is white.
    var shot: SatellitePicture.Shot?
    /// Drawn on the screen above a zoomable picture: the picture's size at zoom 1,
    /// how far it is zoomed and moved. Lines, marks and names then keep their size.
    var screen: (size: CGSize, zoom: CGFloat, offset: CGPoint)?
    @MainActor private var view: LakeView? { LakeViewStore.shared.views[lakeID, club: clubID] }
    /// The wind map's wind, for the arrows on land.
    @MainActor private var land: LandWind? {
        guard let view, !view.hours.isEmpty else { return nil }
        return ModelMapStore.shared.landWind(at: view.grid.centre, time: view.hours[view.hourIndex()].time)
    }

    @MainActor private var brightness: PictureBrightness? {
        let store = SatellitePictureStore.shared
        guard let shot, let url = store.url(lakeID, file: shot.image, date: shot.date) else { return nil }
        return store.brightness(url)
    }

    var body: some View {
        let view = self.view, land = self.land, brightness = self.brightness
        Canvas { context, size in
            guard let box = picture.bbox, box.count == 4 else { return }
            let full = screen?.size ?? size, zoom = screen?.zoom ?? 1, offset = screen?.offset ?? .zero
            func point(_ lon: Double, _ lat: Double) -> CGPoint {
                CGPoint(x: (lon - box[0]) / (box[2] - box[0]) * full.width * zoom - offset.x,
                        y: (box[3] - lat) / (box[3] - box[1]) * full.height * zoom - offset.y)
            }
            let shadow = GraphicsContext.Shading.color(.black.opacity(0.6))
            if let fill = layers.first(where: \.colorsWater), let view, !view.hours.isEmpty,
               let image = LakeRaster.image(view, hour: view.hours[view.hourIndex()], layer: fill == .waves ? .waves : .light) {
                // The lake view's cells for the selected hour, clipped to the shore.
                var shore = Path()
                for ring in view.outline where ring.count > 1 {
                    shore.addLines(ring.map { point($0[0], $0[1]) })
                    shore.closeSubpath()
                }
                let g = view.grid
                let corner = point(g.westEdge, g.north), far = point(g.east, g.southEdge)
                var water = context
                water.clip(to: shore, style: FillStyle(eoFill: true))
                water.opacity = 0.55
                water.draw(
                    Image(decorative: image, scale: 1).interpolation(.high),
                    in: CGRect(x: corner.x, y: corner.y, width: far.x - corner.x, height: far.y - corner.y)
                )
                // Darkness or an official warning for the whole lake: stripes, as on the lake map.
                if fill == .light, let stripes = view.hours[view.hourIndex()].lakeWide.stripes {
                    let red = stripes == .red, gap: CGFloat = red ? 8 : 14, fall = view.stripesFall
                    var lines = Path()
                    for x in stride(from: -size.height, to: size.width, by: gap) {
                        lines.move(to: CGPoint(x: x, y: fall ? 0 : size.height))
                        lines.addLine(to: CGPoint(x: x + size.height, y: fall ? size.height : 0))
                    }
                    var striped = context
                    striped.clip(to: shore, style: FillStyle(eoFill: true))
                    striped.stroke(lines, with: .color(red ? .red.opacity(0.75) : .orange.opacity(0.8)), lineWidth: red ? 1.5 : 1.2)
                }
            }
            // Wind under the lines and marks, so shore, routes and clubs stay on top.
            if layers.contains(.wind), let view {
                SatelliteWind.draw(in: context, view: view, land: land, box: box, size: full, zoom: zoom, offset: offset, visible: size,
                                   brightness: brightness)
            }
            if layers.contains(.shore), let view {
                var path = Path()
                for ring in view.outline where ring.count > 1 {
                    path.addLines(ring.map { point($0[0], $0[1]) })
                    path.closeSubpath()
                }
                // Cold water: the lake view's blue shore, with an edge that stands out from
                // dark water (white) or from cloud (dark). Otherwise white, or dark over cloud.
                let cold = view.coldShore
                let (edge, core): (Color, Color) = switch (cold, cloudy) {
                case let (cold?, false): (.white.opacity(0.9), cold.color)
                case let (cold?, true): (.black.opacity(0.7), cold.color)
                case (nil, true): (.white.opacity(0.85), Color(red: 0.05, green: 0.12, blue: 0.3))
                case (nil, false): (.black.opacity(0.7), .white)
                }
                let width: CGFloat = cold == .cold ? 2.2 : 1.5
                context.stroke(path, with: .color(edge), lineWidth: width + 2)
                context.stroke(path, with: .color(core), lineWidth: width)
            }
            if layers.contains(.routes) {
                for route in RouteStore.shared.routes(on: lakeID) where route.points.count > 1 {
                    var path = Path()
                    path.addLines(route.points.map { point($0.lon, $0.lat) })
                    context.stroke(path, with: shadow, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            if layers.contains(.clubs), let view {
                // As on the lake view: a grey round mark with a rower, the page's club
                // blue with a house. Names go right, left, above or below the mark,
                // wherever they don't touch another; with no room the mark stays alone.
                var taken: [CGRect] = []
                let marks = view.clubs.map { club in (club, point(club.launchPoint.lon, club.launchPoint.lat)) }
                for (_, p) in marks { taken.append(CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)) }
                // The page's club last, so it stays on top of clubs sharing its boathouse.
                for (club, p) in marks.sorted(by: { ($0.0.id == clubID ? 1 : 0) < ($1.0.id == clubID ? 1 : 0) }) {
                    let own = club.id == clubID
                    let dot = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
                    context.fill(dot, with: .color(own ? .blue : Color(white: 0.45)))
                    context.stroke(dot, with: .color(.white), lineWidth: 1.5)
                    context.draw(
                        Text(Image(systemName: own ? LocationStore.markSymbol(for: club.id) : "figure.rower")).font(.system(size: 10, weight: .bold)).foregroundStyle(.white),
                        at: p, anchor: .center
                    )
                }
                for (club, p) in marks.sorted(by: { ($0.0.id == clubID ? 0 : 1, $0.1.y) < ($1.0.id == clubID ? 0 : 1, $1.1.y) }) {
                    let label = context.resolve(Text(club.shortName).font(.caption2.weight(.semibold)).foregroundStyle(.white))
                    let labelSize = label.measure(in: CGSize(width: 200, height: 40))
                    let spots: [(CGRect, UnitPoint)] = [
                        (CGRect(x: p.x + 12, y: p.y - labelSize.height / 2, width: labelSize.width, height: labelSize.height), .leading),
                        (CGRect(x: p.x - 12 - labelSize.width, y: p.y - labelSize.height / 2, width: labelSize.width, height: labelSize.height), .trailing),
                        (CGRect(x: p.x - labelSize.width / 2, y: p.y - 11 - labelSize.height, width: labelSize.width, height: labelSize.height), .bottom),
                        (CGRect(x: p.x - labelSize.width / 2, y: p.y + 11, width: labelSize.width, height: labelSize.height), .top),
                    ]
                    guard let spot = spots.first(where: { rect, _ in
                        let padded = rect.insetBy(dx: -2, dy: -1)
                        // The pill must stay on the picture, not run off its edge.
                        let inside = CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 2).contains(rect)
                        return inside && !taken.contains { $0.intersects(padded) }
                    }) else { continue }
                    taken.append(spot.0)
                    let pill = Path(roundedRect: spot.0.insetBy(dx: -4, dy: -1), cornerRadius: 6)
                    context.fill(pill, with: .color(.black.opacity(0.55)))
                    context.draw(label, in: spot.0)
                }
            }
        }
        .allowsHitTesting(false)
        // Again once the lake has loaded, which can be after the picture.
        .task(id: "\(layers.contains(.wind)) \(view != nil)") {
            if layers.contains(.wind), let view { await ModelMapStore.shared.loadLandWind(at: view.grid.centre) }
        }
    }
}

/// The wind arrows on a satellite picture, as on the lake map: an even grid
/// over the whole picture, more arrows as it zooms in, the same size on screen.
/// On the water the wind is worked out between the lake's forecast points, on
/// land it is the wind map's. The arrow nearest each forecast
/// point carries its speed.
enum SatelliteWind {
    /// Draws on `context`, whose points are the screen's: the picture is `size`
    /// at zoom 1 and shows `zoom` times larger, its corner `offset` above and
    /// left of the drawing's corner; `visible` is the size drawn on. Each arrow and
    /// number is white with a dark edge, or black with a white edge where the
    /// picture under it is white (cloud, snow), judged from `brightness`.
    static func draw(in context: GraphicsContext, view: LakeView, land: LandWind?, box: [Double], size: CGSize,
                     zoom: CGFloat, offset: CGPoint, visible: CGSize, brightness: PictureBrightness? = nil) {
        guard !view.hours.isEmpty, box.count == 4, size.width > 0, size.height > 0, zoom > 0 else { return }
        let hour = view.hours[view.hourIndex()]
        func point(_ lon: Double, _ lat: Double) -> CGPoint {
            CGPoint(x: (lon - box[0]) / (box[2] - box[0]) * size.width, y: (box[3] - lat) / (box[3] - box[1]) * size.height)
        }
        let rings = view.outline.filter { $0.count > 2 }.map { ring in ring.map { point($0[0], $0[1]) } }
        let water = CGMutablePath()
        for ring in rings {
            water.addLines(between: ring)
            water.closeSubpath()
        }
        let widthM = (box[2] - box[0]) * 111_320 * cos((box[1] + box[3]) / 2 * .pi / 180)
        let samples = zip(view.points, hour.wind).compactMap { p, wind -> WindArrows.Sample? in
            guard let from = wind.fromDeg, let speed = wind.speedMs else { return nil }
            return WindArrows.Sample(point: point(p.lon, p.lat), towardDeg: from + 180, speedMs: speed)
        }
        // The part of the picture on screen, in its own points; arrows stay on the picture.
        let area = CGRect(x: offset.x / zoom, y: offset.y / zoom, width: visible.width / zoom, height: visible.height / zoom)
            .intersection(CGRect(origin: .zero, size: size))
        let spacing = WindArrows.spacing / zoom
        // On land the wind map's forecast, at the place the picture shows.
        var onLand: ((CGPoint) -> (towardDeg: Double, speedMs: Double)?)?
        if let land {
            onLand = { p in
                let lat = box[3] - Double(p.y / size.height) * (box[3] - box[1])
                let lon = box[0] + Double(p.x / size.width) * (box[2] - box[0])
                return land.at(MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            }
        }
        let blend = CGFloat(WindArrows.blendM / widthM) * size.width
        let arrows = WindArrows.arrows(in: area, spacing: spacing, water: water, from: samples,
                                       land: onLand, shore: WindArrows.Shore(rings: rings), blend: blend)
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom - offset.x, y: p.y * zoom - offset.y) }

        // Whether the picture is white under a point of the picture, within `reach` screen points.
        func bright(_ p: CGPoint, reach: CGFloat) -> Bool {
            guard let brightness else { return false }
            return brightness.isBright(around: CGPoint(x: p.x / size.width, y: p.y / size.height),
                                       radius: reach / zoom / max(size.width, size.height))
        }
        func colors(bright: Bool) -> (edge: Color, core: Color) {
            bright ? (.white.opacity(0.9), .black) : (.black.opacity(0.6), .white)
        }
        let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        // On land as on the water, at full strength: only black or white, by what lies under each arrow.
        for light in [false, true] {
            var path = Path()
            for a in arrows {
                let length = WindArrows.length(a.speedMs)
                guard bright(a.at, reach: length / 2) == light else { continue }
                path.addPath(LakeArrow.path(at: screen(a.at), towardDeg: a.towardDeg, length: length))
            }
            guard !path.isEmpty else { continue }
            let (edge, core) = colors(bright: light)
            context.stroke(path, with: .color(edge), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(core), style: style)
        }
        // Each forecast point's speed, at the tail of the arrow nearest it, with a
        // halo in the edge colour so it reads on cloud and on dark water alike.
        for s in samples {
            var best: WindArrows.Arrow?
            var bestD = Double(spacing * spacing)
            for a in arrows {
                let dx = Double(a.at.x - s.point.x), dy = Double(a.at.y - s.point.y)
                let d = dx * dx + dy * dy
                if d <= bestD { best = a; bestD = d }
            }
            guard let best else { continue }
            let r = best.towardDeg * .pi / 180
            let half = WindArrows.length(best.speedMs) / 2 + 6
            let offsetX = -CGFloat(sin(r)) * half, offsetY = CGFloat(cos(r)) * half
            let (edge, core) = colors(bright: bright(CGPoint(x: best.at.x + offsetX / zoom, y: best.at.y + offsetY / zoom), reach: 6))
            let at = screen(best.at)
            var number = context
            number.addFilter(.shadow(color: edge, radius: 1))
            number.addFilter(.shadow(color: edge, radius: 1))
            number.draw(
                Text(Format.windNumber(s.speedMs)).font(.caption2.weight(.bold)).foregroundStyle(core),
                at: CGPoint(x: at.x + offsetX, y: at.y + offsetY), anchor: .center
            )
        }
    }
}

/// How far a zoomable view is zoomed and moved, for layers drawn on the screen above it.
@Observable
final class ZoomTracker {
    var scale: CGFloat = 1
    var offset: CGPoint = .zero
    /// The scroll view's size on screen.
    var viewSize: CGSize = .zero

    /// The part of the content in sight, in the content's own points.
    var visible: CGRect {
        CGRect(x: offset.x / scale, y: offset.y / scale, width: viewSize.width / scale, height: viewSize.height / scale)
    }
}

/// The picture on its own, filling the screen, with pinch to zoom, drag to
/// move, a double tap to zoom in or back, and the same switches.
struct SatellitePictureScreen: View {
    let lakeID: String
    let picture: SatellitePicture
    @State var kind: SatellitePicture.Kind
    var clubID: String?
    var overLake = true
    @State private var zoom = ZoomTracker()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @MainActor private var layers: SatelliteLayers { .shared }

    // The panels and buttons over the map stop growing at the largest standard
    // text size: larger, they covered the map and their lines broke apart.
    var body: some View { screen.dynamicTypeSize(...DynamicTypeSize.xxxLarge) }

    @ViewBuilder
    private var screen: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if picture.hasChoice {
                    SatelliteKindPicker(picture: picture, kind: $kind)
                        .padding(.horizontal)
                }
                GeometryReader { geo in
                    // The whole picture fits at first, however the lake lies.
                    let fit = min(geo.size.width, geo.size.height * picture.aspectRatio)
                    if let shot = picture.shot(kind) {
                        let size = CGSize(width: fit, height: fit / picture.aspectRatio)
                        ZoomableView(size: size, focus: focus(in: size), tracker: zoom, maxZoom: maxZoom(fit: fit)) {
                            SatelliteImage(lakeID: lakeID, picture: picture, shot: shot, clubID: clubID, marksOnScreen: true, zoom: zoom)
                                .frame(width: fit, height: fit / picture.aspectRatio)
                        }
                        // No .id(kind): switching pictures keeps the zoom and position.
                        .overlay {
                            // On the screen rather than in the picture, so lines, club marks,
                            // names and arrows stay sharp and the same size when zoomed in,
                            // with more arrows, as on the lake map.
                            SatelliteOverlay(lakeID: lakeID, picture: picture, layers: layers.on, clubID: clubID,
                                             cloudy: shot.lakeCloud >= 0.5, shot: shot, screen: (size, zoom.scale, zoom.offset))
                        }
                        .overlay { SatelliteColdBadge(lakeID: lakeID, picture: picture, clubID: clubID, screen: (size, zoom.scale, zoom.offset)) }
                    }
                }
                if let shot = picture.shot(kind) {
                    VStack(alignment: .leading, spacing: 8) {
                        SatelliteCaption(picture: picture, shot: shot, overLake: overLake)
                        SatelliteLayerChips(lakeID: lakeID, picture: picture, clubID: clubID)
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 8)
            .navigationTitle(tr("Satellite picture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
        // Opening the full view asks for the pictures, also when saving data.
        .onAppear { SatellitePictureStore.shared.allowDownloads(lakeID) }
        // Lakes up to about 37 km load all their tiles at once, so zooming in is
        // sharp straight away; the three biggest only the tiles in sight (SharpTiles).
        .task(id: kind) {
            guard let sharp = picture.sharp, let shot = picture.shot(kind), shot.overview == nil else { return }
            for row in 0..<sharp.rows {
                for column in 0..<sharp.columns {
                    if let url = SatellitePictureStore.shared.tileURL(lakeID, shot: shot, row: row, column: column) {
                        _ = await SatellitePictureStore.shared.tile(url)
                    }
                }
            }
        }
    }

    /// Big lakes with 10 m tiles zoom until a tile pixel is two screen pixels.
    private func maxZoom(fit: CGFloat) -> CGFloat {
        guard let sharp = picture.sharp, picture.shot(kind)?.tiles != nil, fit > 0 else { return 6 }
        return max(6, CGFloat(sharp.width) / (fit * displayScale) * 2)
    }

    /// Where the picture opens: the saved routes on this lake, all of them in
    /// view; without routes the page's club, with the picture filling the width.
    private func focus(in size: CGSize) -> ZoomFocus? {
        guard let box = picture.bbox, box.count == 4 else { return nil }
        func point(_ lon: Double, _ lat: Double) -> CGPoint {
            CGPoint(x: (lon - box[0]) / (box[2] - box[0]) * size.width, y: (box[3] - lat) / (box[3] - box[1]) * size.height)
        }
        let points = RouteStore.shared.routes(on: lakeID).flatMap(\.points).map { point($0.lon, $0.lat) }
        if let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
           let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
            return .whole(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -24, dy: -24))
        }
        let club = LakeViewStore.shared.views[lakeID, club: clubID]?.clubs.first { $0.id == clubID }
        return .fillWidth(around: club.map { point($0.launchPoint.lon, $0.launchPoint.lat) })
    }
}

/// The lake view's life-jacket badge in the picture's corner while the water is
/// cold, as on the lake map (owner's pick 2026-10-27), with the blue shore line.
struct SatelliteColdBadge: View {
    let lakeID: String
    let picture: SatellitePicture
    /// The page's club, whose boat sets the life-jacket limit.
    var clubID: String?
    /// The full view: the picture's size at zoom 1, how far it is zoomed and moved.
    var screen: (size: CGSize, zoom: CGFloat, offset: CGPoint)?

    var body: some View {
        // It explains the blue shore, so it shows only with the shore line.
        if SatelliteLayers.shared.on.contains(.shore), let view = LakeViewStore.shared.views[lakeID, club: clubID], let kit = view.coldWaterKit {
            GeometryReader { geo in
                let estimated = view.waterC == nil
                let text = estimated ? "≈ " + kit.title : kit.title
                let full = CGSize(width: Self.textWidth(text) + 50, height: 34)
                let place = BadgePlacement.choose(shore: shore(view, in: geo.size), size: geo.size, badge: full,
                                                  compact: CGSize(width: 34, height: 34))
                Group {
                    if place.compact {
                        ColdWaterGlyph(kit: kit)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial, in: Circle())
                    } else {
                        ColdWaterBadge(kit: kit, estimated: estimated)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .padding(BadgePlacement.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: place.alignment)
            }
            .allowsHitTesting(false)
        }
    }

    /// The shore in the badge's own points, as the overlay draws it.
    private func shore(_ view: LakeView, in size: CGSize) -> [[CGPoint]] {
        guard let box = picture.bbox, box.count == 4 else { return [] }
        let full = screen?.size ?? size, zoom = screen?.zoom ?? 1, offset = screen?.offset ?? .zero
        return view.outline.map { ring in
            ring.map { p in
                CGPoint(x: (p[0] - box[0]) / (box[2] - box[0]) * full.width * zoom - offset.x,
                        y: (box[3] - p[1]) / (box[3] - box[1]) * full.height * zoom - offset.y)
            }
        }
    }

    private static func textWidth(_ text: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// Where the life-jacket badge goes on a satellite picture: the first corner
/// (top left, top right, bottom left, bottom right) where it covers neither the
/// shore line nor the water; if none is free, just the symbol, in the corner
/// where it covers least.
enum BadgePlacement {
    static let inset: CGFloat = 8

    static func choose(shore: [[CGPoint]], size: CGSize, badge: CGSize, compact: CGSize) -> (alignment: Alignment, compact: Bool) {
        let corners: [Alignment] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        if let free = corners.first(where: { overlap(rect(for: $0, badge, in: size), shore) == 0 }) {
            return (free, false)
        }
        let best = corners.min { overlap(rect(for: $0, compact, in: size), shore) < overlap(rect(for: $1, compact, in: size), shore) }
        return (best ?? .topLeading, true)
    }

    static func rect(for corner: Alignment, _ badge: CGSize, in size: CGSize) -> CGRect {
        let x = corner.horizontal == .leading ? inset : size.width - inset - badge.width
        let y = corner.vertical == .top ? inset : size.height - inset - badge.height
        // A few points around it, so the shore line's width stays clear too.
        return CGRect(x: x, y: y, width: badge.width, height: badge.height).insetBy(dx: -3, dy: -3)
    }

    /// How much of the shore runs through the rectangle (points along it every
    /// 3 pt), or 1 when the rectangle sits on open water inside the shore.
    static func overlap(_ rect: CGRect, _ shore: [[CGPoint]]) -> Int {
        var hits = 0
        for ring in shore where ring.count > 1 {
            for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) {
                let steps = max(1, Int((hypot(b.x - a.x, b.y - a.y) / 3).rounded(.up)))
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    if rect.contains(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) { hits += 1 }
                }
            }
        }
        if hits == 0 && inside(CGPoint(x: rect.midX, y: rect.midY), shore) { return 1 }
        return hits
    }

    /// Even-odd test, so islands count as land.
    static func inside(_ point: CGPoint, _ shore: [[CGPoint]]) -> Bool {
        var inside = false
        for ring in shore where ring.count > 2 {
            var j = ring.count - 1
            for i in ring.indices {
                let a = ring[i], b = ring[j]
                if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }
}

/// The 10 m tiles in sight, once the picture is zoomed in further than the one
/// below them (`below`, its width in pixels) is sharp.
struct SharpTiles: View {
    let lakeID: String
    let shot: SatellitePicture.Shot
    let sharp: SatellitePicture.Sharp
    let zoom: ZoomTracker
    let below: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if size.width * zoom.scale * displayScale > below * 1.1 {
                // A little beyond the screen, so tiles are there before they come into sight.
                let visible = zoom.visible.insetBy(dx: -size.width * 0.05, dy: -size.height * 0.05)
                ForEach(cells(in: visible, size: size), id: \.self) { cell in
                    let rect = sharp.rect(row: cell[0], column: cell[1], in: size)
                    SharpTile(url: SatellitePictureStore.shared.tileURL(lakeID, shot: shot, row: cell[0], column: cell[1]))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }

    private func cells(in visible: CGRect, size: CGSize) -> [[Int]] {
        var out: [[Int]] = []
        for row in 0..<sharp.rows {
            for column in 0..<sharp.columns where sharp.rect(row: row, column: column, in: size).intersects(visible) {
                out.append([row, column])
            }
        }
        return out
    }
}

/// One tile; clear until it has loaded, so the picture below shows meanwhile.
struct SharpTile: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            image = nil
            if let url { image = await SatellitePictureStore.shared.tile(url) }
        }
    }
}

/// How a zoomable picture first shows: one part of it whole, or filling the
/// width around a point (the middle when there is none).
enum ZoomFocus: Equatable {
    case whole(CGRect)
    case fillWidth(around: CGPoint?)
}

/// A scroll view that reports each layout pass.
final class LayoutScrollView: UIScrollView {
    var laidOut: ((UIScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        laidOut?(self)
    }
}

/// SwiftUI content in a UIKit scroll view, which zooms and pans like Photos.
/// The content keeps its size; the scroll view scales it up to 6 times.
struct ZoomableView<Content: View>: UIViewRepresentable {
    let size: CGSize
    var focus: ZoomFocus?
    /// Told the zoom and position after every move, for layers drawn above.
    var tracker: ZoomTracker?
    /// How close the picture may be zoomed: 6 times, more for the 10 m tiles of big lakes.
    var maxZoom: CGFloat = 6
    @ViewBuilder let content: Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = LayoutScrollView()
        // The scroll view only knows its size once laid out: centre and zoom then,
        // also after a new picture or a turn of the phone.
        let coordinator = context.coordinator
        scroll.laidOut = { [weak coordinator] scroll in coordinator?.laidOut(scroll) }
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        let host = context.coordinator.host
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: size)
        scroll.addSubview(host.view)
        scroll.contentSize = size
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host.rootView = AnyView(content)
        context.coordinator.focus = focus
        context.coordinator.tracker = tracker
        if scroll.maximumZoomScale != maxZoom { scroll.maximumZoomScale = maxZoom }
        if context.coordinator.size != size {
            let old = context.coordinator.size, zoom = scroll.zoomScale
            // The part of the picture in the middle of the screen, as a share of it.
            let middle = CGPoint(x: (scroll.contentOffset.x + scroll.bounds.width / 2) / max(old.width * zoom, 1),
                                 y: (scroll.contentOffset.y + scroll.bounds.height / 2) / max(old.height * zoom, 1))
            context.coordinator.size = size
            scroll.zoomScale = 1
            context.coordinator.host.view.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size
            if context.coordinator.touched {
                // Once the user has a view, a new fit (another caption, a turn) keeps it.
                scroll.zoomScale = zoom
                context.coordinator.centre(scroll)
                scroll.contentOffset = CGPoint(x: middle.x * size.width * zoom - scroll.bounds.width / 2,
                                               y: middle.y * size.height * zoom - scroll.bounds.height / 2)
            } else {
                context.coordinator.focused = false
            }
        }
        context.coordinator.centre(scroll)
        scroll.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: AnyView(content), size: size) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<AnyView>
        var size: CGSize
        var focus: ZoomFocus?
        var tracker: ZoomTracker?
        /// Whether the first view (zoom and position) was set for this size.
        var focused = false
        /// Whether the user has moved or zoomed: then switching pictures or a
        /// new size keeps their view.
        var touched = false
        private var bounds = CGSize.zero

        init(content: AnyView, size: CGSize) {
            host = UIHostingController(rootView: content)
            // The picture sits in the scroll view, not at the screen's edges.
            host.safeAreaRegions = []
            self.size = size
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func laidOut(_ scroll: UIScrollView) {
            guard scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            report(scroll)
            if scroll.bounds.size != bounds {
                bounds = scroll.bounds.size
                // Until the user moves or zooms, a new size opens on the focus again.
                if !touched { focused = false }
            }
            centre(scroll)
            guard !focused else { return }
            focused = true
            applyFocus(scroll)
        }

        /// Zooms to the focus and puts it in the middle of the screen.
        private func applyFocus(_ scroll: UIScrollView) {
            guard let focus, size.width > 0, size.height > 0 else { return }
            let view = scroll.bounds.size
            let scale: CGFloat
            let middle: CGPoint
            switch focus {
            case let .whole(rect):
                scale = min(view.width / max(rect.width, 1), view.height / max(rect.height, 1))
                middle = CGPoint(x: rect.midX, y: rect.midY)
            case let .fillWidth(point):
                scale = view.width / size.width
                middle = point ?? CGPoint(x: size.width / 2, y: size.height / 2)
            }
            // Screenshots: -RWSatelliteZoom n opens n times closer.
            let extra = max(UserDefaults.standard.double(forKey: "RWSatelliteZoom"), 1)
            scroll.zoomScale = min(max(scale * extra, scroll.minimumZoomScale), scroll.maximumZoomScale)
            centre(scroll)
            let z = scroll.zoomScale
            let inset = scroll.contentInset
            let x = min(max(middle.x * z - view.width / 2, -inset.left), scroll.contentSize.width + inset.right - view.width)
            let y = min(max(middle.y * z - view.height / 2, -inset.top), scroll.contentSize.height + inset.bottom - view.height)
            scroll.contentOffset = CGPoint(x: x, y: y)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centre(scrollView)
            report(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { report(scrollView) }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { touched = true }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { touched = true }

        /// Tells the tracker where the content now sits: its corner is the
        /// content offset above and left of the scroll view's corner.
        private func report(_ scroll: UIScrollView) {
            guard let tracker else { return }
            if tracker.scale != scroll.zoomScale { tracker.scale = scroll.zoomScale }
            if tracker.offset != scroll.contentOffset { tracker.offset = scroll.contentOffset }
            if tracker.viewSize != scroll.bounds.size { tracker.viewSize = scroll.bounds.size }
        }

        /// Keeps the picture in the middle while it is smaller than the screen.
        func centre(_ scroll: UIScrollView) {
            let content = host.view.frame.size
            let dx = max(0, (scroll.bounds.width - content.width) / 2)
            let dy = max(0, (scroll.bounds.height - content.height) / 2)
            let inset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
            if scroll.contentInset != inset { scroll.contentInset = inset }
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            touched = true
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: host.view)
                let zoomed = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
                scroll.zoom(to: CGRect(x: point.x - zoomed.width / 2, y: point.y - zoomed.height / 2,
                                       width: zoomed.width, height: zoomed.height), animated: true)
            }
        }
    }
}

/// What the picture and the switched-on layers show. Layers that are off are
/// left out, with a line pointing to the switches.
struct SatelliteLegend: View {
    let lakeID: String
    let picture: SatellitePicture
    var clubID: String? = nil
    @MainActor private var layers: SatelliteLayers { .shared }
    @Environment(\.dismiss) private var dismiss
    /// Stripes on the water now, while the whole lake is red or amber.
    @MainActor private var stripes: Light? {
        guard let view = LakeViewStore.shared.views[lakeID, club: clubID], !view.hours.isEmpty else { return nil }
        return view.hours[view.hourIndex()].lakeWide.stripes
    }

    var body: some View {
        let on = layers.on, stripes = self.stripes
        NavigationStack {
            List {
                Section(tr("The picture")) {
                    row(Image(systemName: "photo"), tr("A true-colour photo from the Sentinel-2 satellites, as a camera would see it from space."))
                    row(Image(systemName: "cloud.fill").foregroundStyle(.white, .gray), tr("White and grey: clouds, haze, or snow and ice on the ground."))
                    row(Image(systemName: "drop.fill").foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.3)), tr("Dark blue to black: open water."))
                }
                if on.contains(.light) {
                    Section(tr("Rowing light")) {
                        LakeLegend(layer: .light, clubID: clubID).padding(.vertical, 4)
                        if stripes == .red {
                            row(Image(systemName: "line.diagonal").foregroundStyle(.red),
                                tr("Grey with red stripes: the whole lake is red now (official warning or darkness)."))
                        } else if stripes == .amber {
                            row(Image(systemName: "line.diagonal").foregroundStyle(.orange),
                                tr("Amber stripes: the whole lake is amber now (sunrise or sunset, official warning)."))
                        }
                        MapBoatNote(clubID: clubID)
                    }
                }
                if on.contains(.waves) {
                    Section(tr("Waves")) { LakeLegend(layer: .waves, clubID: clubID).padding(.vertical, 4) }
                }
                if on.contains(.wind) {
                    Section(tr("Wind")) {
                        row(Image(systemName: "arrow.up.right").fontWeight(.bold),
                            tr("Points where the wind blows to in the current hour, estimated between the forecast points, with more arrows as you zoom in; longer arrows mean stronger wind. The number is the wind speed at a forecast point. On land the arrows show the weather map's wind forecast for each place."))
                    }
                }
                if on.contains(.ice), picture.ice != nil {
                    Section(tr("Ice map")) {
                        row(swatch(Color(red: 1, green: 1, blue: 1)), tr("Snow-covered ice"))
                        row(swatch(Color(red: 200 / 255, green: 235 / 255, blue: 1)), tr("Clear ice"))
                        row(swatch(Color(red: 0, green: 90 / 255, blue: 200 / 255).opacity(0.5)), tr("Open water"))
                    }
                }
                if !on.isDisjoint(with: [.shore, .clubs, .routes]) {
                    Section(tr("Lines and marks")) {
                        if on.contains(.shore) {
                            if let cold = LakeViewStore.shared.views[lakeID, club: clubID]?.coldShore {
                                row(line(cold.color),
                                    tr("Blue shore: the water is cold. Bring a life jacket; light blue below %@, deeper blue below %@.",
                                       Format.temperature(AppSettings.shared.limits(at: clubID).value(.lifeJacket)), Format.temperature(RowingLimits.coldWaterC)))
                            } else {
                                row(line(.white), tr("Shore line: white on a clear picture, dark blue on a cloudy one"))
                            }
                        }
                        if on.contains(.routes) { row(line(.yellow), tr("Your saved routes on this lake")) }
                        if on.contains(.clubs) {
                            row(ClubMarkIcon(color: .blue, symbol: LocationStore.markSymbol(for: clubID)), ClubMarkIcon.pageClubText(clubID))
                            row(ClubMarkIcon(color: .gray), tr("Other clubs on the lake"))
                        }
                    }
                }
                Section {
                    Text(tr("Switch layers on and off with the buttons under the picture."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Legend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 22, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.5), lineWidth: 0.5))
    }

    private func line(_ color: Color) -> some View {
        Capsule().fill(color).frame(width: 22, height: 3).shadow(color: .black.opacity(0.6), radius: 1)
    }

    private func row(_ symbol: some View, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            symbol.frame(width: 28)
            Text(text).font(.subheadline)
        }
    }
}

extension EnvironmentValues {
    /// The club page's visible height, between the status bar and the page bar.
    var pageHeight: CGFloat? {
        get { self[SatellitePictureCard.PageHeightKey.self] }
        set { self[SatellitePictureCard.PageHeightKey.self] = newValue }
    }
}
