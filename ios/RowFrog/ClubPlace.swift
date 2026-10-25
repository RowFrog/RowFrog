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
    private static let key = "RWClubPlaces"
    private static let keepFor: TimeInterval = 30 * 24 * 3600
    static let maxDistance: CLLocationDistance = 300

    private var found: [String: MKMapItem] = [:]

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
        if let known = saved[club.id]?["name"] as? String { item = await search(known, near: club) }
        if item == nil { item = await search(club.name, near: club) }
        if item == nil, let short = club.shortName { item = await search(short, near: club) }
        var entry: [String: Any] = ["checked": Date.now.timeIntervalSince1970]
        if let name = item?.name { entry["name"] = name }
        var all = saved
        all[club.id] = entry
        UserDefaults.standard.set(all, forKey: Self.key)
        found[club.id] = item
        return item
    }

    private func search(_ name: String, near club: Club) async -> MKMapItem? {
        let launch = CLLocation(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: launch.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return nil }
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
