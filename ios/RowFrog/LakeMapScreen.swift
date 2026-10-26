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
    @State private var showingLegend = UserDefaults.standard.bool(forKey: "RWLakeLegend")
    @State private var routeMode: Bool
    @State private var waypoints: [CLLocationCoordinate2D]
    @State private var outAndBack: Bool
    /// The saved route being shown, if any.
    @State private var savedRoute: Route?
    /// The imported row the route came from, kept while its route is changed.
    @State private var rowed: Route?
    @State private var showingSave = false
    @State private var showingRoutes = false
    /// "Import a row": from Apple Health or a GPX, TCX or FIT file.
    @State private var showingImport: Bool
    /// An imported route also shows the track as it was rowed.
    @AppStorage("RWShowTrack") private var showTrack = false
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
    /// Apple's satellite pictures under the lake instead of the map.
    @AppStorage("RWLakeImagery") private var imagery = false
    @AppStorage(Tutorial.seenKey) private var tourSeen = false
    private let panelTip = RoutePanelTip()
    private let loopTip = CloseLoopTip()
    private let pointTip = TurningPointTip()
    private let boatTip = BoatTimeTip()
    private let importTip = RowImportTip()
    private let stretchTip = StretchPointTip()
    private let oneWayTip = OneWayTip()
    @State private var showStretchTip = false
    @State private var showOneWayTip = false
    @State private var showImportTip = false
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
        // A new route goes one way; `-RWOutAndBack YES` rows the screenshot routes back too.
        _outAndBack = State(initialValue: args.bool(forKey: "RWOutAndBack") && !RouteEdit.isLoop(points))
        // Screenshot hook: `-RWSavedRoutes "Name=lat,lon;lat,lon|Name=…"` saves these routes on the
        // lake when it has none (a name ending in "↔" is rowed out and back) and opens Manage routes.
        if let saved = args.string(forKey: "RWSavedRoutes"), RouteStore.shared.routes(on: view.lakeId).isEmpty {
            for spec in saved.split(separator: "|") {
                let parts = spec.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let coords = parts[1].split(separator: ";").map { $0.split(separator: ",").compactMap { Double($0) } }
                    .filter { $0.count == 2 }.map { Coordinate(lat: $0[0], lon: $0[1]) }
                let name = String(parts[0])
                RouteStore.shared.save(Route(name: name.replacingOccurrences(of: " ↔", with: ""), lakeId: view.lakeId,
                                             points: coords, outAndBack: name.hasSuffix("↔")))
            }
        }
        _showingRoutes = State(initialValue: args.string(forKey: "RWSavedRoutes") != nil)
        // Screenshot hook: `-RWRoutePoint 2` selects that turning point.
        _selectedPoint = State(initialValue: args.object(forKey: "RWRoutePoint") != nil ? args.integer(forKey: "RWRoutePoint") : nil)
        // Screenshot hook: `-RWPanel expanded` opens the panel in full.
        _panelExpanded = State(initialValue: args.string(forKey: "RWPanel") == "expanded")
        // Screenshot hook: `-RWBoatAt 0.6` shows the lake when the boat is 60 % along the route.
        _followBoat = State(initialValue: args.object(forKey: "RWBoatAt") != nil)
        _boatAt = State(initialValue: min(max(args.double(forKey: "RWBoatAt"), 0), 1))
        // Screenshot hook: `-RWImportRows YES` opens "Import a row" with made-up Health rows.
        _showingImport = State(initialValue: args.bool(forKey: "RWImportRows"))
        // Screenshot hook: `-RWImportedRoute YES` with `-RWRoute` imports a made-up row along those points.
        var imported: Route?
        if args.bool(forKey: "RWImportedRoute"), points.count >= 2 {
            let track = RouteImport.sampleTrack(along: points, outAndBack: !RouteEdit.isLoop(points))
            imported = RouteImport.route(from: track, lakeId: view.lakeId, launchPoints: view.clubs.map(\.launchPoint))
        }
        if let imported {
            RouteStore.shared.save(imported)
            _waypoints = State(initialValue: imported.coordinates)
            _outAndBack = State(initialValue: imported.outAndBack)
        }
        _savedRoute = State(initialValue: imported)
        _rowed = State(initialValue: imported)
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
                insertPoint: { i, point in
                    waypoints = RouteEdit.insert(point, at: i, in: waypoints)
                    selectedPoint = i
                    stretchTip.invalidate(reason: .actionPerformed)
                    savedRoute = nil
                },
                selectPoint: { selectedPoint = $0 },
                imagery: imagery,
                track: routeMode && showTrack ? rowed?.trackCoordinates ?? [] : []
            )
            .ignoresSafeArea()
            topBar
        }
        .overlay(alignment: .bottomLeading) {
            Button { showingLegend = true } label: {
                Label(tr("Legend"), systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { panel(plan: plan, boat: boat, shown: shown) }
        .sheet(isPresented: $showingInfo) { LakeViewInfo() }
        .sheet(isPresented: $showingLegend) {
            LakeMapLegend(layer: layer, stripes: layer == .light ? shown?.lakeWide.stripes : nil,
                          routeMode: routeMode, hasRoute: (plan?.segments.isEmpty == false), boat: boat != nil,
                          spot: spot != nil, hasWind: !(shown?.wind.isEmpty ?? true),
                          track: routeMode && showTrack && rowed?.track != nil, clubID: clubID)
        }
        .sheet(isPresented: $showingImport) {
            RowImportSheet(lakeName: view.name) { importRow($0) }
        }
        .tipVisibility(panelTip, $showPanelTip)
        .tipVisibility(loopTip, $showLoopTip)
        .tipVisibility(pointTip, $showPointTip)
        .tipVisibility(boatTip, $showBoatTip)
        .tipVisibility(importTip, $showImportTip)
        .tipVisibility(stretchTip, $showStretchTip)
        .tipVisibility(oneWayTip, $showOneWayTip)
        .onChange(of: outAndBack) { oneWayTip.invalidate(reason: .actionPerformed) }
        // A tip goes once its feature was used.
        .onChange(of: panelExpanded) { panelTip.invalidate(reason: .actionPerformed) }
        .onChange(of: followBoat) { if followBoat { boatTip.invalidate(reason: .actionPerformed) } }
        .onChange(of: RouteEdit.isLoop(waypoints)) { _, loop in if loop { loopTip.invalidate(reason: .actionPerformed) } }
        .sheet(isPresented: $showingRoutes) {
            ManageRoutesView(lakeID: view.lakeId, current: savedRoute?.id, open: load) { id in
                // The open route was renamed or deleted: show it as it is now.
                guard id == savedRoute?.id else { return }
                savedRoute = routes.routes.first { $0.id == id }
            }
        }
        .alert(tr("Save route"), isPresented: $showingSave) {
            TextField(tr("Name"), text: $routeName)
            Button(tr("Save")) { saveRoute() }
            Button(tr("Cancel"), role: .cancel) {}
        }
    }

    private func toggleRouteMode() {
        routeMode.toggle()
        // Its popover would cover the edit bar and the route tips.
        RoutePlanningTip().invalidate(reason: .actionPerformed)
        spot = nil
        selectedPoint = nil
        // A new route starts at this page's launch point.
        if routeMode, waypoints.isEmpty, let club = view.clubs.first(where: { $0.id == clubID }) {
            waypoints = [CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)]
        }
    }

    private func saveRoute() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        // A changed imported route saved as a new one keeps the row's track.
        var route = savedRoute ?? Route(name: name, lakeId: view.lakeId, points: [], outAndBack: outAndBack,
                                        track: rowed?.track, rowedAt: rowed?.rowedAt, importedFrom: rowed?.importedFrom)
        route.name = name.isEmpty ? tr("Route %@", Format.distance(planner?.distanceM)) : name
        route.points = waypoints.map { Coordinate(lat: $0.latitude, lon: $0.longitude) }
        route.outAndBack = outAndBack
        routes.save(route)
        savedRoute = route
    }

    /// Makes the picked row a saved route on this lake and opens it; an error
    /// to show when the row was elsewhere or too short.
    private func importRow(_ track: RowTrack) -> String? {
        guard RouteImport.shareOnWater(track, grid: view.grid) >= 0.5 else { return RowImportError.notOnLake(view.name).message }
        guard let route = RouteImport.route(from: track, lakeId: view.lakeId, launchPoints: view.clubs.map(\.launchPoint)) else {
            return RowImportError.tooShort.message
        }
        routes.save(route)
        load(route)
        if let pace = track.cleaned.paceSecondsPer500 { RouteImport.usePace(pace) }
        importTip.invalidate(reason: .actionPerformed)
        return nil
    }

    private func load(_ route: Route) {
        waypoints = route.coordinates
        outAndBack = route.outAndBack
        savedRoute = route
        rowed = route.track == nil ? nil : route
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
                Button { imagery.toggle() } label: {
                    Image(systemName: imagery ? "map" : "globe.europe.africa")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .background(.regularMaterial, in: Circle())
                .accessibilityLabel(imagery ? tr("Show the map") : tr("Show satellite pictures"))
                // Its popover would cover the editing bar and the route tips while planning.
                if routeMode {
                    routeButton
                        .background(Color.accentColor, in: Circle())
                        .accessibilityLabel(tr("End route planning"))
                } else {
                    routeButton
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(tr("Plan a route"))
                        .popoverTip(RoutePlanningTip(), arrowEdge: .top)
                }
                if !routeMode {
                    Button { showingInfo = true } label: {
                        Image(systemName: "info").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                    }
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel(tr("About the lake view"))
                }
            }
            // While planning only what the route needs: the editing bar takes the layer switch's place.
            if routeMode {
                editBar
            } else {
                Picker(tr("Show"), selection: $layer) {
                    ForEach(LakeLayer.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    /// Starts or ends route planning. With saved routes on this lake it first
    /// asks: a new route, or one of the saved ones to look at or change.
    @ViewBuilder private var routeButton: some View {
        let icon = Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            .font(.body.weight(.semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(routeMode ? Color.white : Color.accentColor)
        let saved = routes.routes(on: view.lakeId)
        if !routeMode && !saved.isEmpty {
            Menu {
                Button(tr("New route"), systemImage: "plus") {
                    waypoints = []
                    savedRoute = nil
                    rowed = nil
                    toggleRouteMode()
                }
                Button(tr("Import a row"), systemImage: "square.and.arrow.down.on.square") { showingImport = true }
                Section(tr("Saved routes")) {
                    ForEach(saved) { route in
                        Button(route.name) { load(route) }
                    }
                }
                Button(tr("Manage routes…"), systemImage: "list.bullet") { showingRoutes = true }
            } label: { icon }
        } else {
            Button { toggleRouteMode() } label: { icon }
        }
    }

    /// Save, open or delete routes, from the editing bar.
    private var routesMenu: some View {
        let saved = routes.routes(on: view.lakeId)
        return Menu {
            Button(tr("Save route"), systemImage: "square.and.arrow.down") {
                routeName = savedRoute?.name ?? ""
                showingSave = true
            }
            .disabled(waypoints.count < 2)
            Button(tr("Import a row"), systemImage: "square.and.arrow.down.on.square") { showingImport = true }
            if rowed?.track != nil {
                Toggle(tr("Show rowed track"), systemImage: "scribble.variable", isOn: $showTrack)
            }
            if !saved.isEmpty {
                Section(tr("Saved routes")) {
                    ForEach(saved) { route in
                        Button(route.name) { load(route) }
                    }
                }
                Button(tr("Manage routes…"), systemImage: "list.bullet") { showingRoutes = true }
            }
            if let savedRoute {
                Button(tr("Delete this route"), systemImage: "trash", role: .destructive) {
                    routes.delete(savedRoute)
                    self.savedRoute = nil
                    rowed = nil
                }
            }
        } label: {
            Image(systemName: savedRoute == nil ? "bookmark" : "bookmark.fill")
        }
        .accessibilityLabel(savedRoute?.name ?? tr("Routes"))
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
                Button(tr("Clear", key: "Clear route"), systemImage: "trash") {
                    waypoints = Array(waypoints.prefix(1))
                    savedRoute = nil
                    rowed = nil
                }
                // The bin alone, so Undo and Close loop keep their words in German too.
                .labelStyle(.iconOnly)
                .disabled(waypoints.count < 2)
                routesMenu
            }
        }
        .font(.subheadline)
        .labelStyle(.titleAndIcon)
        // Longer German labels shrink a little instead of wrapping.
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        if let i = selectedPoint, i > 0, i < waypoints.count {
            if tourSeen && showPointTip {
                TipView(pointTip)
            } else {
                Text(tr("Drag the point to move it. The magnifier shows where it lands."))
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
            }
        } else if tourSeen && showLoopTip && waypoints.count >= 3 && !loop {
            // After the second turning point.
            TipView(loopTip)
        } else if tourSeen && showStretchTip && waypoints.count >= 3 {
            // Once there are stretches between turning points.
            TipView(stretchTip)
        } else if tourSeen && showOneWayTip && waypoints.count == 2 && !outAndBack {
            // After the first turning point.
            TipView(oneWayTip)
        } else if tourSeen && showImportTip && waypoints.count < 2 {
            // Before the first turning point: draw the route, or bring in one already rowed.
            TipView(importTip)
        }
    }

    @ViewBuilder private func panel(plan: RoutePlan?, boat: RoutePlan.Stop?, shown: LakeHour?) -> some View {
        if routeMode {
            planningPanel(plan: plan, boat: boat, shown: shown)
        } else {
            viewingPanel(shown: shown)
        }
    }

    /// While planning: the route's result in one line, start, pace and out and
    /// back in another, and the details only when pulled up. No hour strip, so
    /// the map keeps the screen.
    private func planningPanel(plan: RoutePlan?, boat: RoutePlan.Stop?, shown: LakeHour?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            grabber
            if let plan {
                HStack(spacing: 6) {
                    TrafficLightDot(light: plan.worstLight, size: 10)
                    Text(plan.worstLight.title).fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Text(tr("%@ · %@ · back %@", Format.distance(plan.distanceM), Format.duration(from: plan.start, to: plan.end), Format.time(plan.end)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                RouteBar(plan: plan).frame(height: 6)
            } else {
                Text(tr("Tap the water to add the turning points of your route."))
                    .font(.subheadline.weight(.semibold))
            }
            if let lakeWide = shown?.lakeWide, lakeWide.light > .green {
                LakeWideBanner(lakeWide: lakeWide).lineLimit(panelExpanded ? nil : 1)
            }
            planningControls
            if panelExpanded {
                CappedScroll(enabled: true, maxHeight: UIScreen.main.bounds.height * 0.3) {
                    VStack(alignment: .leading, spacing: 10) {
                        if view.sample {
                            Label(tr("Sample wind"), systemImage: "exclamationmark.triangle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        routePanel(plan: plan, boat: boat)
                    }
                }
            }
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
        .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
            if drag.translation.height < -30 { withAnimation(.snappy) { panelExpanded = true } }
            if drag.translation.height > 30 { withAnimation(.snappy) { panelExpanded = false } }
        })
    }

    /// Start time (back and forward an hour, or a pick from the list), pace and out and back.
    private var planningControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button { hourIndex = max(hourIndex - 1, 0) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                    .disabled(hourIndex <= 0)
                    .accessibilityLabel(tr("An hour earlier"))
                Menu {
                    Picker(tr("Start time"), selection: $hourIndex) {
                        ForEach(Array(view.hours.enumerated()), id: \.1.id) { i, hour in
                            Text(Format.dayTime(hour.time)).tag(i)
                        }
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(tr("Start")).font(.caption2).foregroundStyle(.secondary)
                        Text(hour.map { Format.time($0.time) } ?? "–").font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .frame(minWidth: 48)
                }
                .accessibilityLabel(tr("Start time"))
                .accessibilityValue(hour.map { Format.dayTime($0.time) } ?? "")
                Button { hourIndex = min(hourIndex + 1, view.hours.count - 1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                    .disabled(hourIndex >= view.hours.count - 1)
                    .accessibilityLabel(tr("An hour later"))
            }
            Spacer(minLength: 0)
            Stepper(value: $pace, in: 90...240, step: 5) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(tr("Pace /500 m")).font(.caption2).foregroundStyle(.secondary)
                    Text(Format.pace(pace)).font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            .fixedSize()
            Toggle(isOn: $outAndBack) {
                Image(systemName: "arrow.uturn.backward")
            }
            .toggleStyle(.button)
            .disabled(RouteEdit.isLoop(waypoints))
            .accessibilityLabel(tr("Out and back"))
        }
    }

    private func viewingPanel(shown: LakeHour?) -> some View {
        let plan: RoutePlan? = nil, boat: RoutePlan.Stop? = nil
        return VStack(alignment: .leading, spacing: 10) {
            grabber
            if tourSeen && showPanelTip {
                TipView(panelTip)
            }
            if !panelExpanded, let hour = shown {
                collapsedSummary(hour, plan: plan, boat: boat)
            } else if let hour = shown {
                // While planning the content scrolls in a part of the screen, so the map keeps its room.
                CappedScroll(enabled: routeMode, maxHeight: UIScreen.main.bounds.height * 0.3) {
                    expandedContent(hour, plan: plan, boat: boat)
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

    @ViewBuilder private func expandedContent(_ hour: LakeHour, plan: RoutePlan?, boat: RoutePlan.Stop?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // While planning, the hour strip below names the start; the hour only shows for the boat.
            if !routeMode || boat != nil || view.sample {
                HStack(alignment: .firstTextBaseline) {
                    if !routeMode || boat != nil {
                        Text(boat == nil ? Format.dayTime(hour.time) : tr("%@ · at the boat", Format.dayTime(hour.time))).font(.headline)
                    }
                    Spacer()
                    if view.sample {
                        Label(tr("Sample wind"), systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
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
        if let planner, let plan {
            RouteSummary(view: view, plan: plan, headline: false)
            if tourSeen && showBoatTip && !followBoat {
                TipView(boatTip)
            }
            HStack(spacing: 12) {
                Toggle(isOn: $followBoat) {
                    Label(tr("Lake at the boat's time"), systemImage: "figure.rower")
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
            Text(tr("Tap the water to add the turning points of your route. It starts at your club and goes one way; turn on Out and back to row the same way back. Tap or pull a stretch to add a point there. Tap a point to delete it, or drag it to move it. A point within 50 m of the start closes the loop."))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                Text(tr("Each square gets the same rowing light as a club page, from wind, gusts, waves, fog and thunderstorm risk at that square. DWD warnings, darkness and cold water apply to the whole lake and are shown in the panel below the map. While they make the whole lake red, the squares turn grey with red stripes; at sunrise or sunset and under an amber DWD warning, fainter amber stripes are drawn over the squares. Cold water shows in the panel only."))
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
    /// Adds a point on a stretch of the route, before the point at that index.
    var insertPoint: (Int, CLLocationCoordinate2D) -> Void = { _, _ in }
    var selectPoint: (Int?) -> Void = { _ in }
    /// Apple's satellite pictures with roads and names instead of the plain map.
    var imagery = false
    /// An imported route's track as it was rowed, drawn thin over the route.
    var track: [CLLocationCoordinate2D] = []

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
            pin.clubID = club.id
            map.addAnnotation(pin)
        }
        map.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        // Turning points move at once under a drag, without MapKit's hold first.
        let drag = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dragged(_:)))
        drag.delegate = context.coordinator
        drag.maximumNumberOfTouches = 1
        map.addGestureRecognizer(drag)
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
        if c.imagery != imagery {
            c.imagery = imagery
            let config: MKMapConfiguration
            if imagery {
                let hybrid = MKHybridMapConfiguration(elevationStyle: .flat)
                hybrid.pointOfInterestFilter = .excludingAll
                config = hybrid
            } else {
                let standard = MKStandardMapConfiguration(emphasisStyle: .muted)
                standard.pointOfInterestFilter = .excludingAll
                config = standard
            }
            map.preferredConfiguration = config
        }
        c.spot = $spot
        c.routeMode = routeMode
        c.addPoint = addPoint
        c.movePoint = movePoint
        c.insertPoint = insertPoint
        c.selectPoint = selectPoint
        c.showRoute(segments: segments, waypoints: waypoints, selected: selectedPoint, on: map)
        c.showTrack(track, on: map)
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
            c.current = (LakeRaster.image(view, hour: hour, layer: layer), arrows(hour), layer == .light ? hour.lakeWide.stripes : nil)
            c.renderer?.update(image: c.current.image, arrows: c.current.arrows, stripes: c.current.stripes)
        }
        c.showSpot(spot.map { view.grid.coordinate(ofCell: $0) }, on: map)
        c.showBoat(boat, on: map)
    }

    private func arrows(_ hour: LakeHour) -> [LakeRenderer.Arrow] {
        zip(view.points, hour.wind).compactMap { point, wind in
            guard let from = wind.fromDeg else { return nil }
            return LakeRenderer.Arrow(point: MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)),
                                      towardDeg: from + 180, speedMs: wind.speedMs ?? 0)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var spot: Binding<Int?>
        var overlay: LakeOverlay?
        var renderer: LakeRenderer?
        var grid: LakeGrid?
        /// The hour and layer drawn, and their picture and arrows.
        var shown: String?
        var current: (image: CGImage?, arrows: [LakeRenderer.Arrow], stripes: Light?) = (nil, [], nil)
        var routeMode = false
        var imagery = false
        /// Whether the lake was fitted below the editing bar of route mode.
        var fittedForRoute = false
        var addPoint: (CLLocationCoordinate2D) -> Void = { _ in }
        var movePoint: (Int, CLLocationCoordinate2D) -> Void = { _, _ in }
        var insertPoint: (Int, CLLocationCoordinate2D) -> Void = { _, _ in }
        var selectPoint: (Int?) -> Void = { _ in }
        private let spotPin = MKPointAnnotation()
        private let boatPin = MKPointAnnotation()
        private var shownRoute: ([RoutePlan.Segment], [Coordinate], Int?)?
        private var routeOverlays: [RouteLine] = []
        private var routePins: [RoutePin] = []
        private var trackLine: RowedTrackLine?
        private var shownTrack: [Coordinate] = []

        init(spot: Binding<Int?>) { self.spot = spot }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? RouteLine {
                return RouteLineRenderer(overlay: line)
            }
            if let line = overlay as? DragLine {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineWidth = 3
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            if let track = overlay as? RowedTrackLine {
                let renderer = MKPolylineRenderer(polyline: track)
                renderer.strokeColor = UIColor.label.withAlphaComponent(0.8)
                renderer.lineWidth = 1.5
                renderer.lineDashPattern = [3, 3]
                return renderer
            }
            guard let overlay = overlay as? LakeOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = LakeRenderer(overlay: overlay)
            renderer.update(image: current.image, arrows: current.arrows, stripes: current.stripes)
            self.renderer = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let pin = annotation as? ClubPin {
                let view = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: nil)
                view.glyphImage = UIImage(systemName: pin.isOwn ? LocationStore.markSymbol(for: pin.clubID) : "figure.rower")
                view.markerTintColor = pin.isOwn ? .systemBlue : .systemGray
                view.displayPriority = .required
                return view
            }
            if let pin = annotation as? RoutePin {
                let view = MKAnnotationView(annotation: pin, reuseIdentifier: nil)
                view.image = Self.image(for: pin)
                // The start is the club's launch point; the turning points move
                // with the drag gesture below, not MapKit's own hold-and-drag.
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

        /// A dot for a turning point: blue start, orange when tapped, white otherwise.
        static func image(for pin: RoutePin) -> UIImage {
            // A touch bigger than it looks, so it is easier to hold and drag.
            let size: CGFloat = pin.isStart || pin.isSelected ? 22 : 18
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                let rect = CGRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3)
                let circle = UIBezierPath(ovalIn: rect)
                (pin.isStart ? UIColor.systemBlue : pin.isSelected ? UIColor.systemOrange : UIColor.white).setFill()
                circle.fill()
                UIColor(white: 0.15, alpha: 1).setStroke()
                circle.lineWidth = 2
                circle.stroke()
            }
        }

        /// While a point is dragged, the route's pins stay as they are:
        /// replacing them would drop the point from under the finger.
        private var dragPin: RoutePin?
        /// A point being added on a stretch, not yet part of the route.
        private var dragIsNew = false
        /// Where the dragged point was, for when the drag is cancelled.
        private var dragOrigin: CLLocationCoordinate2D?
        /// Where the drag started, to find the point under the finger.
        private var touchStart: CGPoint?
        /// From the finger to the point, so the point stays where it was grabbed.
        private var grab = CGVector.zero
        /// The dashed line from the point before to the point after the dragged one.
        private var dragLine: DragLine?
        /// Shows, above the finger, the map under the dragged point.
        private lazy var loupe = Loupe()
        /// The route's points as shown, a loop's last point being the start again.
        private var shownWaypoints: [CLLocationCoordinate2D] = []

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pin = view.annotation as? RoutePin, !pin.isStart else { return }
            selectPoint(pin.index)
        }

        /// The turning point nearest to a touch, within reach of it; never the start.
        private func pin(near location: CGPoint, on map: MKMapView) -> RoutePin? {
            var nearest: RoutePin?
            var nearestDistance: CGFloat = 30
            for pin in routePins where !pin.isStart {
                let at: CGPoint = map.convert(pin.coordinate, toPointTo: map)
                let distance: CGFloat = hypot(at.x - location.x, at.y - location.y)
                if distance < nearestDistance {
                    nearest = pin
                    nearestDistance = distance
                }
            }
            return nearest
        }

        /// The stretch of the route under a touch, as the index a new point there gets.
        private func stretch(near location: CGPoint, on map: MKMapView) -> Int? {
            guard shownWaypoints.count >= 2 else { return nil }
            var nearest: Int?
            var nearestDistance: CGFloat = 22
            for i in 0..<(shownWaypoints.count - 1) {
                let a: CGPoint = map.convert(shownWaypoints[i], toPointTo: map)
                let b: CGPoint = map.convert(shownWaypoints[i + 1], toPointTo: map)
                let distance = Self.distance(from: location, toSegment: a, b)
                if distance < nearestDistance {
                    nearest = i + 1
                    nearestDistance = distance
                }
            }
            return nearest
        }

        static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx: CGFloat = b.x - a.x, dy: CGFloat = b.y - a.y
            let length2: CGFloat = dx * dx + dy * dy
            guard length2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
            let t: CGFloat = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touchStart = touch.location(in: gesture.view)
            return true
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard routeMode, let map = gesture.view as? MKMapView, let touchStart else { return false }
            return pin(near: touchStart, on: map) != nil || stretch(near: touchStart, on: map) != nil
        }

        /// The map's own panning waits until a drag has turned out not to start on the route.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            gesture is UIPanGestureRecognizer && other is UIPanGestureRecognizer
        }

        @objc func dragged(_ gesture: UIPanGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let finger = gesture.location(in: map)
            let point = CGPoint(x: finger.x + grab.dx, y: finger.y + grab.dy)
            switch gesture.state {
            case .began:
                guard let touchStart else { return }
                let pin: RoutePin
                if let existing = self.pin(near: touchStart, on: map) {
                    pin = existing
                    dragIsNew = false
                    let at: CGPoint = map.convert(pin.coordinate, toPointTo: map)
                    grab = CGVector(dx: at.x - touchStart.x, dy: at.y - touchStart.y)
                    selectPoint(pin.index)
                } else if let index = stretch(near: touchStart, on: map) {
                    // Pulling a stretch adds a point there.
                    pin = RoutePin()
                    pin.index = index
                    pin.coordinate = map.convert(touchStart, toCoordinateFrom: map)
                    dragIsNew = true
                    grab = .zero
                    map.addAnnotation(pin)
                } else {
                    return
                }
                dragPin = pin
                dragOrigin = pin.coordinate
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                pin.isSelected = true
                map.view(for: pin)?.image = Self.image(for: pin)
                showDragLine(for: pin, on: map)
                loupe.show(at: pin.coordinate, finger: finger, on: map)
            case .changed:
                guard let pin = dragPin else { return }
                pin.coordinate = map.convert(point, toCoordinateFrom: map)
                showDragLine(for: pin, on: map)
                loupe.show(at: pin.coordinate, finger: finger, on: map)
            case .ended, .cancelled, .failed:
                guard let pin = dragPin else { return }
                loupe.hide()
                if let dragLine { map.removeOverlay(dragLine) }
                dragLine = nil
                dragPin = nil
                if dragIsNew {
                    map.removeAnnotation(pin)
                    if gesture.state == .ended { insertPoint(pin.index, pin.coordinate) }
                } else if gesture.state == .ended {
                    movePoint(pin.index, pin.coordinate)
                } else if let dragOrigin {
                    pin.coordinate = dragOrigin
                }
                dragOrigin = nil
                dragIsNew = false
            default:
                break
            }
        }

        /// The route's shape around the dragged point, drawn as the finger moves;
        /// the colours of the route follow once the point is let go.
        private func showDragLine(for pin: RoutePin, on map: MKMapView) {
            let i = pin.index, points = shownWaypoints
            // A new point sits between the points before and at its index.
            let after = dragIsNew ? i : i + 1
            var neighbours: [CLLocationCoordinate2D] = []
            if i > 0, i - 1 < points.count { neighbours.append(points[i - 1]) }
            neighbours.append(pin.coordinate)
            if after < points.count { neighbours.append(points[after]) }
            if let dragLine { map.removeOverlay(dragLine) }
            let line = DragLine(coordinates: neighbours, count: neighbours.count)
            map.addOverlay(line, level: .aboveLabels)
            dragLine = line
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
            if routeMode, let index = stretch(near: location, on: map) {
                // A tap on a stretch adds a point there, not at the end.
                insertPoint(index, coordinate)
            } else if routeMode {
                addPoint(coordinate)
            } else {
                spot.wrappedValue = grid.cell(at: coordinate)
            }
        }

        func showRoute(segments: [RoutePlan.Segment], waypoints: [CLLocationCoordinate2D], selected: Int?, on map: MKMapView) {
            // A loop's last point is the start again and gets no pin of its own.
            shownWaypoints = routeMode ? waypoints : []
            let pinned = RouteEdit.isLoop(waypoints) ? Array(waypoints.dropLast()) : waypoints
            let points = routeMode ? pinned.map { Coordinate(lat: $0.latitude, lon: $0.longitude) } : []
            let lines = routeMode ? segments : []
            if dragPin != nil { return }
            if let shownRoute, shownRoute.0 == lines, shownRoute.1 == points {
                guard shownRoute.2 != selected else { return }
                // Only the tapped point changed: recolour the dots, keep the pins (and their selection).
                self.shownRoute = (lines, points, selected)
                for pin in routePins {
                    pin.isSelected = pin.index == selected
                    map.view(for: pin)?.image = Self.image(for: pin)
                    // So the same point can be tapped again after "Done".
                    if !pin.isSelected { map.deselectAnnotation(pin, animated: false) }
                }
                return
            }
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
            // The rowed track stays on top of the route, or the route's line would hide it.
            if let trackLine {
                map.removeOverlay(trackLine)
                map.addOverlay(trackLine, level: .aboveLabels)
            }
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

        func showTrack(_ points: [CLLocationCoordinate2D], on map: MKMapView) {
            let shown = points.map { Coordinate(lat: $0.latitude, lon: $0.longitude) }
            guard shown != shownTrack else { return }
            shownTrack = shown
            if let trackLine { map.removeOverlay(trackLine) }
            trackLine = nil
            guard points.count > 1 else { return }
            let line = RowedTrackLine(coordinates: points, count: points.count)
            // Over the route, which is wider and would hide it.
            map.addOverlay(line, level: .aboveLabels)
            trackLine = line
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
    var clubID: String?
}

final class RoutePin: MKPointAnnotation {
    var isStart = false
    var isSelected = false
    /// Its index in the route's waypoints.
    var index = 0
}

/// The route around a turning point while it is dragged.
final class DragLine: MKPolyline {}

/// A round magnifier above the finger that shows the map under a dragged
/// point, with cross hairs where the point will land.
final class Loupe: UIView {
    static let size: CGFloat = 116
    private let map = MKMapView()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isUserInteractionEnabled = false
        layer.cornerRadius = Self.size / 2
        layer.borderWidth = 3
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        map.frame = bounds
        map.layer.cornerRadius = Self.size / 2
        map.clipsToBounds = true
        map.isUserInteractionEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        addSubview(map)
        let cross = CAShapeLayer()
        let path = UIBezierPath()
        let c = Self.size / 2
        for (from, to) in [(CGPoint(x: c - 14, y: c), CGPoint(x: c - 5, y: c)), (CGPoint(x: c + 5, y: c), CGPoint(x: c + 14, y: c)),
                           (CGPoint(x: c, y: c - 14), CGPoint(x: c, y: c - 5)), (CGPoint(x: c, y: c + 5), CGPoint(x: c, y: c + 14))] {
            path.move(to: from)
            path.addLine(to: to)
        }
        path.append(UIBezierPath(ovalIn: CGRect(x: c - 3, y: c - 3, width: 6, height: 6)))
        cross.path = path.cgPath
        cross.strokeColor = UIColor.systemOrange.cgColor
        cross.fillColor = UIColor.systemOrange.cgColor
        cross.lineWidth = 2.5
        layer.addSublayer(cross)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `coordinate` magnified, above the finger, or below it near the top.
    func show(at coordinate: CLLocationCoordinate2D, finger: CGPoint, on host: MKMapView) {
        if superview !== host {
            map.preferredConfiguration = host.preferredConfiguration
            host.addSubview(self)
        }
        let span = MKCoordinateSpan(latitudeDelta: max(host.region.span.latitudeDelta / 8, 0.0008),
                                    longitudeDelta: max(host.region.span.longitudeDelta / 8, 0.0008))
        map.setRegion(MKCoordinateRegion(center: coordinate, span: span), animated: false)
        let half = Self.size / 2, gap: CGFloat = 70
        var y = finger.y - gap - half
        if y - half < host.safeAreaInsets.top + 8 { y = finger.y + gap + half }
        let x = min(max(finger.x, half + 8), host.bounds.width - half - 8)
        center = CGPoint(x: x, y: y)
    }

    func hide() { removeFromSuperview() }
}

/// An imported row's track as it was rowed.
final class RowedTrackLine: MKPolyline {}

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
    /// The wind at a forecast point.
    struct Arrow {
        let point: MKMapPoint
        let towardDeg: Double
        var speedMs: Double = 0
    }

    /// Screen points between arrows: more arrows as the map zooms in, fewer out.
    static let arrowSpacing: CGFloat = 60

    /// Arrow length on screen: longer in stronger wind.
    static func arrowLength(_ speedMs: Double) -> CGFloat { 14 + CGFloat(min(max(speedMs, 0), 15)) * 1.6 }

    /// The wind anywhere on the lake, from the forecast points weighted by
    /// distance (nearer counts more), averaged as east and north parts so
    /// opposite directions don't add up to a wrong one.
    static func wind(at p: MKMapPoint, from arrows: [Arrow]) -> (towardDeg: Double, speedMs: Double)? {
        guard !arrows.isEmpty else { return nil }
        var east = 0.0, north = 0.0, speed = 0.0, total = 0.0
        for a in arrows {
            let d2 = max(pow(a.point.x - p.x, 2) + pow(a.point.y - p.y, 2), 1)
            let w = 1 / d2
            let r = a.towardDeg * .pi / 180
            east += sin(r) * w
            north += cos(r) * w
            speed += a.speedMs * w
            total += w
        }
        let toward = atan2(east, north) * 180 / .pi
        return ((toward + 360).truncatingRemainder(dividingBy: 360), speed / total)
    }

    private let lock = NSLock()
    private var image: CGImage?
    private var arrows: [Arrow] = []
    /// Stripes over the water while the whole lake is red or amber (see LakeWide.stripes).
    private var stripes: Light?

    func update(image: CGImage?, arrows: [Arrow], stripes: Light?) {
        lock.lock()
        self.image = image
        self.arrows = arrows
        self.stripes = stripes
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let lake = overlay as? LakeOverlay else { return }
        lock.lock()
        let image = self.image, arrows = self.arrows, stripes = self.stripes
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
        if let stripes {
            // Amber stripes are wider apart and fainter than red ones.
            let red = stripes == .red
            context.saveGState()
            context.addPath(shore)
            context.clip(using: .evenOdd)
            // Lines x + y = k * gap, so the stripes run on across the map's tiles.
            let tile = self.rect(for: mapRect), gap = (red ? 14 : 24) / zoomScale
            let lines = CGMutablePath()
            var k = ((tile.minX + tile.minY) / gap).rounded(.down)
            while k * gap <= tile.maxX + tile.maxY {
                lines.move(to: CGPoint(x: k * gap - tile.minY, y: tile.minY))
                lines.addLine(to: CGPoint(x: k * gap - tile.maxY, y: tile.maxY))
                k += 1
            }
            context.addPath(lines)
            let color = red ? UIColor.systemRed.withAlphaComponent(0.55) : UIColor.systemOrange.withAlphaComponent(0.5)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth((red ? 3 : 2) / zoomScale)
            context.strokePath()
            context.restoreGState()
        }
        context.addPath(shore)
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1 / zoomScale)
        context.strokePath()

        // Arrows on an even grid over the water, fixed to the map so the tiles
        // agree; the grid gets finer as the map zooms in. Dark arrows with a
        // light edge read on light and dark maps alike.
        let spacing = Double(Self.arrowSpacing / zoomScale)
        let margin = Double(Self.arrowLength(15) / zoomScale)
        let area = mapRect.insetBy(dx: -margin, dy: -margin).intersection(lake.boundingMapRect)
        var paths: [CGPath] = []
        if !arrows.isEmpty, !area.isNull, spacing > 0 {
            var y = (area.minY / spacing).rounded(.down) * spacing + spacing / 2
            while y < area.maxY {
                // Every other row shifted by half, so the arrows don't line up in columns.
                let shift = Int((y / spacing).rounded(.down)) % 2 == 0 ? 0 : spacing / 2
                var x = ((area.minX - shift) / spacing).rounded(.down) * spacing + shift + spacing / 2
                while x < area.maxX {
                    let p = MKMapPoint(x: x, y: y)
                    let at = point(for: p)
                    if shore.contains(at, using: .evenOdd), let wind = Self.wind(at: p, from: arrows) {
                        paths.append(LakeArrow.path(at: at, towardDeg: wind.towardDeg, length: Self.arrowLength(wind.speedMs) / zoomScale).cgPath)
                    }
                    x += spacing
                }
                y += spacing
            }
        }
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

/// Its content as is, or (when enabled) in a scroll view no taller than
/// `maxHeight`, and only as tall as the content when that is shorter.
private struct CappedScroll<Content: View>: View {
    let enabled: Bool
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        if enabled {
            ScrollView {
                content.background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { height = geo.size.height }
                            .onChange(of: geo.size.height) { _, new in height = new }
                    }
                }
            }
            .frame(height: min(max(height, 1), maxHeight))
            .scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

/// What each symbol and colour on the lake map means, listing only what is on
/// the map right now (layer, whole-lake stripes, route, boat, spot).
struct LakeMapLegend: View {
    let layer: LakeLayer
    let stripes: Light?
    let routeMode: Bool
    let hasRoute: Bool
    let boat: Bool
    let spot: Bool
    let hasWind: Bool
    var track = false
    var clubID: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(layer.title) {
                    LakeLegend(layer: layer).padding(.vertical, 4)
                    MapBoatNote()
                    if stripes == .red {
                        row(Image(systemName: "line.diagonal").foregroundStyle(.red),
                            tr("Grey squares with red stripes: the whole lake is red (DWD warning or darkness), see the panel."))
                    } else if stripes == .amber {
                        row(Image(systemName: "line.diagonal").foregroundStyle(.orange),
                            tr("Amber stripes: the whole lake is amber (sunrise or sunset, DWD warning), see the panel. The squares keep their own colours."))
                    }
                }
                Section(tr("On the map")) {
                    row(ClubMarkIcon(color: .blue, symbol: LocationStore.markSymbol(for: clubID)), ClubMarkIcon.pageClubText(clubID))
                    row(ClubMarkIcon(color: .gray), tr("Other clubs on the lake"))
                    if hasWind {
                        row(Image(systemName: "arrow.up.right").fontWeight(.bold),
                            tr("Wind: points where the wind blows to; longer arrows mean stronger wind. Between the forecast points the wind is estimated from the nearest ones."))
                    }
                    if spot { row(Image(systemName: "scope"), tr("The spot you tapped")) }
                }
                if routeMode {
                    Section(tr("Route")) {
                        row(Image(systemName: "circle.fill").foregroundStyle(.blue), tr("Start at your club"))
                        row(Image(systemName: "circle").fontWeight(.bold), tr("Turning point: tap to select, hold and drag to move"))
                        if hasRoute {
                            row(HStack(spacing: 2) { ForEach([Light.green, .amber, .red], id: \.self) { Capsule().fill($0.color).frame(width: 8, height: 4) } },
                                tr("The route in the light the boat meets there; out and back run side by side"))
                        }
                        if boat { row(ClubMarkIcon(color: .indigo), tr("Where the boat is at the time shown")) }
                        if track { row(Image(systemName: "scribble.variable").foregroundStyle(.secondary), tr("Dashed: the track as you rowed it (imported row)")) }
                    }
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

    private func row(_ symbol: some View, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            symbol.frame(width: 28)
            Text(text).font(.subheadline)
        }
    }
}

/// A club mark as the maps draw it, for the legends: a white rower in a coloured circle.
struct ClubMarkIcon: View {
    let color: Color
    var symbol = "figure.rower"

    /// The legend line for the page's club, as its mark is drawn on this map.
    static func pageClubText(_ clubID: String?) -> String {
        LocationStore.markSymbol(for: clubID) == "house.fill" ? tr("Your home base, the club of this page") : tr("The club of this page")
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
    }
}
