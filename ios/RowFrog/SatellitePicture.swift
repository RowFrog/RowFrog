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
            } else {
                missing.insert(lakeID)
            }
        } catch let error as URLError where error.code != .badServerResponse {
            // Offline or a timeout: try again the next time the page opens. A lake
            // without pictures answers 404 (badServerResponse) and stays missing.
        } catch {
            missing.insert(lakeID)
        }
    }

    /// A file's address; the day it shows keeps caches from showing an older one.
    func url(_ lakeID: String, file: String, date: String) -> URL? {
        var components = URLComponents(url: api.url("lakes/\(lakeID)/\(file)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "d", value: date)]
        return components?.url
    }

    /// Pictures already shown in this run of the app, by address.
    private(set) var images: [URL: UIImage] = [:]
    private var loading: Set<URL> = []
    /// Lakes whose pictures the user asked for while the app saves data.
    private(set) var allowedLakes: Set<String> = []

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

    /// Caches/Satellite/<lake>-<file>-<day>; the system may clear it when space runs low.
    private static func cacheFile(for url: URL) -> URL {
        let folder = URL.cachesDirectory.appending(path: "Satellite", directoryHint: .isDirectory)
        let parts = url.pathComponents.suffix(2).joined(separator: "-")
        let day = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
        return folder.appending(path: "\(parts)-\(day)")
    }

    /// Saves a picture and drops older passes of the same lake and file.
    private static func store(_ data: Data, at file: URL) {
        let folder = file.deletingLastPathComponent()
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // "<lake>-<file>-" without the day.
        let prefix = String(file.lastPathComponent.dropLast(10))
        for old in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where old.hasPrefix(prefix) {
            try? manager.removeItem(at: folder.appending(path: old))
        }
        try? data.write(to: file, options: .atomic)
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
    @MainActor private var store: SatellitePictureStore { .shared }
    @State private var kind: SatellitePicture.Kind = .latest
    /// The page's visible height, which follows turning the device and resizing the window.
    @Environment(\.pageHeight) private var pageHeight
    /// The card's height without the picture: title, picker, caption and switches.
    @State private var cardHeight: CGFloat = 0
    @State private var pictureHeight: CGFloat = 0
    /// Screenshot hook: `-RWOpenSatellite YES` opens the picture full screen.
    @State private var showingFull = UserDefaults.standard.bool(forKey: "RWOpenSatellite")

    /// The tallest the picture may be so the card fits the page with a margin above and below.
    private var pictureLimit: CGFloat {
        guard let pageHeight, cardHeight > 0 else { return max(300, UIScreen.main.bounds.height - 360) }
        return max(240, pageHeight - (cardHeight - pictureHeight) - 32)
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
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pictureHeight = $0 }
                            .frame(maxHeight: pictureLimit)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Satellite picture of the lake"))
                    SatelliteCaption(picture: picture, shot: shot)
                    SatelliteLayerChips(lakeID: lakeID, picture: picture, clubID: clubID)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                .fullScreenCover(isPresented: $showingFull) {
                    SatellitePictureScreen(lakeID: lakeID, picture: picture, kind: kind, clubID: clubID)
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
        let view = LakeViewStore.shared.views[lakeID]
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
    /// The full view draws the wind on the screen above the zoomed picture.
    var windOnScreen = false
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
        .overlay { iceOverlay }
        .overlay {
            SatelliteOverlay(lakeID: lakeID, picture: picture, layers: windOnScreen ? layers.on.subtracting([.wind]) : layers.on,
                             clubID: clubID, cloudy: shot.lakeCloud >= 0.5)
        }
        .frame(maxWidth: .infinity)
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
    @MainActor private var view: LakeView? { LakeViewStore.shared.views[lakeID] }

    var body: some View {
        Canvas { context, size in
            guard let box = picture.bbox, box.count == 4 else { return }
            func point(_ lon: Double, _ lat: Double) -> CGPoint {
                CGPoint(x: (lon - box[0]) / (box[2] - box[0]) * size.width, y: (box[3] - lat) / (box[3] - box[1]) * size.height)
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
            }
            // Wind under the lines and marks, so shore, routes and clubs stay on top.
            if layers.contains(.wind), let view {
                SatelliteWind.draw(in: context, view: view, box: box, size: size, zoom: 1, offset: .zero, visible: size)
            }
            if layers.contains(.shore), let view {
                var path = Path()
                for ring in view.outline where ring.count > 1 {
                    path.addLines(ring.map { point($0[0], $0[1]) })
                    path.closeSubpath()
                }
                let (edge, core): (Color, Color) = cloudy
                    ? (.white.opacity(0.85), Color(red: 0.05, green: 0.12, blue: 0.3))
                    : (.black.opacity(0.7), .white)
                context.stroke(path, with: .color(edge), lineWidth: 3.5)
                context.stroke(path, with: .color(core), lineWidth: 1.5)
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
                for (club, p) in marks.sorted(by: { ($0.0.id == clubID ? 0 : 1, $0.1.y) < ($1.0.id == clubID ? 0 : 1, $1.1.y) }) {
                    let own = club.id == clubID
                    let dot = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
                    context.fill(dot, with: .color(own ? .blue : Color(white: 0.45)))
                    context.stroke(dot, with: .color(.white), lineWidth: 1.5)
                    context.draw(
                        Text(Image(systemName: own ? LocationStore.markSymbol(for: club.id) : "figure.rower")).font(.system(size: 10, weight: .bold)).foregroundStyle(.white),
                        at: p, anchor: .center
                    )
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
    }
}

/// The wind arrows on a satellite picture, as on the lake map: an even grid
/// worked out between the forecast points, more arrows as the picture zooms
/// in, the same size on screen, fainter on land up to WindArrows.ashoreM from
/// the shore. The arrow nearest each forecast point carries its speed.
enum SatelliteWind {
    /// Draws on `context`, whose points are the screen's: the picture is `size`
    /// at zoom 1 and shows `zoom` times larger, its corner `offset` above and
    /// left of the drawing's corner; `visible` is the size drawn on.
    static func draw(in context: GraphicsContext, view: LakeView, box: [Double], size: CGSize,
                     zoom: CGFloat, offset: CGPoint, visible: CGSize) {
        guard !view.hours.isEmpty, box.count == 4, size.width > 0, size.height > 0, zoom > 0 else { return }
        let hour = view.hours[view.hourIndex()]
        func point(_ lon: Double, _ lat: Double) -> CGPoint {
            CGPoint(x: (lon - box[0]) / (box[2] - box[0]) * size.width, y: (box[3] - lat) / (box[3] - box[1]) * size.height)
        }
        let water = CGMutablePath()
        for ring in view.outline where ring.count > 2 {
            water.addLines(between: ring.map { point($0[0], $0[1]) })
            water.closeSubpath()
        }
        let widthM = (box[2] - box[0]) * 111_320 * cos((box[1] + box[3]) / 2 * .pi / 180)
        let nearShore = WindArrows.nearShore(water, margin: CGFloat(WindArrows.ashoreM / widthM) * size.width)
        let samples = zip(view.points, hour.wind).compactMap { p, wind -> WindArrows.Sample? in
            guard let from = wind.fromDeg, let speed = wind.speedMs else { return nil }
            return WindArrows.Sample(point: point(p.lon, p.lat), towardDeg: from + 180, speedMs: speed)
        }
        // The part of the picture on screen, in its own points, with room for the arrows at the edges.
        let margin = WindArrows.length(15) / zoom
        let area = CGRect(x: offset.x / zoom, y: offset.y / zoom, width: visible.width / zoom, height: visible.height / zoom)
            .insetBy(dx: -margin, dy: -margin)
        let spacing = WindArrows.spacing / zoom
        let arrows = WindArrows.arrows(in: area, spacing: spacing, water: water, nearShore: nearShore, from: samples)
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom - offset.x, y: p.y * zoom - offset.y) }

        let shadow = GraphicsContext.Shading.color(.black.opacity(0.6))
        let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        for ashore in [true, false] {
            var path = Path()
            for a in arrows where a.ashore == ashore {
                path.addPath(LakeArrow.path(at: screen(a.at), towardDeg: a.towardDeg, length: WindArrows.length(a.speedMs)))
            }
            guard !path.isEmpty else { continue }
            var layer = context
            layer.opacity = ashore ? WindArrows.ashoreOpacity : 1
            layer.drawLayer { inner in
                inner.stroke(path, with: shadow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                inner.stroke(path, with: .color(.white), style: style)
            }
        }
        // Each forecast point's speed, at the tail of the arrow nearest it.
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
            let at = screen(best.at)
            context.draw(
                Text(Format.windNumber(s.speedMs)).font(.caption2.weight(.bold)).foregroundStyle(.white),
                at: CGPoint(x: at.x - CGFloat(sin(r)) * half, y: at.y + CGFloat(cos(r)) * half), anchor: .center
            )
        }
    }
}

/// How far a zoomable view is zoomed and moved, for layers drawn on the screen above it.
@Observable
final class ZoomTracker {
    var scale: CGFloat = 1
    var offset: CGPoint = .zero
}

/// The picture on its own, filling the screen, with pinch to zoom, drag to
/// move, a double tap to zoom in or back, and the same switches.
struct SatellitePictureScreen: View {
    let lakeID: String
    let picture: SatellitePicture
    @State var kind: SatellitePicture.Kind
    var clubID: String?
    @State private var zoom = ZoomTracker()
    @Environment(\.dismiss) private var dismiss
    @MainActor private var layers: SatelliteLayers { .shared }

    var body: some View {
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
                        ZoomableView(size: size, focus: focus(in: size), tracker: zoom) {
                            SatelliteImage(lakeID: lakeID, picture: picture, shot: shot, clubID: clubID, windOnScreen: true)
                                .frame(width: fit, height: fit / picture.aspectRatio)
                        }
                        .id(kind)
                        .overlay {
                            // On the screen rather than in the picture, so the arrows stay
                            // sharp and the same size, with more of them when zoomed in.
                            if layers.on.contains(.wind), let view = LakeViewStore.shared.views[lakeID], let box = picture.bbox {
                                Canvas { context, visible in
                                    SatelliteWind.draw(in: context, view: view, box: box, size: size,
                                                       zoom: zoom.scale, offset: zoom.offset, visible: visible)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
                if let shot = picture.shot(kind) {
                    VStack(alignment: .leading, spacing: 8) {
                        SatelliteCaption(picture: picture, shot: shot)
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
        let club = LakeViewStore.shared.views[lakeID]?.clubs.first { $0.id == clubID }
        return .fillWidth(around: club.map { point($0.launchPoint.lon, $0.launchPoint.lat) })
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
        if context.coordinator.size != size {
            context.coordinator.size = size
            scroll.zoomScale = 1
            context.coordinator.host.view.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size
            context.coordinator.focused = false
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
            if scroll.bounds.size != bounds {
                bounds = scroll.bounds.size
                focused = false
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

        /// Tells the tracker where the content now sits: its corner is the
        /// content offset above and left of the scroll view's corner.
        private func report(_ scroll: UIScrollView) {
            guard let tracker else { return }
            if tracker.scale != scroll.zoomScale { tracker.scale = scroll.zoomScale }
            if tracker.offset != scroll.contentOffset { tracker.offset = scroll.contentOffset }
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

    var body: some View {
        let on = layers.on
        NavigationStack {
            List {
                Section(tr("The picture")) {
                    row(Image(systemName: "photo"), tr("A true-colour photo from the Sentinel-2 satellites, as a camera would see it from space."))
                    row(Image(systemName: "cloud.fill").foregroundStyle(.white, .gray), tr("White and grey: clouds, haze, or snow and ice on the ground."))
                    row(Image(systemName: "drop.fill").foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.3)), tr("Dark blue to black: open water."))
                }
                if on.contains(.light) {
                    Section(tr("Rowing light")) { LakeLegend(layer: .light).padding(.vertical, 4); MapBoatNote() }
                }
                if on.contains(.waves) {
                    Section(tr("Waves")) { LakeLegend(layer: .waves).padding(.vertical, 4) }
                }
                if on.contains(.wind) {
                    Section(tr("Wind")) {
                        row(Image(systemName: "arrow.up.right").fontWeight(.bold),
                            tr("Points where the wind blows to in the current hour, estimated between the forecast points, with more arrows as you zoom in; longer arrows mean stronger wind. The number is the wind speed at a forecast point. Fainter arrows on land show the wind up to 2 km from the shore."))
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
                        if on.contains(.shore) { row(line(.white), tr("Shore line: white on a clear picture, dark blue on a cloudy one")) }
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
