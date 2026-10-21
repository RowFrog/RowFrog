import AppIntents
import SwiftUI
import WidgetKit

@main
struct RowerWeatherWidgets: WidgetBundle {
    var body: some Widget {
        RowingLightWidget()
    }
}

struct RowingLightWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.kind, intent: RowingWidgetIntent.self, provider: RowingProvider()) { entry in
            RowingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Rowing light")
        .description("The rowing light, weather and good rowing times for your home base or another club.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct RowingWidgetEntryView: View {
    let entry: RowingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        RowingWidgetView(snapshot: entry.snapshot, family: family, focus: entry.focus)
            .containerBackground(for: .widget) {
                WidgetSky(snapshot: entry.snapshot)
            }
            .widgetURL(URL(string: "rowerweather://club/\(entry.clubID)"))
    }
}

// MARK: Configuration

struct RowingWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Rowing light"
    static var description = IntentDescription("Choose the club and what the widget shows.")

    @Parameter(title: "Club", description: "Leave empty for your home base.")
    var club: ClubEntity?

    @Parameter(title: "Show", default: .hourly)
    var focus: FocusOption
}

enum FocusOption: String, AppEnum {
    case hourly, conditions, windows

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static var caseDisplayRepresentations: [FocusOption: DisplayRepresentation] = [
        .hourly: "Hourly forecast",
        .conditions: "Conditions",
        .windows: "Good rowing times",
    ]

    var focus: WidgetFocus { WidgetFocus(rawValue: rawValue) ?? .hourly }
}

/// A club from the app's saved locations.
struct ClubEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Club"
    static var defaultQuery = ClubQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ClubQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ClubEntity] {
        let names = Self.names
        return identifiers.map { ClubEntity(id: $0, name: names[$0] ?? $0) }
    }

    func suggestedEntities() async throws -> [ClubEntity] {
        let names = Self.names
        let saved = WidgetShared.defaults.stringArray(forKey: WidgetShared.savedKey) ?? []
        return saved.map { ClubEntity(id: $0, name: names[$0] ?? $0) }
    }

    private static var names: [String: String] {
        WidgetShared.defaults.dictionary(forKey: WidgetShared.namesKey) as? [String: String] ?? [:]
    }
}

// MARK: Timeline

struct RowingEntry: TimelineEntry {
    let date: Date
    let clubID: String
    let snapshot: RowingSnapshot
    let focus: WidgetFocus
}

struct RowingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RowingEntry {
        RowingEntry(date: .now, clubID: "", snapshot: .placeholder, focus: .hourly)
    }

    func snapshot(for configuration: RowingWidgetIntent, in context: Context) async -> RowingEntry {
        await entries(for: configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: RowingWidgetIntent, in context: Context) async -> Timeline<RowingEntry> {
        // A new forecast every half hour; until then the light moves on hour by hour.
        let upcoming = await entries(for: configuration)
        return Timeline(entries: upcoming, policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entries(for configuration: RowingWidgetIntent) async -> [RowingEntry] {
        let shared = WidgetShared.defaults
        let homeID = shared.string(forKey: WidgetShared.homeKey) ?? WidgetShared.defaultHomeID
        let clubID = configuration.club?.id ?? homeID
        let names = shared.dictionary(forKey: WidgetShared.namesKey) as? [String: String] ?? [:]
        let forecast = await loadForecast(clubID)
        let now = Date.now
        let hourStarts = (0..<6).compactMap { offset -> Date? in
            guard offset > 0 else { return now }
            let next = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now
            return next.addingTimeInterval(Double(offset - 1) * 3600)
        }
        return hourStarts.map { date in
            RowingEntry(
                date: date, clubID: clubID,
                snapshot: RowingSnapshot(date: date, clubName: names[clubID] ?? clubID, isHome: clubID == homeID, forecast: forecast),
                focus: configuration.focus.focus
            )
        }
    }

    /// The live forecast, or the last one fetched when the backend can't be reached.
    private func loadForecast(_ clubID: String) async -> ClubForecast? {
        let shared = WidgetShared.defaults
        let url = APIClient.fromBundle().baseURL.appending(path: "clubs/\(clubID)/forecast")
        if let result = try? await URLSession.shared.data(from: url),
           (result.1 as? HTTPURLResponse)?.statusCode == 200,
           let forecast = try? APIClient.decoder.decode(ClubForecast.self, from: result.0) {
            let data = result.0
            shared.set(data, forKey: WidgetShared.cacheKey(clubID))
            return forecast
        }
        guard let cached = shared.data(forKey: WidgetShared.cacheKey(clubID)) else { return nil }
        return try? APIClient.decoder.decode(ClubForecast.self, from: cached)
    }
}
