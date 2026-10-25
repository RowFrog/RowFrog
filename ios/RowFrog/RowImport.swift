import HealthKit
import SwiftUI
import UniformTypeIdentifiers

/// Rowing workouts in Apple Health that carry a GPS route: from Apple Watch, or
/// from a rowing app that saves its rows to Health. Read only and on the phone;
/// Health asks the user the first time "Import a row" opens.
@MainActor
@Observable
final class HealthRows {
    struct Row: Identifiable, Hashable {
        let id: UUID
        let start: Date
        let end: Date
        let distanceM: Double?
        /// The app or watch that recorded it.
        let source: String
    }

    enum State: Equatable { case idle, loading, loaded, unavailable, failed }

    private(set) var rows: [Row] = []
    private(set) var state = State.idle
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var routes: [UUID: HKWorkoutRoute] = [:]
    /// How far back to look.
    static let days = 365

    func load() async {
        // Screenshot hook: `-RWImportRows YES` lists made-up rows without asking Health.
        if UserDefaults.standard.bool(forKey: "RWImportRows") {
            let day = 86_400.0
            rows = [(2, 8_400.0, "Apple Watch"), (5, 12_100, "CrewNerd"), (9, 6_200, "Apple Watch")].map { ago, metres, source in
                let start = Date.now.addingTimeInterval(-ago * day)
                return Row(id: UUID(), start: start, end: start.addingTimeInterval(metres / 500 * 140), distanceM: metres, source: source)
            }
            state = .loaded
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { state = .unavailable; return }
        state = .loading
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), HKSeriesType.workoutRoute()])
            let since = Calendar.current.date(byAdding: .day, value: -Self.days, to: .now) ?? .distantPast
            let inRange = HKQuery.predicateForSamples(withStart: since, end: .now)
            let rowing = NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForWorkouts(with: .rowing), inRange])
            let workouts = try await HKSampleQueryDescriptor(predicates: [.workout(rowing)],
                                                             sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
                                                             limit: 100).result(for: store)
            // One query for all routes, matched to their workout by time: a
            // route starts within the workout it belongs to.
            let allRoutes = try await HKSampleQueryDescriptor(predicates: [.workoutRoute(inRange)], sortDescriptors: []).result(for: store)
            var found: [UUID: HKWorkoutRoute] = [:]
            for workout in workouts {
                let window = workout.startDate.addingTimeInterval(-60)...workout.endDate.addingTimeInterval(60)
                if let route = allRoutes.first(where: { window.contains($0.startDate) }) { found[workout.uuid] = route }
            }
            routes = found
            rows = workouts.filter { found[$0.uuid] != nil }.map { workout in
                Row(id: workout.uuid, start: workout.startDate, end: workout.endDate,
                    distanceM: workout.totalDistance?.doubleValue(for: .meter()),
                    source: workout.sourceRevision.source.name)
            }
            state = .loaded
        } catch {
            // Health says nothing when reading was not allowed: it then finds no workouts.
            state = .failed
        }
    }

    /// The row's GPS points.
    func track(_ row: Row) async throws -> RowTrack {
        guard let route = routes[row.id] else { throw TrackFile.Failure.noPoints }
        var points: [RowTrack.Point] = []
        for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
            points.append(RowTrack.Point(lat: location.coordinate.latitude, lon: location.coordinate.longitude, time: location.timestamp))
        }
        guard points.count >= 2 else { throw TrackFile.Failure.noPoints }
        return RowTrack(points: points, source: .health)
    }
}

/// "Import a row": a rowing workout from Apple Health, or a GPX, TCX or FIT file.
struct RowImportSheet: View {
    let lakeName: String
    /// The picked row's track; returns an error to show, or nil when it became a route.
    let onPick: (RowTrack) -> String?
    @State private var health = HealthRows()
    @State private var showingFiles = false
    @State private var loadingRow: UUID?
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
                Section {
                    healthRows
                } header: {
                    Label("Apple Health", systemImage: "heart.text.square")
                } footer: {
                    Text(tr("Rowing workouts with a GPS route, e.g. from Apple Watch or a rowing app that saves its rows to Health. Row Frog only reads them, on this iPhone."))
                }
                Section {
                    Button(tr("Choose a file"), systemImage: "doc") { showingFiles = true }
                } header: {
                    Label(tr("File"), systemImage: "folder")
                } footer: {
                    Text(tr("GPX, TCX or FIT files from CrewNerd, Garmin Connect, Strava and other apps. You can also share a file to Row Frog straight from those apps."))
                }
            }
            .navigationTitle(tr("Import a row"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel")) { dismiss() } }
            }
            .fileImporter(isPresented: $showingFiles, allowedContentTypes: TrackFile.types) { result in
                guard case .success(let url) = result else { return }
                do {
                    pick(try TrackFile.read(contentsOf: url))
                } catch {
                    problem = tr("Row Frog could not read a GPS track in this file.")
                }
            }
            .task { if health.state == .idle { await health.load() } }
        }
    }

    @ViewBuilder private var healthRows: some View {
        switch health.state {
        case .idle, .loading:
            HStack { ProgressView(); Text(tr("Looking in Apple Health …")).foregroundStyle(.secondary) }
        case .unavailable:
            Text(tr("Apple Health is not available on this device.")).foregroundStyle(.secondary)
        case .failed:
            Text(tr("Apple Health could not be read.")).foregroundStyle(.secondary)
        case .loaded where health.rows.isEmpty:
            Text(tr("No rowing workouts with a route in Apple Health. If you said no to reading them, allow it in the Health app under Sharing › Apps › Row Frog."))
                .foregroundStyle(.secondary)
        case .loaded:
            ForEach(health.rows) { row in
                Button { Task { await pick(row) } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.day(row.start) + " " + Format.time(row.start)).foregroundStyle(.primary)
                            Text([row.distanceM.map { Format.distance($0) }, Format.duration(from: row.start, to: row.end), row.source]
                                    .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if loadingRow == row.id { ProgressView() }
                    }
                }
                .disabled(loadingRow != nil)
            }
        }
    }

    private func pick(_ row: HealthRows.Row) async {
        loadingRow = row.id
        defer { loadingRow = nil }
        do {
            pick(try await health.track(row))
        } catch {
            problem = tr("Apple Health has no GPS points for this row.")
        }
    }

    private func pick(_ track: RowTrack) {
        if let error = onPick(track) {
            problem = error
        } else {
            dismiss()
        }
    }
}

/// A file shared to Row Frog from another app: it becomes a saved route on the
/// lake whose clubs are nearest to where the row went.
enum RowFileInbox {
    /// Lakes this far from every point of the row are not where it was rowed.
    static let nearKm = 3.0

    /// The saved route and the lake's name, or an error to show.
    static func importRow(_ track: RowTrack, lakes: [Lake], store: RouteStore = .shared) -> Result<(Route, String), RowImportError> {
        let step = max(track.points.count / 100, 1)
        let sample = stride(from: 0, to: track.points.count, by: step).map { track.points[$0] }
        let nearest = lakes.compactMap { lake -> (Lake, Double)? in
            let d = sample.flatMap { p in lake.clubs.map { LocationStore.distance($0.launchPoint, Coordinate(lat: p.lat, lon: p.lon)) } }.min()
            return d.map { (lake, $0) }
        }
        .filter { $0.1 <= nearKm }
        .min { $0.1 < $1.1 }?.0
        guard let lake = nearest else { return .failure(.noLake) }
        guard let route = RouteImport.route(from: track, lakeId: lake.id, launchPoints: lake.clubs.map(\.launchPoint)) else {
            return .failure(.tooShort)
        }
        store.save(route)
        return .success((route, lake.name))
    }
}

/// The note after a shared file was imported, and the import itself once the
/// catalog has loaded (a file can open the app before the lakes are known).
struct SharedRowNote: ViewModifier {
    @Binding var note: String?
    let catalogCount: Int
    let catalogLoaded: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: catalogCount) { catalogLoaded() }
            .alert(tr("Import a row"), isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
                Button(tr("OK")) {}
            } message: {
                Text(note ?? "")
            }
    }
}

enum RowImportError: Error {
    case unreadable, noLake, tooShort, notOnLake(String)

    var message: String {
        switch self {
        case .unreadable: tr("Row Frog could not read a GPS track in this file.")
        case .noLake: tr("Row Frog knows no lake with rowing clubs where this row went.")
        case .tooShort: tr("This row is too short to make a route of.")
        case .notOnLake(let name): tr("This row was not on %@.", name)
        }
    }
}
