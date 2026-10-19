import SwiftUI

/// Like the iOS Weather app: one full-screen page per saved location, swiped
/// left and right, with the home base first, and a list of all locations
/// behind the button at the bottom, or beside the pages on a wide screen.
struct RootView: View {
    let api: APIClient
    @State private var locations = LocationStore.forLaunch()
    @State private var forecasts: ForecastStore
    @State private var selection = ""
    @State private var showingList = false
    @State private var initialSearch = ""
    @State private var showingTour = !Tutorial.seen

    init(api: APIClient) {
        self.api = api
        _forecasts = State(initialValue: ForecastStore(api: api))
    }

    var body: some View {
        let saved = locations.saved
        Group {
            if saved.isEmpty {
                if let error = locations.catalogError {
                    ContentUnavailableView {
                        Label(tr("No connection"), systemImage: "wifi.slash")
                    } description: {
                        Text(error)
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
        .task { await loadCatalog() }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PageBar(clubs: saved, homeID: locations.homeID, selection: $selection, showList: showsListButton ? { showingList = true } : nil)
        }
    }

    private func loadCatalog() async {
        do {
            locations.setCatalog(try await api.lakes())
            locations.catalogError = nil
            applyLaunchArguments()
        } catch {
            locations.catalogError = tr("Could not load the rowing locations.")
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
    /// `-RWLandscape YES` turns the phone on its side.
    private func applyLaunchArguments() {
        let args = UserDefaults.standard
        if args.bool(forKey: "RWLandscape") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        if let id = args.string(forKey: "RWOpenClub"), let club = locations.catalog.first(where: { $0.id == id }) {
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
