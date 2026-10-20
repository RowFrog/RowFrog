import MapKit
import SwiftUI

/// The full lake view: the lake on a map, coloured by the rowing light, the
/// waves or the wind, hour by hour. Tap the water to see the conditions there.
struct LakeMapScreen: View {
    let view: LakeView
    let clubID: String?
    @State private var hourIndex: Int
    @State private var layer: LakeLayer
    @State private var spot: Int?
    @State private var showingInfo = false
    @Environment(\.dismiss) private var dismiss

    init(view: LakeView, clubID: String?) {
        self.view = view
        self.clubID = clubID
        let args = UserDefaults.standard
        let start = view.hourIndex() + args.integer(forKey: "RWLakeHour")
        _hourIndex = State(initialValue: min(max(start, 0), max(view.hours.count - 1, 0)))
        _layer = State(initialValue: LakeLayer(rawValue: args.string(forKey: "RWLakeLayer") ?? "") ?? .light)
        var spot: Int?
        if let text = args.string(forKey: "RWLakeSpot") {
            let parts = text.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { spot = view.grid.cell(at: CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])) }
        }
        _spot = State(initialValue: spot)
    }

    private var hour: LakeHour? { view.hours.indices.contains(hourIndex) ? view.hours[hourIndex] : nil }

    var body: some View {
        ZStack(alignment: .top) {
            LakeMapView(view: view, hour: hour, layer: layer, clubID: clubID, spot: $spot)
                .ignoresSafeArea()
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { panel }
        .sheet(isPresented: $showingInfo) { LakeViewInfo() }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .background(.regularMaterial, in: Circle())
                .accessibilityLabel(tr("Close"))
                Spacer()
                Text(view.name)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                Spacer()
                Button { showingInfo = true } label: {
                    Image(systemName: "info").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .background(.regularMaterial, in: Circle())
                .accessibilityLabel(tr("About the lake view"))
            }
            Picker(tr("Show"), selection: $layer) {
                ForEach(LakeLayer.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hour {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.dayTime(hour.time)).font(.headline)
                    Spacer()
                    if view.sample {
                        Label(tr("Sample wind"), systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                if hour.lakeWide.light > .green {
                    LakeWideBanner(lakeWide: hour.lakeWide)
                }
                if let spot, spot < hour.lights.count {
                    spotDetails(spot, hour)
                } else {
                    Text(view.headline(for: hour)).font(.subheadline.weight(.semibold))
                    if let wind = view.windSummary(for: hour) {
                        Label(wind, systemImage: Condition.wind.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(tr("Tap the water to see the conditions there."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LakeLegend(layer: layer)
            }
            LakeHourStrip(hours: view.hours, selection: $hourIndex)
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func spotDetails(_ i: Int, _ hour: LakeHour) -> some View {
        let p = view.grid.cellPoint[i]
        let wind = p < hour.wind.count ? hour.wind[p] : nil
        let zone = view.grid.cellZone[i]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                TrafficLightDot(light: hour.lights[i], size: 14)
                Text(hour.lights[i].title).font(.headline)
                Spacer()
                Button { spot = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel(tr("Close"))
            }
            if view.zones.count > 1, zone < view.zones.count {
                Text(tr("Selected spot · %@", LakeZoneName.title(view.zones[zone])))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                MetricView(title: tr("Waves"), symbol: Condition.waves.symbol, value: Format.waves(hour.wave(ofCell: i)), size: 20)
                MetricView(title: tr("Wind"), symbol: Condition.wind.symbol, value: Format.windRange(wind?.speedMs, wind?.gustMs), size: 20)
                if let from = wind?.fromDeg {
                    MetricView(title: tr("From"), symbol: "location.north.line", value: Format.compass(from), size: 20)
                }
            }
            .symbolRenderingMode(.hierarchical)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the colours mean for the chosen layer.
struct LakeLegend: View {
    let layer: LakeLayer

    var body: some View {
        HStack(spacing: 12) {
            switch layer {
            case .light:
                ForEach([Light.green, .amber, .red], id: \.self) { light in
                    HStack(spacing: 4) { TrafficLightDot(light: light, size: 9); Text(light.title) }
                }
            case .waves:
                ramp(LakeRaster.waveColor, stops: [0, 0.15, 0.30, 0.48], labels: [Format.waves(0), Format.waves(0.15), Format.waves(0.3)])
            case .wind:
                ramp(LakeRaster.windColor, stops: [0, 5.5, 8, 12.8], labels: [Format.wind(0), Format.wind(5.5), Format.wind(8)])
            }
        }
        .font(.caption)
    }

    private func ramp(_ color: @escaping (Double) -> LakeRaster.RGB, stops: [Double], labels: [String]) -> some View {
        let colors = stride(from: 0.0, through: 1.0, by: 0.1).map { t -> Color in
            let c = color(stops[0] + (stops[stops.count - 1] - stops[0]) * t)
            return Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
        }
        return VStack(alignment: .leading, spacing: 2) {
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(Capsule())
            GeometryReader { geo in
                ForEach(Array(labels.enumerated()), id: \.0) { i, label in
                    Text(label)
                        .fixedSize()
                        .position(x: geo.size.width * stops[i] / stops[stops.count - 1] + (i == 0 ? 14 : 0), y: 7)
                }
            }
            .frame(height: 14)
            .foregroundStyle(.secondary)
        }
    }
}

/// The hours to pick from, each with the share of the lake that is green, amber and red.
struct LakeHourStrip: View {
    let hours: [LakeHour]
    @Binding var selection: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(hours.enumerated()), id: \.1.id) { i, hour in
                        Button { selection = i } label: {
                            VStack(spacing: 4) {
                                Text(Format.time(hour.time)).font(.caption.monospacedDigit())
                                ShareBar(hour: hour).frame(width: 34, height: 8)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                            .background(i == selection ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .accessibilityLabel(Format.dayTime(hour.time))
                        .accessibilityAddTraits(i == selection ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
    }
}

private struct ShareBar: View {
    let hour: LakeHour

    var body: some View {
        // A lake-wide red (a storm warning, dark) closes the whole lake.
        let shares: [Light: Double] = hour.lakeWide.light == .red ? [.red: 1] : hour.shares
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach([Light.green, .amber, .red], id: \.self) { light in
                    let share = shares[light] ?? 0
                    if share > 0 {
                        Rectangle().fill(max(light, hour.lakeWide.light).color).frame(width: geo.size.width * share)
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

/// How the lake view works, from the info button.
private struct LakeViewInfo: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text(tr("The lake is divided into small squares. For each square and hour, the app takes the wind from the nearest forecast point and works out the waves from how much open water the wind has crossed to get there."))
                Text(tr("Each square gets the same rowing light as a club page, from wind, gusts, waves, fog and thunderstorm risk at that square. DWD warnings, darkness and cold water apply to the whole lake and are shown above the map."))
                Text(tr("Waves are an estimate: there are no wave measurements on these lakes, and shelter from steep shores or currents is not taken into account."))
                Section(tr("Data")) {
                    Text(tr("Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0"))
                    Text(tr("Lake outlines: © OpenStreetMap contributors, ODbL"))
                }
            }
            .navigationTitle(tr("About the lake view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(tr("Done")) { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Map

/// MapKit map with the lake's colours drawn over the water.
struct LakeMapView: UIViewRepresentable {
    let view: LakeView
    let hour: LakeHour?
    let layer: LakeLayer
    let clubID: String?
    @Binding var spot: Int?

    func makeCoordinator() -> Coordinator { Coordinator(spot: $spot) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.showsCompass = true
        let overlay = LakeOverlay(view: view)
        context.coordinator.overlay = overlay
        context.coordinator.grid = view.grid
        map.addOverlay(overlay, level: .aboveRoads)
        for club in view.clubs {
            let pin = ClubPin()
            pin.coordinate = CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
            pin.title = club.shortName
            pin.isOwn = club.id == clubID
            map.addAnnotation(pin)
        }
        map.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        map.setVisibleMapRect(overlay.boundingMapRect, animated: false)
        // Fit the lake once the map has its size, clear of the buttons at the top.
        DispatchQueue.main.async {
            map.setVisibleMapRect(overlay.boundingMapRect, edgePadding: UIEdgeInsets(top: 130, left: 24, bottom: 30, right: 24), animated: false)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.spot = $spot
        if let hour, c.shown != "\(hour.time.timeIntervalSince1970) \(layer.rawValue)" {
            c.shown = "\(hour.time.timeIntervalSince1970) \(layer.rawValue)"
            c.current = (LakeRaster.image(view, hour: hour, layer: layer), arrows(hour))
            c.renderer?.update(image: c.current.image, arrows: c.current.arrows)
        }
        c.showSpot(spot.map { view.grid.coordinate(ofCell: $0) }, on: map)
    }

    private func arrows(_ hour: LakeHour) -> [LakeRenderer.Arrow] {
        zip(view.points, hour.wind).compactMap { point, wind in
            guard let from = wind.fromDeg else { return nil }
            return LakeRenderer.Arrow(point: MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)), towardDeg: from + 180)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var spot: Binding<Int?>
        var overlay: LakeOverlay?
        var renderer: LakeRenderer?
        var grid: LakeGrid?
        /// The hour and layer drawn, and their picture and arrows.
        var shown: String?
        var current: (image: CGImage?, arrows: [LakeRenderer.Arrow]) = (nil, [])
        private let spotPin = MKPointAnnotation()

        init(spot: Binding<Int?>) { self.spot = spot }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let overlay = overlay as? LakeOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = LakeRenderer(overlay: overlay)
            renderer.update(image: current.image, arrows: current.arrows)
            self.renderer = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let pin = annotation as? ClubPin {
                let view = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: nil)
                view.glyphImage = UIImage(systemName: pin.isOwn ? "house.fill" : "figure.rowing")
                view.markerTintColor = pin.isOwn ? .systemBlue : .systemGray
                view.displayPriority = .required
                return view
            }
            if annotation === spotPin {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
                view.glyphImage = UIImage(systemName: "scope")
                view.markerTintColor = .label
                view.displayPriority = .required
                return view
            }
            return nil
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView, let grid else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            spot.wrappedValue = grid.cell(at: coordinate)
        }

        func showSpot(_ coordinate: CLLocationCoordinate2D?, on map: MKMapView) {
            guard let coordinate else {
                map.removeAnnotation(spotPin)
                return
            }
            if !map.annotations.contains(where: { $0 === spotPin }) { map.addAnnotation(spotPin) }
            spotPin.coordinate = coordinate
        }
    }
}

final class ClubPin: MKPointAnnotation {
    var isOwn = false
}

/// The area of the lake's grid, as one map overlay.
final class LakeOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    /// Shore and islands in map points, for clipping.
    let rings: [[MKMapPoint]]

    init(view: LakeView) {
        let g = view.grid
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: g.north, longitude: g.westEdge))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: g.southEdge, longitude: g.east))
        boundingMapRect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        coordinate = CLLocationCoordinate2D(latitude: (g.north + g.southEdge) / 2, longitude: (g.westEdge + g.east) / 2)
        rings = view.outline.map { ring in ring.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])) } }
    }
}

/// Draws the cell picture smoothly scaled over the grid, clipped to the shore,
/// and the wind arrows at the forecast points.
final class LakeRenderer: MKOverlayRenderer {
    struct Arrow {
        let point: MKMapPoint
        let towardDeg: Double
    }

    private let lock = NSLock()
    private var image: CGImage?
    private var arrows: [Arrow] = []

    func update(image: CGImage?, arrows: [Arrow]) {
        lock.lock()
        self.image = image
        self.arrows = arrows
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let lake = overlay as? LakeOverlay else { return }
        lock.lock()
        let image = self.image, arrows = self.arrows
        lock.unlock()

        let shore = CGMutablePath()
        for ring in lake.rings where ring.count > 2 {
            shore.addLines(between: ring.map { point(for: $0) })
            shore.closeSubpath()
        }
        if let image {
            let rect = self.rect(for: lake.boundingMapRect)
            context.saveGState()
            context.addPath(shore)
            context.clip(using: .evenOdd)
            context.interpolationQuality = .high
            context.setAlpha(0.72)
            // CGContext draws images bottom up; the overlay's points run top down.
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        }
        context.addPath(shore)
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1 / zoomScale)
        context.strokePath()

        // Dark arrows with a light edge read on light and dark maps alike.
        let length = 26 / zoomScale
        let paths = arrows.map { LakeArrow.path(at: point(for: $0.point), towardDeg: $0.towardDeg, length: length).cgPath }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (color, width) in [(UIColor(white: 1, alpha: 0.7), CGFloat(4)), (UIColor(white: 0.1, alpha: 0.75), CGFloat(2))] {
            paths.forEach { context.addPath($0) }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width / zoomScale)
            context.strokePath()
        }
    }
}
