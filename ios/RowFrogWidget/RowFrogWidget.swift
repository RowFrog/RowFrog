import AppIntents
import SwiftUI
import WidgetKit

@main
struct RowFrogWidgets: WidgetBundle {
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
        RowingWidgetView(snapshot: entry.snapshot, family: family, focus: entry.focus, plain: entry.background == .system,
                         layout: entry.layout, marks: entry.marks)
            .containerBackground(for: .widget) {
                WidgetBackdrop(background: entry.background, snapshot: entry.snapshot, picture: entry.picture,
                               focus: entry.pictureFocus)
            }
            .widgetURL(URL(string: "rowfrog://club/\(entry.clubID)"))
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

    @Parameter(title: "Background", default: .app)
    var background: BackgroundOption

    @Parameter(title: "Layout", default: .fewer)
    var layout: LayoutOption

    @Parameter(title: "Marks", description: "A check, ! or × in the light's dots, so the light reads without its colour.", default: true)
    var marks: Bool
}

/// Fewer values, or all six of the top tile beside or under the light (owner, 11 Nov 2026).
enum LayoutOption: String, AppEnum {
    case fewer, beside, below

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static var caseDisplayRepresentations: [LayoutOption: DisplayRepresentation] = [
        .fewer: "Fewer values",
        .beside: "All values beside the light",
        .below: "All values in a row (large widget)",
    ]

    var layout: WidgetLayout { WidgetLayout(rawValue: rawValue) ?? .fewer }
}

/// A widget's own background, or the one set in the app.
enum BackgroundOption: String, AppEnum {
    case app, sky, light, picture, satellite, system

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Background"
    static var caseDisplayRepresentations: [BackgroundOption: DisplayRepresentation] = [
        .app: "As set in the app",
        .sky: "Weather sky",
        .light: "Rowing light colour",
        .picture: "Club page picture",
        .satellite: "Satellite picture of the lake",
        .system: "Plain, light or dark",
    ]

    /// nil for "as set in the app".
    var background: WidgetBackground? {
        switch self {
        case .app: nil
        case .sky: .sky
        case .light: .light
        case .picture: .appPicture
        case .satellite: .satellite
        case .system: .system
        }
    }
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
    var background: WidgetBackground = .sky
    /// The picture the app prepared for a picture background, at widget size.
    var picture: UIImage?
    var layout: WidgetLayout = .fewer
    var marks = true
    /// Where the club lies in the satellite picture; nil for other pictures.
    var pictureFocus: UnitPoint?
}

struct RowingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RowingEntry {
        RowingEntry(date: .now, clubID: "", snapshot: .placeholder, focus: .hourly)
    }

    func snapshot(for configuration: RowingWidgetIntent, in context: Context) async -> RowingEntry {
        await entries(for: configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: RowingWidgetIntent, in context: Context) async -> Timeline<RowingEntry> {
        // A new forecast as often as Settings > Widgets says (every half hour unless
        // changed); until then the light moves on hour by hour. "Only after using the
        // app" waits for the app, which asks for a new timeline as the user leaves it.
        let upcoming = await entries(for: configuration)
        guard let interval = AppSettings.shared.widgetUpdates.interval else { return Timeline(entries: upcoming, policy: .never) }
        return Timeline(entries: upcoming, policy: .after(.now.addingTimeInterval(interval)))
    }

    private func entries(for configuration: RowingWidgetIntent) async -> [RowingEntry] {
        // Language, units and limits as the app last left them.
        AppSettings.reload()
        let shared = WidgetShared.defaults
        let homeID = shared.string(forKey: WidgetShared.homeKey) ?? WidgetShared.defaultHomeID
        let clubID = configuration.club?.id ?? homeID
        let names = shared.dictionary(forKey: WidgetShared.namesKey) as? [String: String] ?? [:]
        let forecast = await loadForecast(clubID)
        let background = configuration.background.background ?? AppSettings.shared.widgetBackground(for: clubID)
        let picture = picture(for: background, clubID: clubID)
        let now = Date.now
        // Hours ahead: enough to last until the next load.
        let count = AppSettings.shared.widgetUpdates.interval == nil ? 12 : 6
        let hourStarts = (0..<count).compactMap { offset -> Date? in
            guard offset > 0 else { return now }
            let next = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now
            return next.addingTimeInterval(Double(offset - 1) * 3600)
        }
        return hourStarts.map { date in
            RowingEntry(
                date: date, clubID: clubID,
                snapshot: RowingSnapshot(date: date, clubName: names[clubID] ?? clubID, isHome: clubID == homeID, forecast: forecast),
                focus: configuration.focus.focus, background: background, picture: picture,
                layout: configuration.layout.layout, marks: configuration.marks,
                pictureFocus: pictureFocus(for: background, clubID: clubID)
            )
        }
    }

    /// Where the club lies in the picture: the satellite file's place, and the picture
    /// file's when the club page shows the satellite picture; nil for other pictures.
    private func pictureFocus(for background: WidgetBackground, clubID: String) -> UnitPoint? {
        switch background {
        case .satellite: WidgetPictures.focus(clubID)
        case .appPicture, .picture: WidgetPictures.focus(clubID, .picture)
        default: nil
        }
    }

    /// The small file the app made for this club; when it is missing, the app is
    /// asked to make it the next time it runs, and the sky shows until then.
    private func picture(for background: WidgetBackground, clubID: String) -> UIImage? {
        let kind: WidgetPictures.Kind
        switch background {
        case .appPicture, .picture: kind = .picture
        case .satellite: kind = .satellite
        default: return nil
        }
        if let url = WidgetPictures.file(clubID, kind), let image = UIImage(contentsOfFile: url.path) { return image }
        WidgetShared.defaults.set(true, forKey: WidgetPictures.wantedKey(clubID, kind))
        return nil
    }

    /// The live forecast, or the last one kept when the backend can't be reached.
    private func loadForecast(_ clubID: String) async -> ClubForecast? {
        if clubID.hasPrefix(OwnPlace.idPrefix) {
            // An own place: the widget asks Open-Meteo itself, as the app does.
            let places = WidgetShared.defaults.dictionary(forKey: WidgetShared.ownPlacesKey) as? [String: [Double]] ?? [:]
            if let point = places[clubID], point.count == 2 {
                let club = Club(id: clubID, name: "", shortName: nil, address: "", website: nil,
                                launchPoint: Coordinate(lat: point[0], lon: point[1]), launchPointVerified: true, source: "own")
                if let forecast = try? await PlaceForecaster.load(club) {
                    WidgetForecasts.keep(forecast, for: clubID)
                    return forecast
                }
            }
            return WidgetForecasts.lastKept(clubID)
        }
        return await WidgetForecasts.load(clubID)?.applyingUserLimits()
    }
}
