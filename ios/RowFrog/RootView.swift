import SwiftUI
import TipKit

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
    /// Where the club pages' picture lies, for their frosted cards.
    @State private var pagesPictureFrame = CGRect.zero
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
    /// The list beside the page slid away with the sidebar button, as in Weather;
    /// screenshot hook `-RWSideListHidden YES` starts with it away.
    @State private var sideListHidden = UserDefaults.standard.bool(forKey: DefaultsKey.sideListHidden)
    /// An iPad held upright: the list slid in over the page from the sidebar button.
    @State private var showingSideOverlay = false
    /// The lake view or radar a Home Screen menu item opens (QuickActions).
    @State private var quickOpen: QuickOpen?
    /// A rowfrog:// link that came before the clubs were loaded; opened once they are.
    @State private var pendingLink: URL?
    @State private var linksReady = false

    init(api: APIClient) {
        self.api = api
        let store = LocationStore.forLaunch()
        store.countryLoader = { try await api.lakes(country: $0) }
        _locations = State(initialValue: store)
        // Own places get their forecast on the phone; the store knows where they are.
        let forecasts = ForecastStore(api: api) { [weak store] id in store?.ownPlace(id) }
        _forecasts = State(initialValue: forecasts)
        // What the last visit showed, read before the first frame (decision 0046).
        ColdStart.prime(locations: store, forecasts: forecasts, api: api)
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
                    // A wide and tall screen (an iPad on its side) keeps the list on the
                    // left until the sidebar button slides it away; an iPad upright slides
                    // it in over the page; phones show it behind the list button.
                    let wide = geometry.size.width >= Self.sideListMinWidth && geometry.size.height >= Self.sideListMinHeight
                    let chrome: PageChrome = wide ? .wide(listShown: !sideListHidden) : Orientation.isPad ? .pad : .phone
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            if wide && !sideListHidden {
                                // Over the same picture as the page, so only the list moves when it slides away.
                                sideList(sharedPicture: true) { withAnimation(Self.slide) { sideListHidden = true } }
                                    .transition(.move(edge: .leading))
                            }
                            pages(saved, chrome: chrome, insets: geometry.safeAreaInsets)
                                // The column count is worked out as if the list were shown (rule B).
                                .environment(\.widthBesideList, wide ? geometry.size.width - Self.sideListWidth : nil)
                        }
                        .background { clubPicture }
                        .environment(\.pictureFrame, pagesPictureFrame)
                        if chrome == .pad && showingSideOverlay {
                            Color.black.opacity(0.15)
                                .ignoresSafeArea()
                                .onTapGesture { withAnimation(Self.slide) { showingSideOverlay = false } }
                                .accessibilityHidden(true)
                                .transition(.opacity)
                            sideList { withAnimation(Self.slide) { showingSideOverlay = false } }
                                .background(Color(.systemGroupedBackground))
                                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 24, topTrailingRadius: 24))
                                .shadow(radius: 12)
                                .ignoresSafeArea(edges: .bottom)
                                .transition(.move(edge: .leading))
                        }
                    }
                    .onChange(of: wide) { showingSideOverlay = false }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        // No accessibilityHidden(showingSafety) here: hidden(false) on the whole
        // page undid the hiding of the picture and the top bar fade inside it, so
        // VoiceOver read them as unnamed elements. The notice is modal instead.
        .overlay {
            // The safety notice comes first, before the tour and before any
            // question; it stays until it is accepted.
            if showingSafety {
                SafetyNoticeView {
                    withAnimation { showingSafety = false }
                }
                // VoiceOver stays on the notice, as the page behind used to be hidden.
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
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
        .environment(\.clubName, { locations.name(of: $0) })
        // Boats from before clubs were kept go to the home base, once there is one.
        .task(id: locations.homeID) { AppSettings.shared.keepUnplacedBoats(at: locations.homeID) }
        // Once after an update, when the safety notice was accepted and there are clubs to show.
        .sheet(isPresented: Binding(
            get: { showingWhatsNew && !showingSafety && !showingTour && !locations.saved.isEmpty },
            set: { if !$0 { showingWhatsNew = false; WhatsNew.markSeen() } }
        )) {
            WhatsNewView().environment(\.locale, AppSettings.shared.locale)
        }
        .fullScreenCover(isPresented: $showingList) {
            LocationListView(locations: locations, forecasts: forecasts, initialSearch: initialSearch) { club in
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
        // The developer options switch the app's own Light/Dark, rotation and language on and off.
        .onChange(of: AppSettings.shared.developerOptions) {
            applyAppearance()
            Orientation.apply()
            WidgetBridge.publish(locations)
        }
        .task { await loadCatalog() }
        // The widget picks up the home base, clubs and settings when the user leaves the app.
        // Only on leaving, not on every pull-down of Control Center or the app switcher.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                WidgetBridge.publish(locations)
                QuickActions.publish(locations)
                wasInBackground = true
            } else if phase == .active, wasInBackground {
                wasInBackground = false
                // A new day may wake the tips after the tour's quiet day (TipPacing).
                TipPacing.update()
                Task { await refreshOnReturn() }
            }
        }
        .modifier(DiagnosisSteps(page: selection, list: showingList, settings: showingSettings))
        // A new language or units show on the widget straight away.
        .onChange(of: AppSettings.shared.language) { WidgetBridge.publish(locations) }
        .onChange(of: AppSettings.shared.temperatureUnit) { WidgetBridge.publish(locations) }
        .onChange(of: AppSettings.shared.windUnit) { WidgetBridge.publish(locations) }
        // A tap on the widget opens its club.
        .onOpenURL { open($0) }
        // The Home Screen menu (QuickActions): a tap on a cold start waits in the inbox.
        .onAppear { if let url = QuickActionInbox.shared.take() { open(url) } }
        .onChange(of: QuickActionInbox.shared.pending) { if let url = QuickActionInbox.shared.take() { open(url) } }
        .onChange(of: selection) { QuickActions.noteShown(selection, in: locations) }
        .fullScreenCover(item: $quickOpen) { item in
            Group {
                switch item {
                case .lake(let lakeID, let clubID):
                    QuickLakeScreen(lakeID: lakeID, clubID: clubID)
                case .radar(let club):
                    RadarMapScreen(point: club.launchPoint, clubID: club.id,
                                   reference: RadarStore.shared.radar(at: club.launchPoint)?.reference, step: RadarWindow.step)
                        .diagnosisNamed("radar map")
                }
            }
            .environment(\.locale, AppSettings.shared.locale)
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

    /// A rowfrog:// link from the widget (club/<id>) or the Home Screen menu (also
    /// lake/<id>, radar/<id> and add), or a GPX, TCX or FIT file shared from another app.
    private func open(_ url: URL) {
        if url.isFileURL { return openRowFile(url) }
        guard url.scheme == "rowfrog" else { return }
        // On a cold start the clubs load first; loadCatalog would show the home base over the link.
        guard linksReady else { pendingLink = url; return }
        if showingSafety || showingTour { return }
        if url.host() == "add" {
            showingSettings = false
            showingList = true
            return
        }
        guard let id = url.pathComponents.last, let club = locations.saved.first(where: { $0.id == id }) else { return }
        showingList = false
        showingSettings = false
        selection = id
        switch url.host() {
        case "lake":
            if let lake = locations.lake(of: club), lake.hasOutline != false { quickOpen = .lake(lakeID: lake.id, clubID: id) }
        case "radar":
            quickOpen = .radar(club)
        default:
            quickOpen = nil
        }
    }

    /// The clubs are loaded (or could not load): a link that waited opens now.
    private func openPendingLink() {
        linksReady = true
        if let url = pendingLink {
            pendingLink = nil
            open(url)
        }
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

    /// The list on the left of the page (iPad), with the sidebar button that slides it away.
    private func sideList(sharedPicture: Bool = false, close: @escaping () -> Void) -> some View {
        LocationListView(locations: locations, forecasts: forecasts, selectedID: selection, hideList: close,
                         sharedPicture: sharedPicture) { club in
            PageJump.go(to: club.id, from: selection, in: locations.saved.map(\.id)) { selection = $0 }
            if showingSideOverlay { withAnimation(Self.slide) { showingSideOverlay = false } }
        }
        .environment(\.openBoatSettings, openBoatSettings)
        .frame(width: Self.sideListWidth)
    }

    /// The shown club's picture over the whole screen, behind the pages (and the
    /// list beside them on a wide iPad), not on each page: a swiping TabView keeps
    /// its pages out of the status bar and the page bar, which left black bars.
    private var clubPicture: some View {
        let settings = AppSettings.shared
        return ZStack {
            PagePicture(image: BackgroundPictures.shared.image(for: settings.background(for: .clubPages, clubID: selection), clubID: selection),
                        blurred: settings.blurBackground) { pagesPictureFrame = $0 }
                .id(selection)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: selection)
    }

    /// How the list slides in and out; the cog moves over with it.
    static let slide = Animation.easeInOut(duration: 0.3)

    /// As wide as an iPhone's list, so a row's numbers and text fit side by side (iPad).
    static let sideListWidth: CGFloat = 400
    static let sideListMinWidth: CGFloat = 860
    static let sideListMinHeight: CGFloat = 560

    private func pages(_ saved: [Club], chrome: PageChrome, insets: EdgeInsets) -> some View {
        // Each page keeps clear of the clock and the floating buttons with its own
        // margins, while the cards scroll on under both (Apple's guide).
        // On an iPad the page's buttons sit in a line at the top, level with the list's;
        // the page starts below that line, so the club's header card never slides under
        // them, however long the name (owner's shot, 12 Nov 2026).
        let topButtons = chrome != .phone
        let barBottom = insets.top + InlineClubTitle.barHeight(statusBar: insets.top, topButtons: topButtons)
        let top = topButtons ? barBottom + PageTopButtons.gapBelow : insets.top
        let margins = EdgeInsets(top: top, leading: 0, bottom: insets.bottom + PageBar.height, trailing: 0)
        return TabView(selection: $selection) {
            ForEach(saved) { club in
                LocationPageView(club: club, lake: locations.lake(of: club), isHome: club.id == locations.homeID, forecasts: forecasts,
                                 savedIDs: saved.map(\.id))
                    .pageBackground(.clubPages, clubID: club.id, drawsPicture: false)
                    .environment(\.isCurrentPage, club.id == selection)
                    .environment(\.openBoatSettings, openBoatSettings)
                    .environment(\.pageMargins, margins)
                    .environment(\.pageBarBottom, barBottom)
                    .tag(club.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: [.top, .bottom])
        .overlay(alignment: .top) {
            let scroll = PageScroll.shared
            let club = saved.first { $0.id == selection }
            let forecast = forecasts.forecasts[selection]
            TopEdgeFade(statusBar: insets.top, scrolled: scroll.scrolled.contains(selection),
                        title: scroll.titleGone.contains(selection) ? club : nil,
                        light: forecast?.current()?.light, stale: forecast?.isStale() ?? false,
                        sideRoom: PageTopButtons.sideRoom(chrome))
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .top) {
            let forecast = forecasts.forecasts[selection]
            PageTopButtons(clubID: selection, chrome: chrome, statusBar: insets.top,
                           now: forecast?.current(), waterC: forecast?.waterTemperature?.celsius,
                           showList: {
                               withAnimation(Self.slide) {
                                   if chrome == .pad { showingSideOverlay = true } else { sideListHidden = false }
                               }
                           },
                           showSettings: { showingSettings = true })
                .environment(\.openBoatSettings, openBoatSettings)
        }
        .overlay(alignment: .bottom) {
            let forecast = forecasts.forecasts[selection]
            PageBar(clubs: saved, homeID: locations.homeID ?? "", selection: $selection,
                    showList: chrome == .phone ? { showingList = true } : nil,
                    showSettings: chrome == .phone ? { showingSettings = true } : nil,
                    // With the list beside the page, the list already switches clubs and marks the one shown.
                    showsDots: chrome != .wide(listShown: true),
                    now: forecast?.current(), waterC: forecast?.waterTemperature?.celsius)
                .environment(\.openBoatSettings, openBoatSettings)
        }
        .onAppear { if selection.isEmpty { selection = saved[0].id } }
        .onChange(of: chrome, initial: true) {
            PageScroll.shared.update(topButtons: chrome != .phone)
        }
    }

    /// The countries of the saved clubs, the phone's and any near the user;
    /// an older backend without country files sends every club at once.
    private func loadCatalog() async {
        do {
            if let countries = try? await api.countries(), !countries.isEmpty {
                locations.setCountries(countries)
                // Screenshot hook `-RWOpenClub` may name a club abroad: then every country loads.
                let all = UserDefaults.standard.string(forKey: DefaultsKey.openClub) != nil
                // Countries a cold start showed from the kept files come again, as the others.
                let primed = locations.takePrimedCountries()
                for code in all ? countries.map(\.code) : primed + locations.countriesToLoad(near: KnownLocation.coordinate) {
                    locations.addCountry(code, lakes: try await api.lakes(country: code))
                }
            } else {
                locations.setCatalog(try await api.lakes())
            }
            locations.catalogFailed = false
            applyLaunchArguments()
            WidgetBridge.publish(locations)
            openPendingLink()
        } catch {
            locations.catalogFailed = true
            openPendingLink()
        }
    }

    /// Light, dark or the phone's setting, for every window and sheet.
    private func applyAppearance() {
        let style: UIUserInterfaceStyle = switch AppSettings.shared.activeAppearance {
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
        if args.bool(forKey: DefaultsKey.landscape) {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        // `-RWOwnPlace "Name;lat;lon"` adds that own place (once) and opens it.
        if let spec = args.string(forKey: DefaultsKey.ownPlace)?.split(separator: ";"), spec.count == 3,
           let lat = Double(spec[1]), let lon = Double(spec[2]) {
            let point = Coordinate(lat: lat, lon: lon)
            let place = locations.ownPlaces.first { $0.name == String(spec[0]) } ?? OwnPlace(
                name: String(spec[0]), kind: .boathouse, website: nil, coordinate: point,
                waterName: locations.nearestLake(to: point)?.name, shared: false)
            if locations.ownPlace(place.id) == nil { locations.addOwnPlace(place) }
            selection = place.id
        } else if let id = args.string(forKey: DefaultsKey.openClub), let club = locations.catalog.first(where: { $0.id == id }) {
            locations.add(club)
            selection = id
        } else {
            selection = locations.homeID ?? ""
        }
        if let search = args.string(forKey: DefaultsKey.search) {
            initialSearch = search
            showingList = true
        } else if args.bool(forKey: DefaultsKey.showList) || args.bool(forKey: DefaultsKey.showSettings) {
            showingList = true
        }
    }
}

/// Behind the clock and the signal icons, and the small club name once the big one
/// has scrolled away. No bar is drawn (owner's pick D, 19 Nov 2026, with or without a
/// background picture): the page's scroll view blurs the cards itself (PageTopEdge),
/// and the name sits in a glass capsule, as in Apple's own apps. Low Power Mode, which
/// draws nothing live, keeps a plain strip. At the bottom only the floating buttons sit
/// over the cards (owner, 30 Oct 2026).
private struct TopEdgeFade: View {
    let statusBar: CGFloat
    /// Whether cards are under the clock; at the top of a page nothing is drawn.
    let scrolled: Bool
    /// The club whose name the bar shows once its big title has scrolled away.
    let title: Club?
    let light: Light?
    let stale: Bool
    /// Kept free on each side of the small title for the buttons beside it.
    let sideRoom: CGFloat

    var body: some View {
        let bar = statusBar + (title == nil ? 0 : InlineClubTitle.barHeight(statusBar: statusBar))
        let lowPower = PowerState.shared.lowPower
        ZStack(alignment: .bottom) {
            if lowPower {
                Rectangle().fill(Color(.systemGroupedBackground))
                    .frame(height: bar)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(height: bar)
            }
            if let title {
                InlineClubTitle(club: title, light: light, stale: stale, sideRoom: sideRoom, capsule: !lowPower)
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
    var sideRoom: CGFloat = 60
    /// The name in its own glass capsule, with no bar behind it (owner's pick D,
    /// 19 Nov 2026, as in Apple's own apps); not in Low Power Mode.
    var capsule = false
    static let height: CGFloat = 44

    /// How far the top bar with the small name reaches below the clock. On an iPad the
    /// name sits on the line of the top buttons (PageTopButtons), a little lower; on a
    /// phone the bar is just the name's height.
    @MainActor static func barHeight(statusBar: CGFloat, topButtons: Bool? = nil) -> CGFloat {
        guard topButtons ?? PageScroll.shared.topButtons else { return height }
        let mid = PageTopButtons.midY(statusBar: statusBar, listButtonsMidY: PageScroll.shared.listButtonsMidY)
        return max(height, mid - statusBar + height / 2)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let light { TrafficLightDot(light: light, size: 12, stale: stale) }
            Text(club.displayName).font(.headline).lineLimit(1)
        }
        .padding(.horizontal, capsule ? 16 : 0)
        .frame(minHeight: capsule ? 36 : nil)
        .modifier(CapsuleGlass(on: capsule))
        .padding(.horizontal, sideRoom + 16)
        .frame(height: Self.height)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The small club name's glass capsule over a background picture (InlineClubTitle).
private struct CapsuleGlass: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.glass(in: Capsule()) } else { content }
    }
}

/// Where the page's buttons go on this screen (owner's pick, 2 Nov 2026, after Apple's guide).
enum PageChrome: Equatable {
    /// Cog and boat, page dots and list button in the bar at the bottom, as in Weather.
    case phone
    /// An iPad upright: sidebar button and cog at the top left, the boat at the top right, the list slides in over the page.
    case pad
    /// The list beside the page (an iPad on its side); slid away, its sidebar button comes onto the page.
    case wide(listShown: Bool)
}

/// The page's top buttons (iPad): on the left the sidebar button (while the list
/// is not on screen) and the cog, on the right the boat, as Apple's guide splits
/// a bar's leading and trailing items (owner's pick, 4 Nov 2026).
/// They stay on one line level with the list's own top buttons, at the top of the
/// page and while it scrolls, with the list beside the page, slid away or upright,
/// and the small name in the top bar sits on the same line; the page starts below
/// that line (owner, 12 Nov 2026: they sat beside the big name, lower than the
/// list's, and over the header card's corners with a long name).
/// When the list slides away, the sidebar button comes in and the cog moves over.
/// The phone has none: its cog and boat sit in the bar at the bottom.
struct PageTopButtons: View {
    let clubID: String
    let chrome: PageChrome
    let statusBar: CGFloat
    let now: ForecastHour?
    let waterC: Double?
    let showList: () -> Void
    let showSettings: () -> Void

    private var showsSidebarButton: Bool { chrome == .pad || chrome == .wide(listShown: false) }

    /// What the small title in the top bar keeps free on each side for these buttons.
    static func sideRoom(_ chrome: PageChrome) -> CGFloat {
        switch chrome {
        case .phone: 0
        case .pad, .wide(listShown: false): 104
        case .wide(listShown: true): 56
        }
    }

    var body: some View {
        if chrome != .phone { buttons }
    }

    /// The list header's gap above its button row (SideListHeader's top padding).
    static let listHeaderTop: CGFloat = 4
    /// Between the button line and the top of the page's first card: as the list's
    /// search field sits below its buttons, so both tops are level.
    static let gapBelow: CGFloat = 10

    /// The middle of the top button line on screen: the list's buttons where measured,
    /// else where the list puts them (its row of 44 pt buttons under its top gap).
    static func midY(statusBar: CGFloat, listButtonsMidY: CGFloat?) -> CGFloat {
        listButtonsMidY ?? statusBar + listHeaderTop + 22
    }

    private var buttons: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).minY
            let y = Self.midY(statusBar: statusBar, listButtonsMidY: PageScroll.shared.listButtonsMidY) - origin
            HStack(spacing: 8) {
                if showsSidebarButton {
                    Button(action: showList) {
                        Image(systemName: "sidebar.left")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .floatingControl(Circle())
                    .accessibilityLabel(tr("Show the club list"))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Button(action: showSettings) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .floatingControl(Circle())
                .accessibilityLabel(tr("Settings"))
                Spacer(minLength: 0)
                PageBoatButton(clubID: clubID, now: now, waterC: waterC, tipEdge: .top)
                    .padding(.horizontal, 4)
                    .floatingControl(Capsule())
            }
            .tint(.primary)
            .foregroundStyle(.primary)
            .padding(.horizontal)
            // Over the page's column of cards, not at the window's edges (owner, 12 Nov 2026).
            .frame(maxWidth: PageScroll.shared.pageWidth[clubID] ?? .infinity)
            .frame(height: 44)
            .position(x: proxy.size.width / 2, y: y)
        }
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityShowsLargeContentViewer()
    }
}

/// The settings cog with the boat beside it, the page dots with a house for the
/// home base and the list button, as the Weather app has its map and list at the
/// two ends (phone; owner's pick, 4 Nov 2026: easy to reach on big phones).
/// On an iPad only the dots, and none while the list beside the page marks the club.
/// Each group floats on its own piece of glass, all as tall as the bar, with
/// the symbols in one colour over the picture (Apple's guide for toolbars).
private struct PageBar: View {
    let clubs: [Club]
    let homeID: String
    @Binding var selection: String
    /// Nil when the list opens from elsewhere (iPad).
    let showList: (() -> Void)?
    /// Nil when the cog sits at the top beside the club's name (iPad).
    let showSettings: (() -> Void)?
    let showsDots: Bool
    /// For the boat button beside the cog.
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
    /// Cog and boat on the left, the list button on the right: each end takes as
    /// much, so the dots stay in the middle.
    private static let sideWidth: CGFloat = 44 + 8 + 56
    /// Only one club saved: the house alone, in a round button.
    private var single: Bool { clubs.count == 1 }

    var body: some View {
        HStack(spacing: 0) {
            if let showSettings {
                HStack(spacing: 8) {
                    Button(action: showSettings) {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                    }
                    .floatingControl(Circle())
                    .accessibilityLabel(tr("Settings"))
                    PageBoatButton(clubID: selection, now: now, waterC: waterC, tipEdge: .bottom)
                        .padding(.horizontal, 4)
                        .floatingControl(Capsule())
                }
                .frame(width: Self.sideWidth, alignment: .leading)
            }
            Spacer(minLength: 8)
            if showsDots {
                HStack(spacing: 0) {
                    ForEach(clubs) { club in
                        let current = club.id == selection
                        // Fixed colours, as Weather's dots: Liquid Glass draws the label
                        // colours vibrant, which evened out a fainter shade of them, so the
                        // current page did not light up.
                        Group {
                            if club.id == homeID {
                                Image(systemName: current ? "house.fill" : "house").font(single ? .body : .caption2)
                            } else {
                                Circle().frame(width: current ? 8 : 6, height: current ? 8 : 6)
                            }
                        }
                        .foregroundStyle(dotColor.opacity(current ? 1 : 0.4))
                        .accessibilityAddTraits(current ? .isSelected : [])
                        // Wider than the dot and as tall as the bar, so it is easier to hit.
                        .frame(width: single ? Self.buttonHeight : Self.dotWidth, height: Self.buttonHeight)
                        .contentShape(Rectangle())
                        // As Weather's page dots: a tap moves one club towards it, with the slide;
                        // a finger running along the dots jumps (owner, 12 Nov 2026).
                        .onTapGesture {
                            let ids = clubs.map(\.id)
                            guard let next = PageJump.step(towards: club.id, from: selection, in: ids) else { return }
                            PageJump.go(to: next, from: selection, in: ids) { selection = $0 }
                        }
                        .accessibilityLabel(club.displayName)
                    }
                }
                // One club: a round button as big as the others, as Weather with one place (owner, 14 Nov 2026).
                .padding(.horizontal, single ? 0 : 8)
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
            }
            Spacer(minLength: 8)
            if let showList {
                Button(action: showList) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                }
                .floatingControl(Circle())
                .accessibilityLabel(tr("All locations"))
                .frame(width: Self.sideWidth, alignment: .trailing)
            }
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
}

/// The boat the rowing light is for, picked on the spot: beside the cog (phone) or level with the club's name (iPad).
struct PageBoatButton: View {
    let clubID: String
    let now: ForecastHour?
    let waterC: Double?
    /// Where the tip's arrow sits: under the button at the top, over it in the bottom bar.
    let tipEdge: Edge
    @AppStorage(Tutorial.seenKey) private var tourSeen = false

    var body: some View {
        let boat = AppSettings.shared.boat(at: clubID)
        let away = AppSettings.shared.myBoats.contains { !AppSettings.shared.isKept($0, at: clubID) }
        BoatMenu(clubID: clubID, hour: now, waterC: waterC) {
            BoatClassTag(boat: boat)
                .frame(width: 48, height: 44)
        }
        // A menu draws its label in the tint, which the bar sets to the label
        // colour; an own boat keeps the accent colour.
        .tint(boat.isGroup ? Color.primary : Color.accentColor)
        .accessibilityLabel(tr("Boat: %@", boat.title))
        .accessibilityHint(tr("Picks another boat for the rowing light."))
        // Once, on the first club where an own boat is kept elsewhere.
        .modifier(BoatsElsewhereTipAnchor(shown: tourSeen && away, arrowEdge: tipEdge))
    }
}

/// `popoverTip` with an optional tip needs iOS 18.4, so the tip is attached only when it applies.
private struct BoatsElsewhereTipAnchor: ViewModifier {
    let shown: Bool
    let arrowEdge: Edge

    func body(content: Content) -> some View {
        if shown {
            content.popoverTip(BoatsElsewhereTip(), arrowEdge: arrowEdge)
        } else {
            content
        }
    }
}


/// Switching club pages from a dot or the list. A step to the next club slides
/// as a swipe does; a longer jump goes straight there, since sliding past the
/// clubs in between made iOS build and drop each of those pages on the way.
enum PageJump {
    /// The club one step from the current one towards a tapped dot, as a page
    /// control's tap; nil for the current dot.
    static func step(towards id: String, from current: String, in ids: [String]) -> String? {
        guard let a = ids.firstIndex(of: current), let b = ids.firstIndex(of: id), a != b else { return nil }
        return ids[a + (b > a ? 1 : -1)]
    }

    static func go(to id: String, from current: String, in ids: [String], set: (String) -> Void) {
        guard id != current else { return }
        if let a = ids.firstIndex(of: current), let b = ids.firstIndex(of: id), abs(a - b) == 1 {
            withAnimation { set(id) }
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { set(id) }
        }
    }
}
