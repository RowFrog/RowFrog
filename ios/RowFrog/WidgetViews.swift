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

    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func cacheKey(_ clubID: String) -> String { "RWWidgetForecast-\(clubID)" }
    /// When the widget last downloaded that forecast.
    static func loadedKey(_ clubID: String) -> String { "RWWidgetLoaded-\(clubID)" }
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

    /// Stretches of green, daylight hours from now on: the times to go rowing.
    /// None from an out-of-date forecast.
    var rowingWindows: [ClosedRange<Date>] {
        guard !isStale else { return [] }
        var windows: [ClosedRange<Date>] = []
        var start: Date?
        var end: Date?
        for hour in hours {
            if hour.light == .green && hour.sunUp != false {
                if start == nil { start = max(hour.time, date) }
                end = hour.time.addingTimeInterval(3600)
            } else if let s = start, let e = end {
                windows.append(s...e)
                start = nil
            }
        }
        if let s = start, let e = end { windows.append(s...e) }
        return windows.filter { $0.upperBound.timeIntervalSince($0.lowerBound) >= 3600 }
    }

    static let placeholder = RowingSnapshot(date: .now, clubName: "MRC 1880", isHome: true, forecast: nil)
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
/// background, the temperature large, and the rowing light as a coloured pill.
struct RowingWidgetView: View {
    let snapshot: RowingSnapshot
    let family: WidgetFamily
    var focus: WidgetFocus = .hourly
    /// On the plain light or dark background the text follows the system's colours instead of white.
    var plain = false

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            default:
                if snapshot.current == nil {
                    noData
                } else {
                    switch family {
                    case .systemSmall: small
                    case .systemMedium: medium
                    case .systemExtraLarge: extraLarge
                    default: large
                    }
                }
            }
        }
        .foregroundStyle(family.isAccessory || plain ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white))
        .environment(\.locale, AppSettings.shared.locale)
    }

    // MARK: Home screen

    /// The light and why on top, temperature, feels like and sky below, the club at the bottom.
    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let hour = snapshot.current {
                lightAndWhy(hour)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 6) {
                    temperature(hour, size: 34)
                    skyIcon(hour).font(.title2)
                }
                feelsLike(hour)
            }
            title
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            focusSection(focus, rows: 1)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().overlay(rule)
            ForEach(Array(orderedFocus.enumerated()), id: \.element) { index, section in
                if index > 0 { Divider().overlay(rule) }
                focusSection(section, rows: section == .conditions ? 2 : 3)
            }
            Spacer(minLength: 0)
        }
    }

    private var extraLarge: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider().overlay(rule)
                focusSection(.conditions, rows: 2)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                hourly(count: 8)
                Divider().overlay(rule)
                windows(limit: 4)
                Spacer(minLength: 0)
            }
        }
    }

    private var noData: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            Spacer(minLength: 0)
            Image(systemName: "wifi.slash").font(.title3)
            Text(tr("Open Row Frog to load the forecast."))
                .font(.caption)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rule: Color { plain ? Color.secondary.opacity(0.4) : .white.opacity(0.35) }

    private var orderedFocus: [WidgetFocus] {
        [focus] + WidgetFocus.allCases.filter { $0 != focus }
    }

    @ViewBuilder
    private func focusSection(_ section: WidgetFocus, rows: Int) -> some View {
        switch section {
        case .hourly: hourly(count: 6)
        case .conditions: conditions(rows: rows)
        case .windows: windows(limit: rows)
        }
    }

    // MARK: Parts

    private var title: some View {
        HStack(spacing: 4) {
            Text(snapshot.clubName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if snapshot.isHome {
                Image(systemName: "location.fill").font(.caption2)
            }
        }
    }

    /// The air temperature large with its thermometer, as in the club page's top tile.
    private func temperature(_ hour: ForecastHour, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: Condition.temperature.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.42))
            Text(Format.degrees(hour.temperatureC))
                .font(.system(size: size, weight: .light))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("Air temperature %@", Format.temperature(hour.temperatureC)))
    }

    /// "Feels like 9°" with its symbol, right under the temperature.
    @ViewBuilder
    private func feelsLike(_ hour: ForecastHour) -> some View {
        if let feels = hour.apparentTemperatureC {
            Label(tr("Feels like %@", Format.degrees(feels)), systemImage: Condition.feelsLike.symbol)
                .font(.caption.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .opacity(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The light, why and club on the left; sky, temperature and feels like on the right.
    private var header: some View {
        HStack(alignment: .top) {
            if let hour = snapshot.current {
                VStack(alignment: .leading, spacing: 4) {
                    lightAndWhy(hour)
                    title
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .center, spacing: 6) {
                        skyIcon(hour).font(.title)
                        temperature(hour, size: 38)
                    }
                    feelsLike(hour)
                }
            }
        }
    }

    /// The rowing light large, with the reason under it.
    private func lightAndWhy(_ hour: ForecastHour) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LightPill(light: hour.light, compact: false, stale: snapshot.isStale, plain: plain)
            Text(detailLine(hour))
                .font(.caption.weight(.medium))
                .opacity(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 4)
        }
    }

    /// The main reason for amber or red, else rain on DWD's radar within two
    /// hours ("Light rain from 14:30"), else wind and gusts.
    private func detailLine(_ hour: ForecastHour) -> String {
        if snapshot.isStale, let forecast = snapshot.forecast {
            return tr("As of %@", Format.dayTime(forecast.generatedAt))
        }
        if let reason = hour.reasons.filter({ $0.light == hour.light }).first, hour.light != .green {
            return reason.label
        }
        if let radar = snapshot.rainAhead { return radar.summary }
        return "\(tr("Wind")) \(Format.windRange(hour.windSpeedMs, hour.windGustMs))"
    }

    private func skyIcon(_ hour: ForecastHour) -> some View {
        let night = hour.sunUp == false
        let sky = Sky(hour: hour)
        return Image(systemName: sky.symbol(night: night))
            .symbolRenderingMode(.multicolor)
            .accessibilityLabel(sky.title)
    }

    private func hourly(count: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.hours.prefix(count).enumerated()), id: \.element.time) { index, hour in
                VStack(spacing: 5) {
                    Text(index == 0 ? tr("Now") : Format.time(hour.time))
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    skyIcon(hour).font(.subheadline)
                    Circle()
                        .fill(hour.light.color(stale: snapshot.isStale))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                        .accessibilityLabel(hour.light.title(stale: snapshot.isStale))
                    Text(Format.degrees(hour.temperatureC))
                        .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The top tile's values in its order: water, wind, waves, then rain,
    /// visibility and daylight (ice joins in winter, daylight then gets a line of its own).
    private func conditions(rows: Int) -> some View {
        let hour = snapshot.current
        let forecast = snapshot.forecast
        let water: String = {
            if let measured = forecast?.waterTemperature?.celsius { return Format.temperature(measured, digits: 1) }
            if let estimate = forecast?.estimatedWaterC { return "≈ " + Format.temperature(estimate) }
            return "–"
        }()
        var tiles: [ConditionTile] = [
            ConditionTile(condition: .waterTemperature, value: water),
            ConditionTile(condition: .wind, value: Format.windRange(hour?.windSpeedMs, hour?.windGustMs)),
            ConditionTile(condition: .waves, value: Format.waves(hour?.waveHeightM)),
        ]
        if rows > 1 {
            tiles += [
                ConditionTile(condition: .precipitation, value: hour.flatMap(precipitationText) ?? tr("None")),
                ConditionTile(condition: .visibility, value: Format.distance(hour?.visibilityM)),
            ]
            if let ice = forecast?.iceValue { tiles.append(ConditionTile(condition: .ice, value: ice)) }
            tiles.append(ConditionTile(condition: .daylight, value: sunText))
        }
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(0..<(tiles.count + 2) / 3, id: \.self) { row in
                GridRow {
                    ForEach(tiles[(row * 3)..<min(row * 3 + 3, tiles.count)], id: \.condition) { tile in
                        let (condition, value) = (tile.condition, tile.value)
                        HStack(spacing: 5) {
                            Image(systemName: condition.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .font(.caption)
                                .frame(width: 16)
                            Text(value)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(condition.title) \(value)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// "↓ 18:42" while the sun is up, else "↑ 07:12".
    private var sunText: String {
        guard let sun = snapshot.forecast?.sunState(at: snapshot.date) else { return "–" }
        switch sun {
        case let .up(_, sunset): return "↓ \(Format.time(sunset))"
        case let .down(sunrise, _): return "↑ \(Format.time(sunrise))"
        }
    }

    private func windows(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(tr("Good to row"), systemImage: "figure.rower")
                .font(.caption.weight(.semibold))
            let windows = snapshot.rowingWindows.prefix(limit)
            if windows.isEmpty {
                Text(snapshot.isStale ? tr("Forecast out of date. Open Row Frog to update.") : tr("No green hours in the forecast."))
                    .font(.caption)
                    .opacity(0.85)
            }
            ForEach(Array(windows), id: \.lowerBound) { window in
                HStack(spacing: 6) {
                    Circle().fill(Light.green.color).frame(width: 8, height: 8)
                    Text(Format.day(window.lowerBound))
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 4)
                    Text("\(Format.time(window.lowerBound))–\(Format.time(window.upperBound))")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: Lock screen

    private var inline: some View {
        let light = snapshot.current?.light
        let stale = snapshot.isStale
        return Label {
            Text("\(snapshot.clubName) · \(light?.title(stale: stale) ?? "–") · \(Format.degrees(snapshot.current?.temperatureC))")
        } icon: {
            Image(systemName: light?.glyph(stale: stale) ?? "questionmark.circle")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: snapshot.current?.light.glyph(stale: snapshot.isStale) ?? "questionmark.circle")
                    .font(.title3)
                Text(Format.degrees(snapshot.current?.temperatureC))
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.clubName).font(.headline).lineLimit(1)
            if let hour = snapshot.current {
                Label(hour.light.title(stale: snapshot.isStale), systemImage: hour.light.glyph(stale: snapshot.isStale))
                    .font(.subheadline.weight(.medium))
                Text("\(Format.degrees(hour.temperatureC)) · \(detailLine(hour))")
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text(tr("Open Row Frog to load the forecast.")).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConditionTile {
    let condition: Condition
    let value: String
}

private extension WidgetFamily {
    var isAccessory: Bool {
        [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(self)
    }
}

/// The rowing light as a pill: coloured dot and words, on a light glass.
struct LightPill: View {
    let light: Light
    let compact: Bool
    var stale = false
    var plain = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(light.color(stale: stale))
                .frame(width: compact ? 10 : 16, height: compact ? 10 : 16)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
            Text(light.title(stale: stale))
                .font((compact ? Font.caption : Font.headline).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(plain ? Color.secondary.opacity(0.15) : .white.opacity(0.22), in: Capsule())
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
