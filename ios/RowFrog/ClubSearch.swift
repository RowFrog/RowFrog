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
    @State private var filter = ""

    private struct Water: Identifiable {
        let lake: Lake
        let clubs: [Club]
        var id: String { lake.id }
    }

    var body: some View {
        let clubs = locations.catalog.filter { $0.countryCode == country.code }
        let waters = Dictionary(grouping: clubs) { locations.lake(of: $0)?.id ?? "" }
            .values
            .compactMap { clubs -> Water? in
                guard let lake = locations.lake(of: clubs[0]) else { return nil }
                return Water(lake: lake, clubs: clubs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
            .filter { filter.isEmpty || LocationStore.fold($0.lake.title).contains(LocationStore.fold(filter)) }
            .sorted { $0.lake.title.localizedStandardCompare($1.lake.title) == .orderedAscending }
        let byRegion = clubs.contains { $0.region != nil }
        let groups = Dictionary(grouping: waters) { water -> String in
            byRegion ? (water.clubs.first?.region ?? tr("Other")) : LocationStore.fold(String(water.lake.title.prefix(1))).uppercased()
        }
        List {
            if clubs.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            // Ä under A, Ö under O, Ü under U, as in a dictionary.
            ForEach(groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { key in
                Section(key) {
                    ForEach(groups[key] ?? []) { water in
                        NavigationLink {
                            WaterClubsView(locations: locations, lake: water.lake, clubs: water.clubs)
                        } label: {
                            HStack {
                                Text(water.lake.title)
                                Spacer()
                                Text("\(water.clubs.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $filter, prompt: Text(tr("Lake or river")))
        .navigationTitle("\(country.flag) \(country.localizedName)")
        .task { await locations.ensureLoaded([country.code]) }
    }
}

struct WaterClubsView: View {
    let locations: LocationStore
    let lake: Lake
    let clubs: [Club]

    var body: some View {
        List(clubs) { club in
            SearchResultRow(club: club, lake: lake, saved: locations.isSaved(club)) { locations.add(club) }
        }
        .navigationTitle(lake.title)
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
