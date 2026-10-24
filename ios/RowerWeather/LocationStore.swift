import Foundation
import Observation

/// The user's saved locations, kept on the device like the Weather app's list.
/// The home base is always first and opens at launch. The list starts empty;
/// the user picks a home base and more clubs in the first-start tour.
@Observable
final class LocationStore {
    private(set) var savedIDs: [String]
    private(set) var homeID: String?
    /// Every club the backend can serve, used for the list and the search.
    private(set) var catalog: [Club] = []
    private(set) var lakesByClub: [String: Lake] = [:]
    /// Set when the catalog could not be loaded; the message is translated where it shows.
    var catalogFailed = false

    private let defaults: UserDefaults
    private static let savedKey = "RWSavedClubs"
    private static let homeKey = "RWHomeClub"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeID = defaults.string(forKey: Self.homeKey)
        savedIDs = defaults.stringArray(forKey: Self.savedKey) ?? []
    }

    /// For screenshots (`-RWDemoClubs YES`): MRC 1880 as home base and the other
    /// confirmed clubs, kept apart from the user's own list.
    static func forLaunch() -> LocationStore {
        guard UserDefaults.standard.bool(forKey: "RWDemoClubs") else { return LocationStore() }
        let suite = "RWDemoClubs"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = LocationStore(defaults: defaults)
        store.seedsDemoClubs = true
        return store
    }

    private var seedsDemoClubs = false

    /// Saved clubs that the backend knows, home base first.
    var saved: [Club] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ((homeID.map { [$0] } ?? []) + savedIDs.filter { $0 != homeID }).compactMap { byID[$0] }
    }

    /// Three clubs picked at random when the catalog loads, for suggestions without a location.
    private var randomPicks: [String] = []

    /// Clubs offered before the user searches: the five nearest to `location`,
    /// or three picked at random when the location is unknown.
    func suggestions(near location: Coordinate?) -> [Club] {
        if let location {
            return Array(catalog.sorted { Self.distance($0.launchPoint, location) < Self.distance($1.launchPoint, location) }.prefix(5))
        }
        return randomPicks.compactMap { id in catalog.first { $0.id == id } }
    }

    /// Rough distance in km, good enough to sort clubs by.
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let x = (b.lon - a.lon) * cos((a.lat + b.lat) / 2 * .pi / 180)
        let y = b.lat - a.lat
        return (x * x + y * y).squareRoot() * 111.2
    }

    func lake(of club: Club) -> Lake? { lakesByClub[club.id] }

    func isSaved(_ club: Club) -> Bool { club.id == homeID || savedIDs.contains(club.id) }

    /// Catalog clubs matching every word of the search, by club, lake or town.
    func search(_ text: String) -> [Club] {
        let terms = Self.fold(text).split(separator: " ")
        guard !terms.isEmpty else { return [] }
        return catalog.filter { club in
            let haystack = Self.fold([club.name, club.shortName ?? "", club.abbreviation ?? "", club.address, lake(of: club)?.name ?? ""].joined(separator: " "))
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// "Dießen" and "diessen" match, as do "Würm" and "wurm".
    private static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    func setCatalog(_ lakes: [Lake]) {
        catalog = lakes.flatMap(\.clubs)
        lakesByClub = Dictionary(lakes.flatMap { lake in lake.clubs.map { ($0.id, lake) } }, uniquingKeysWith: { a, _ in a })
        randomPicks = catalog.shuffled().prefix(3).map(\.id)
        if seedsDemoClubs, homeID == nil {
            homeID = "mrc-1880"
            savedIDs = catalog.filter { $0.launchPointVerified && $0.id != homeID }.map(\.id)
            persist()
        }
    }

    /// Adds a club to the list; the first one becomes the home base.
    func add(_ club: Club) {
        guard !isSaved(club) else { return }
        guard homeID != nil else { return makeHome(club) }
        savedIDs.append(club.id)
        persist()
    }

    func remove(_ club: Club) {
        guard club.id != homeID else { return }
        savedIDs.removeAll { $0 == club.id }
        persist()
    }

    /// Reorders the list as dragged; offsets are into `saved`. The home base stays first.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = saved.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        if let homeID {
            order.removeAll { $0 == homeID }
            order.insert(homeID, at: 0)
        }
        // Clubs the backend does not serve right now keep their place at the end.
        savedIDs = order + savedIDs.filter { !order.contains($0) }
        persist()
    }

    func makeHome(_ club: Club) {
        if !savedIDs.contains(club.id) { savedIDs.append(club.id) }
        homeID = club.id
        persist()
    }

    /// For the first-start choice: the new home base takes the old one's place,
    /// so trying several does not fill the list.
    func replaceHome(with club: Club) {
        if let old = homeID, old != club.id { savedIDs.removeAll { $0 == old } }
        makeHome(club)
    }

    private func persist() {
        defaults.set(savedIDs, forKey: Self.savedKey)
        if let homeID { defaults.set(homeID, forKey: Self.homeKey) } else { defaults.removeObject(forKey: Self.homeKey) }
    }
}

/// Forecasts by club, shared by the list and the pages so each loads once.
@MainActor
@Observable
final class ForecastStore {
    /// As the backend sent them, with the app's standard limits.
    private var raw: [String: ClubForecast] = [:]
    /// With the boat and limits chosen in the settings, worked out when read,
    /// so a change of limits shows at once.
    var forecasts: Forecasts { Forecasts(store: self) }
    /// The last forecast worked out per club and the limits it used, so pages
    /// that read it many times per frame neither redo the work nor get a new value.
    @ObservationIgnored private var applied: [String: (limits: RowingLimits, forecast: ClubForecast)] = [:]
    private(set) var failed: Set<String> = []
    private let api: APIClient

    nonisolated init(api: APIClient) { self.api = api }

    func load(_ clubID: String, force: Bool = false) async {
        if !force, raw[clubID] != nil { return }
        do {
            let forecast = try await api.forecast(clubID: clubID)
            applied[clubID] = nil
            raw[clubID] = forecast
            failed.remove(clubID)
        } catch {
            failed.insert(clubID)
        }
    }

    /// The forecast for a club with the user's boat and limits.
    func forecast(_ clubID: String) -> ClubForecast? {
        guard let base = raw[clubID] else { return nil }
        let limits = AppSettings.shared.limits
        if let cached = applied[clubID], cached.limits == limits { return cached.forecast }
        let forecast = base.applying(limits)
        applied[clubID] = (limits, forecast)
        return forecast
    }

    /// Reloads several locations in parallel, for pull to refresh on the list.
    func reload(_ clubIDs: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for id in clubIDs {
                group.addTask { await self.load(id, force: true) }
            }
        }
    }
}

@MainActor
struct Forecasts {
    let store: ForecastStore

    subscript(clubID: String) -> ClubForecast? { store.forecast(clubID) }
}
