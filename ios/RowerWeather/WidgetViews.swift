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

    /// Stretches of green, daylight hours from now on: the times to go rowing.
    var rowingWindows: [ClosedRange<Date>] {
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
}

/// The widget for every size, in the style of the iOS Weather widgets: a sky
/// background, the temperature large, and the rowing light as a coloured pill.
struct RowingWidgetView: View {
    let snapshot: RowingSnapshot
    let family: WidgetFamily
    var focus: WidgetFocus = .hourly

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
        .foregroundStyle(family.isAccessory ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white))
        .environment(\.locale, AppSettings.shared.locale)
    }

    // MARK: Home screen

    /// The light and why on top, temperature and sky below, the club at the bottom.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let hour = snapshot.current {
                lightAndWhy(hour)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 6) {
                    temperature.font(.system(size: 38, weight: .light))
                    skyIcon(hour).font(.title2)
                }
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
            Divider().overlay(.white.opacity(0.35))
            ForEach(Array(orderedFocus.enumerated()), id: \.element) { index, section in
                if index > 0 { Divider().overlay(.white.opacity(0.35)) }
                focusSection(section, rows: section == .conditions ? 2 : 3)
            }
            Spacer(minLength: 0)
        }
    }

    private var extraLarge: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider().overlay(.white.opacity(0.35))
                focusSection(.conditions, rows: 2)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                hourly(count: 8)
                Divider().overlay(.white.opacity(0.35))
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

    private var temperature: Text {
        Text(Format.degrees(snapshot.current?.temperatureC))
    }

    /// The light, why and club on the left; sky and temperature on the right.
    private var header: some View {
        HStack(alignment: .top) {
            if let hour = snapshot.current {
                VStack(alignment: .leading, spacing: 4) {
                    lightAndWhy(hour)
                    title
                }
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 6) {
                    skyIcon(hour).font(.title)
                    temperature.font(.system(size: 40, weight: .light))
                }
            }
        }
    }

    /// The rowing light large, with the reason under it.
    private func lightAndWhy(_ hour: ForecastHour) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LightPill(light: hour.light, compact: false)
            Text(detailLine(hour))
                .font(.caption.weight(.medium))
                .opacity(0.9)
                .lineLimit(1)
                .padding(.leading, 4)
        }
    }

    /// The main reason for amber or red, else wind and gusts.
    private func detailLine(_ hour: ForecastHour) -> String {
        if let reason = hour.reasons.filter({ $0.light == hour.light }).first, hour.light != .green {
            return reason.label
        }
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
                        .fill(hour.light.color)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                        .accessibilityLabel(hour.light.title)
                    Text(Format.degrees(hour.temperatureC))
                        .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func conditions(rows: Int) -> some View {
        let hour = snapshot.current
        var tiles: [ConditionTile] = [
            ConditionTile(condition: .wind, value: Format.windRange(hour?.windSpeedMs, hour?.windGustMs)),
            ConditionTile(condition: .waves, value: Format.waves(hour?.waveHeightM)),
            ConditionTile(condition: .waterTemperature, value: Format.temperature(snapshot.forecast?.waterTemperature?.celsius)),
        ]
        if rows > 1 {
            tiles += [
                ConditionTile(condition: .feelsLike, value: Format.temperature(hour?.apparentTemperatureC)),
                ConditionTile(condition: .visibility, value: Format.distance(hour?.visibilityM)),
                ConditionTile(condition: .daylight, value: sunText),
            ]
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
                Text(tr("No green hours in the forecast."))
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
        return Label {
            Text("\(snapshot.clubName) · \(light?.title ?? "–") · \(Format.degrees(snapshot.current?.temperatureC))")
        } icon: {
            Image(systemName: light?.glyph ?? "questionmark.circle")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: snapshot.current?.light.glyph ?? "questionmark.circle")
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
                Label(hour.light.title, systemImage: hour.light.glyph)
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

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(light.color)
                .frame(width: compact ? 10 : 16, height: compact ? 10 : 16)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
            Text(light.title)
                .font((compact ? Font.caption : Font.headline).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(.white.opacity(0.22), in: Capsule())
    }
}

/// The Weather widgets' sky: blue by day, dark blue at night, and a touch of
/// the rowing light's colour when it is amber or red.
struct WidgetSky: View {
    let snapshot: RowingSnapshot

    var body: some View {
        let colors: [Color] = snapshot.isNight
            ? [Color(red: 0.05, green: 0.09, blue: 0.2), Color(red: 0.12, green: 0.2, blue: 0.36)]
            : [Color(red: 0.2, green: 0.5, blue: 0.86), Color(red: 0.45, green: 0.7, blue: 0.95)]
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .overlay {
                if let light = snapshot.current?.light, light != .green {
                    LinearGradient(colors: [light.color.opacity(0.35), .clear], startPoint: .bottomTrailing, endPoint: .center)
                }
            }
    }
}
