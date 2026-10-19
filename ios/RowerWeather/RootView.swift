import SwiftUI

/// Like the iOS Weather app: one full-screen page per saved location, swiped
/// left and right, with the home base first, and a list of all locations
/// behind the button at the bottom.
struct RootView: View {
    let api: APIClient
    @State private var locations = LocationStore()
    @State private var forecasts: ForecastStore
    @State private var selection: String = LocationStore.defaultHomeID
    @State private var showingList = false
    @State private var initialSearch = ""
    @Environment(\.scenePhase) private var scenePhase

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
                } else {
                    ProgressView()
                }
            } else {
                TabView(selection: $selection) {
                    ForEach(saved) { club in
                        LocationPageView(club: club, lake: locations.lake(of: club), isHome: club.id == locations.homeID, forecasts: forecasts)
                            .pageBackground(.clubPages, clubID: club.id)
                            .tag(club.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PageBar(clubs: saved, homeID: locations.homeID, selection: $selection) {
                        showingList = true
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
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
        // The widget picks up the home base, clubs and settings when the user leaves the app.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { WidgetBridge.publish(locations) }
        }
        // A tap on the widget opens its club.
        .onOpenURL { url in
            guard url.scheme == "rowerweather", url.host() == "club", let id = url.pathComponents.last,
                  locations.saved.contains(where: { $0.id == id }) else { return }
            showingList = false
            selection = id
        }
    }

    private func loadCatalog() async {
        do {
            locations.setCatalog(try await api.lakes())
            locations.catalogError = nil
            applyLaunchArguments()
            WidgetBridge.publish(locations)
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
    /// opens the list and `-RWSearch <text>` opens it searching for the text.
    private func applyLaunchArguments() {
        let args = UserDefaults.standard
        if let id = args.string(forKey: "RWOpenClub"), let club = locations.catalog.first(where: { $0.id == id }) {
            locations.add(club)
            selection = id
        } else {
            selection = locations.homeID
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
    let showList: () -> Void

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
            Button(action: showList) {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(tr("All locations"))
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .background(.bar)
    }
}
