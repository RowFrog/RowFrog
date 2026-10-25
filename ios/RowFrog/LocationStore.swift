import Foundation
import Observation

/// The user's saved locations, kept on the device like the Weather app's list.
/// The home base is always first and opens at launch. The list starts empty;
/// the user picks a home base and more clubs in the first-start tour.
///
/// The clubs come one country at a time (countries/<cc>/lakes): at start the
/// countries of the saved clubs, the phone's country and any country within
/// `nearbyKm` of the user; the others when the user searches all countries
/// or browses one. Own places (OwnPlaces.swift) live only on the device.
@Observable
final class LocationStore {
    private(set) var savedIDs: [String]
    private(set) var homeID: String?
    /// Every club loaded so far, used for the list and the search.
    private(set) var catalog: [Club] = []
    private(set) var lakesByClub: [String: Lake] = [:]
    /// Set when the catalog could not be loaded; the message is translated where it shows.
    var catalogFailed = false
    /// The countries the search covers; empty with an older backend, whose one list has every club.
    private(set) var countries: [Country] = []
    private(set) var loadedCountries: Set<String> = []
    /// Places the user put on the map.
    private(set) var ownPlaces: [OwnPlace]
    /// Countries of the saved clubs, so they load at the next start before anything else.
    private(set) var savedCountries: Set<String>

    private let defaults: UserDefaults
    private static let savedKey = "RWSavedClubs"
    private static let homeKey = "RWHomeClub"

    /// The mark of the page's club on every map: a house for the home base,
    /// a rower for any other club (as in the page bar). The page's club is blue,
    /// other clubs grey.
    static func markSymbol(for clubID: String?) -> String {
        clubID != nil && clubID == homeDefaults.string(forKey: homeKey) ? "house.fill" : "figure.rower"
    }
    /// Where the home base is kept: the screenshots' demo list has its own.
    private static var homeDefaults: UserDefaults = .standard
    private static let ownPlacesKey = "RWOwnPlaces"
    private static let savedCountriesKey = "RWSavedCountries"
    /// Countries whose clubs lie this close to the user load at start too, for places near a border.
    static let nearbyKm = 50.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeID = defaults.string(forKey: Self.homeKey)
        savedIDs = defaults.stringArray(forKey: Self.savedKey) ?? []
        ownPlaces = defaults.data(forKey: Self.ownPlacesKey).flatMap { try? JSONDecoder().decode([OwnPlace].self, from: $0) } ?? []
        savedCountries = Set(defaults.stringArray(forKey: Self.savedCountriesKey) ?? [])
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
        homeDefaults = defaults
        return store
    }

    private var seedsDemoClubs = false

    /// Saved clubs that the backend knows and own places, home base first.
    var saved: [Club] {
        let byID = Dictionary((catalog + ownPlaces.map(\.club)).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ((homeID.map { [$0] } ?? []) + savedIDs.filter { $0 != homeID }).compactMap { byID[$0] }
    }

    func ownPlace(_ id: String) -> OwnPlace? { ownPlaces.first { $0.id == id } }

    /// Saves a new own place and adds it to the list (as home base when the list is empty).
    func addOwnPlace(_ place: OwnPlace) {
        ownPlaces.append(place)
        persistOwnPlaces()
        add(place.club)
    }

    private func persistOwnPlaces() {
        defaults.set(try? JSONEncoder().encode(ownPlaces), forKey: Self.ownPlacesKey)
    }

    /// The catalog lake nearest `point` within `km`, to name the water of an own place.
    func nearestLake(to point: Coordinate, within km: Double = 2) -> Lake? {
        let lakes = Set(lakesByClub.values)
        return lakes.map { ($0, Self.distance($0.center, point)) }
            .filter { $0.1 <= km }
            .min { $0.1 < $1.1 }?.0
    }

    /// Which countries to load: the saved clubs' countries, the phone's region,
    /// and any country with clubs within `nearbyKm` of `location`. Falls back to
    /// the first country when none of these is covered.
    func countriesToLoad(near location: Coordinate?, region: String? = Locale.current.region?.identifier) -> [String] {
        let known = countries.map(\.code)
        var wanted = savedCountries
        if let region { wanted.insert(region.lowercased()) }
        if let location {
            for c in countries where c.bounds.distance(to: location) <= Self.nearbyKm { wanted.insert(c.code) }
        }
        let codes = known.filter { wanted.contains($0) && !loadedCountries.contains($0) }
        if codes.isEmpty, loadedCountries.isEmpty, let first = known.first { return [first] }
        return codes
    }

    var unloadedCountries: [String] { countries.map(\.code).filter { !loadedCountries.contains($0) } }

    func country(_ code: String) -> Country? { countries.first { $0.code == code } }

    /// Fetches one country's clubs; set by the root view.
    @ObservationIgnored var countryLoader: ((String) async throws -> [Lake])?
    private(set) var loadingCountries: Set<String> = []

    /// Loads the countries not loaded yet, for a search across all countries or browsing one.
    @MainActor
    func ensureLoaded(_ codes: [String]) async {
        for code in codes where !loadedCountries.contains(code) && !loadingCountries.contains(code) {
            guard let countryLoader else { return }
            loadingCountries.insert(code)
            if let lakes = try? await countryLoader(code) { addCountry(code, lakes: lakes) }
            loadingCountries.remove(code)
        }
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

    func lake(of club: Club) -> Lake? {
        if club.isOwnPlace { return ownPlace(club.id)?.lake }
        return lakesByClub[club.id]
    }

    func isSaved(_ club: Club) -> Bool { club.id == homeID || savedIDs.contains(club.id) }

    /// Loaded clubs matching every word of the search, by club, abbreviation,
    /// lake, town or state, in `country` (nil for all). Names starting with the
    /// search come first, then the nearest to `location`, then by name.
    func search(_ text: String, country: String? = nil, near location: Coordinate? = nil) -> [Club] {
        let terms = Self.fold(text).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        let matches = catalog.filter { club in
            guard country == nil || club.countryCode == country else { return false }
            let haystack = Self.fold([club.name, club.shortName ?? "", club.abbreviation ?? "", club.address,
                                      lake(of: club)?.name ?? "", club.region ?? ""].joined(separator: " "))
            return terms.allSatisfy { haystack.contains($0) }
        }
        let first = terms[0]
        func starts(_ club: Club) -> Bool {
            [club.name, club.shortName ?? "", club.abbreviation ?? ""].contains { Self.fold($0).hasPrefix(first) }
        }
        return matches.sorted { a, b in
            let (sa, sb) = (starts(a), starts(b))
            if sa != sb { return sa }
            if let location {
                let (da, db) = (Self.distance(a.launchPoint, location), Self.distance(b.launchPoint, location))
                if da != db { return da < db }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// "Dießen" and "diessen" match, as do "Würm" and "wurm" or "Zürich" and "Zurich".
    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    func setCountries(_ list: [Country]) {
        countries = list
    }

    /// Adds one country's waters and clubs, replacing what was loaded for it before.
    func addCountry(_ code: String, lakes: [Lake]) {
        let others = catalog.filter { $0.countryCode != code }
        let otherLakes = Dictionary(grouping: others, by: { lakesByClub[$0.id] }).compactMap { lake, clubs in
            lake.map { Lake(id: $0.id, name: $0.name, center: $0.center, clubs: clubs, hasOutline: $0.hasOutline, country: $0.country) }
        }
        loadedCountries.insert(code)
        apply(otherLakes + lakes)
    }

    /// Every club at once, from an older backend without country files.
    func setCatalog(_ lakes: [Lake]) {
        loadedCountries = Set(lakes.flatMap { $0.clubs.map(\.countryCode) })
        apply(lakes)
    }

    private func apply(_ lakes: [Lake]) {
        catalog = lakes.flatMap(\.clubs)
        lakesByClub = Dictionary(lakes.flatMap { lake in lake.clubs.map { ($0.id, lake) } }, uniquingKeysWith: { a, _ in a })
        let known = Set(randomPicks).intersection(catalog.map(\.id))
        if known.count < 3 { randomPicks = catalog.shuffled().prefix(3).map(\.id) }
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
        noteCountry(of: club)
        persist()
    }

    /// Removes a club from the list; an own place exists only in the list, so it is deleted.
    func remove(_ club: Club) {
        guard club.id != homeID else { return }
        savedIDs.removeAll { $0 == club.id }
        if club.isOwnPlace {
            ownPlaces.removeAll { $0.id == club.id }
            persistOwnPlaces()
        }
        persist()
    }

    private func noteCountry(of club: Club) {
        guard !club.isOwnPlace else { return }
        savedCountries.insert(club.countryCode)
        defaults.set(Array(savedCountries).sorted(), forKey: Self.savedCountriesKey)
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
        noteCountry(of: club)
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
    /// Why the last refresh of a club failed; gone once one works.
    private(set) var failures: [String: RefreshFailure] = [:]
    var failed: Set<String> { Set(failures.keys) }
    /// Clubs whose picked model has no forecast yet, so the automatic one is shown.
    private(set) var pickedModelMissing: Set<String> = []
    private let api: APIClient
    /// The own place behind an id, whose forecast the phone works out itself.
    private let ownPlace: @MainActor (String) -> OwnPlace?

    nonisolated init(api: APIClient, ownPlace: @escaping @MainActor (String) -> OwnPlace? = { _ in nil }) {
        self.api = api
        self.ownPlace = ownPlace
    }

    func load(_ clubID: String, force: Bool = false) async {
        if !force, raw[clubID] != nil { return }
        if let model = AppSettings.shared.pickedModel(for: clubID) {
            if let forecast = try? await api.forecast(clubID: clubID, model: model) {
                applied[clubID] = nil
                raw[clubID] = forecast
                failures[clubID] = nil
                pickedModelMissing.remove(clubID)
                return
            }
            pickedModelMissing.insert(clubID)
        } else {
            pickedModelMissing.remove(clubID)
        }
        do {
            let forecast: ClubForecast
            if clubID.hasPrefix(OwnPlace.idPrefix) {
                guard let place = ownPlace(clubID) else { throw URLError(.fileDoesNotExist) }
                forecast = try await PlaceForecaster.load(place.club)
            } else {
                forecast = try await api.forecast(clubID: clubID)
            }
            applied[clubID] = nil
            raw[clubID] = forecast
            failures[clubID] = nil
        } catch {
            failures[clubID] = RefreshFailure(error, ownPlace: clubID.hasPrefix(OwnPlace.idPrefix))
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

/// Why a forecast could not be loaded, in words: what happened, on whose
/// side, and what helps.
enum RefreshFailure: Equatable {
    case offline, timeout, notFound, server(Int), unreadable, other(String)
    /// An own place's forecast comes from Open-Meteo, not from our server.
    case placeService

    init(_ error: Error, ownPlace: Bool = false) {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost, .dnsLookupFailed:
                self = .offline
            case .timedOut:
                self = .timeout
            default:
                self = ownPlace ? .placeService : .other(url.localizedDescription)
            }
        } else if let http = error as? HTTPStatusError {
            self = ownPlace ? .placeService : (http.code == 404 ? .notFound : .server(http.code))
        } else if error is DecodingError {
            self = .unreadable
        } else {
            self = ownPlace ? .placeService : .other(error.localizedDescription)
        }
    }

    /// A few words for the line under the club's name.
    var short: String {
        switch self {
        case .offline: tr("no internet connection")
        case .timeout: tr("the server did not answer in time")
        case .notFound: tr("no forecast for this club on the server")
        case let .server(code): tr("server error %d", code)
        case .unreadable: tr("the forecast could not be read")
        case .placeService: tr("the weather service did not answer")
        case .other: tr("unexpected error")
        }
    }

    /// What happened, where, and what to do.
    var explanation: String {
        switch self {
        case .offline:
            tr("Your phone could not reach the internet, or the connection dropped during the download. Check Wi-Fi or mobile data, and in the iPhone settings whether Row Frog may use mobile data. Then pull down to refresh.")
        case .timeout:
            tr("The forecast server (api.rowfrog.com) did not answer in time. That is usually a slow connection or a short hiccup at the server. Pull down to try again in a minute.")
        case .notFound:
            tr("The server has no forecast file for this club. A newly added club gets one with the next forecast run, every 30 minutes. Nothing to fix on your phone.")
        case let .server(code):
            tr("The forecast server (api.rowfrog.com) answered with error %d. That is on our side, not your phone's, and usually fixes itself. Try again later.", code)
        case .unreadable:
            tr("The forecast arrived, but this version of the app could not read it. The server probably sends something newer than the app knows. Update the app; if that doesn't help, tell us.")
        case .placeService:
            tr("Your own places get their forecast straight from Open-Meteo, which did not answer properly. That is on their side and usually passes quickly. Try again later.")
        case let .other(detail):
            tr("Something unexpected went wrong (%@). Pull down to try again.", detail)
        }
    }
}

@MainActor
struct Forecasts {
    let store: ForecastStore

    subscript(clubID: String) -> ClubForecast? { store.forecast(clubID) }
}
