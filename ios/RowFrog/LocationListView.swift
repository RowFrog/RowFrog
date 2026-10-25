import SwiftUI

/// All saved locations with overview data, like the Weather app's list.
/// The search finds more clubs the backend can serve and adds them.
struct LocationListView: View {
    let locations: LocationStore
    let forecasts: ForecastStore
    /// The page on screen when the list sits beside the pages; nil when it is a full-screen cover.
    var selectedID: String?
    /// The club page the full-screen list goes back to.
    var returnTo: Club?
    let select: (Club) -> Void
    @State private var search: String
    @State private var showingSettings = false
    /// The country chip picked above the results; nil searches every country.
    @State private var countryFilter: String?
    @State private var addingPlace = false
    /// Screenshot hook `-RWBrowse YES` (the country list) or `-RWBrowse <code>` (one country).
    @State private var browseHook: String?
    @Environment(\.dismiss) private var dismiss

    init(locations: LocationStore, forecasts: ForecastStore, initialSearch: String = "", selectedID: String? = nil,
         returnTo: Club? = nil, select: @escaping (Club) -> Void) {
        self.locations = locations
        self.forecasts = forecasts
        self.selectedID = selectedID
        self.returnTo = returnTo
        self.select = select
        _search = State(initialValue: initialSearch)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                if search.isEmpty {
                    ForEach(locations.saved) { club in
                        Button { select(club) } label: {
                            LocationSummaryRow(
                                club: club,
                                lake: locations.lake(of: club),
                                isHome: club.id == locations.homeID,
                                forecast: forecasts.forecasts[club.id]
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(club.id == selectedID ? Color.accentColor.opacity(0.18) : Color.clear)
                                .padding(.horizontal, 10)
                        )
                        .swipeActions(edge: .trailing) {
                            if club.id != locations.homeID {
                                Button(role: .destructive) { locations.remove(club) } label: {
                                    Label(tr("Remove"), systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if club.id != locations.homeID {
                                Button { locations.makeHome(club) } label: {
                                    Label(tr("Home base"), systemImage: "house.fill")
                                }
                                .tint(.blue)
                            }
                        }
                        .task { await forecasts.load(club.id) }
                        .moveDisabled(club.id == locations.homeID)
                        .deleteDisabled(club.id == locations.homeID)
                    }
                    // Touch and hold a row to drag it, or use Edit, as in the Weather app.
                    .onMove { locations.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        let saved = locations.saved
                        offsets.map { saved[$0] }.forEach(locations.remove)
                    }
                    if let updated = locations.saved.compactMap({ forecasts.forecasts[$0.id]?.generatedAt }).min() {
                        Text(tr("Updated %@ · Pull down to refresh", Format.time(updated)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        if locations.countries.count > 1 {
                            NavigationLink {
                                CountryListView(locations: locations)
                            } label: {
                                Label(tr("Browse clubs by country"), systemImage: "globe.europe.africa")
                            }
                        }
                        Button { addingPlace = true } label: {
                            Label(tr("Add a place yourself"), systemImage: "mappin.and.ellipse")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    if locations.countries.count > 1 {
                        CountryChips(countries: locations.countries, selection: $countryFilter)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    let results = locations.search(search, country: countryFilter, near: KnownLocation.coordinate)
                    let showsFlags = locations.loadedCountries.count > 1 && countryFilter == nil
                    if results.isEmpty {
                        if locations.loadingCountries.isEmpty {
                            ContentUnavailableView.search(text: search)
                                .listRowBackground(Color.clear)
                        } else {
                            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                        }
                    }
                    ForEach(results) { club in
                        SearchResultRow(club: club, lake: locations.lake(of: club), saved: locations.isSaved(club),
                                        flag: showsFlags ? Country.flag(club.countryCode) : nil) {
                            locations.add(club)
                            search = ""
                        }
                    }
                    Button { addingPlace = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(tr("Not in the list? Add a place"), systemImage: "mappin.and.ellipse")
                            Text(tr("Put your club, boathouse or spot on the map yourself."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .pageBackground(.list)
            .navigationTitle(tr("Locations"))
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(tr("Search clubs, lakes or towns")))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(tr("Settings"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    if search.isEmpty { EditButton() }
                }
                if selectedID == nil {
                    // Back to the club page it came from, named, rather than a "Done" that sounds like a finished task.
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            if let returnTo {
                                HStack(spacing: 4) {
                                    Text(returnTo.displayName).lineLimit(1)
                                    Image(systemName: "chevron.forward")
                                }
                            } else {
                                Image(systemName: "xmark")
                            }
                        }
                        .accessibilityLabel(returnTo.map { tr("Back to %@", $0.displayName) } ?? tr("Close"))
                    }
                }
            }
            // Searching all countries, or one, loads the clubs not loaded yet.
            .task(id: "\(search.isEmpty)|\(countryFilter ?? "all")") {
                guard !search.isEmpty else { return }
                await locations.ensureLoaded(countryFilter.map { [$0] } ?? locations.unloadedCountries)
            }
            .navigationDestination(item: $browseHook) { code in
                if let country = locations.country(code) {
                    CountryWatersView(locations: locations, country: country)
                } else {
                    CountryListView(locations: locations)
                }
            }
            .task {
                // Screenshot hooks: `-RWAddPlace YES` opens "Add a place", `-RWBrowse` browses.
                let args = UserDefaults.standard
                guard args.bool(forKey: "RWAddPlace") || args.string(forKey: "RWBrowse") != nil else { return }
                try? await Task.sleep(for: .seconds(1))
                if args.bool(forKey: "RWAddPlace") { addingPlace = true }
                browseHook = args.string(forKey: "RWBrowse")
            }
            .sheet(isPresented: $addingPlace) {
                AddPlaceView(locations: locations, name: search) { place in
                    search = ""
                    select(place.club)
                }
                .environment(\.locale, AppSettings.shared.locale)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(locations: locations)
                    .environment(\.locale, AppSettings.shared.locale)
            }
            // Pull down to reload every saved location at once, as in Mail.
            .refreshable { await forecasts.reload(locations.saved.map(\.id)) }
            .task {
                // Screenshot hook: `-RWShowSettings YES` opens the settings once the list is up.
                guard UserDefaults.standard.bool(forKey: "RWShowSettings") else { return }
                try? await Task.sleep(for: .seconds(1))
                showingSettings = true
            }
            .task {
                // Screenshot hook: `-RWScrollPage n` (n > 0) scrolls to the end of the list.
                guard UserDefaults.standard.integer(forKey: "RWScrollPage") > 0, let last = locations.saved.last else { return }
                try? await Task.sleep(for: .seconds(3))
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            }
        }
    }
}

/// A Weather-style card: name, lake and town, the rowing light and the key numbers now.
private struct LocationSummaryRow: View {
    let club: Club
    let lake: Lake?
    let isHome: Bool
    let forecast: ClubForecast?

    var body: some View {
        let now = forecast?.current()
        let stale = forecast?.isStale() ?? false
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isHome {
                            Image(systemName: "house.fill").font(.footnote)
                        }
                        Text(club.displayName).font(.title3.bold()).lineLimit(1)
                    }
                    Text([lake?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let now {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 6) {
                            TrafficLightDot(light: now.light, size: 18, stale: stale)
                            SkyIcon(sky: Sky(hour: now), night: now.sunUp == false)
                                .font(.title3)
                            Image(systemName: Condition.temperature.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .accessibilityLabel(tr("Air"))
                            Text(Format.degrees(now.temperatureC)).font(.system(size: 36, weight: .light))
                        }
                        // Right under the temperature, as on the club page and the widgets.
                        if let feels = now.apparentTemperatureC {
                            Label(tr("Feels like %@", Format.degrees(feels)), systemImage: Condition.feelsLike.symbol)
                                .font(.caption)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if let now {
                        Text(now.light.title(stale: stale)).font(.subheadline.weight(.semibold))
                        if let forecast, stale {
                            Label(tr("As of %@", Format.dayTime(forecast.generatedAt)), systemImage: "clock.badge.exclamationmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Text(now.reasons.isEmpty ? tr("All conditions within the limits") : tr("Why: %@", now.reasons.map(\.label).joined(separator: ", ")))
                            .font(.caption)
                            .lineLimit(2)
                    }
                    if let warning = forecast?.warnings?.items.first {
                        Label(warning.shortLabel, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(warning.severity == "minor" ? Color.orange : warning.color)
                            .lineLimit(1)
                    }
                    if let forecast, let sun = forecast.sunState(at: .now) {
                        Group {
                            switch sun {
                            case let .up(_, sunset): Label(tr("Sunset %@", Format.time(sunset)), systemImage: "sunset.fill")
                            case let .down(sunrise, _): Label(tr("Sunrise %@", Format.time(sunrise)), systemImage: "sunrise.fill")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(SunLabelStyle())
                    }
                }
                Spacer(minLength: 8)
                if let now {
                    // Numbers first, e.g. "12–17 m/s" in full; the text on the left wraps instead.
                    ListMetrics(hour: now, water: forecast?.waterTemperature, ice: forecast?.ice)
                        .layoutPriority(1)
                }
            }
        }
        .padding(14)
        .background { TintedCardBackground(tint: now?.light.color(stale: stale) ?? .gray, cornerRadius: 16) }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The row's numbers in two columns: water, wind and waves on the left;
/// visibility, rain and ice on the right.
struct ListMetrics: View {
    let hour: ForecastHour
    let water: WaterTemperature?
    var ice: IceEstimate? = nil
    var visibilitySymbol = Condition.visibility.symbol

    var body: some View {
        let rain = precipitationText(hour)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Label(Format.degrees(water?.celsius, digits: 1), systemImage: Condition.waterTemperature.symbol)
                    .accessibilityLabel(tr("Water: %@", water.map { Format.temperature($0.celsius, digits: 1) } ?? tr("no data")))
                Label(Format.distance(hour.visibilityM), systemImage: visibilitySymbol)
                    .accessibilityLabel(tr("Visibility: %@", Format.distance(hour.visibilityM)))
            }
            GridRow {
                Label(Format.windRange(hour.windSpeedMs, hour.windGustMs), systemImage: Condition.wind.symbol)
                Label(rain ?? tr("Dry"), systemImage: Condition.precipitation.symbol)
                    .accessibilityLabel(tr("Rain, hail, snow: %@", rain ?? tr("None")))
            }
            GridRow {
                Label(Format.waves(hour.waveHeightM), systemImage: Condition.waves.symbol)
                if let ice, ice.status != "unavailable" {
                    Label(ice.title, systemImage: Condition.ice.symbol)
                        .accessibilityLabel(tr("Ice: %@", ice.title))
                } else {
                    Label("–", systemImage: Condition.ice.symbol)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(tr("Ice: no data yet"))
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

struct SearchResultRow: View {
    let club: Club
    let lake: Lake?
    let saved: Bool
    /// The country's flag, when the results mix countries.
    var flag: String? = nil
    let add: () -> Void

    var body: some View {
        HStack {
            if let flag {
                Text(flag).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(club.name)
                Text([lake?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !club.launchPointVerified {
                    Text(tr("Launch point not yet confirmed")).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            if saved {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityLabel(tr("In your list"))
            } else {
                Button(action: add) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(tr("Add %@", club.displayName))
            }
        }
    }
}
