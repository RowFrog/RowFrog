import MapKit

/// The club's own place in Apple Maps, when Apple has one (with photos,
/// opening hours, website), so "Open in Maps" shows its place card instead of
/// a bare address pin. Searched on the phone and remembered for 30 days; a
/// place is only taken when its name matches the club's and it lies within
/// 300 m of the launch point. Later the server could look these up once
/// (Apple Maps Server API, needs the paid developer account) and send them
/// with the club list.
@MainActor
final class ClubPlaces {
    static let shared = ClubPlaces()
    private nonisolated static let key = "RWClubPlaces"
    private nonisolated static let keepFor: TimeInterval = 30 * 24 * 3600
    static let maxDistance: CLLocationDistance = 300

    private var found: [String: MKMapItem] = [:]

    /// Where the club's Apple Maps place is, as last found; nil when none was found.
    nonisolated static func savedLocation(forID id: String) -> CLLocationCoordinate2D? {
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Any]] ?? [:]
        guard let pair = saved[id]?["at"] as? [Double], pair.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }

    /// Whether the club was looked up within the last 30 days, found or not, so
    /// maps that only need its position don't search again.
    nonisolated static func lookedUpRecently(forID id: String) -> Bool {
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Any]] ?? [:]
        guard let entry = saved[id], let checked = entry["checked"] as? Double else { return false }
        // A place found before its position was kept (before Nov 2026) is looked up again.
        if entry["name"] != nil, entry["at"] == nil { return false }
        return Date.now.timeIntervalSince1970 - checked < keepFor
    }

    /// The club's place, or nil when Apple Maps has none that fits.
    func place(for club: Club) async -> MKMapItem? {
        if let item = found[club.id] { return item }
        let saved = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [String: Any]] ?? [:]
        if let entry = saved[club.id], let checked = entry["checked"] as? Double,
           Date.now.timeIntervalSince1970 - checked < Self.keepFor, entry["name"] == nil {
            return nil  // looked recently and found nothing
        }
        // A name found before finds the same place again quickest.
        var item: MKMapItem?
        do {
            if let known = saved[club.id]?["name"] as? String { item = try await search(known, near: club) }
            if item == nil { item = try await search(club.name, near: club) }
            if item == nil, let short = club.shortName { item = try await search(short, near: club) }
        } catch {
            // Offline or too many searches at once (a lake map with many clubs):
            // nothing is remembered, so the next look tries again.
            return nil
        }
        var entry: [String: Any] = ["checked": Date.now.timeIntervalSince1970]
        if let name = item?.name { entry["name"] = name }
        // Its position, for the club's pin on every map once zoomed in (ClubMarks).
        if let at = item?.placemark.location?.coordinate { entry["at"] = [at.latitude, at.longitude] }
        var all = saved
        all[club.id] = entry
        UserDefaults.standard.set(all, forKey: Self.key)
        found[club.id] = item
        return item
    }

    /// The first place with a matching name near the club; throws when the search
    /// itself failed, as opposed to finding nothing.
    private func search(_ name: String, near club: Club) async throws -> MKMapItem? {
        let launch = CLLocation(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: launch.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)
        let items: [MKMapItem]
        do {
            items = try await MKLocalSearch(request: request).start().mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return nil  // no place by that name nearby: an answer, not a failure
        }
        return items.first { item in
            guard let placeName = item.name, let location = item.placemark.location,
                  location.distance(from: launch) <= Self.maxDistance else { return false }
            return Self.namesMatch(placeName, club.name) || club.shortName.map { Self.namesMatch(placeName, $0) } == true
        }
    }

    /// Whether two club names mean the same club: most of the shorter name's
    /// words (without "e.V.", "Club" and the like) appear in the other.
    nonisolated static func namesMatch(_ a: String, _ b: String) -> Bool {
        let ignored: Set<String> = ["ev", "e", "v", "der", "die", "das", "von", "und", "the", "club", "verein"]
        func words(_ s: String) -> Set<String> {
            let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            return Set(folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !ignored.contains($0) })
        }
        let wa = words(a), wb = words(b)
        let (short, long) = wa.count <= wb.count ? (wa, wb) : (wb, wa)
        guard !short.isEmpty else { return false }
        return Double(short.intersection(long).count) / Double(short.count) >= 0.6
    }
}
