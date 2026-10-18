import Foundation
import Observation

/// The user's saved locations, kept on the device like the Weather app's list.
/// The home base is always first and opens at launch.
@Observable
final class LocationStore {
    static let defaultHomeID = "mrc-1880"

    private(set) var savedIDs: [String]
    private(set) var homeID: String
    /// Every club the backend can serve, used for the list and the search.
    private(set) var catalog: [Club] = []
    private(set) var lakesByClub: [String: Lake] = [:]
    var catalogError: String?

    private let defaults: UserDefaults
    private static let savedKey = "RWSavedClubs"
    private static let homeKey = "RWHomeClub"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeID = defaults.string(forKey: Self.homeKey) ?? Self.defaultHomeID
        savedIDs = defaults.stringArray(forKey: Self.savedKey) ?? []
    }

    /// Saved clubs that the backend knows, home base first.
    var saved: [Club] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ([homeID] + savedIDs.filter { $0 != homeID }).compactMap { byID[$0] }
    }

    func lake(of club: Club) -> Lake? { lakesByClub[club.id] }

    func isSaved(_ club: Club) -> Bool { club.id == homeID || savedIDs.contains(club.id) }

    /// Catalog clubs matching every word of the search, by club, lake or town.
    func search(_ text: String) -> [Club] {
        let terms = Self.fold(text).split(separator: " ")
        guard !terms.isEmpty else { return [] }
        return catalog.filter { club in
            let haystack = Self.fold([club.name, club.shortName ?? "", club.address, lake(of: club)?.name ?? ""].joined(separator: " "))
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
        if defaults.stringArray(forKey: Self.savedKey) == nil {
            // First launch: the home base plus the other confirmed clubs.
            savedIDs = [homeID] + catalog.filter { $0.launchPointVerified && $0.id != homeID }.map(\.id)
            persist()
        }
    }

    func add(_ club: Club) {
        guard !isSaved(club) else { return }
        savedIDs.append(club.id)
        persist()
    }

    func remove(_ club: Club) {
        guard club.id != homeID else { return }
        savedIDs.removeAll { $0 == club.id }
        persist()
    }

    func makeHome(_ club: Club) {
        if !savedIDs.contains(club.id) { savedIDs.append(club.id) }
        homeID = club.id
        persist()
    }

    private func persist() {
        defaults.set(savedIDs, forKey: Self.savedKey)
        defaults.set(homeID, forKey: Self.homeKey)
    }
}

/// Forecasts by club, shared by the list and the pages so each loads once.
@Observable
final class ForecastStore {
    private(set) var forecasts: [String: ClubForecast] = [:]
    private(set) var failed: Set<String> = []
    private let api: APIClient

    init(api: APIClient) { self.api = api }

    func load(_ clubID: String, force: Bool = false) async {
        if !force, forecasts[clubID] != nil { return }
        do {
            forecasts[clubID] = try await api.forecast(clubID: clubID)
            failed.remove(clubID)
        } catch {
            failed.insert(clubID)
        }
    }
}
