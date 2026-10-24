import SwiftUI

/// Like the iOS Weather app: one full-screen page per saved location, swiped
/// left and right, with the home base first, and a list of all locations
/// behind the button at the bottom, or beside the pages on a wide screen.
struct RootView: View {
    let api: APIClient
    @State private var locations: LocationStore
    @State private var forecasts: ForecastStore
    @State private var selection = ""
    @State private var showingList = false
    @State private var initialSearch = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingTour = !Tutorial.seen

    init(api: APIClient) {
        self.api = api
        let store = LocationStore.forLaunch()
        store.countryLoader = { try await api.lakes(country: $0) }
        _locations = State(initialValue: store)
        // Own places get their forecast on the phone; the store knows where they are.
        _forecasts = State(initialValue: ForecastStore(api: api) { [weak store] id in store?.ownPlace(id) })
    }

    var body: some View {
        let saved = locations.saved
        Group {
            if saved.isEmpty {
                if locations.catalogFailed {
                    ContentUnavailableView {
                        Label(tr("No connection"), systemImage: "wifi.slash")
                    } description: {
                        Text(tr("Could not load the rowing locations."))
                    } actions: {
                        Button(tr("Try again")) { Task { await loadCatalog() } }
                    }
                } else if locations.catalog.isEmpty {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label(tr("No clubs yet"), systemImage: "figure.rower")
                    } description: {
                        Text(tr("Choose your home base and the other places you row."))
                    } actions: {
                        Button(tr("Add a club")) { showingList = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                GeometryReader { geometry in
                    // A wide and tall screen (an unfolded iPhone Duo on its side)
                    // keeps the list on the left; phones show it behind the button.
                    let sideList = geometry.size.width >= Self.sideListMinWidth && geometry.size.height >= Self.sideListMinHeight
                    HStack(spacing: 0) {
                        if sideList {
                            LocationListView(locations: locations, forecasts: forecasts, selectedID: selection) { club in
                                withAnimation { selection = club.id }
                            }
                            .frame(width: Self.sideListWidth)
                            Divider().ignoresSafeArea()
                        }
                        pages(saved, showsListButton: !sideList)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            // The first-start tour, over everything until it is finished or skipped.
            if showingTour {
                TutorialView(locations: locations, reload: loadCatalog) {
                    Tutorial.markSeen()
                    selection = locations.homeID ?? ""
                    withAnimation { showingTour = false }
                }
                .transition(.opacity)
            }
        }
        .environment(\.locale, AppSettings.shared.locale)
        .fullScreenCover(isPresented: $showingList) {
            LocationListView(locations: locations, forecasts: forecasts, initialSearch: initialSearch) { club in
                selection = club.id
                showingList = false
            }
            .environment(\.locale, AppSettings.shared.locale)
        }
        .onAppear { applyAppearance() }
        .onChange(of: AppSettings.shared.appearance) { applyAppearance() }
        .onChange(of: AppSettings.shared.allowsLandscape) { Orientation.apply() }
        .task { await loadCatalog() }
        // The widget picks up the home base, clubs and settings when the user leaves the app.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { WidgetBridge.publish(locations) }
        }
        // A tap on the widget opens its club.
        .onOpenURL { url in
            guard url.scheme == "rowfrog", url.host() == "club", let id = url.pathComponents.last,
                  locations.saved.contains(where: { $0.id == id }) else { return }
            showingList = false
            selection = id
        }
    }

    static let sideListWidth: CGFloat = 320
    static let sideListMinWidth: CGFloat = 860
    static let sideListMinHeight: CGFloat = 560

    private func pages(_ saved: [Club], showsListButton: Bool) -> some View {
        TabView(selection: $selection) {
            ForEach(saved) { club in
                LocationPageView(club: club, lake: locations.lake(of: club), isHome: club.id == locations.homeID, forecasts: forecasts)
                    .pageBackground(.clubPages, clubID: club.id)
                    .tag(club.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear { if selection.isEmpty { selection = saved[0].id } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PageBar(clubs: saved, homeID: locations.homeID ?? "", selection: $selection, showList: showsListButton ? { showingList = true } : nil)
        }
    }

    /// The countries of the saved clubs, the phone's and any near the user;
    /// an older backend without country files sends every club at once.
    private func loadCatalog() async {
        do {
            if let countries = try? await api.countries(), !countries.isEmpty {
                locations.setCountries(countries)
                for code in locations.countriesToLoad(near: KnownLocation.coordinate) {
                    locations.addCountry(code, lakes: try await api.lakes(country: code))
                }
            } else {
                locations.setCatalog(try await api.lakes())
            }
            locations.catalogFailed = false
            applyLaunchArguments()
            WidgetBridge.publish(locations)
        } catch {
            locations.catalogFailed = true
        }
    }

    /// Light, dark or the phone's setting, for every window and sheet.
    private func applyAppearance() {
        let style: UIUserInterfaceStyle = switch AppSettings.shared.appearance {
        case .device: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }

    /// Screenshot hooks: `-RWOpenClub <id>` opens that page (adding it from the
    /// catalog if needed), `-RWShowList YES` (or `-RWShowSettings YES`)
    /// opens the list, `-RWSearch <text>` opens it searching for the text and
    /// `-RWLandscape YES` turns the phone on its side. In the list, `-RWAddPlace YES`
    /// and `-RWBrowse YES|<country>` open "Add a place" and browsing by country.
    private func applyLaunchArguments() {
        let args = UserDefaults.standard
        if args.bool(forKey: "RWLandscape") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        // `-RWOwnPlace "Name;lat;lon"` adds that own place (once) and opens it.
        if let spec = args.string(forKey: "RWOwnPlace")?.split(separator: ";"), spec.count == 3,
           let lat = Double(spec[1]), let lon = Double(spec[2]) {
            let point = Coordinate(lat: lat, lon: lon)
            let place = locations.ownPlaces.first { $0.name == String(spec[0]) } ?? OwnPlace(
                name: String(spec[0]), kind: .boathouse, website: nil, coordinate: point,
                waterName: locations.nearestLake(to: point)?.name, shared: false)
            if locations.ownPlace(place.id) == nil { locations.addOwnPlace(place) }
            selection = place.id
        } else if let id = args.string(forKey: "RWOpenClub"), let club = locations.catalog.first(where: { $0.id == id }) {
            locations.add(club)
            selection = id
        } else {
            selection = locations.homeID ?? ""
        }
        if let search = args.string(forKey: "RWSearch") {
            initialSearch = search
            showingList = true
        } else if args.bool(forKey: "RWShowList") || args.bool(forKey: "RWShowSettings") {
            showingList = true
        }
    }
}

/// Page dots with a house for the home base, and the list button.
private struct PageBar: View {
    let clubs: [Club]
    let homeID: String
    @Binding var selection: String
    /// Nil when the list is already on screen.
    let showList: (() -> Void)?

    var body: some View {
        HStack {
            Spacer().frame(width: 44)
            Spacer()
            HStack(spacing: 8) {
                ForEach(clubs) { club in
                    Group {
                        if club.id == homeID {
                            Image(systemName: "house.fill").font(.system(size: 9))
                        } else {
                            Circle().frame(width: 7, height: 7)
                        }
                    }
                    .foregroundStyle(club.id == selection ? Color.primary : Color.secondary.opacity(0.5))
                    .onTapGesture { withAnimation { selection = club.id } }
                    .accessibilityLabel(club.displayName)
                }
            }
            Spacer()
            if let showList {
                Button(action: showList) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("All locations"))
            } else {
                Spacer().frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .background(.bar)
    }
}
