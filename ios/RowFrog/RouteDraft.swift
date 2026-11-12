import CoreLocation

/// How the boat gets back to the club: not at all, the same way back, or
/// straight from the last turning point.
enum RouteReturn: CaseIterable, Identifiable {
    case oneWay, outAndBack, loop

    var id: Self { self }

    var title: String {
        switch self {
        // Short, for the three parts of the switch.
        case .oneWay: tr("One way", key: "Way back one way")
        case .outAndBack: tr("Out and back", key: "Way back out and back")
        case .loop: tr("Loop")
        }
    }

    /// The name the route editor's chart and its shared table use.
    var name: String {
        switch self {
        case .oneWay: "oneWay"
        case .outAndBack: "outAndBack"
        case .loop: "loop"
        }
    }
}

/// What the person does in the route editor: the events of its chart
/// (Charts/route-editor.json), with what each one carries.
enum RouteEditorEvent {
    case togglePlanning, newRoute, openRoute(Route)
    case add(CLLocationCoordinate2D), insert(Int, CLLocationCoordinate2D), move(Int, CLLocationCoordinate2D)
    case select(Int), done, deletePoint
    case wayBack(RouteReturn), clear, undo
    case save(name: String), saveAsNew(name: String), deleteRoute
    /// The route was renamed or deleted (nil) in Manage routes.
    case routeChanged(id: UUID, Route?)

    var name: String {
        switch self {
        case .togglePlanning: "TOGGLE_PLANNING"
        case .newRoute: "NEW_ROUTE"
        case .openRoute: "OPEN_ROUTE"
        case .add: "ADD"
        case .insert: "INSERT"
        case .move: "MOVE"
        case .select: "SELECT"
        case .done: "DONE"
        case .deletePoint: "DELETE_POINT"
        case .wayBack: "WAY_BACK"
        case .clear: "CLEAR"
        case .undo: "UNDO"
        case .save: "SAVE"
        case .saveAsNew: "SAVE_AS_NEW"
        case .deleteRoute: "DELETE_ROUTE"
        case .routeChanged: "ROUTE_CHANGED"
        }
    }

    /// The turning point an event names, if any.
    var index: Int? {
        switch self {
        case let .insert(i, _), let .move(i, _), let .select(i): i
        default: nil
        }
    }
}

/// The route being planned on the lake map: its turning points, the way back, the
/// saved route it came from and the undo history, driven by the route editor's
/// statechart, as the website's routedraft.js. Split off LakeMapScreen.swift, which
/// kept all of this in @State properties set by hand. The screen sends events and
/// draws what this holds.
struct RouteDraft {
    /// Whether the route is as saved; compared, not a flag, so undoing back to the
    /// saved route makes it Saved again (owner decision 12 Nov 2026).
    enum Status: String { case new, saved, changed }

    /// One step of the undo history.
    struct Snapshot: Equatable {
        var points: [Coordinate]
        var outAndBack: Bool
        var rowed: Route?
    }

    static let chart = Statechart.load("route-editor")
    /// Undo goes back this many changes.
    static let historyLimit = 100

    let chart: Statechart
    let lakeId: String
    /// Where a new route starts: the club's launch point.
    let launch: CLLocationCoordinate2D?
    private(set) var state: [String]
    private(set) var points: [CLLocationCoordinate2D]
    private(set) var outAndBack: Bool
    /// The saved route open on the map, if any.
    private(set) var saved: Route?
    /// The imported row the route came from, kept while its route is changed.
    private(set) var rowed: Route?
    /// The turning point tapped for changing, by its index in `points`.
    private(set) var selected: Int?
    private(set) var history: [Snapshot] = []

    init(chart: Statechart = RouteDraft.chart, lakeId: String, launch: CLLocationCoordinate2D?,
         points: [CLLocationCoordinate2D] = [], outAndBack: Bool = false, saved: Route? = nil, rowed: Route? = nil,
         state: [String]? = nil, selected: Int? = nil) {
        self.chart = chart
        self.lakeId = lakeId
        self.launch = launch
        self.points = points
        self.outAndBack = outAndBack
        self.saved = saved
        self.rowed = rowed
        self.state = state ?? chart.initial
        self.selected = selected
    }

    var planning: Bool { state.first == "planning" }
    var stateName: String { state.joined(separator: ".") }
    var canUndo: Bool { !history.isEmpty }

    var status: Status {
        guard let saved else { return .new }
        return Self.same(saved.points, points) && saved.outAndBack == outAndBack ? .saved : .changed
    }

    /// Whether the event would do anything now, for a button's disabled state.
    func can(_ event: RouteEditorEvent) -> Bool {
        chart.transition(from: state, on: event.name) { allows($0, event) } != nil
    }

    /// Runs the event through the chart; false when nothing takes it.
    @discardableResult
    mutating func send(_ event: RouteEditorEvent) -> Bool {
        guard let step = chart.transition(from: state, on: event.name, allowed: { allows($0, event) }) else { return false }
        for action in step.actions { run(action, event) }
        // An edit that changed nothing leaves no step to undo.
        if step.actions.contains("record"), history.last == snapshot { history.removeLast() }
        state = step.state
        return true
    }

    private var snapshot: Snapshot {
        Snapshot(points: points.map { Coordinate(lat: $0.latitude, lon: $0.longitude) }, outAndBack: outAndBack, rowed: rowed)
    }

    private static func same(_ saved: [Coordinate], _ points: [CLLocationCoordinate2D]) -> Bool {
        saved.count == points.count && zip(saved, points).allSatisfy { $0.lat == $1.latitude && $0.lon == $1.longitude }
    }

    static let guardNames: Set<String> = ["canAdd", "isStretch", "isTurningPoint", "wayBackAllowed", "hasRoute",
                                          "canUndo", "hasSaved", "canSaveAsNew"]

    private func allows(_ name: String, _ event: RouteEditorEvent) -> Bool {
        let i = event.index ?? -1
        switch name {
        // A closed loop takes no more points.
        case "canAdd": return !RouteEdit.isLoop(points)
        // A stretch to add a point on: before the point at `index`, not before the start.
        case "isStretch": return i > 0 && i < points.count
        // Not the start, nor a loop's end, which is the start again.
        case "isTurningPoint": return i > 0 && i < points.count && !(RouteEdit.isLoop(points) && i == points.count - 1)
        // A loop needs two turning points first.
        case "wayBackAllowed":
            if case .wayBack(.loop) = event { return points.count >= 3 }
            return true
        case "hasRoute": return points.count >= 2
        case "canUndo": return !history.isEmpty
        case "hasSaved": return saved != nil
        case "canSaveAsNew": return points.count >= 2 && saved != nil
        default: preconditionFailure("route editor: no guard \(name)")
        }
    }

    static let actionNames: Set<String> = ["deselect", "startAtClub", "newRoute", "openRoute", "record", "add", "insert",
                                           "move", "select", "removeSelected", "wayBack", "clear", "undo", "save",
                                           "saveAsNew", "forgetSaved", "routeChanged"]

    private mutating func run(_ name: String, _ event: RouteEditorEvent) {
        switch (name, event) {
        case ("deselect", _): selected = nil
        // A new route starts at the club's launch point.
        case ("startAtClub", _): if points.isEmpty, let launch { points = [launch] }
        case ("newRoute", _):
            points = []
            outAndBack = false
            saved = nil
            rowed = nil
            history = []
        // A saved route opens with its own history: undo does not go back to the route shown before.
        case let ("openRoute", .openRoute(route)):
            points = route.coordinates
            outAndBack = route.outAndBack
            saved = route
            rowed = route.track == nil ? nil : route
            history = []
        case ("record", _):
            history.append(snapshot)
            if history.count > Self.historyLimit { history.removeFirst() }
        case let ("add", .add(point)):
            points = RouteEdit.add(point, to: points)
            if RouteEdit.isLoop(points) { outAndBack = false }
        // The new point is the one tapped after, to drag or delete it.
        case let ("insert", .insert(i, point)):
            points = RouteEdit.insert(point, at: i, in: points)
            selected = i
        case let ("move", .move(i, point)): points = RouteEdit.move(at: i, to: point, in: points)
        case let ("select", .select(i)): selected = i
        case ("removeSelected", _): if let selected { points = RouteEdit.remove(at: selected, from: points) }
        case let ("wayBack", .wayBack(way)):
            points = way == .loop ? RouteEdit.close(points) : RouteEdit.open(points)
            outAndBack = way == .outAndBack
        // Back to the launch point; the imported row's track goes too.
        case ("clear", _):
            points = Array(points.prefix(1))
            rowed = nil
        case ("undo", _):
            guard let last = history.popLast() else { return }
            points = last.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            outAndBack = last.outAndBack
            rowed = last.rowed
        // Updates the open saved route, or saves a new one.
        case let ("save", .save(name)):
            saved = stored(saved ?? Route(name: name, lakeId: lakeId, points: [], outAndBack: outAndBack), name: name)
        // A new saved route; the one opened before stays as it was.
        case let ("saveAsNew", .saveAsNew(name)):
            saved = stored(Route(name: name, lakeId: lakeId, points: [], outAndBack: outAndBack), name: name)
        case ("forgetSaved", _):
            saved = nil
            rowed = nil
        case let ("routeChanged", .routeChanged(id, route)): if saved?.id == id { saved = route }
        default: preconditionFailure("route editor: action \(name) cannot run on \(event.name)")
        }
    }

    /// The route as drawn now, under `name`; an imported row's track and date go with it.
    private func stored(_ base: Route, name: String) -> Route {
        var route = base
        route.name = name
        route.points = snapshot.points
        route.outAndBack = outAndBack
        route.track = rowed?.track
        route.rowedAt = rowed?.rowedAt
        route.importedFrom = rowed?.importedFrom
        return route
    }
}
