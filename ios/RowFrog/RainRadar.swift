import MapKit
import SwiftUI
import TipKit

/// Reads DWD's radar at the launch point for the rain radar card (see
/// `RainRadar` in Models.swift). The app asks DWD directly (open data, no
/// account), so the radar is as fresh as DWD's 5-minute updates whatever
/// hosts the backend.
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

/// The last radar reading per launch point, so a page swiped back to, or the
/// hour view opened over it, shows it without asking DWD again (10 requests
/// a time).
@MainActor
enum RadarCache {
    /// DWD's 5 minutes; 15 in Low Power Mode and when saving data.
    static var refresh: TimeInterval { PowerState.shared.lowPower || DataSaver.shared.saving ? 900 : 300 }
    private static var entries: [Coordinate: (radar: RainRadar, loaded: Date)] = [:]

    static func entry(at point: Coordinate) -> (radar: RainRadar, loaded: Date)? { entries[point] }

    static func store(_ radar: RainRadar, at point: Coordinate) {
        entries[point] = (radar, .now)
    }
}

/// The rain radar card: a one-line summary and a bar per 15 minutes. A tap
/// opens the radar map.
struct RainRadarCard: View {
    let point: Coordinate
    var clubID: String?
    @State private var radar: RainRadar?
    @State private var failed = false
    @State private var showingMap = UserDefaults.standard.bool(forKey: "RWOpenRadarMap")
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isCurrentPage) private var isCurrentPage

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
            RadarMapScreen(point: point, clubID: clubID, reference: radar?.reference, step: DataSaver.shared.saving ? 30 : 15)
        }
        .onChange(of: showingMap) { if showingMap { RadarMapTip().invalidate(reason: .actionPerformed) } }
        .task(id: [point.lat, point.lon, scenePhase == .active && isCurrentPage ? 1 : 0]) {
            // DWD updates the radar every 5 minutes; follow it while the page is in
            // front and the app is open. A swiping TabView keeps the pages beside it
            // alive too, and they wait, showing what was loaded last.
            if let cached = RadarCache.entry(at: point) { radar = cached.radar }
            guard scenePhase == .active, isCurrentPage else { return }
            while !Task.isCancelled {
                // Back on a page within 5 minutes: no new requests until the 5 minutes are up.
                if let age = RadarCache.entry(at: point).map({ Date.now.timeIntervalSince($0.loaded) }), age < RadarCache.refresh {
                    try? await Task.sleep(for: .seconds(RadarCache.refresh - age))
                    continue
                }
                do {
                    let loaded = try await RadarClient().load(lat: point.lat, lon: point.lon)
                    radar = loaded
                    failed = false
                    RadarCache.store(loaded, at: point)
                } catch is CancellationError {
                    return
                } catch {
                    failed = radar == nil
                }
                try? await Task.sleep(for: .seconds(RadarCache.refresh))
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
    let clubID: String?
    /// The radar picture the nowcast starts from; now (to 5 minutes) when not known yet.
    let reference: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var playing = false
    @State private var loader: RadarFrames
    @State private var showingLegend = false
    @AppStorage("RWRadarLoop") private var loops = true
    private let frames: [Date]
    /// Rounds played with repeat on, about half a minute.
    private static let rounds = 3
    /// The frame for the latest radar picture.
    private let nowIndex: Int

    /// `step`: minutes between pictures; 30 when saving data (7 pictures instead of 13).
    init(point: Coordinate, clubID: String? = nil, reference: Date?, step: Int = 15) {
        self.point = point
        self.clubID = clubID
        self.reference = reference
        let base = reference ?? Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 / 300).rounded(.down) * 300)
        let frames = stride(from: -60, through: 120, by: step).map { base.addingTimeInterval(Double($0) * 60) }
        self.frames = frames
        nowIndex = 60 / step
        _index = State(initialValue: 60 / step)
        _loader = State(initialValue: RadarFrames(point: point, times: frames, nowIndex: 60 / step))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RadarMapView(point: point, clubID: clubID, region: loader.region, image: loader.images[frames[index]])
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
            // Starts playing on its own once every picture is there, except in Low Power Mode.
            .onChange(of: loader.complete) { _, complete in if complete, !PowerState.shared.lowPower { playing = true } }
            .task(id: playing) {
                guard playing else { return }
                if index == frames.count - 1 { index = 0 }
                // Repeating stops after a few rounds, back on the latest picture;
                // the play button starts it again.
                var rounds = 0
                while playing, !Task.isCancelled {
                    // A little longer on the latest picture and at the end, so they can be read.
                    try? await Task.sleep(for: .milliseconds(index == nowIndex || index == frames.count - 1 ? 1400 : 600))
                    guard playing, !Task.isCancelled else { return }
                    if index < frames.count - 1 {
                        index += 1
                    } else if loops, rounds < Self.rounds - 1 {
                        rounds += 1
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
                .accessibilityLabel(tr("Play 3 times"))
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

/// One colour of DWD's radar layer and the rain it stands for, in mm per hour.
struct RadarColour {
    let hex: UInt32
    let from: Double
    let to: Double?

    var color: Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// "0.4–1 mm/h", "≥ 150 mm/h".
    var range: String {
        let n = Self.number
        guard let to else { return "≥ \(n(from)) mm/h" }
        return "\(n(from))–\(n(to)) mm/h"
    }

    /// "0,1", "7,5", "10": a decimal only where there is one.
    static func number(_ v: Double) -> String {
        Format.number(v, digits: v.rounded() == v ? 0 : 1)
    }
}

/// The colours of DWD's layer dwd:Niederschlagsradar, as its legend gives them
/// (GetLegendGraphic, checked with scripts/radar_probe.py on 25 Oct 2026).
enum RadarColours {
    static let all: [RadarColour] = [
        RadarColour(hex: 0x33FFFF, from: 0.1, to: 0.2),
        RadarColour(hex: 0x1ACC9A, from: 0.2, to: 0.4),
        RadarColour(hex: 0x019934, from: 0.4, to: 1),
        RadarColour(hex: 0x4DB31B, from: 1, to: 2),
        RadarColour(hex: 0x99CC01, from: 2, to: 3),
        RadarColour(hex: 0xCCE601, from: 3, to: 5),
        RadarColour(hex: 0xFFFF01, from: 5, to: 7.5),
        RadarColour(hex: 0xFFC401, from: 7.5, to: 10),
        RadarColour(hex: 0xFF8901, from: 10, to: 15),
        RadarColour(hex: 0xFF4501, from: 15, to: 30),
        RadarColour(hex: 0xFE0000, from: 30, to: 45),
        RadarColour(hex: 0xE5004C, from: 45, to: 75),
        RadarColour(hex: 0xCC0098, from: 75, to: 100),
        RadarColour(hex: 0x6600CB, from: 100, to: 150),
        RadarColour(hex: 0x0000FE, from: 150, to: nil),
    ]
}

/// A thin colour bar from light to heavy rain with a few numbers under it.
private struct RadarColourBar: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(RadarColours.all.indices, id: \.self) { i in
                    RadarColours.all[i].color.frame(height: 6)
                }
            }
            .clipShape(Capsule())
            // The numbers sit under the start of their colour.
            GeometryReader { geo in
                let step = geo.size.width / CGFloat(RadarColours.all.count)
                ForEach([0, 4, 8, 11], id: \.self) { i in
                    Text(RadarColour.number(RadarColours.all[i].from))
                        .fixedSize()
                        .position(x: step * CGFloat(i) + (i == 0 ? 8 : 0), y: 6)
                }
                Text("mm/h").fixedSize().position(x: geo.size.width - 14, y: 6)
            }
            .frame(height: 12)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Colours from light blue for light rain over green and yellow to red and purple for heavy rain"))
    }
}

/// What each colour on the radar map means.
private struct RadarLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RadarColours.all.indices, id: \.self) { i in
                        let colour = RadarColours.all[i]
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4).fill(colour.color).frame(width: 28, height: 18)
                            Text(colour.range).monospacedDigit()
                            Spacer()
                            Text(RainRadar.intensity(colour.from)).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(tr("Rain as measured by DWD's radar (past and latest picture) and as DWD expects it to move (forecast). Snow and hail show as rain. Radar: Deutscher Wetterdienst (DWD), CC BY 4.0"))
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

    /// The latest radar picture's place in `times`; loading starts there.
    let nowIndex: Int

    init(point: Coordinate, times: [Date], nowIndex: Int = 4) {
        region = RadarRegion(center: point)
        self.times = times
        self.nowIndex = nowIndex
    }

    func load() async {
        guard !done else { return }
        // Opened again for the same club before DWD's next radar picture:
        // the pictures of the last opening, with nothing to load.
        let region = region
        if let saved = Self.saved, saved.region == region, saved.times == times {
            for (time, data) in saved.data where images[time] == nil { images[time] = UIImage(data: data) }
        } else {
            Self.saved = (region, times, [:])
        }
        // The latest picture first, then outwards, so the map shows something at once.
        let order = times.indices.sorted { abs($0 - nowIndex) < abs($1 - nowIndex) }.map { times[$0] }.filter { images[$0] == nil }
        await withTaskGroup(of: (Date, Data?).self) { group in
            // DWD's server is slow with many parallel requests; three at a time.
            var next = 0
            while next < min(3, order.count) {
                let time = order[next]
                group.addTask { (time, await Self.fetch(region.url(time: time))) }
                next += 1
            }
            while let (time, data) = await group.next() {
                if let data, let image = UIImage(data: data) {
                    images[time] = image
                    if Self.saved?.region == region, Self.saved?.times == times { Self.saved?.data[time] = data }
                } else {
                    failedCount += 1
                }
                if next < order.count {
                    let time = order[next]
                    group.addTask { (time, await Self.fetch(region.url(time: time))) }
                    next += 1
                }
            }
        }
        done = true
    }

    /// The last map's pictures as DWD sent them (about 2 MB).
    private static var saved: (region: RadarRegion, times: [Date], data: [Date: Data])?

    private nonisolated static func fetch(_ url: URL) async -> Data? {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               UIImage(data: data) != nil {
                return data
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
    var clubID: String?
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

    func makeCoordinator() -> Coordinator { Coordinator(symbol: LocationStore.markSymbol(for: clubID)) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let symbol: String
        var renderer: RadarImageRenderer?
        var pending: UIImage?

        init(symbol: String) { self.symbol = symbol }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let overlay = overlay as? RadarImageOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = RadarImageRenderer(overlay: overlay)
            renderer.alpha = 0.75
            renderer.show(pending)
            self.renderer = renderer
            return renderer
        }

        /// The club as on the other maps: blue, with a house for the home base.
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
