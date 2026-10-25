import MapKit
import SwiftUI
import TipKit

/// The full lake view: the lake on a map, coloured by the rowing light, the
/// waves or the wind, hour by hour. Tap the water to see the conditions there.
/// In route mode, taps add turning points, and the route is coloured by the
/// conditions the boat meets when it gets there.
struct LakeMapScreen: View {
    let view: LakeView
    let clubID: String?
    @State private var hourIndex: Int
    @State private var layer: LakeLayer
    @State private var spot: Int?
    @State private var showingInfo = false
    @State private var routeMode: Bool
    @State private var waypoints: [CLLocationCoordinate2D]
    @State private var outAndBack: Bool
    /// The saved route being shown, if any.
    @State private var savedRoute: Route?
    @State private var showingSave = false
    @State private var routeName = ""
    /// Shows the lake at the time the boat reaches a point of the route, not at the start.
    @State private var followBoat: Bool
    /// Where the boat is, as a share of the route from start (0) to finish (1).
    @State private var boatAt: Double
    /// The turning point tapped for changing, by its index in `waypoints`.
    @State private var selectedPoint: Int?
    /// The panel at the bottom shows everything, or only a summary and the hours.
    @State private var panelExpanded: Bool
    /// Seconds per 500 m.
    @AppStorage("RWRoutePace") private var pace = 150.0
    @AppStorage(Tutorial.seenKey) private var tourSeen = false
    private let panelTip = RoutePanelTip()
    private let loopTip = CloseLoopTip()
    private let pointTip = TurningPointTip()
    private let boatTip = BoatTimeTip()
    @State private var showPanelTip = false
    @State private var showLoopTip = false
    @State private var showPointTip = false
    @State private var showBoatTip = false
    @Environment(\.dismiss) private var dismiss
    private let routes = RouteStore.shared

    /// `at` opens the map at a later hour, e.g. from an hour in the club page's table.
    init(view: LakeView, clubID: String?, at date: Date = .now) {
        self.view = view
        self.clubID = clubID
        let args = UserDefaults.standard
        let start = view.hourIndex(at: date) + args.integer(forKey: "RWLakeHour")
        _hourIndex = State(initialValue: min(max(start, 0), max(view.hours.count - 1, 0)))
        _layer = State(initialValue: LakeLayer(rawValue: args.string(forKey: "RWLakeLayer") ?? "") ?? .light)
        var spot: Int?
        if let text = args.string(forKey: "RWLakeSpot") {
            let parts = text.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { spot = view.grid.cell(at: CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])) }
        }
        _spot = State(initialValue: spot)
        // Screenshot hook: `-RWRoute "lat,lon;lat,lon;..."` opens route mode with these points.
        let route = (args.string(forKey: "RWRoute") ?? "").split(separator: ";").compactMap { pair -> CLLocationCoordinate2D? in
            let parts = pair.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]) : nil
        }
        let points = route.reduce(into: [CLLocationCoordinate2D]()) { built, p in
            built = built.isEmpty ? [p] : RouteEdit.add(p, to: built)
        }
        _waypoints = State(initialValue: points)
        _routeMode = State(initialValue: !route.isEmpty)
        _outAndBack = State(initialValue: !RouteEdit.isLoop(points))
        // Screenshot hook: `-RWRoutePoint 2` selects that turning point.
        _selectedPoint = State(initialValue: args.object(forKey: "RWRoutePoint") != nil ? args.integer(forKey: "RWRoutePoint") : nil)
        // Screenshot hook: `-RWPanel expanded` opens the panel in full.
        _panelExpanded = State(initialValue: args.string(forKey: "RWPanel") == "expanded")
        // Screenshot hook: `-RWBoatAt 0.6` shows the lake when the boat is 60 % along the route.
        _followBoat = State(initialValue: args.object(forKey: "RWBoatAt") != nil)
        _boatAt = State(initialValue: min(max(args.double(forKey: "RWBoatAt"), 0), 1))
    }

    private var planner: RoutePlanner? {
        routeMode ? RoutePlanner(view: view, waypoints: waypoints, outAndBack: outAndBack) : nil
    }

    /// The route starts at the chosen hour, or now when that hour has begun.
    private var startTime: Date { max(hour?.time ?? .now, .now) }

    private var hour: LakeHour? { view.hours.indices.contains(hourIndex) ? view.hours[hourIndex] : nil }

    /// The stop nearest to where the boat is, when the lake follows the boat.
    private func boatStop(_ plan: RoutePlan?) -> RoutePlan.Stop? {
        guard followBoat, let plan, !plan.stops.isEmpty else { return nil }
        let target = boatAt * plan.distanceM
        return plan.stops.min { abs($0.distanceM - target) < abs($1.distanceM - target) }
    }

    /// The hour the map shows: the start hour, or the hour the boat is at that point.
    private func shownHour(_ boat: RoutePlan.Stop?) -> LakeHour? {
        guard let boat, let i = view.hours.lastIndex(where: { $0.time <= boat.time }) else { return hour }
        return view.hours[i]
    }

    var body: some View {
        let plan = planner?.plan(start: startTime, paceSecondsPer500: pace)
        let boat = boatStop(plan)
        let shown = shownHour(boat)
        ZStack(alignment: .top) {
            LakeMapView(
                view: view, hour: shown, layer: layer, clubID: clubID, spot: $spot,
                routeMode: routeMode, waypoints: waypoints, segments: plan?.segments ?? [],
                boat: boat.map { CLLocationCoordinate2D(latitude: $0.coordinate.lat, longitude: $0.coordinate.lon) },
                selectedPoint: selectedPoint,
                addPoint: { point in
                    selectedPoint = nil
                    let new = RouteEdit.add(point, to: waypoints)
                    if RouteEdit.isLoop(new) { outAndBack = false }
                    waypoints = new
                    savedRoute = nil
                },
                movePoint: { i, point in
                    waypoints = RouteEdit.move(at: i, to: point, in: waypoints)
                    pointTip.invalidate(reason: .actionPerformed)
                },
                selectPoint: { selectedPoint = $0 }
            )
            .ignoresSafeArea()
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { panel(plan: plan, boat: boat, shown: shown) }
        .sheet(isPresented: $showingInfo) { LakeViewInfo() }
        .tipVisibility(panelTip, $showPanelTip)
        .tipVisibility(loopTip, $showLoopTip)
        .tipVisibility(pointTip, $showPointTip)
        .tipVisibility(boatTip, $showBoatTip)
        // A tip goes once its feature was used.
        .onChange(of: panelExpanded) { panelTip.invalidate(reason: .actionPerformed) }
        .onChange(of: followBoat) { if followBoat { boatTip.invalidate(reason: .actionPerformed) } }
        .onChange(of: RouteEdit.isLoop(waypoints)) { _, loop in if loop { loopTip.invalidate(reason: .actionPerformed) } }
        .alert(tr("Save route"), isPresented: $showingSave) {
            TextField(tr("Name"), text: $routeName)
            Button(tr("Save")) { saveRoute() }
            Button(tr("Cancel"), role: .cancel) {}
        }
    }

    private func toggleRouteMode() {
        routeMode.toggle()
        spot = nil
        selectedPoint = nil
        // A new route starts at this page's launch point.
        if routeMode, waypoints.isEmpty, let club = view.clubs.first(where: { $0.id == clubID }) {
            waypoints = [CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)]
        }
    }

    private func saveRoute() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        var route = savedRoute ?? Route(name: name, lakeId: view.lakeId, points: [], outAndBack: outAndBack)
        route.name = name.isEmpty ? tr("Route %@", Format.distance(planner?.distanceM)) : name
        route.points = waypoints.map { Coordinate(lat: $0.latitude, lon: $0.longitude) }
        route.outAndBack = outAndBack
        routes.save(route)
        savedRoute = route
    }

    private func load(_ route: Route) {
        waypoints = route.coordinates
        outAndBack = route.outAndBack
        savedRoute = route
        routeMode = true
        spot = nil
        selectedPoint = nil
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
                Button { toggleRouteMode() } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(routeMode ? Color.white : Color.accentColor)
                }
                .background(routeMode ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Material.regularMaterial), in: Circle())
                .accessibilityLabel(routeMode ? tr("End route planning") : tr("Plan a route"))
                .popoverTip(RoutePlanningTip(), arrowEdge: .top)
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
            if routeMode { editBar }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    /// Changing the route, on the map where the points are: undo, close the
    /// loop, clear, and delete the turning point that is tapped.
    @ViewBuilder private var editBar: some View {
        let loop = RouteEdit.isLoop(waypoints)
        HStack(spacing: 14) {
            if let i = selectedPoint, i > 0, i < waypoints.count {
                Text(tr("Turning point %d", i)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button(tr("Delete point"), systemImage: "trash", role: .destructive) {
                    waypoints = RouteEdit.remove(at: i, from: waypoints)
                    selectedPoint = nil
                    pointTip.invalidate(reason: .actionPerformed)
                    savedRoute = nil
                }
                Button(tr("Done")) { selectedPoint = nil }
                    .fontWeight(.semibold)
            } else {
                Button(tr("Undo"), systemImage: "arrow.uturn.backward") {
                    if waypoints.count > 1 { waypoints.removeLast() }
                }
                .disabled(waypoints.count < 2)
                Button(tr("Close loop"), systemImage: "arrow.triangle.capsulepath") {
                    waypoints = RouteEdit.close(waypoints)
                    outAndBack = false
                }
                .disabled(waypoints.count < 3 || loop)
                Spacer(minLength: 0)
                Button(tr("Clear"), systemImage: "trash") {
                    waypoints = Array(waypoints.prefix(1))
                    savedRoute = nil
                }
                .disabled(waypoints.count < 2)
            }
        }
        .font(.subheadline)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        if let i = selectedPoint, i > 0, i < waypoints.count {
            if tourSeen && showPointTip {
                TipView(pointTip)
            } else {
                Text(tr("Hold the point and drag it to move it."))
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
            }
        } else if tourSeen && showLoopTip && waypoints.count >= 3 && !loop {
            // After the second turning point.
            TipView(loopTip)
        }
    }

    private func panel(plan: RoutePlan?, boat: RoutePlan.Stop?, shown: LakeHour?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            grabber
            if tourSeen && showPanelTip {
                TipView(panelTip)
            }
            if !panelExpanded, let hour = shown {
                collapsedSummary(hour, plan: plan, boat: boat)
            } else if let hour = shown {
                HStack(alignment: .firstTextBaseline) {
                    Text(boat == nil ? Format.dayTime(hour.time) : tr("%@ · at the boat", Format.dayTime(hour.time))).font(.headline)
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
                if routeMode {
                    routePanel(plan: plan, boat: boat)
                } else if let spot, spot < hour.lights.count {
                    spotDetails(spot, hour)
                } else {
                    Text(view.headline(for: hour)).font(.subheadline.weight(.semibold))
                    if let wind = view.windSummary(for: hour) {
                        Label(wind, systemImage: Condition.wind.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let waves = view.waveSummary(for: hour) {
                        Label(waves, systemImage: Condition.waves.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(tr("Tap the water to see the conditions there."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !routeMode {
                    LakeLegend(layer: layer)
                    MapBoatNote()
                }
            }
            if routeMode {
                Text(tr("Start time")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            LakeHourStrip(hours: view.hours, selection: $hourIndex)
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        // Pull up for everything, push down for the map.
        .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
            if drag.translation.height < -30 { withAnimation(.snappy) { panelExpanded = true } }
            if drag.translation.height > 30 { withAnimation(.snappy) { panelExpanded = false } }
        })
    }

    private var grabber: some View {
        Button { withAnimation(.snappy) { panelExpanded.toggle() } } label: {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panelExpanded ? tr("Show less") : tr("Show more"))
    }

    /// The panel when pushed down: the hour, one line on the conditions or
    /// the route, and the hour strip.
    @ViewBuilder private func collapsedSummary(_ hour: LakeHour, plan: RoutePlan?, boat: RoutePlan.Stop?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(boat == nil ? Format.dayTime(hour.time) : tr("%@ · at the boat", Format.dayTime(hour.time))).font(.headline)
            Spacer()
            if view.sample {
                Label(tr("Sample wind"), systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        if hour.lakeWide.light > .green {
            LakeWideBanner(lakeWide: hour.lakeWide).lineLimit(1)
        }
        Group {
            if routeMode, let plan {
                HStack(spacing: 6) {
                    TrafficLightDot(light: plan.worstLight, size: 10)
                    Text(tr("%@ · %@ · finished at %@", Format.distance(plan.distanceM), Format.duration(from: plan.start, to: plan.end), Format.time(plan.end)))
                        .monospacedDigit()
                }
            } else if routeMode {
                Text(tr("Tap the water to add the turning points of your route."))
            } else if let spot, spot < hour.lights.count {
                HStack(spacing: 6) {
                    TrafficLightDot(light: hour.lights[spot], size: 10)
                    Text(hour.lights[spot].title + " · " + tr("Waves up to %@", Format.waves(hour.wave(ofCell: spot))))
                }
            } else {
                Text(view.headline(for: hour))
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
    }

    @ViewBuilder private func routePanel(plan: RoutePlan?, boat: RoutePlan.Stop?) -> some View {
        let saved = routes.routes(on: view.lakeId)
        let loop = RouteEdit.isLoop(waypoints)
        if let planner, let plan {
            RouteSummary(view: view, plan: plan)
            if tourSeen && showBoatTip && !followBoat {
                TipView(boatTip)
            }
            HStack(spacing: 12) {
                Toggle(isOn: $followBoat) {
                    Label(tr("Lake at the boat's time"), systemImage: "figure.rowing")
                }
                .toggleStyle(.button)
                .fixedSize()
                if followBoat {
                    Slider(value: $boatAt, in: 0...1)
                        .accessibilityLabel(tr("Where the boat is"))
                        .accessibilityValue(Format.distance(boat?.distanceM))
                }
            }
            .font(.subheadline)
            if let boat {
                Text(boatText(boat))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let best = planner.bestStart(paceSecondsPer500: pace),
               (best.worstLight, (best.maxWaveM * 100).rounded()) < (plan.worstLight, (plan.maxWaveM * 100).rounded()),
               let i = view.hours.lastIndex(where: { $0.time <= best.start }) {
                Button { hourIndex = i } label: {
                    Label(tr("Better start: %@ · %@", Format.dayTime(best.start), best.worstLight.title), systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                }
            }
        } else {
            Text(tr("Tap the water to add the turning points of your route. It starts at your club. Tap a point to delete it, or hold and drag it to move it. A point within 50 m of the start closes the loop."))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
            Toggle(tr("Out and back"), isOn: $outAndBack)
                .toggleStyle(.button)
                .font(.subheadline)
                .disabled(loop)
            Stepper(value: $pace, in: 90...240, step: 5) {
                Text(tr("Pace %@ /500 m", Format.pace(pace))).font(.subheadline.monospacedDigit())
            }
        }
        HStack(spacing: 16) {
            Spacer()
            Menu {
                Button(tr("Save route"), systemImage: "square.and.arrow.down") {
                    routeName = savedRoute?.name ?? ""
                    showingSave = true
                }
                .disabled(waypoints.count < 2)
                if !saved.isEmpty {
                    Section(tr("Saved routes")) {
                        ForEach(saved) { route in
                            Button(route.name) { load(route) }
                        }
                    }
                }
                if let savedRoute {
                    Button(tr("Delete this route"), systemImage: "trash", role: .destructive) {
                        routes.delete(savedRoute)
                        self.savedRoute = nil
                    }
                }
            } label: {
                Label(savedRoute?.name ?? tr("Routes"), systemImage: "bookmark")
            }
        }
        .font(.subheadline)
        .labelStyle(.titleAndIcon)
    }

    /// "The boat at 10:35 after 6.2 km: Row with care, waves 0.25 m head sea".
    private func boatText(_ stop: RoutePlan.Stop) -> String {
        let waves = Format.waves(stop.waveM) + (stop.relation.map { " " + $0.waves } ?? "")
        return tr("The boat at %@ after %@: %@, waves %@", Format.time(stop.time), Format.distance(stop.distanceM), stop.light.title, waves)
    }

    private func spotDetails(_ i: Int, _ hour: LakeHour) -> some View {
        let p = view.grid.cellPoint[i]
        let wind = p < hour.wind.count ? hour.wind[p] : nil
        let zone = view.grid.cellZone[i]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                TrafficLightDot(light: hour.lights[i], size: 14, stale: view.isStale)
                Text(hour.lights[i].title(stale: view.isStale)).font(.headline)
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

/// Which boat the lake is coloured for, with a warning when that boat takes
/// more wind or waves than the one the rowing light is for.
struct MapBoatNote: View {
    var body: some View {
        let settings = AppSettings.shared
        if settings.mapLooksCalmer {
            Label(tr("Coloured for %@, not for %@: the lake may look calmer than it is for you.", settings.mapBoat.inSentence, settings.selectedBoat.inSentence),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label(tr("Coloured for %@", settings.mapBoat.inSentence), systemImage: "figure.rower")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// What the colours mean for the chosen layer.
struct LakeLegend: View {
    let layer: LakeLayer
    private var limits: RowingLimits { AppSettings.shared.mapLimits }

    var body: some View {
        HStack(spacing: 12) {
            switch layer {
            case .light:
                ForEach([Light.green, .amber, .red], id: \.self) { light in
                    HStack(spacing: 4) { TrafficLightDot(light: light, size: 9); Text(light.title) }
                }
            case .waves:
                let amber = limits.value(.waveAmber), red = limits.value(.waveRed)
                ramp(LakeRaster.waveColor, stops: [0, amber, red, red * 1.6], labels: [Format.waves(0), Format.waves(amber), Format.waves(red)])
            case .wind:
                let amber = limits.value(.windAmber), red = limits.value(.windRed)
                ramp(LakeRaster.windColor, stops: [0, amber, red, red * 1.6], labels: [Format.wind(0), Format.wind(amber), Format.wind(red)])
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
                Text(tr("Each square gets the same rowing light as a club page, from wind, gusts, waves, fog and thunderstorm risk at that square. DWD warnings, darkness and cold water apply to the whole lake and are shown in the panel below the map; while they make the whole lake red, the squares turn grey with red stripes."))
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
    var routeMode = false
    var waypoints: [CLLocationCoordinate2D] = []
    var segments: [RoutePlan.Segment] = []
    /// Where the boat is, when the lake follows it.
    var boat: CLLocationCoordinate2D?
    var selectedPoint: Int?
    var addPoint: (CLLocationCoordinate2D) -> Void = { _ in }
    var movePoint: (Int, CLLocationCoordinate2D) -> Void = { _, _ in }
    var selectPoint: (Int?) -> Void = { _ in }

    /// Room the pushed-down panel and the home indicator take at the bottom.
    static let panelHeight: CGFloat = 230

    func makeCoordinator() -> Coordinator { Coordinator(spot: $spot) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        // MapKit's own compass sits under the buttons at the top; this one sits
        // on the right below the layer picker and the route bar.
        map.showsCompass = false
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        compass.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(compass)
        NSLayoutConstraint.activate([
            compass.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            compass.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 185),
        ])
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
        // Fit the lake once the map has its size, clear of the buttons at the top
        // and of the panel at the bottom, so the whole lake and every club show.
        let inRouteMode = routeMode
        DispatchQueue.main.async { Self.fit(overlay, in: map, routeMode: inRouteMode, animated: false) }
        context.coordinator.fittedForRoute = routeMode
        return map
    }

    /// Room the buttons at the top take; in route mode the editing bar adds a row.
    static let routeTop: CGFloat = 215

    static func fit(_ overlay: LakeOverlay, in map: MKMapView, routeMode: Bool, animated: Bool) {
        let padding = UIEdgeInsets(top: routeMode ? routeTop : 130, left: 24, bottom: panelHeight, right: 24)
        map.setVisibleMapRect(overlay.boundingMapRect, edgePadding: padding, animated: animated)
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.spot = $spot
        c.routeMode = routeMode
        c.addPoint = addPoint
        c.movePoint = movePoint
        c.selectPoint = selectPoint
        c.showRoute(segments: segments, waypoints: waypoints, selected: selectedPoint, on: map)
        // The editing bar shows in route mode; move the lake down when the bar
        // would hide the start of the route.
        if !routeMode { c.fittedForRoute = false }
        if routeMode, !c.fittedForRoute, let overlay = c.overlay, let start = waypoints.first {
            c.fittedForRoute = true
            if map.convert(start, toPointTo: map).y < Self.routeTop {
                Self.fit(overlay, in: map, routeMode: true, animated: true)
            }
        }
        if let hour, c.shown != "\(hour.time.timeIntervalSince1970) \(layer.rawValue)" {
            c.shown = "\(hour.time.timeIntervalSince1970) \(layer.rawValue)"
            c.current = (LakeRaster.image(view, hour: hour, layer: layer), arrows(hour), layer == .light && hour.lakeWide.light == .red)
            c.renderer?.update(image: c.current.image, arrows: c.current.arrows, striped: c.current.striped)
        }
        c.showSpot(spot.map { view.grid.coordinate(ofCell: $0) }, on: map)
        c.showBoat(boat, on: map)
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
        var current: (image: CGImage?, arrows: [LakeRenderer.Arrow], striped: Bool) = (nil, [], false)
        var routeMode = false
        /// Whether the lake was fitted below the editing bar of route mode.
        var fittedForRoute = false
        var addPoint: (CLLocationCoordinate2D) -> Void = { _ in }
        var movePoint: (Int, CLLocationCoordinate2D) -> Void = { _, _ in }
        var selectPoint: (Int?) -> Void = { _ in }
        private let spotPin = MKPointAnnotation()
        private let boatPin = MKPointAnnotation()
        private var shownRoute: ([RoutePlan.Segment], [Coordinate], Int?)?
        private var routeOverlays: [RouteLine] = []
        private var routePins: [RoutePin] = []

        init(spot: Binding<Int?>) { self.spot = spot }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? RouteLine {
                return RouteLineRenderer(overlay: line)
            }
            guard let overlay = overlay as? LakeOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = LakeRenderer(overlay: overlay)
            renderer.update(image: current.image, arrows: current.arrows, striped: current.striped)
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
            if let pin = annotation as? RoutePin {
                let view = MKAnnotationView(annotation: pin, reuseIdentifier: nil)
                let size: CGFloat = pin.isStart || pin.isSelected ? 18 : 14
                view.image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                    let rect = CGRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3)
                    let circle = UIBezierPath(ovalIn: rect)
                    (pin.isStart ? UIColor.systemBlue : pin.isSelected ? UIColor.systemOrange : UIColor.white).setFill()
                    circle.fill()
                    UIColor(white: 0.15, alpha: 1).setStroke()
                    circle.lineWidth = 2
                    circle.stroke()
                }
                // The start is the club's launch point; the turning points can be moved.
                view.isDraggable = !pin.isStart
                view.displayPriority = .required
                return view
            }
            if annotation === boatPin {
                // A round boat badge sitting on the route, not a pin above it.
                let view = MKAnnotationView(annotation: annotation, reuseIdentifier: nil)
                let size: CGFloat = 34
                view.image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                    let circle = UIBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3))
                    UIColor.systemIndigo.setFill()
                    circle.fill()
                    UIColor.white.setStroke()
                    circle.lineWidth = 2.5
                    circle.stroke()
                    let glyph = UIImage(systemName: "figure.rower", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))?
                        .withTintColor(.white, renderingMode: .alwaysOriginal)
                    if let glyph {
                        glyph.draw(at: CGPoint(x: (size - glyph.size.width) / 2, y: (size - glyph.size.height) / 2))
                    }
                }
                view.layer.shadowColor = UIColor.black.cgColor
                view.layer.shadowOpacity = 0.3
                view.layer.shadowRadius = 2
                view.layer.shadowOffset = CGSize(width: 0, height: 1)
                view.accessibilityLabel = tr("Where the boat is")
                view.displayPriority = .required
                view.zPriority = .max
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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pin = view.annotation as? RoutePin else { return }
            mapView.deselectAnnotation(pin, animated: false)
            if !pin.isStart { selectPoint(pin.index) }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard newState == .ending || newState == .canceling else { return }
            view.dragState = .none
            if newState == .ending, let pin = view.annotation as? RoutePin {
                selectPoint(pin.index)
                movePoint(pin.index, pin.coordinate)
            }
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView, let grid else { return }
            let location = gesture.location(in: map)
            // A tap on a pin selects it rather than adding a point under it.
            if let hit = map.hitTest(location, with: nil),
               sequence(first: hit, next: { $0.superview }).contains(where: { $0 is MKAnnotationView }) {
                return
            }
            let coordinate = map.convert(location, toCoordinateFrom: map)
            if routeMode {
                addPoint(coordinate)
            } else {
                spot.wrappedValue = grid.cell(at: coordinate)
            }
        }

        func showRoute(segments: [RoutePlan.Segment], waypoints: [CLLocationCoordinate2D], selected: Int?, on map: MKMapView) {
            // A loop's last point is the start again and gets no pin of its own.
            let pinned = RouteEdit.isLoop(waypoints) ? Array(waypoints.dropLast()) : waypoints
            let points = routeMode ? pinned.map { Coordinate(lat: $0.latitude, lon: $0.longitude) } : []
            let lines = routeMode ? segments : []
            if let shownRoute, shownRoute.0 == lines, shownRoute.1 == points, shownRoute.2 == selected { return }
            shownRoute = (lines, points, selected)
            map.removeOverlays(routeOverlays)
            map.removeAnnotations(routePins)
            routeOverlays = []
            for casing in [true, false] {
                for segment in lines {
                    let coordinates = segment.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    let line = RouteLine(coordinates: coordinates, count: coordinates.count)
                    line.light = segment.light
                    line.casing = casing
                    routeOverlays.append(line)
                }
            }
            map.addOverlays(routeOverlays, level: .aboveLabels)
            routePins = points.enumerated().map { i, p in
                let pin = RoutePin()
                pin.coordinate = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
                pin.isStart = i == 0
                pin.index = i
                pin.isSelected = i == selected
                return pin
            }
            map.addAnnotations(routePins)
        }

        func showBoat(_ coordinate: CLLocationCoordinate2D?, on map: MKMapView) {
            guard let coordinate else {
                map.removeAnnotation(boatPin)
                return
            }
            if !map.annotations.contains(where: { $0 === boatPin }) { map.addAnnotation(boatPin) }
            boatPin.coordinate = coordinate
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

final class RoutePin: MKPointAnnotation {
    var isStart = false
    var isSelected = false
    /// Its index in the route's waypoints.
    var index = 0
}

/// One stretch of a planned route in the colour of its conditions; the casing
/// is a wider white line under it.
final class RouteLine: MKPolyline {
    var light: Light = .green
    var casing = false

    /// Room for the line drawn beside its points (about 2 km).
    override var boundingMapRect: MKMapRect { super.boundingMapRect.insetBy(dx: -20_000, dy: -20_000) }
}

/// Draws a route stretch a few points to the right of the way the boat goes,
/// so where a route is rowed out and back both trips show side by side, each
/// in the colour of the time the boat is there.
final class RouteLineRenderer: MKOverlayRenderer {
    /// Screen points between the line's middle and the route.
    static let offset: CGFloat = 3.5

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let line = overlay as? RouteLine, line.pointCount > 1 else { return }
        let points = UnsafeBufferPointer(start: line.points(), count: line.pointCount).map { point(for: $0) }
        let path = CGMutablePath()
        path.addLines(between: Self.shifted(points, by: Self.offset / zoomScale))
        context.addPath(path)
        context.setStrokeColor((line.casing ? UIColor(white: 1, alpha: 0.9) : UIColor(line.light.color)).cgColor)
        context.setLineWidth((line.casing ? 9 : 5) / zoomScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    /// The points moved `distance` to the right of the direction of travel, with y running down.
    static func shifted(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let normals = zip(points, points.dropFirst()).map { a, b -> CGVector in
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(hypot(dx, dy), .ulpOfOne)
            return CGVector(dx: -dy / length, dy: dx / length)
        }
        return points.indices.map { i in
            let before = i > 0 ? normals[i - 1] : normals[0]
            let after = i < normals.count ? normals[i] : normals[normals.count - 1]
            var n = CGVector(dx: before.dx + after.dx, dy: before.dy + after.dy)
            let length = hypot(n.dx, n.dy)
            n = length > 0.01 ? CGVector(dx: n.dx / length, dy: n.dy / length) : after
            return CGPoint(x: points[i].x + n.dx * distance, y: points[i].y + n.dy * distance)
        }
    }
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
    /// Red stripes over the water while the whole lake is red.
    private var striped = false

    func update(image: CGImage?, arrows: [Arrow], striped: Bool) {
        lock.lock()
        self.image = image
        self.arrows = arrows
        self.striped = striped
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let lake = overlay as? LakeOverlay else { return }
        lock.lock()
        let image = self.image, arrows = self.arrows, striped = self.striped
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
        if striped {
            context.saveGState()
            context.addPath(shore)
            context.clip(using: .evenOdd)
            // Lines x + y = k * gap, so the stripes run on across the map's tiles.
            let tile = self.rect(for: mapRect), gap = 14 / zoomScale
            let stripes = CGMutablePath()
            var k = ((tile.minX + tile.minY) / gap).rounded(.down)
            while k * gap <= tile.maxX + tile.maxY {
                stripes.move(to: CGPoint(x: k * gap - tile.minY, y: tile.minY))
                stripes.addLine(to: CGPoint(x: k * gap - tile.maxY, y: tile.maxY))
                k += 1
            }
            context.addPath(stripes)
            context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(3 / zoomScale)
            context.strokePath()
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
