import CoreLocation
import XCTest
@testable import RowFrog

/// Runs testdata/states/route-editor.json, the cases the website's tests run too,
/// through the route editor's chart (Charts/route-editor.json), so planning a route
/// works the same on the iPhone and on rowfrog.com.
final class RouteDraftTests: XCTestCase {
    private struct Table: Decodable {
        struct Spec: Decodable { let name: String; let points: [String]; let outAndBack: Bool }
        struct Send: Decodable {
            let type: String
            let point: String?
            let index: Int?
            let way: String?
            let route: String?
            let name: String?
            let id: String?
        }

        /// Only the keys a step lists are checked; `selected` and `saved` may be null.
        struct Expect: Decodable {
            let taken: Bool?
            let state: String?
            let status: String?
            let points: [String]?
            let outAndBack: Bool?
            let canUndo: Bool?
            let selected: Int??
            let saved: String??
            let savedName: String?

            private enum CodingKeys: String, CodingKey {
                case taken, state, status, points, outAndBack, canUndo, selected, saved, savedName
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                taken = try c.decodeIfPresent(Bool.self, forKey: .taken)
                state = try c.decodeIfPresent(String.self, forKey: .state)
                status = try c.decodeIfPresent(String.self, forKey: .status)
                points = try c.decodeIfPresent([String].self, forKey: .points)
                outAndBack = try c.decodeIfPresent(Bool.self, forKey: .outAndBack)
                canUndo = try c.decodeIfPresent(Bool.self, forKey: .canUndo)
                selected = try c.contains(.selected) ? .some(c.decodeIfPresent(Int.self, forKey: .selected)) : .none
                saved = try c.contains(.saved) ? .some(c.decodeIfPresent(String.self, forKey: .saved)) : .none
                savedName = try c.decodeIfPresent(String.self, forKey: .savedName)
            }
        }

        struct Step: Decodable { let send: Send; let expect: Expect? }
        struct Case: Decodable { let name: String; let steps: [Step] }
        let points: [String: [Double]]
        let routes: [String: Spec]
        let cases: [Case]
    }

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let table = try! JSONDecoder().decode(
        Table.self, from: Data(contentsOf: root.appending(path: "testdata/states/route-editor.json")))
    private static let chart = try! JSONDecoder().decode(
        Statechart.self, from: Data(contentsOf: root.appending(path: "ios/RowFrog/Charts/route-editor.json")))

    private func point(_ name: String) -> CLLocationCoordinate2D {
        let p = Self.table.points[name]!
        return CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
    }

    private func name(of p: CLLocationCoordinate2D) -> String {
        Self.table.points.first { $0.value[0] == p.latitude && $0.value[1] == p.longitude }?.key ?? "\(p.latitude),\(p.longitude)"
    }

    func testTheChartNamesOnlyGuardsAndActionsTheAppWrites() {
        XCTAssertEqual(Self.chart.guardNames, RouteDraft.guardNames)
        XCTAssertEqual(Self.chart.actionNames, RouteDraft.actionNames)
        XCTAssertEqual(Self.chart.initial, ["looking"])
        for (path, node) in Self.chart.paths {
            for (event, list) in node.on {
                for target in list.compactMap(\.target) {
                    XCTAssertNotNil(Self.chart.resolve(target, from: path), "\(event) on \(path): \(target)")
                }
            }
        }
    }

    func testTheAppShipsTheChart() {
        XCTAssertNotNil(Bundle.main.url(forResource: "route-editor", withExtension: "json"), "Charts/route-editor.json in the app")
        XCTAssertEqual(RouteDraft.chart.id, Self.chart.id)
    }

    func testEveryCaseInTheSharedTable() {
        XCTAssertGreaterThanOrEqual(Self.table.cases.count, 8)
        for c in Self.table.cases {
            // The table's route ids, as the app's routes have UUIDs.
            var ids: [String: UUID] = [:]
            func route(_ id: String) -> Route {
                let spec = Self.table.routes[id]!
                let uuid = ids[id] ?? UUID()
                ids[id] = uuid
                return Route(id: uuid, name: spec.name, lakeId: "lake", points: spec.points.map { name in
                    let p = Self.table.points[name]!
                    return Coordinate(lat: p[0], lon: p[1])
                }, outAndBack: spec.outAndBack)
            }
            var draft = RouteDraft(chart: Self.chart, lakeId: "lake", launch: point("club"))
            for (i, step) in c.steps.enumerated() {
                let at = "\(c.name), step \(i + 1) (\(step.send.type))"
                let taken = draft.send(event(step.send, route: route))
                let want = step.expect
                XCTAssertEqual(taken, want?.taken ?? true, "\(at): taken")
                guard let want else { continue }
                if let state = want.state { XCTAssertEqual(draft.stateName, state, "\(at): state") }
                if let status = want.status { XCTAssertEqual(draft.status.rawValue, status, "\(at): status") }
                if let points = want.points { XCTAssertEqual(draft.points.map(name(of:)), points, "\(at): points") }
                if let outAndBack = want.outAndBack { XCTAssertEqual(draft.outAndBack, outAndBack, "\(at): outAndBack") }
                if let canUndo = want.canUndo { XCTAssertEqual(draft.canUndo, canUndo, "\(at): canUndo") }
                if let selected = want.selected { XCTAssertEqual(draft.selected, selected, "\(at): selected") }
                if let saved = want.saved {
                    let id = draft.saved?.id
                    let named = id.map { id in ids.first { $0.value == id }?.key ?? "other" }
                    XCTAssertEqual(named, saved, "\(at): saved")
                }
                if let savedName = want.savedName { XCTAssertEqual(draft.saved?.name, savedName, "\(at): savedName") }
            }
        }
    }

    private func event(_ send: Table.Send, route: (String) -> Route) -> RouteEditorEvent {
        let p = send.point.map(point) ?? CLLocationCoordinate2D()
        let i = send.index ?? 0
        switch send.type {
        case "TOGGLE_PLANNING": return .togglePlanning
        case "NEW_ROUTE": return .newRoute
        case "OPEN_ROUTE": return .openRoute(route(send.route!))
        case "ADD": return .add(p)
        case "INSERT": return .insert(i, p)
        case "MOVE": return .move(i, p)
        case "SELECT": return .select(i)
        case "DONE": return .done
        case "DELETE_POINT": return .deletePoint
        case "WAY_BACK": return .wayBack(RouteReturn.allCases.first { $0.name == send.way }!)
        case "CLEAR": return .clear
        case "UNDO": return .undo
        case "SAVE": return .save(name: send.name!)
        case "SAVE_AS_NEW": return .saveAsNew(name: send.name!)
        case "DELETE_ROUTE": return .deleteRoute
        case "ROUTE_CHANGED": return .routeChanged(id: route(send.id!).id, send.route.map(route))
        default: preconditionFailure("unknown event \(send.type)")
        }
    }

    func testUndoGoesBackAtMostTheHistoryLimit() {
        var draft = RouteDraft(chart: Self.chart, lakeId: "lake", launch: point("club"))
        draft.send(.togglePlanning)
        for i in 0..<(RouteDraft.historyLimit + 20) {
            draft.send(.add(CLLocationCoordinate2D(latitude: 48 + Double(i) / 1000, longitude: 11.3)))
        }
        var undone = 0
        while draft.send(.undo) { undone += 1 }
        XCTAssertEqual(undone, RouteDraft.historyLimit)
    }

    func testASavedRouteKeepsAnImportedRowsTrackUntilCleared() {
        var rowed = Route(name: "Rowed", lakeId: "lake", points: [Coordinate(lat: 47.99, lon: 11.34), Coordinate(lat: 47.995, lon: 11.345)],
                          outAndBack: false)
        rowed.track = [Coordinate(lat: 47.995, lon: 11.345)]
        rowed.importedFrom = .file
        var draft = RouteDraft(chart: Self.chart, lakeId: "lake", launch: point("club"))
        draft.send(.openRoute(rowed))
        draft.send(.add(point("c")))
        draft.send(.saveAsNew(name: "Copy"))
        XCTAssertEqual(draft.saved?.track, rowed.track)
        XCTAssertNotEqual(draft.saved?.id, rowed.id)
        draft.send(.clear)
        draft.send(.add(point("b")))
        draft.send(.save(name: "Plain"))
        XCTAssertNil(draft.saved?.track)
        XCTAssertNil(draft.saved?.importedFrom)
    }

    /// The reader alone: an event passes to the parent, and a state already on the path is not entered again.
    func testTheReaderPassesEventsUpAndEntersStatesOnce() throws {
        let chart = try JSONDecoder().decode(Statechart.self, from: Data("""
        {"id": "t", "initial": "a", "states": {
          "a": {"initial": "x", "entry": ["inA"], "on": {"GO": {"target": "b"}},
                "states": {"x": {"entry": ["inX"], "on": {"GO": {"guard": "no", "target": "y"}}}, "y": {}}},
          "b": {"entry": ["inB"], "on": {"BACK": [{"guard": "no", "target": "b"}, {"target": "a", "actions": ["back"]}]}}}}
        """.utf8))
        XCTAssertEqual(chart.initial, ["a", "x"])
        XCTAssertEqual(chart.transition(from: ["a", "x"], on: "GO") { _ in false }, .init(state: ["b"], actions: ["inB"]))
        XCTAssertEqual(chart.transition(from: ["b"], on: "BACK") { _ in false }, .init(state: ["a", "x"], actions: ["back", "inA", "inX"]))
        XCTAssertNil(chart.transition(from: ["b"], on: "GO") { _ in true })
        XCTAssertNil(chart.resolve("nowhere", from: ["a"]))
    }
}
