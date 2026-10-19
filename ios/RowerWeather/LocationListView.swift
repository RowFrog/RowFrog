import SwiftUI

/// All saved locations with overview data, like the Weather app's list.
/// The search finds more clubs the backend can serve and adds them.
struct LocationListView: View {
    let locations: LocationStore
    let forecasts: ForecastStore
    let select: (Club) -> Void
    @State private var search: String
    @Environment(\.dismiss) private var dismiss

    init(locations: LocationStore, forecasts: ForecastStore, initialSearch: String = "", select: @escaping (Club) -> Void) {
        self.locations = locations
        self.forecasts = forecasts
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
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            if club.id != locations.homeID {
                                Button(role: .destructive) { locations.remove(club) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if club.id != locations.homeID {
                                Button { locations.makeHome(club) } label: {
                                    Label("Home base", systemImage: "house.fill")
                                }
                                .tint(.blue)
                            }
                        }
                        .task { await forecasts.load(club.id) }
                    }
                    if let updated = locations.saved.compactMap({ forecasts.forecasts[$0.id]?.generatedAt }).min() {
                        Text("Updated \(Format.time(updated)) · Pull down to refresh")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    let results = locations.search(search)
                    if results.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(results) { club in
                        SearchResultRow(club: club, lake: locations.lake(of: club), saved: locations.isSaved(club)) {
                            locations.add(club)
                            search = ""
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .scrollContentBackground(.hidden)
            .navigationTitle("Locations")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search clubs, lakes or towns")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Pull down to reload every saved location at once, as in Mail.
            .refreshable { await forecasts.reload(locations.saved.map(\.id)) }
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
                    HStack(spacing: 6) {
                        TrafficLightDot(light: now.light, size: 18)
                        SkyIcon(sky: Sky(hour: now), night: now.sunUp == false)
                            .font(.title3)
                        Image(systemName: Condition.temperature.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityLabel("Air")
                        Text("\(Format.number(now.temperatureC))°").font(.system(size: 36, weight: .light))
                    }
                } else {
                    ProgressView()
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if let now {
                        Text(now.light.title).font(.subheadline.weight(.semibold))
                        Text(now.reasons.isEmpty ? "All conditions within the limits" : "Why: " + now.reasons.map(\.label).joined(separator: ", "))
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
                            case let .up(_, sunset): Label("Sunset \(Format.time(sunset))", systemImage: "sunset.fill")
                            case let .down(sunrise, _): Label("Sunrise \(Format.time(sunrise))", systemImage: "sunrise.fill")
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
                    ListMetrics(hour: now, water: forecast?.waterTemperature)
                        .layoutPriority(1)
                }
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var cardBackground: some ShapeStyle {
        (forecast?.current()?.light.color ?? .gray).opacity(0.18)
    }
}

/// The row's numbers in two columns: water, wind and waves on the left;
/// visibility, rain and ice on the right.
struct ListMetrics: View {
    let hour: ForecastHour
    let water: WaterTemperature?
    var visibilitySymbol = Condition.visibility.symbol

    var body: some View {
        let rain = precipitationText(hour)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Label(water.map { "\(Format.number($0.celsius, digits: 1))°" } ?? "–", systemImage: Condition.waterTemperature.symbol)
                    .accessibilityLabel("Water: \(water.map { "\(Format.number($0.celsius, digits: 1)) degrees" } ?? "no data")")
                Label(visibilityText(hour.visibilityM), systemImage: visibilitySymbol)
                    .accessibilityLabel("Visibility: \(visibilityText(hour.visibilityM))")
            }
            GridRow {
                Label("\(Format.number(hour.windSpeedMs))–\(Format.number(hour.windGustMs)) m/s", systemImage: Condition.wind.symbol)
                Label(rain == "None" ? "Dry" : rain, systemImage: Condition.precipitation.symbol)
                    .accessibilityLabel("Rain, hail, snow: \(rain)")
            }
            GridRow {
                Label(hour.waveHeightM.map { "\(Format.number($0, digits: 2)) m" } ?? "–", systemImage: Condition.waves.symbol)
                Label("–", systemImage: Condition.ice.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Ice: no data yet")
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

private struct SearchResultRow: View {
    let club: Club
    let lake: Lake?
    let saved: Bool
    let add: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(club.name)
                Text([lake?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !club.launchPointVerified {
                    Text("Launch point not yet confirmed").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            if saved {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityLabel("In your list")
            } else {
                Button(action: add) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(club.displayName)")
            }
        }
    }
}
