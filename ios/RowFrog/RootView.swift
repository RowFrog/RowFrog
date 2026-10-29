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
    /// Set on leaving the app, so coming back loads new forecasts (not a pull-down of Control Center).
    @State private var wasInBackground = false
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
            if phase == .background {
                WidgetBridge.publish(locations)
                wasInBackground = true
            } else if phase == .active, wasInBackground {
                wasInBackground = false
                Task { await refreshOnReturn() }
            }
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

    /// Back in the app: what is on screen loads first, the list top to
    /// bottom or the club page shown, then every other saved club.
    private func refreshOnReturn() async {
        let ids = locations.saved.map(\.id)
        let first = showingList || !ids.contains(selection) ? ids : [selection]
        await forecasts.refreshOnReturn(first: first, then: ids)
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
                LocationPageView(club: club, lake: locations.lake(of: club), isHome: club.id == locations.homeID, forecasts: forecasts,
                                 savedIDs: saved.map(\.id))
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
            let scroll = PageScroll.shared
            let club = saved.first { $0.id == selection }
            let forecast = forecasts.forecasts[selection]
            TopEdgeFade(statusBar: insets.top, scrolled: scroll.scrolled.contains(selection),
                        title: scroll.titleGone.contains(selection) ? club : nil,
                        light: forecast?.current()?.light, stale: forecast?.isStale() ?? false)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            BottomEdgeFade(homeIndicator: insets.bottom, underBar: PageScroll.shared.underBar.contains(selection))
                .ignoresSafeArea(edges: .bottom)
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
/// The same soft blur at the bottom, behind the floating buttons, while cards
/// are under them, as Apple's scroll edge effect; nothing at a page's end.
/// Low Power Mode draws the buttons solid and needs no blur behind them.
private struct BottomEdgeFade: View {
    let homeIndicator: CGFloat
    let underBar: Bool

    var body: some View {
        let bar = homeIndicator + PageBar.height
        let height = bar + TopEdgeFade.tail
        Rectangle().fill(.thinMaterial)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black.opacity(0.8), location: TopEdgeFade.tail / max(height, 1)),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .opacity(underBar && !PowerState.shared.lowPower ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: underBar)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TopEdgeFade: View {
    let statusBar: CGFloat
    /// Whether cards are under the clock; at the top of a page nothing is drawn.
    let scrolled: Bool
    /// The club whose name the bar shows once its big title has scrolled away.
    let title: Club?
    let light: Light?
    let stale: Bool
    /// How far the fade reaches below the bar.
    static let tail: CGFloat = 28

    var body: some View {
        let bar = statusBar + (title == nil ? 0 : InlineClubTitle.height)
        ZStack(alignment: .bottom) {
            if PowerState.shared.lowPower {
                Rectangle().fill(Color(.systemGroupedBackground))
                    .frame(height: bar)
            } else {
                let height = bar + Self.tail
                // Thin, so the cards still show through blurred, as under Mail's
                // bar, and fading out over a longer way rather than ending in a band.
                Rectangle().fill(.thinMaterial)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: statusBar * 0.5 / max(height, 1)),
                                               .init(color: .black.opacity(0.8), location: bar / max(height, 1)),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: height)
            }
            if let title {
                InlineClubTitle(club: title, light: light, stale: stale)
                    .padding(.bottom, PowerState.shared.lowPower ? 0 : Self.tail)
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(scrolled ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: scrolled)
        .animation(.easeInOut(duration: 0.2), value: title?.id)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The club's name with its rowing light, small in the top bar once the big
/// title has scrolled away, as iOS's navigation bars do with theirs.
struct InlineClubTitle: View {
    let club: Club
    let light: Light?
    let stale: Bool
    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            if let light { TrafficLightDot(light: light, size: 12, stale: stale) }
            Text(club.displayName).font(.headline).lineLimit(1)
        }
        .padding(.horizontal, 60)
        .frame(height: Self.height)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
    @Environment(\.colorScheme) private var colorScheme

    /// White over dark glass, black over light, as the system's page dots.
    private var dotColor: Color { colorScheme == .dark ? .white : .black }

    /// The buttons' height, which every piece shares.
    static let buttonHeight: CGFloat = 44
    /// Each page dot's width, to tap; sliding along the dots needs no aim.
    private static let dotWidth: CGFloat = 16
    /// Clubs passed while sliding along the dots, each with a tick.
    @State private var dragSteps = 0
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
            .floatingControl(Capsule())
            .frame(width: Self.sideWidth, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(clubs) { club in
                    let current = club.id == selection
                    // Fixed colours, as Weather's dots: Liquid Glass draws the label
                    // colours vibrant, which evened out a fainter shade of them, so the
                    // current page did not light up.
                    Group {
                        if club.id == homeID {
                            Image(systemName: current ? "house.fill" : "house").font(.caption2)
                        } else {
                            Circle().frame(width: current ? 8 : 6, height: current ? 8 : 6)
                        }
                    }
                    .foregroundStyle(dotColor.opacity(current ? 1 : 0.4))
                    .accessibilityAddTraits(current ? .isSelected : [])
                    // Wider than the dot and as tall as the bar, so it is easier to hit.
                    .frame(width: Self.dotWidth, height: Self.buttonHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { selection = club.id } }
                    .accessibilityLabel(club.displayName)
                }
            }
            .padding(.horizontal, 8)
            // A finger sliding along the dots moves through the clubs, as in Weather.
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 6).onChanged { drag in
                guard !clubs.isEmpty else { return }
                let index = min(max(Int((drag.location.x - 8) / Self.dotWidth), 0), clubs.count - 1)
                if clubs[index].id != selection {
                    selection = clubs[index].id
                    dragSteps += 1
                }
            })
            .sensoryFeedback(.selection, trigger: dragSteps)
            .floatingControl(Capsule())
            Spacer(minLength: 8)
            Group {
                if let showList {
                    Button(action: showList) {
                        Image(systemName: "list.bullet")
                            .font(.title3)
                            .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                    }
                    .floatingControl(Circle())
                    .accessibilityLabel(tr("All locations"))
                }
            }
            .frame(width: Self.sideWidth, alignment: .trailing)
        }
        .tint(.primary)
        .foregroundStyle(.primary)
        .padding(.horizontal)
        .padding(.bottom, 4)
        // The bar keeps its size at larger text sizes, as the system's bars do
        // (its pieces are 44 pt high); a long press shows a piece enlarged.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityShowsLargeContentViewer()
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

