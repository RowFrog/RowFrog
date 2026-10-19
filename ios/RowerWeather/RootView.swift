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
                        Label("No connection", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await loadCatalog() } }
                    }
                } else {
                    ProgressView()
                }
            } else {
                TabView(selection: $selection) {
                    ForEach(saved) { club in
                        LocationPageView(club: club, lake: locations.lake(of: club), isHome: club.id == locations.homeID, forecasts: forecasts)
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
        .fullScreenCover(isPresented: $showingList) {
            LocationListView(locations: locations, forecasts: forecasts, initialSearch: initialSearch) { club in
                selection = club.id
                showingList = false
            }
        }
        .task { await loadCatalog() }
    }

    private func loadCatalog() async {
        do {
            locations.setCatalog(try await api.lakes())
            locations.catalogError = nil
            applyLaunchArguments()
        } catch {
            locations.catalogError = "Could not load the rowing locations."
        }
    }

    /// Screenshot hooks: `-RWOpenClub <id>` opens that page (adding it from the
    /// catalog if needed), `-RWShowList YES`
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
        } else if args.bool(forKey: "RWShowList") {
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
            .accessibilityLabel("All locations")
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .background(.bar)
    }
}
