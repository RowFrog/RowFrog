import SwiftUI

/// Sentinel-2 pictures of a lake, published by the backend
/// (backend/rowerweather/sources/sentinel2.py, scripts/publish_static.py) next to
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
    /// The newest pass that shows most of the lake, even with some cloud.
    var latest: Shot?
    /// The newest pass with the lake (nearly) free of cloud.
    var clearest: Shot?
    var ice: IceMap?
    var attribution: String?

    var aspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 1.6 }
        return CGFloat(width) / CGFloat(height)
    }

    /// Both pictures, when they are different passes.
    var hasChoice: Bool {
        guard let latest, let clearest else { return false }
        return latest.date != clearest.date
    }

    func shot(_ kind: Kind) -> Shot? {
        switch kind {
        case .latest: latest ?? clearest
        case .clearest: clearest ?? latest
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case latest, clearest
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
    static let shared = SatellitePictureStore(api: .fromBundle())

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
            } else {
                missing.insert(lakeID)
            }
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
}

/// What can be drawn over the picture.
enum SatelliteLayer: String, CaseIterable, Identifiable {
    case shore, clubs, routes, wind, ice
    var id: String { rawValue }

    var title: String {
        switch self {
        case .shore: tr("Shore")
        case .clubs: tr("Clubs")
        case .routes: tr("Routes")
        case .wind: tr("Wind")
        case .ice: tr("Ice map")
        }
    }

    var symbol: String {
        switch self {
        case .shore: "scribble"
        case .clubs: "mappin"
        case .routes: "point.topleft.down.to.point.bottomright.curvepath"
        case .wind: "wind"
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
        if on.contains(layer) { on.remove(layer) } else { on.insert(layer) }
    }
}

/// "Satellite picture": the lake from space. Shows the latest picture; when it
/// is cloudy, a switch offers the clearest one. Shore, clubs, saved routes, wind
/// and (in winter) the ice map can be drawn over it. Tap for full screen.
/// Hidden when there is no picture.
struct SatellitePictureCard: View {
    let lakeID: String
    @MainActor private var store: SatellitePictureStore { .shared }
    @State private var kind: SatellitePicture.Kind = .latest
    @State private var showingFull = false

    var body: some View {
        Group {
            if let picture = store.pictures[lakeID], let shot = picture.shot(kind) {
                Card(title: tr("Satellite picture"), symbol: "globe.europe.africa") {
                    if picture.hasChoice {
                        SatelliteKindPicker(picture: picture, kind: $kind)
                    }
                    Button { showingFull = true } label: {
                        SatelliteImage(lakeID: lakeID, picture: picture, shot: shot)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Satellite picture of the lake"))
                    SatelliteCaption(picture: picture, shot: shot)
                    SatelliteLayerChips(lakeID: lakeID, picture: picture)
                }
                .fullScreenCover(isPresented: $showingFull) {
                    SatellitePictureScreen(lakeID: lakeID, picture: picture, kind: kind)
                }
            }
        }
        .task {
            await store.load(lakeID)
            await LakeViewStore.shared.load(lakeID)
        }
    }
}

/// "Latest, 21 Oct" | "Clearest, 12 Oct".
struct SatelliteKindPicker: View {
    let picture: SatellitePicture
    @Binding var kind: SatellitePicture.Kind

    var body: some View {
        Picker(tr("Satellite picture"), selection: $kind) {
            ForEach(SatellitePicture.Kind.allCases) { kind in
                Text(label(kind)).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    private func label(_ kind: SatellitePicture.Kind) -> String {
        let day = picture.shot(kind)?.day.map { Format.day($0) } ?? ""
        return kind == .latest ? tr("Latest, %@", day) : tr("Clearest, %@", day)
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
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
    @MainActor private var layers: SatelliteLayers { .shared }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
    }

    private var available: [SatelliteLayer] {
        let view = LakeViewStore.shared.views[lakeID]
        return SatelliteLayer.allCases.filter { layer in
            switch layer {
            case .shore: view != nil
            case .clubs: !(view?.clubs.isEmpty ?? true)
            case .routes: !RouteStore.shared.routes(on: lakeID).isEmpty
            case .wind: !(view?.hours.isEmpty ?? true)
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
    @MainActor private var store: SatellitePictureStore { .shared }
    @MainActor private var layers: SatelliteLayers { .shared }

    var body: some View {
        AsyncImage(url: store.url(lakeID, file: shot.image, date: shot.date)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Color.secondary.opacity(0.15).overlay { ProgressView() }
            }
        }
        .aspectRatio(picture.aspectRatio, contentMode: .fit)
        .overlay { iceOverlay }
        .overlay { SatelliteOverlay(lakeID: lakeID, picture: picture, layers: layers.on) }
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
                AsyncImage(url: url) { phase in
                    phase.image?.resizable().interpolation(.none)
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
    @MainActor private var view: LakeView? { LakeViewStore.shared.views[lakeID] }

    var body: some View {
        Canvas { context, size in
            guard let box = picture.bbox, box.count == 4 else { return }
            func point(_ lon: Double, _ lat: Double) -> CGPoint {
                CGPoint(x: (lon - box[0]) / (box[2] - box[0]) * size.width, y: (box[3] - lat) / (box[3] - box[1]) * size.height)
            }
            let shadow = GraphicsContext.Shading.color(.black.opacity(0.6))
            if layers.contains(.shore), let view {
                var path = Path()
                for ring in view.outline where ring.count > 1 {
                    path.addLines(ring.map { point($0[0], $0[1]) })
                    path.closeSubpath()
                }
                context.stroke(path, with: shadow, lineWidth: 3)
                context.stroke(path, with: .color(.white), lineWidth: 1.5)
            }
            if layers.contains(.routes) {
                for route in RouteStore.shared.routes(on: lakeID) where route.points.count > 1 {
                    var path = Path()
                    path.addLines(route.points.map { point($0.lon, $0.lat) })
                    context.stroke(path, with: shadow, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            if layers.contains(.wind), let view, !view.hours.isEmpty {
                let hour = view.hours[view.hourIndex()]
                for (p, wind) in zip(view.points, hour.wind) {
                    guard let from = wind.fromDeg, let speed = wind.speedMs else { continue }
                    let centre = point(p.lon, p.lat)
                    let toward = (from + 180) * .pi / 180
                    let length = 10 + min(speed, 15) * 1.6
                    let dx = sin(toward) * length / 2, dy = -cos(toward) * length / 2
                    let tail = CGPoint(x: centre.x - dx, y: centre.y - dy)
                    let tip = CGPoint(x: centre.x + dx, y: centre.y + dy)
                    var arrow = Path()
                    arrow.move(to: tail)
                    arrow.addLine(to: tip)
                    for side in [-0.5, 0.5] {
                        let a = toward + .pi + side
                        arrow.move(to: tip)
                        arrow.addLine(to: CGPoint(x: tip.x + sin(a) * 6, y: tip.y - cos(a) * 6))
                    }
                    context.stroke(arrow, with: shadow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    context.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    context.draw(
                        Text(Format.windNumber(speed)).font(.caption2.weight(.bold)).foregroundStyle(.white),
                        at: CGPoint(x: tail.x, y: tail.y), anchor: .center
                    )
                }
            }
            if layers.contains(.clubs), let view {
                for club in view.clubs {
                    let p = point(club.launchPoint.lon, club.launchPoint.lat)
                    let dot = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(.red))
                    context.stroke(dot, with: .color(.white), lineWidth: 1.5)
                    context.draw(
                        Text(club.shortName).font(.caption2.weight(.semibold)).foregroundStyle(.white),
                        at: CGPoint(x: p.x + 7, y: p.y), anchor: .leading
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The picture on its own, filling the screen, with pinch to zoom and the same switches.
struct SatellitePictureScreen: View {
    let lakeID: String
    let picture: SatellitePicture
    @State var kind: SatellitePicture.Kind
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if picture.hasChoice {
                    SatelliteKindPicker(picture: picture, kind: $kind)
                        .padding(.horizontal)
                }
                ScrollView([.horizontal, .vertical]) {
                    if let shot = picture.shot(kind) {
                        SatelliteImage(lakeID: lakeID, picture: picture, shot: shot)
                            .frame(width: UIScreen.main.bounds.width * scale * pinch)
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in scale = min(6, max(1, scale * value.magnification)) }
                )
                if let shot = picture.shot(kind) {
                    VStack(alignment: .leading, spacing: 8) {
                        SatelliteCaption(picture: picture, shot: shot)
                        SatelliteLayerChips(lakeID: lakeID, picture: picture)
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
    }
}
