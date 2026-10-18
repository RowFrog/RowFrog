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
            .refreshable {
                for club in locations.saved { await forecasts.load(club.id, force: true) }
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
                Spacer(minLength: 6)
                if let now {
                    Text(now.reasons.isEmpty ? now.light.title : now.reasons.map(\.label).joined(separator: ", "))
                        .font(.subheadline)
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
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let now {
                    HStack(spacing: 6) {
                        TrafficLightDot(light: now.light, size: 18)
                        Image(systemName: Condition.temperature.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityLabel("Air")
                        Text("\(Format.number(now.temperatureC))°").font(.system(size: 36, weight: .light))
                    }
                    Label(forecast?.waterTemperature.map { "Water \(Format.number($0.celsius, digits: 1))°" } ?? "Water –",
                          systemImage: Condition.waterTemperature.symbol)
                        .font(.caption)
                    Label("\(Format.number(now.windSpeedMs))–\(Format.number(now.windGustMs)) m/s", systemImage: Condition.wind.symbol)
                        .font(.caption)
                    if let wave = now.waveHeightM {
                        Label("\(Format.number(wave, digits: 2)) m", systemImage: Condition.waves.symbol)
                            .font(.caption)
                    }
                } else {
                    ProgressView()
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
