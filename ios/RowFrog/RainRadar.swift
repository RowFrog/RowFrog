import MapKit
import SwiftUI
import TipKit

/// Rain at the launch point from DWD's radar: now and DWD's nowcast for the
/// next two hours. The app asks DWD directly (open data, no account), so the
/// radar is as fresh as DWD's 5-minute updates whatever hosts the backend.
/// Source: WMS layer dwd:Niederschlagsradar (RV product, 1 km), read at the
/// launch point with GetFeatureInfo; no rain comes back as a tiny negative value.
struct RadarStep: Hashable {
    let time: Date
    let mmPerHour: Double
}

struct RainRadar: Hashable {
    /// The radar picture the nowcast starts from.
    let reference: Date
    /// Now and every 15 minutes up to two hours ahead.
    let steps: [RadarStep]

    static let rainFrom = 0.1  // mm/h; less is noise or drizzle that does not count

    var rainingNow: Bool { (steps.first?.mmPerHour ?? 0) >= Self.rainFrom }
    var firstRain: RadarStep? { steps.first { $0.mmPerHour >= Self.rainFrom } }
    var dryAgain: RadarStep? {
        guard rainingNow else { return nil }
        return steps.first { $0.mmPerHour < Self.rainFrom }
    }
    var peak: Double { steps.map(\.mmPerHour).max() ?? 0 }

    /// One line, e.g. "Light rain from 21:30".
    var summary: String {
        guard let first = firstRain else { return tr("No rain in the next 2 hours") }
        if rainingNow {
            if let dry = dryAgain { return tr("%@ now, dry from %@", Self.intensity(peak), Format.time(dry.time)) }
            return tr("%@ for the next 2 hours", Self.intensity(peak))
        }
        return tr("%@ from %@", Self.intensity(peak), Format.time(first.time))
    }

    static func intensity(_ mmPerHour: Double) -> String {
        switch mmPerHour {
        case ..<2.5: tr("Light rain")
        case ..<10: tr("Rain")
        default: tr("Heavy rain")
        }
    }
}

struct RadarClient {
    static let wms = URL(string: "https://maps.dwd.de/geoserver/dwd/wms")!
    var session: URLSession = .shared

    func load(lat: Double, lon: Double) async throws -> RainRadar {
        let now = try await reading(lat: lat, lon: lon, time: nil)
        let reference = now.reference
        let steps = try await withThrowingTaskGroup(of: RadarStep.self) { group in
            for minutes in stride(from: 0, through: 120, by: 15) {
                let time = reference.addingTimeInterval(Double(minutes) * 60)
                group.addTask { try await reading(lat: lat, lon: lon, time: time).step }
            }
            var steps: [RadarStep] = []
            for try await step in group { steps.append(step) }
            return steps.sorted { $0.time < $1.time }
        }
        return RainRadar(reference: reference, steps: steps)
    }

    private func reading(lat: Double, lon: Double, time: Date?) async throws -> (step: RadarStep, reference: Date) {
        let d = 0.01
        var components = URLComponents(url: Self.wms, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "SERVICE", value: "WMS"),
            .init(name: "VERSION", value: "1.3.0"),
            .init(name: "REQUEST", value: "GetFeatureInfo"),
            .init(name: "LAYERS", value: "dwd:Niederschlagsradar"),
            .init(name: "QUERY_LAYERS", value: "dwd:Niederschlagsradar"),
            .init(name: "CRS", value: "EPSG:4326"),
            // WMS 1.3.0 with EPSG:4326 takes latitude first.
            .init(name: "BBOX", value: "\(lat - d),\(lon - d),\(lat + d),\(lon + d)"),
            .init(name: "WIDTH", value: "101"),
            .init(name: "HEIGHT", value: "101"),
            .init(name: "I", value: "50"),
            .init(name: "J", value: "50"),
            .init(name: "INFO_FORMAT", value: "application/json"),
        ]
        if let time {
            components.queryItems?.append(.init(name: "TIME", value: ISO8601DateFormatter().string(from: time)))
        }
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let props = try JSONDecoder().decode(FeatureInfo.self, from: data).features.first?.properties,
              let at = ISO8601DateFormatter().date(from: props.time),
              let reference = ISO8601DateFormatter().date(from: props.reference) else {
            throw URLError(.cannotParseResponse)
        }
        return (RadarStep(time: at, mmPerHour: max(0, props.value ?? 0)), reference)
    }

    private struct FeatureInfo: Decodable {
        struct Feature: Decodable { let properties: Properties }
        struct Properties: Decodable {
            let value: Double?
            let time: String
            let reference: String

            enum CodingKeys: String, CodingKey {
                case value = "RV_ANALYSIS"
                case time = "TIME"
                case reference = "REFERENCE_TIME"
            }
        }
        let features: [Feature]
    }
}

/// The rain radar card: a one-line summary and a bar per 15 minutes. A tap
/// opens the radar map.
struct RainRadarCard: View {
    let point: Coordinate
    @State private var radar: RainRadar?
    @State private var failed = false
    @State private var showingMap = UserDefaults.standard.bool(forKey: "RWOpenRadarMap")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button { showingMap = true } label: {
            Card(title: tr("Rain radar"), symbol: "umbrella") {
                if let radar {
                    HStack {
                        Text(radar.summary).font(.headline)
                        Spacer(minLength: 0)
                        Label(tr("Map"), systemImage: "chevron.right")
                            .labelStyle(TrailingIcon())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    bars(radar)
                    Text(tr("Radar: Deutscher Wetterdienst (DWD), CC BY 4.0"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if failed {
                    Text(tr("Radar not available right now")).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("Opens the rain radar map"))
        .fullScreenCover(isPresented: $showingMap) {
            RadarMapScreen(point: point, reference: radar?.reference)
        }
        .onChange(of: showingMap) { if showingMap { RadarMapTip().invalidate(reason: .actionPerformed) } }
        .task(id: [point.lat, point.lon, scenePhase == .active ? 1 : 0]) {
            // DWD updates the radar every 5 minutes; follow it while the page is open
            // and the app is in front.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                    radar = try await RadarClient().load(lat: point.lat, lon: point.lon)
                    failed = false
                } catch is CancellationError {
                    return
                } catch {
                    failed = radar == nil
                }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private func bars(_ radar: RainRadar) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(radar.steps, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step.mmPerHour >= RainRadar.rainFrom ? Color.blue : Color.secondary.opacity(0.25))
                        .frame(height: 4 + 36 * min(step.mmPerHour / 10, 1))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(Format.time(step.time)): \(Format.rain(step.mmPerHour))")
                }
            }
            .frame(height: 40, alignment: .bottom)
            HStack {
                Text(tr("Now"))
                Spacer()
                Text("+1 h")
                Spacer()
                Text("+2 h")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon
        }
    }
}

/// The rain radar as a map around the club: DWD's radar pictures from an
/// hour ago to DWD's nowcast two hours ahead, every 15 minutes, with a
/// slider, a play button and a loop switch. Every picture is loaded first,
/// as one image of the region around the club, so playing never waits for
/// map tiles and the picture never drops out between steps.
struct RadarMapScreen: View {
    let point: Coordinate
    /// The radar picture the nowcast starts from; now (to 5 minutes) when not known yet.
    let reference: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var playing = false
    @State private var loader: RadarFrames
    @State private var showingLegend = false
    @AppStorage("RWRadarLoop") private var loops = true
    private let frames: [Date]
    /// The frame for the latest radar picture.
    private let nowIndex: Int

    init(point: Coordinate, reference: Date?) {
        self.point = point
        self.reference = reference
        let base = reference ?? Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 / 300).rounded(.down) * 300)
        let frames = stride(from: -60, through: 120, by: 15).map { base.addingTimeInterval(Double($0) * 60) }
        self.frames = frames
        nowIndex = 4
        _index = State(initialValue: 4)
        _loader = State(initialValue: RadarFrames(point: point, times: frames))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RadarMapView(point: point, region: loader.region, image: loader.images[frames[index]])
                    .ignoresSafeArea(edges: .bottom)
                controls
            }
            .navigationTitle(tr("Rain radar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
            .sheet(isPresented: $showingLegend) { RadarLegendSheet() }
            .task { await loader.load() }
            // Starts playing on its own once every picture is there.
            .onChange(of: loader.complete) { _, complete in if complete { playing = true } }
            .task(id: playing) {
                guard playing else { return }
                if index == frames.count - 1 { index = 0 }
                while playing, !Task.isCancelled {
                    // A little longer on the latest picture and at the end, so they can be read.
                    try? await Task.sleep(for: .milliseconds(index == nowIndex || index == frames.count - 1 ? 1400 : 600))
                    guard playing, !Task.isCancelled else { return }
                    if index < frames.count - 1 {
                        index += 1
                    } else if loops {
                        index = 0
                    } else {
                        playing = false
                        index = nowIndex
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Format.time(frames[index])).font(.headline.monospacedDigit())
                Text(index < nowIndex ? tr("radar") : index == nowIndex ? tr("latest radar picture") : tr("forecast"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !loader.complete {
                    ProgressView(value: Double(loader.images.count), total: Double(frames.count))
                        .frame(width: 60)
                        .accessibilityLabel(tr("Loading the radar pictures"))
                }
                Button { showingLegend = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel(tr("What the colours mean"))
            }
            RadarColourBar()
            HStack(spacing: 12) {
                Button {
                    playing.toggle()
                } label: {
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
                .accessibilityLabel(tr("Keep playing"))
                .accessibilityAddTraits(loops ? .isSelected : [])
            }
            HStack {
                Text("−1 h")
                Spacer()
                Text(tr("Now"))
                Spacer()
                Text("+1 h")
                Spacer()
                Text("+2 h")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if loader.failedCount > 0, loader.done {
                Text(tr("%@ of %@ pictures could not be loaded.", "\(loader.failedCount)", "\(frames.count)"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text(tr("Radar: Deutscher Wetterdienst (DWD), CC BY 4.0"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

/// DWD's colours for rain (RV product, mm per hour), light to heavy, as in
/// its radar layer. Shown as a bar on the map and explained in the legend.
enum RadarColours {
    static let steps: [(mm: Double, color: Color)] = [
        (0.1, Color(red: 0.70, green: 0.94, blue: 0.98)),
        (0.5, Color(red: 0.36, green: 0.80, blue: 0.95)),
        (1, Color(red: 0.13, green: 0.55, blue: 0.95)),
        (2, Color(red: 0.12, green: 0.30, blue: 0.85)),
        (5, Color(red: 0.98, green: 0.90, blue: 0.20)),
        (10, Color(red: 0.98, green: 0.60, blue: 0.10)),
        (20, Color(red: 0.92, green: 0.15, blue: 0.10)),
        (50, Color(red: 0.75, green: 0.10, blue: 0.70)),
    ]
}

/// A thin colour bar from light to heavy rain with a few numbers under it.
private struct RadarColourBar: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(RadarColours.steps.indices, id: \.self) { i in
                    RadarColours.steps[i].color.frame(height: 6)
                }
            }
            .clipShape(Capsule())
            HStack {
                Text(tr("light"))
                Spacer()
                Text(Format.rain(2))
                Spacer()
                Text(Format.rain(10))
                Spacer()
                Text(tr("heavy"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Colours from light blue for light rain to red and purple for heavy rain"))
    }
}

/// What each colour on the radar map means.
private struct RadarLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RadarColours.steps.indices, id: \.self) { i in
                        let step = RadarColours.steps[i]
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4).fill(step.color).frame(width: 28, height: 18)
                            Text(tr("from %@ per hour", Format.rain(step.mm)))
                            Spacer()
                            Text(RainRadar.intensity(step.mm)).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(tr("Rain as measured by DWD's radar (past and latest picture) and as DWD expects it to move (forecast). Colours are close to DWD's own; snow and hail show as rain. Radar: Deutscher Wetterdienst (DWD), CC BY 4.0"))
                }
            }
            .navigationTitle(tr("What the colours mean"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Loads DWD's radar picture for every frame as one image of the region
/// around the club, a few at a time, with retries. Frames that fail stay
/// empty and the slider skips nothing, so the time is still clear.
@Observable
@MainActor
final class RadarFrames {
    let region: RadarRegion
    let times: [Date]
    private(set) var images: [Date: UIImage] = [:]
    private(set) var failedCount = 0
    private(set) var done = false
    var complete: Bool { images.count == times.count }

    init(point: Coordinate, times: [Date]) {
        region = RadarRegion(center: point)
        self.times = times
    }

    func load() async {
        guard !done else { return }
        // The latest picture first, then outwards, so the map shows something at once.
        let order = times.indices.sorted { abs($0 - 4) < abs($1 - 4) }.map { times[$0] }
        let region = region
        await withTaskGroup(of: (Date, UIImage?).self) { group in
            // DWD's server is slow with many parallel requests; three at a time.
            var next = 0
            while next < min(3, order.count) {
                let time = order[next]
                group.addTask { (time, await Self.fetch(region.url(time: time))) }
                next += 1
            }
            while let (time, image) = await group.next() {
                if let image { images[time] = image } else { failedCount += 1 }
                if next < order.count {
                    let time = order[next]
                    group.addTask { (time, await Self.fetch(region.url(time: time))) }
                    next += 1
                }
            }
        }
        done = true
    }

    private nonisolated static func fetch(_ url: URL) async -> UIImage? {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let image = UIImage(data: data) {
                return image
            }
            if Task.isCancelled { return nil }
        }
        return nil
    }
}

/// The square of map around the club the radar pictures cover, about
/// 400 km across, in web-mercator so the picture lies straight on the map.
struct RadarRegion: Hashable {
    let minX: Double, minY: Double, maxX: Double, maxY: Double
    static let pixels = 1024
    private static let radius = 6_378_137.0

    init(center: Coordinate) {
        let x = center.lon * .pi / 180 * Self.radius
        let y = log(tan(.pi / 4 + center.lat * .pi / 360)) * Self.radius
        // 200 km of map each way; mercator stretches it to about 300 km at 47° N.
        let half = 300_000.0
        minX = x - half; maxX = x + half
        minY = y - half; maxY = y + half
    }

    /// The corners as map coordinates, for the overlay.
    var northWest: CLLocationCoordinate2D { Self.coordinate(x: minX, y: maxY) }
    var southEast: CLLocationCoordinate2D { Self.coordinate(x: maxX, y: minY) }

    private static func coordinate(x: Double, y: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (2 * atan(exp(y / radius)) - .pi / 2) * 180 / .pi, longitude: x / radius * 180 / .pi)
    }

    /// The WMS request for the whole region at one time.
    func url(time: Date) -> URL {
        var components = URLComponents(url: RadarClient.wms, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "SERVICE", value: "WMS"),
            .init(name: "VERSION", value: "1.3.0"),
            .init(name: "REQUEST", value: "GetMap"),
            .init(name: "LAYERS", value: "dwd:Niederschlagsradar"),
            .init(name: "STYLES", value: ""),
            .init(name: "CRS", value: "EPSG:3857"),
            .init(name: "BBOX", value: "\(minX),\(minY),\(maxX),\(maxY)"),
            .init(name: "WIDTH", value: "\(Self.pixels)"),
            .init(name: "HEIGHT", value: "\(Self.pixels)"),
            .init(name: "FORMAT", value: "image/png"),
            .init(name: "TRANSPARENT", value: "TRUE"),
            .init(name: "TIME", value: ISO8601DateFormatter().string(from: time)),
        ]
        return components.url!
    }
}

/// The map with the launch point and one radar picture over the region.
private struct RadarMapView: UIViewRepresentable {
    let point: Coordinate
    let region: RadarRegion
    let image: UIImage?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        let center = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        map.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.6)), animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = center
        map.addAnnotation(pin)
        map.addOverlay(RadarImageOverlay(region: region), level: .aboveRoads)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // One overlay for all frames; only its picture changes, so nothing flashes.
        context.coordinator.pending = image
        context.coordinator.renderer?.show(image)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderer: RadarImageRenderer?
        var pending: UIImage?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let overlay = overlay as? RadarImageOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = RadarImageRenderer(overlay: overlay)
            renderer.alpha = 0.75
            renderer.show(pending)
            self.renderer = renderer
            return renderer
        }
    }
}

/// Where the radar picture lies on the map.
final class RadarImageOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(region: RadarRegion) {
        let nw = MKMapPoint(region.northWest), se = MKMapPoint(region.southEast)
        boundingMapRect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
    }
}

/// Draws the current radar picture over its region.
final class RadarImageRenderer: MKOverlayRenderer {
    private var image: CGImage?

    func show(_ picture: UIImage?) {
        let next = picture?.cgImage
        guard next !== image else { return }
        // A frame still loading keeps the last picture rather than an empty map.
        if next == nil, image != nil { return }
        image = next
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let image else { return }
        let rect = self.rect(for: overlay.boundingMapRect)
        // Core Graphics draws images upside down in the map's flipped context.
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
