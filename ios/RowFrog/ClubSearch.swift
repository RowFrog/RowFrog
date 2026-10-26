import CoreLocation
import MapKit
import SwiftUI

/// The phone's last known position, when the user already allowed it (the
/// first-start tour asks); never asks by itself. Used to sort the search
/// and to load the countries near the user.
enum KnownLocation {
    private static let manager = CLLocationManager()

    static var coordinate: Coordinate? {
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus),
              let location = manager.location else { return nil }
        return Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
    }
}

/// "All" and one chip per country above the search results.
struct CountryChips: View {
    let countries: [Country]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(tr("All countries"), selected: selection == nil) { selection = nil }
                ForEach(countries) { country in
                    chip("\(country.flag) \(country.localizedName)", selected: selection == country.code) {
                        selection = country.code
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Browse by country

/// Every country the search covers, then its states or waters, then the clubs.
struct CountryListView: View {
    let locations: LocationStore

    var body: some View {
        List(locations.countries) { country in
            NavigationLink {
                CountryWatersView(locations: locations, country: country)
            } label: {
                HStack {
                    Text(country.flag)
                    Text(country.localizedName)
                    Spacer()
                    Text(tr("%@ clubs", "\(country.clubs)")).foregroundStyle(.secondary).font(.subheadline)
                }
            }
        }
        .navigationTitle(tr("Countries"))
    }
}

/// One country's waters, grouped by state or canton where the list names
/// them, otherwise by first letter; loads the country when needed.
struct CountryWatersView: View {
    let locations: LocationStore
    let country: Country
    /// Screenshot hook: `-RWCountryFilter Havel` starts with that search.
    @State private var filter = UserDefaults.standard.string(forKey: "RWCountryFilter") ?? ""
    /// By water (the lake or river a club rows on) or by town, which helps in a
    /// city with many waters, such as Berlin or Hamburg.
    @AppStorage("RWCountryListByTown") private var byTown = false

    /// One row: a water or a town with its clubs. Pieces of one river or lake
    /// that the map data keeps apart (the Havel in Spandau, Tegel and Potsdam)
    /// share a row; each club keeps its own lake and forecast point.
    private struct Row: Identifiable {
        let title: String
        /// A club whose water the catalogs don't know, listed under its town.
        let unknown: Bool
        let clubs: [Club]
        var id: String { (unknown ? "near:" : "") + title }
    }

    private func rows(_ clubs: [Club]) -> [Row] {
        let groups = Dictionary(grouping: clubs) { club -> String in
            if byTown { return LocationStore.fold(club.town ?? locations.lake(of: club)?.listTitle ?? "") }
            guard let lake = locations.lake(of: club) else { return "" }
            return (lake.waterUnknown ? "near:" : "") + LocationStore.fold(lake.listTitle)
        }
        return groups.compactMap { key, clubs -> Row? in
            guard !key.isEmpty, let first = clubs.first else { return nil }
            let lake = locations.lake(of: first)
            let sorted = clubs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if byTown {
                return Row(title: first.town ?? lake?.listTitle ?? "", unknown: false, clubs: sorted)
            }
            guard let lake else { return nil }
            return Row(title: lake.listTitle, unknown: lake.waterUnknown, clubs: sorted)
        }
    }

    var body: some View {
        let clubs = locations.catalog.filter { $0.countryCode == country.code }
        let query = LocationStore.fold(filter)
        let shown = rows(clubs)
            // The water or town, or one of its clubs by name or town.
            .filter { row in
                query.isEmpty || LocationStore.fold(row.title).contains(query) || row.clubs.contains { club in
                    [club.name, club.shortName, club.abbreviation, club.town, locations.lake(of: club)?.listTitle].compactMap { $0 }
                        .contains { LocationStore.fold($0).contains(query) }
                }
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let byRegion = clubs.contains { $0.region != nil }
        let groups = Dictionary(grouping: shown) { row -> String in
            byRegion ? (row.clubs.first?.region ?? tr("Other")) : LocationStore.fold(String(row.title.prefix(1))).uppercased()
        }
        List {
            Picker(tr("List by"), selection: $byTown) {
                Text(tr("By water")).tag(false)
                Text(tr("By town")).tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if clubs.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            // Ä under A, Ö under O, Ü under U, as in a dictionary.
            ForEach(groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { key in
                Section(key) {
                    ForEach(groups[key] ?? []) { row in
                        NavigationLink {
                            WaterClubsView(locations: locations, title: row.title, clubs: row.clubs)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                    if row.unknown {
                                        Text(tr("Water not yet known")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(row.clubs.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $filter, prompt: Text(tr("Lake, river, club or town")))
        .navigationTitle("\(country.flag) \(country.localizedName)")
        .task { await locations.ensureLoaded([country.code]) }
    }
}

struct WaterClubsView: View {
    let locations: LocationStore
    let title: String
    let clubs: [Club]

    var body: some View {
        List(clubs) { club in
            SearchResultRow(club: club, lake: locations.lake(of: club), saved: locations.isSaved(club)) { locations.add(club) }
        }
        .navigationTitle(title)
    }
}

// MARK: - Add a place

/// "Not in the list? Add a place": the user moves the map until the pin sits
/// on their launch point, names it and saves it. It stays on this iPhone; a
/// switch (off unless the user turns it on) opens a prefilled suggestion for
/// everyone's list.
struct AddPlaceView: View {
    let locations: LocationStore
    @State var name: String
    let added: (OwnPlace) -> Void
    @State private var kind: OwnPlace.Kind = .club
    @State private var website = ""
    @State private var share = false
    @State private var satellite = true
    @State private var camera: MapCameraPosition
    @State private var center: Coordinate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(locations: LocationStore, name: String = "", added: @escaping (OwnPlace) -> Void) {
        self.locations = locations
        _name = State(initialValue: name)
        self.added = added
        // Start where the user is, else at the home base, else over the Alps' northern lakes.
        let start = KnownLocation.coordinate ?? locations.saved.first?.launchPoint ?? Coordinate(lat: 47.9, lon: 11.3)
        _center = State(initialValue: start)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: start.lat, longitude: start.lon),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
    }

    private var water: Lake? { locations.nearestLake(to: center) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        Map(position: $camera)
                            .mapStyle(satellite ? .imagery : .standard)
                            // Once the map stops: the nearest water is looked up among every lake.
                            .onMapCameraChange(frequency: .onEnd) { context in
                                center = Coordinate(lat: context.region.center.latitude, lon: context.region.center.longitude)
                            }
                        // The pin stays in the middle; the map moves under it.
                        Image(systemName: "mappin")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.red)
                            .shadow(radius: 2)
                            .offset(y: -17)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                    Toggle(tr("Satellite view"), isOn: $satellite)
                } header: {
                    Text(tr("Move the map until the pin sits where you launch"))
                } footer: {
                    if let water {
                        Text(tr("Near %@.", water.name))
                    }
                }
                Section {
                    TextField(tr("Name"), text: $name)
                    Picker(tr("What it is"), selection: $kind) {
                        ForEach(OwnPlace.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField(tr("Website (optional)"), text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Toggle(tr("Suggest it for everyone's list"), isOn: $share)
                } footer: {
                    Text(share
                        ? tr("When you save, the name, kind, position, water and website are sent to us. Nothing about you is sent. We check the place and add it to the list for everyone.")
                        : tr("The place stays on this iPhone and nobody else sees it."))
                }
                Section {
                    Text(tr("The forecast for your own place is worked out on this iPhone: wind, gusts, rain, fog, thunderstorms and daylight. Waves, water temperature and warnings are not available for it."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Add a place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save"), action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        var site = website.trimmingCharacters(in: .whitespaces)
        if !site.isEmpty, !site.contains("://") { site = "https://" + site }
        let place = OwnPlace(
            name: name.trimmingCharacters(in: .whitespaces), kind: kind, website: URL(string: site),
            coordinate: center, waterName: water?.name, shared: share
        )
        locations.addOwnPlace(place)
        if share {
            let country = water?.country
            let open = openURL
            Task { await place.suggest(api: .fromBundle(), country: country) { open($0) } }
        }
        added(place)
        dismiss()
    }
}
