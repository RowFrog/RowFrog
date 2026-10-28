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
    @State private var showingSettings = false
    /// The settings page to open with, as Boats and limits from a club page's boat menu.
    @State private var settingsPath: [SettingsRoute] = []
    @State private var initialSearch = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingTour = !Tutorial.seen
    @State private var showingSafety = SafetyNotice.needsAcceptance
    @State private var showingWhatsNew = WhatsNew.needsShowing
    /// A row shared from another app, kept until the clubs and lakes have loaded.
    @State private var sharedRow: RowTrack?
    @State private var rowNote: String?

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
                        pages(saved, showsListButton: !sideList, insets: geometry.safeAreaInsets)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .accessibilityHidden(showingSafety)
        .overlay {
            // The safety notice comes first, before the tour and before any
            // question; it stays until it is accepted.
            if showingSafety {
                SafetyNoticeView {
                    withAnimation { showingSafety = false }
                }
                .transition(.opacity)
            } else if showingTour {
                // The first-start tour, over everything until it is finished or skipped.
                TutorialView(locations: locations, reload: loadCatalog) {
                    Tutorial.markSeen()
                    selection = locations.homeID ?? ""
                    withAnimation { showingTour = false }
                }
                .transition(.opacity)
            }
        }
        .environment(\.locale, AppSettings.shared.locale)
        // Once after an update, when the safety notice was accepted and there are clubs to show.
        .sheet(isPresented: Binding(
            get: { showingWhatsNew && !showingSafety && !showingTour && !locations.saved.isEmpty },
            set: { if !$0 { showingWhatsNew = false; WhatsNew.markSeen() } }
        )) {
            WhatsNewView().environment(\.locale, AppSettings.shared.locale)
        }
        .fullScreenCover(isPresented: $showingList) {
            LocationListView(locations: locations, forecasts: forecasts, initialSearch: initialSearch,
                             returnTo: locations.saved.first { $0.id == selection }) { club in
                selection = club.id
                showingList = false
            }
            .environment(\.locale, AppSettings.shared.locale)
        }
        .sheet(isPresented: $showingSettings, onDismiss: { settingsPath = [] }) {
            SettingsView(locations: locations, path: settingsPath)
                .environment(\.locale, AppSettings.shared.locale)
        }
        .onAppear { applyAppearance() }
        .onChange(of: AppSettings.shared.appearance) { applyAppearance() }
        .onChange(of: AppSettings.shared.allowsLandscape) { Orientation.apply() }
        .task { await loadCatalog() }
        // The widget picks up the home base, clubs and settings when the user leaves the app.
        // Only on leaving, not on every pull-down of Control Center or the app switcher.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { WidgetBridge.publish(locations) }
        }
        // A new language or units show on the widget straight away.
        .onChange(of: AppSettings.shared.language) { WidgetBridge.publish(locations) }
        .onChange(of: AppSettings.shared.temperatureUnit) { WidgetBridge.publish(locations) }
        .onChange(of: AppSettings.shared.windUnit) { WidgetBridge.publish(locations) }
        // A tap on the widget opens its club.
        .onOpenURL { url in
            // A GPX, TCX or FIT file shared from another app.
            if url.isFileURL { return openRowFile(url) }
            guard url.scheme == "rowfrog", url.host() == "club", let id = url.pathComponents.last,
                  locations.saved.contains(where: { $0.id == id }) else { return }
            showingList = false
            selection = id
        }
        .modifier(SharedRowNote(note: $rowNote, catalogCount: locations.catalog.count, catalogLoaded: importSharedRow))
    }

    private func openRowFile(_ url: URL) {
        do {
            sharedRow = try TrackFile.read(contentsOf: url)
            importSharedRow()
        } catch {
            rowNote = RowImportError.unreadable.message
        }
    }

    /// Saves the shared row as a route on its lake, once the lakes are known.
    private func importSharedRow() {
        guard let track = sharedRow, !locations.catalog.isEmpty else { return }
        sharedRow = nil
        switch RowFileInbox.importRow(track, lakes: locations.lakes) {
        case .success(let (route, lake)):
            if let pace = track.cleaned.paceSecondsPer500 { RouteImport.usePace(pace) }
            rowNote = tr("Saved “%@” on %@. Open the lake view and pick it under Saved routes.", route.name, lake)
        case .failure(let error):
            rowNote = error.message
        }
    }

    private func openBoatSettings() {
        settingsPath = [.limits]
        showingSettings = true
    }

    /// As wide as an iPhone's list, so a row's numbers and text fit side by side (iPad).
    static let sideListWidth: CGFloat = 400
    static let sideListMinWidth: CGFloat = 860
    static let sideListMinHeight: CGFloat = 560

    private func pages(_ saved: [Club], showsListButton: Bool, insets: EdgeInsets) -> some View {
        // Each page keeps clear of the clock and the floating buttons with its own
        // margins, while the cards scroll on under both (Apple's guide).
        let margins = EdgeInsets(top: insets.top, leading: 0, bottom: insets.bottom + PageBar.height, trailing: 0)
        return TabView(selection: $selection) {
            ForEach(saved) { club in
                LocationPageView(club: club, lake: locations.lake(of: club), isHome: club.id == locations.homeID, forecasts: forecasts)
                    .pageBackground(.clubPages, clubID: club.id, drawsPicture: false)
                    .environment(\.isCurrentPage, club.id == selection)
                    .environment(\.openBoatSettings, openBoatSettings)
                    .environment(\.pageMargins, margins)
                    .tag(club.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: [.top, .bottom])
        .background {
            // Behind the pages, not on each one: a swiping TabView keeps its
            // pages out of the status bar and the page bar, which left black bars.
            let settings = AppSettings.shared
            ZStack {
                PagePicture(image: BackgroundLibrary.image(for: settings.background(for: .clubPages, clubID: selection), clubID: selection),
                            blurred: settings.blurBackground)
                    .id(selection)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: selection)
        }
        .overlay(alignment: .top) {
            TopEdgeFade(statusBar: insets.top)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            let forecast = forecasts.forecasts[selection]
            PageBar(clubs: saved, homeID: locations.homeID ?? "", selection: $selection,
                    showList: showsListButton ? { showingList = true } : nil,
                    showSettings: { showingSettings = true },
                    now: forecast?.current(), waterC: forecast?.waterTemperature?.celsius)
                .environment(\.openBoatSettings, openBoatSettings)
        }
        .onAppear { if selection.isEmpty { selection = saved[0].id } }
    }

    /// The countries of the saved clubs, the phone's and any near the user;
    /// an older backend without country files sends every club at once.
    private func loadCatalog() async {
        do {
            if let countries = try? await api.countries(), !countries.isEmpty {
                locations.setCountries(countries)
                // Screenshot hook `-RWOpenClub` may name a club abroad: then every country loads.
                let all = UserDefaults.standard.string(forKey: "RWOpenClub") != nil
                for code in all ? countries.map(\.code) : locations.countriesToLoad(near: KnownLocation.coordinate) {
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

/// Behind the clock and the signal icons: the cards blur and fade out as they
/// scroll under, as Apple's guide asks for the status bar; a plain strip in
/// Low Power Mode, which draws nothing live.
private struct TopEdgeFade: View {
    let statusBar: CGFloat
    /// How far the fade reaches below the status bar.
    static let tail: CGFloat = 14

    var body: some View {
        Group {
            if PowerState.shared.lowPower {
                Rectangle().fill(Color(.systemGroupedBackground))
                    .frame(height: statusBar)
            } else {
                let height = statusBar + Self.tail
                Rectangle().fill(.regularMaterial)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: statusBar * 0.6 / max(height, 1)),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The settings cog with the boat, the page dots with a house for the home base,
/// and the list button, as the Weather app has its map and list at the two ends.
/// Each group floats on its own piece of glass, all as tall as the bar, with
/// the symbols in one colour over the picture (Apple's guide for toolbars).
private struct PageBar: View {
    let clubs: [Club]
    let homeID: String
    @Binding var selection: String
    /// Nil when the list is already on screen.
    let showList: (() -> Void)?
    /// Always set: the cog stays here, beside the boat, also while the side
    /// list is on screen, so it does not move when the iPad turns.
    let showSettings: (() -> Void)?
    /// The selected club's hour now, for the lights in the boat menu.
    let now: ForecastHour?
    let waterC: Double?

    /// The buttons' height, which every piece shares.
    static let buttonHeight: CGFloat = 44
    /// What the pages keep free above the home indicator: the buttons and a gap.
    static let height: CGFloat = buttonHeight + 12
    /// The cog and the boat with their piece's inner margins; the list's side
    /// is as wide, so the dots stay in the middle.
    private static let sideWidth: CGFloat = 44 + 56 + 8

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if let showSettings {
                    Button(action: showSettings) {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .frame(width: 44, height: Self.buttonHeight)
                    }
                    .accessibilityLabel(tr("Settings"))
                }
                boatButton
            }
            .padding(.horizontal, 4)
            .barPiece(Capsule())
            .frame(width: Self.sideWidth, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(clubs) { club in
                    Group {
                        if club.id == homeID {
                            Image(systemName: "house.fill").font(.caption2)
                        } else {
                            Circle().frame(width: 7, height: 7)
                        }
                    }
                    .foregroundStyle(club.id == selection ? Color.primary : Color.secondary.opacity(0.5))
                    // Wider than the dot and as tall as the bar, so it is easier to hit.
                    .frame(width: 16, height: Self.buttonHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { selection = club.id } }
                    .accessibilityLabel(club.displayName)
                }
            }
            .padding(.horizontal, 8)
            .barPiece(Capsule())
            Spacer(minLength: 8)
            Group {
                if let showList {
                    Button(action: showList) {
                        Image(systemName: "list.bullet")
                            .font(.title3)
                            .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                    }
                    .barPiece(Circle())
                    .accessibilityLabel(tr("All locations"))
                }
            }
            .frame(width: Self.sideWidth, alignment: .trailing)
        }
        .tint(.primary)
        .foregroundStyle(.primary)
        .padding(.horizontal)
        .padding(.bottom, 4)
        // Bars keep their size at the largest text sizes, as the system's do.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The boat the rowing light is for, picked on the spot.
    private var boatButton: some View {
        let boat = AppSettings.shared.selectedBoat
        return BoatMenu(hour: now, waterC: waterC) {
            VStack(spacing: 0) {
                Image(systemName: "figure.rower").font(.body)
                Text(boat.shortName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 56, height: Self.buttonHeight)
        }
        .accessibilityLabel(tr("Boat: %@", boat.title))
        .accessibilityHint(tr("Picks another boat for the rowing light."))
    }
}

private extension View {
    /// A floating piece of the page bar: Liquid Glass (frosted before iOS 26),
    /// solid in Low Power Mode, which draws nothing live.
    @ViewBuilder
    func barPiece(_ shape: some Shape) -> some View {
        if PowerState.shared.lowPower {
            background(shape.fill(Color(.secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.15), radius: 6, y: 2))
        } else {
            glass(in: shape)
        }
    }
}
