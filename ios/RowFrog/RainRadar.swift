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
        .task(id: point) {
            // DWD updates the radar every 5 minutes; follow it while the page is open.
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
/// slider and a play button. Pictures come straight from DWD's map server.
struct RadarMapScreen: View {
    let point: Coordinate
    /// The radar picture the nowcast starts from; now (to 5 minutes) when not known yet.
    let reference: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var playing = false
    private let frames: [Date]
    /// The frame for the latest radar picture.
    private let nowIndex: Int

    init(point: Coordinate, reference: Date?) {
        self.point = point
        self.reference = reference
        let base = reference ?? Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 / 300).rounded(.down) * 300)
        frames = stride(from: -60, through: 120, by: 15).map { base.addingTimeInterval(Double($0) * 60) }
        nowIndex = 4
        _index = State(initialValue: 4)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RadarMapView(point: point, time: frames[index])
                    .ignoresSafeArea(edges: .bottom)
                controls
            }
            .navigationTitle(tr("Rain radar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
            .task(id: playing) {
                // Plays through every frame once, then stops on the latest picture.
                guard playing else { return }
                if index == frames.count - 1 { index = 0 }
                while playing, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(700))
                    if index < frames.count - 1 { index += 1 } else { playing = false }
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
            }
            HStack(spacing: 12) {
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.title3)
                }
                .accessibilityLabel(playing ? tr("Pause") : tr("Play"))
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()); playing = false }),
                       in: 0...Double(frames.count - 1), step: 1)
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
            Text(tr("Radar: Deutscher Wetterdienst (DWD), CC BY 4.0"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

/// The map with the launch point and DWD's radar layer for one time.
private struct RadarMapView: UIViewRepresentable {
    let point: Coordinate
    let time: Date

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        let center = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        map.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.6)), animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = center
        map.addAnnotation(pin)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard context.coordinator.time != time else { return }
        context.coordinator.time = time
        let old = map.overlays
        map.addOverlay(RadarTileOverlay(time: time), level: .aboveRoads)
        // Removing the old picture after adding the new one avoids a flash of the bare map.
        map.removeOverlays(old)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var time: Date?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKTileOverlayRenderer(overlay: overlay)
            renderer.alpha = 0.75
            return renderer
        }
    }
}

/// DWD's radar layer (WMS GetMap) cut into map tiles.
final class RadarTileOverlay: MKTileOverlay {
    let time: Date

    init(time: Date) {
        self.time = time
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        Self.url(x: path.x, y: path.y, z: path.z, time: time)
    }

    /// The WMS request for one web-mercator tile.
    static func url(x: Int, y: Int, z: Int, time: Date) -> URL {
        let extent = 20_037_508.342789244
        let size = 2 * extent / pow(2, Double(z))
        let minX = -extent + Double(x) * size, maxY = extent - Double(y) * size
        var components = URLComponents(url: RadarClient.wms, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "SERVICE", value: "WMS"),
            .init(name: "VERSION", value: "1.3.0"),
            .init(name: "REQUEST", value: "GetMap"),
            .init(name: "LAYERS", value: "dwd:Niederschlagsradar"),
            .init(name: "STYLES", value: ""),
            .init(name: "CRS", value: "EPSG:3857"),
            .init(name: "BBOX", value: "\(minX),\(maxY - size),\(minX + size),\(maxY)"),
            .init(name: "WIDTH", value: "256"),
            .init(name: "HEIGHT", value: "256"),
            .init(name: "FORMAT", value: "image/png"),
            .init(name: "TRANSPARENT", value: "TRUE"),
            .init(name: "TIME", value: ISO8601DateFormatter().string(from: time)),
        ]
        return components.url!
    }
}
