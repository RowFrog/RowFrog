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
}

/// What can be drawn over the picture.
enum SatelliteLayer: String, CaseIterable, Identifiable {
    case shore, clubs, routes, wind, waves, light, ice
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
    /// Screenshot hook: `-RWOpenSatellite YES` opens the picture full screen.
    @State private var showingFull = UserDefaults.standard.bool(forKey: "RWOpenSatellite")

    var body: some View {
        Group {
            if let picture = store.pictures[lakeID], let shot = picture.shot(kind) {
                Card(title: tr("Satellite picture"), symbol: "globe.europe.africa") {
                    if picture.hasChoice {
                        SatelliteKindPicker(picture: picture, kind: $kind)
                    }
                    Button { showingFull = true } label: {
                        // The whole card fits on one screen: the picture takes what the screen
                        // leaves after the bars, the picker, the caption and the switches.
                        SatelliteImage(lakeID: lakeID, picture: picture, shot: shot, clubID: clubID)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(maxHeight: max(300, UIScreen.main.bounds.height - 360))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Satellite picture of the lake"))
                    SatelliteCaption(picture: picture, shot: shot)
                    SatelliteLayerChips(lakeID: lakeID, picture: picture)
                }
                .fullScreenCover(isPresented: $showingFull) {
                    SatellitePictureScreen(lakeID: lakeID, picture: picture, kind: kind, clubID: clubID)
                }
            }
        }
        // Runs once the picture shows (LocationPageView loads the picture itself):
        // the overlays need the lake view.
        .task { await LakeViewStore.shared.load(lakeID) }
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
            case .mostlyClear: return tr("Mostly clear")
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
        .overlay { SatelliteOverlay(lakeID: lakeID, picture: picture, layers: layers.on, clubID: clubID) }
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
    var clubID: String?
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
                        Text(Image(systemName: own ? "house.fill" : "figure.rower")).font(.system(size: 10, weight: .bold)).foregroundStyle(.white),
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

/// The picture on its own, filling the screen, with pinch to zoom, drag to
/// move, a double tap to zoom in or back, and the same switches.
struct SatellitePictureScreen: View {
    let lakeID: String
    let picture: SatellitePicture
    @State var kind: SatellitePicture.Kind
    var clubID: String?
    @Environment(\.dismiss) private var dismiss

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
                        ZoomableView(size: CGSize(width: fit, height: fit / picture.aspectRatio)) {
                            SatelliteImage(lakeID: lakeID, picture: picture, shot: shot, clubID: clubID)
                                .frame(width: fit, height: fit / picture.aspectRatio)
                        }
                        .id(kind)
                    }
                }
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

/// SwiftUI content in a UIKit scroll view, which zooms and pans like Photos.
/// The content keeps its size; the scroll view scales it up to 6 times.
struct ZoomableView<Content: View>: UIViewRepresentable {
    let size: CGSize
    @ViewBuilder let content: Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
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
        if context.coordinator.size != size {
            context.coordinator.size = size
            scroll.zoomScale = 1
            context.coordinator.host.view.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size
        }
        context.coordinator.centre(scroll)
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: AnyView(content), size: size) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<AnyView>
        var size: CGSize

        init(content: AnyView, size: CGSize) {
            host = UIHostingController(rootView: content)
            // The picture sits in the scroll view, not at the screen's edges.
            host.safeAreaRegions = []
            self.size = size
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centre(scrollView) }

        /// Keeps the picture in the middle while it is smaller than the screen.
        func centre(_ scroll: UIScrollView) {
            let content = host.view.frame.size
            let dx = max(0, (scroll.bounds.width - content.width) / 2)
            let dy = max(0, (scroll.bounds.height - content.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
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
