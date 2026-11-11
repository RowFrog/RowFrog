import SwiftUI

/// At the end of a club page, above the credits: opens how often each value is
/// renewed (owner, 6 Nov 2026: kept out of the crowded header).
struct UpdateCyclesButton: View {
    let forecast: ClubForecast
    @Environment(\.isCurrentPage) private var isCurrentPage
    @Environment(\.surface) private var surface
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label(tr("How often data is updated"), systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .cardBackground(surface, cornerRadius: 18)
        }
        .sheet(isPresented: $showing) {
            UpdateCyclesSheet(run: forecast.weatherRun, checked: forecast.generatedAt)
        }
        // Screenshot hook: `-RWOpenUpdates YES` opens the sheet on the page in front.
        .task {
            guard UserDefaults.standard.bool(forKey: "RWOpenUpdates"), isCurrentPage else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            showing = true
        }
    }
}

/// Behind "How often data is updated" at a club page's end: how often each kind
/// of value is renewed at its source and how often Row Frog fetches it, each
/// with the symbol it has on the club page (owner, 6 Nov 2026).
struct UpdateCyclesSheet: View {
    /// The weather model run the shown forecast comes from, when known.
    let run: WeatherRun?
    /// When the server last built this club's file (warnings, water, gauges).
    let checked: Date
    @Environment(\.dismiss) private var dismiss

    struct Cycle: Identifiable {
        let symbol: String
        let title: String
        let source: String
        let fetched: String
        var id: String { title }
    }

    static var cycles: [Cycle] {
        [
            Cycle(symbol: "wind", title: tr("Weather forecast"),
                  source: tr("Wind, gusts, temperature, rain, clouds and visibility: DWD's ICON-D2 model, a new run every 3 hours, ready about 1½ to 3 hours after it starts."),
                  fetched: tr("Fetched once the new run is ready, checked every 30 minutes. Clubs nobody opened lately: every 6 hours.")),
            Cycle(symbol: "water.waves", title: tr("Waves"),
                  source: tr("Worked out from the forecast wind and the open water in front of the club."),
                  fetched: tr("With every new forecast.")),
            Cycle(symbol: "exclamationmark.triangle", title: tr("Official warnings"),
                  source: tr("DWD, GeoSphere Austria or MeteoSwiss, whenever they issue or change one."),
                  fetched: tr("Every 30 minutes.")),
            Cycle(symbol: "thermometer.and.liquid.waves", title: tr("Water temperature"),
                  source: tr("Measuring stations, every 15 to 60 minutes; without a station, satellites once a day or an estimate from the air temperatures."),
                  fetched: tr("Every 30 minutes.")),
            Cycle(symbol: "gauge.with.dots.needle.50percent", title: tr("River current and lake level"),
                  source: tr("Gauges, every 15 minutes."),
                  fetched: tr("Every 30 minutes.")),
            Cycle(symbol: "cloud.rain", title: tr("Rain radar"),
                  source: tr("DWD, every 5 minutes."),
                  fetched: tr("The radar map loads live when you open it; the widget's rain line every 30 minutes.")),
            Cycle(symbol: "map", title: tr("Lake view"),
                  source: tr("The same model runs as the forecast, for points across the water."),
                  fetched: tr("Every 3 hours; lakes nobody opened lately twice a day.")),
            Cycle(symbol: "chart.xyaxis.line", title: tr("8-day outlook"),
                  source: tr("The same model runs, longer models after 2 days."),
                  fetched: tr("Every 3 hours.")),
            Cycle(symbol: "photo", title: tr("Satellite picture"),
                  source: tr("Sentinel-2 passes every few days; clouds can hide the water."),
                  fetched: tr("Looked for once a day.")),
            Cycle(symbol: "snowflake", title: tr("Ice"),
                  source: tr("A satellite ice map once a day in winter, and an estimate from the water and air temperatures."),
                  fetched: tr("Twice a day.")),
            Cycle(symbol: "sun.horizon", title: tr("Daylight"),
                  source: tr("Worked out from the date and the place."),
                  fetched: tr("Always current.")),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let run {
                        Text(tr("This forecast: model run of %@, ready at %@.", Format.time(run.started), Format.time(run.available)))
                    } else {
                        Text(tr("This forecast was built at %@.", Format.time(checked)))
                    }
                    Text(tr("Warnings, water and gauges checked at %@.", Format.time(checked)))
                } footer: {
                    Text(tr("The server renews the clubs you use every 30 minutes; your phone loads them when you open or come back to the app, or pull down."))
                }
                Section {
                    ForEach(Self.cycles) { cycle in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cycle.title).font(.subheadline.weight(.semibold))
                                Text(cycle.source).font(.footnote)
                                Text(cycle.fetched).font(.footnote).foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: cycle.symbol).foregroundStyle(.tint)
                        }
                    }
                } header: {
                    Text(tr("How often values are renewed"))
                }
            }
            .navigationTitle(tr("Updates"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
