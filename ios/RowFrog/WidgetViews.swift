import SwiftUI
import WidgetKit

/// What the app shares with its widget through the app group: the home base,
/// the saved clubs with their names, the settings, and the last forecast of
/// each club so the widget still shows something without a connection.
enum WidgetShared {
    static let group = "group.com.rowfrog.RowFrog"
    static let kind = "RowingLight"
    /// Until the app has run once and shared its home base.
    static let defaultHomeID = "mrc-1880"

    static let homeKey = "RWWidgetHome"
    static let savedKey = "RWWidgetSaved"
    static let namesKey = "RWWidgetClubNames"
    /// Own places by id, as [lat, lon]: their forecast is worked out in the widget too.
    static let ownPlacesKey = "RWWidgetOwnPlaces"
    /// The app's language as iOS gives it (per-app language), for the widget's texts.
    static let appLanguageKey = "RWWidgetAppLanguage"

    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

}

/// The widgets' copies of the club forecasts: files in the app group folder,
/// not the shared settings, which are read and written whole each time (one
/// forecast is about 100 KB). Downloads go through `APIClient`, so an
/// unchanged forecast answers "304 Not Modified" instead of coming again.
enum WidgetForecasts {
    /// Several widgets of one club, or a redraw soon after the last one, share one download.
    static let reuseFor: TimeInterval = 15 * 60
    /// A widget has little time to draw: a slow server must not hold it for the system's minute.
    static let timeout: TimeInterval = 20

    static var folder: URL {
        (FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.group) ?? URL.cachesDirectory)
            .appending(path: "WidgetForecasts", directoryHint: .isDirectory)
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The backend the app uses, with the widgets' folder and timeout.
    static func client(_ base: APIClient = .fromBundle()) -> APIClient {
        APIClient(baseURL: base.baseURL, session: session, cache: KeptFiles(folder: folder))
    }

    /// The live forecast; the copy from the last 15 minutes; or, when the backend
    /// can't be reached or answers with an error, the last one kept.
    static func load(_ clubID: String, api: APIClient = client()) async -> ClubForecast? {
        try? await api.forecast(clubID: clubID, keepFor: reuseFor)
    }

    /// The last forecast kept for a club or own place, however old.
    static func lastKept(_ clubID: String, api: APIClient = client()) -> ClubForecast? {
        guard let data = api.cache?.copy(of: url(clubID, api: api))?.data else { return nil }
        return try? APIClient.decoder.decode(ClubForecast.self, from: data)
    }

    /// Keeps an own place's forecast, which the widget works out itself.
    static func keep(_ forecast: ClubForecast, for clubID: String, api: APIClient = client()) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(forecast) else { return }
        api.cache?.keep(data, etag: "", for: url(clubID, api: api))
    }

    private static func url(_ clubID: String, api: APIClient) -> URL {
        api.baseURL.appending(path: clubID.hasPrefix(OwnPlace.idPrefix) ? "own-places/\(clubID)" : "clubs/\(clubID)/forecast")
    }

    /// Forecasts that versions before November 2026 kept in the shared settings.
    static func dropOldCopies(_ defaults: UserDefaults = WidgetShared.defaults) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("RWWidgetForecast-") || key.hasPrefix("RWWidgetLoaded-") {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Pictures the app prepares for the widgets' backgrounds, at widget size, in
/// the shared app group: <club>-picture.jpg (the club page's or a chosen picture)
/// and <club>-satellite.jpg. The widget only loads these small files.
enum WidgetPictures {
    enum Kind: String { case picture, satellite }

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.group)?
            .appending(path: "WidgetBackgrounds", directoryHint: .isDirectory)
    }

    static func file(_ clubID: String, _ kind: Kind) -> URL? {
        folder?.appending(path: "\(clubID)-\(kind.rawValue).jpg")
    }

    /// What the file was made from, so the app makes it again only after a change.
    static func sourceKey(_ clubID: String, _ kind: Kind) -> String { "RWWidgetPictureSource-\(clubID)-\(kind.rawValue)" }
    /// Set by the widget when a widget of its own asks for a picture the app has not made yet.
    static func wantedKey(_ clubID: String, _ kind: Kind) -> String { "RWWidgetPictureWanted-\(clubID)-\(kind.rawValue)" }
}

/// What the medium widget shows below the rowing light; the large one shows it first.
enum WidgetFocus: String, CaseIterable, Codable {
    case hourly, conditions, windows
}

/// One moment of a widget: a club's forecast as it stands at `date`.
struct RowingSnapshot {
    let date: Date
    let clubName: String
    let isHome: Bool
    let forecast: ClubForecast?

    /// The forecast hours from the one `date` falls in onwards.
    var hours: [ForecastHour] {
        guard let forecast else { return [] }
        let start = date.addingTimeInterval(-3600)
        return forecast.hours.filter { $0.time > start }
    }

    var current: ForecastHour? {
        guard let forecast, !hours.isEmpty else { return nil }
        let trimmed = ClubForecast(
            clubId: forecast.clubId, lakeId: forecast.lakeId, generatedAt: forecast.generatedAt,
            waterTemperature: forecast.waterTemperature, warnings: forecast.warnings,
            attribution: forecast.attribution, daylight: forecast.daylight, hours: hours
        )
        return trimmed.current(at: date)
    }

    var isNight: Bool { current?.sunUp == false }

    /// DWD's radar from `date` on, when it brings rain within its two hours.
    var rainAhead: RainRadar? {
        guard let radar = forecast?.radar?.ahead(of: date), radar.firstRain != nil else { return nil }
        return radar
    }

    /// The forecast is too old at `date` to show green.
    var isStale: Bool { forecast?.isStale(at: date) ?? false }

    static let placeholder = RowingSnapshot(date: .now, clubName: "MRC 1880", isHome: true, forecast: nil)
}

/// The words the widget shows, worked out here so the tests can read them.
extension RowingSnapshot {
    /// The main reason for amber or red, else rain on DWD's radar within two
    /// hours ("Light rain from 14:30", "Dry from 15:10"), else wind and gusts. An out-of-date
    /// forecast says how old it is instead.
    func detailLine(_ hour: ForecastHour) -> String {
        if isStale, let forecast {
            return tr("As of %@", Format.dayTime(forecast.generatedAt))
        }
        if let reason = hour.reasons.filter({ $0.light == hour.light }).first, hour.light != .green {
            return reason.label
        }
        if let radar = rainAhead { return radarLine(radar) }
        return "\(tr("Wind")) \(Format.windRange(hour.windSpeedMs, hour.windGustMs))"
    }

    /// Under "Good to row" when there is no window to show.
    var noWindowsText: String {
        isStale ? tr("Forecast out of date. Open Row Frog to update.") : tr("No green hours in the forecast.")
    }

    /// The lock screen's line: "Good until 16:00 · 15°"; the club's name stays off the lock screen.
    var inlineText: String {
        "\(current == nil ? "–" : lockTitle) · \(Format.degrees(current?.temperatureC))"
    }
}

extension Light {
    /// A symbol that tells the lights apart without colour, for the lock screen.
    var glyph: String {
        switch self {
        case .green: "checkmark.circle.fill"
        case .amber: "exclamationmark.circle.fill"
        case .red: "xmark.circle.fill"
        }
    }

    func glyph(stale: Bool) -> String { stale && self == .green ? "clock.badge.exclamationmark" : glyph }
}

/// The widget for every size, in the style of the iOS Weather widgets: a sky
/// background, the club and the forecast's time on top, the rowing light with
/// its reason, and the values as symbol and value. The layouts themselves are in
/// WidgetLayouts.swift.
struct RowingWidgetView: View {
    let snapshot: RowingSnapshot
    let family: WidgetFamily
    var focus: WidgetFocus = .hourly
    /// On the plain light or dark background the text follows the system's colours instead of white.
    var plain = false
    /// Fewer values, or all six of the top tile (the widget's "Layout" option).
    var layout: WidgetLayout = .fewer
    /// A check, "!" or "×" in the light's dots and stripes in the day bars (the widget's "Marks" option).
    var marks = true
    @Environment(\.accessibilityDifferentiateWithoutColor) var withoutColor

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            default:
                if let hour = snapshot.current {
                    switch family {
                    case .systemSmall: smallLayout(hour)
                    case .systemMedium: mediumLayout(hour)
                    case .systemExtraLarge: extraLargeLayout(hour)
                    default: largeLayout(hour)
                    }
                } else {
                    noData
                }
            }
        }
        .foregroundStyle(family.isAccessory || plain ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white))
        .environment(\.locale, AppSettings.shared.locale)
    }

    private var noData: some View {
        VStack(alignment: .leading, spacing: 6) {
            topLine
            Spacer(minLength: 0)
            Image(systemName: "wifi.slash").font(.title3)
            Text(tr("Open Row Frog to load the forecast."))
                .font(.caption)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func skyIcon(_ hour: ForecastHour) -> some View {
        let night = hour.sunUp == false
        let sky = Sky(hour: hour)
        return Image(systemName: sky.symbol(night: night))
            .symbolRenderingMode(.multicolor)
            .accessibilityLabel(sky.title)
    }

    // MARK: Lock screen

    /// The mark of the light now, or a question mark without a forecast.
    private var lockMark: String {
        snapshot.current?.light.plainMark(stale: snapshot.isStale) ?? "questionmark"
    }

    /// "Good until 16:00 · 15°" with the light's mark; no club name.
    private var inline: some View {
        Label {
            Text(snapshot.inlineText)
        } icon: {
            Image(systemName: snapshot.current?.light.glyph(stale: snapshot.isStale) ?? "questionmark.circle")
        }
    }

    /// The daylight ring (owner's pick D): today's hours from sunrise to sunset, bright where good.
    private var circular: some View {
        DaylightRing(day: snapshot.current == nil ? nil : snapshot.ringDay, now: snapshot.ringNow, mark: lockMark)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.current == nil ? tr("Open Row Frog to load the forecast.") : snapshot.lockTitle)
    }

    /// The light in short words with its mark, why or what comes, and wind, waves and visibility.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if snapshot.current != nil {
                Label(snapshot.lockTitle, systemImage: snapshot.current?.light.glyph(stale: snapshot.isStale) ?? "questionmark.circle")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(snapshot.lockDetail)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 6) {
                    ForEach([Condition.wind, .waves, .visibility], id: \.self) { condition in
                        let value = snapshot.value(condition)
                        HStack(spacing: 2) {
                            Image(systemName: value.symbol)
                            Text(value.text)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(condition.title) \(value.text)")
                    }
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(snapshot.clubName).font(.headline).lineLimit(1)
                Text(tr("Open Row Frog to load the forecast.")).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A sky in the weather's colours, as in the iOS Weather widgets: blue when
/// clear, grey-blue when cloudy, slate in rain, pale in fog, navy at night and
/// warm around sunrise and sunset. Amber or red adds a glow of that colour.
struct WidgetSky: View {
    let snapshot: RowingSnapshot

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .overlay {
                if let light = snapshot.current?.light, light != .green {
                    LinearGradient(colors: [light.color.opacity(0.35), .clear], startPoint: .bottomTrailing, endPoint: .center)
                }
            }
    }

    private var colors: [Color] {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        guard let hour = snapshot.current else { return [rgb(0.2, 0.5, 0.86), rgb(0.45, 0.7, 0.95)] }
        let sky = Sky(hour: hour)
        if snapshot.isNight {
            switch sky {
            case .clear, .mostlyClear, .partlyCloudy: return [rgb(0.04, 0.07, 0.18), rgb(0.12, 0.19, 0.35)]
            default: return [rgb(0.1, 0.12, 0.17), rgb(0.2, 0.23, 0.3)]
            }
        }
        // Within 45 minutes of sunrise or sunset: dawn and dusk colours.
        if case let .up(sunrise, sunset)? = snapshot.forecast?.sunState(at: snapshot.date),
           min(abs(snapshot.date.timeIntervalSince(sunrise)), abs(snapshot.date.timeIntervalSince(sunset))) < 45 * 60,
           [.clear, .mostlyClear, .partlyCloudy].contains(sky) {
            return [rgb(0.29, 0.36, 0.62), rgb(0.93, 0.6, 0.45)]
        }
        switch sky {
        case .clear, .mostlyClear: return [rgb(0.2, 0.5, 0.86), rgb(0.45, 0.7, 0.95)]
        case .partlyCloudy: return [rgb(0.3, 0.52, 0.78), rgb(0.6, 0.72, 0.86)]
        case .cloudy: return [rgb(0.36, 0.42, 0.5), rgb(0.59, 0.64, 0.71)]
        case .fog: return [rgb(0.55, 0.59, 0.64), rgb(0.74, 0.77, 0.8)]
        case .drizzle, .rain, .showers, .freezingRain: return [rgb(0.26, 0.31, 0.39), rgb(0.43, 0.49, 0.57)]
        case .heavyRain, .thunderstorm, .hail: return [rgb(0.17, 0.2, 0.27), rgb(0.32, 0.36, 0.44)]
        case .snow: return [rgb(0.55, 0.62, 0.72), rgb(0.8, 0.84, 0.9)]
        }
    }
}

/// What a widget draws behind its content, for each background choice. A
/// picture the app has not prepared yet falls back to the sky.
struct WidgetBackdrop: View {
    let background: WidgetBackground
    let snapshot: RowingSnapshot
    var picture: UIImage?

    var body: some View {
        switch background {
        case .sky:
            WidgetSky(snapshot: snapshot)
        case .light:
            let tint = snapshot.current?.light.color(stale: snapshot.isStale) ?? .gray
            LinearGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.14), Color(red: 0.16, green: 0.16, blue: 0.2)],
                           startPoint: .top, endPoint: .bottom)
                .overlay {
                    RadialGradient(colors: [tint.opacity(0.6), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 320)
                }
        case .appPicture, .picture, .satellite:
            if let picture {
                Color.clear
                    .overlay { Image(uiImage: picture).resizable().scaledToFill() }
                    .clipped()
                    .overlay {
                        // Darker towards the bottom, so the white text stays readable.
                        LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    }
            } else {
                WidgetSky(snapshot: snapshot)
            }
        case .system:
            Color(.systemBackground)
        }
    }
}
