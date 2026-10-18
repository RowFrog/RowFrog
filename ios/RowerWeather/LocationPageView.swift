import SwiftUI

/// One full-screen location page: rowing light now, daylight, current
/// conditions, the hourly forecast with its icon legend, and the credits.
struct LocationPageView: View {
    let club: Club
    let lake: Lake?
    let isHome: Bool
    let forecasts: ForecastStore

    var body: some View {
        let forecast = forecasts.forecasts[club.id]
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let forecast, let now = forecast.current() {
                        NowCard(hour: now, water: forecast.waterTemperature)
                        if let sun = forecast.sunState(at: .now) {
                            DaylightCard(state: sun)
                        }
                        CurrentConditionsCard(hour: now, water: forecast.waterTemperature)
                        HourlyCard(forecast: forecast).id("hourly")
                        LegendCard()
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(forecast.attribution, id: \.self) { Text($0) }
                            if !club.launchPointVerified {
                                if club.source == "drv" {
                                    Text("Club data: Deutscher Ruderverband e.V. (rudern.de). Launch point geocoded with © OpenStreetMap contributors, ODbL")
                                } else {
                                    Text("Launch point from © OpenStreetMap contributors, ODbL")
                                }
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if forecasts.failed.contains(club.id) {
                        ContentUnavailableView {
                            Label("No forecast", systemImage: "icloud.slash")
                        } description: {
                            Text("Could not load the forecast. Pull to retry.")
                        }
                    } else {
                        ProgressView().padding(.top, 40)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { await forecasts.load(club.id, force: true) }
            .task {
                await forecasts.load(club.id)
                if UserDefaults.standard.string(forKey: "RWScrollTo") == "hourly" {
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo("hourly", anchor: .top)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            if isHome {
                Label("Home base", systemImage: "house.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(club.displayName)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text([lake?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            if !club.launchPointVerified {
                Label("Launch point not yet confirmed", systemImage: "mappin.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 24)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title.uppercased(), systemImage: symbol ?? "")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NowCard: View {
    let hour: ForecastHour
    let water: WaterTemperature?

    var body: some View {
        Card {
            HStack(spacing: 14) {
                TrafficLightDot(light: hour.light, size: 36)
                Text(hour.light.title).font(.title2.bold())
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                if hour.reasons.isEmpty {
                    Label("All conditions are within the limits.", systemImage: "checkmark.circle")
                } else {
                    ForEach(hour.reasons, id: \.self) { reason in
                        Label(reason.explanation, systemImage: reason.symbol)
                            .foregroundStyle(reason.light == .red ? Color.red : Color.orange)
                    }
                }
            }
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(hour.reasons.isEmpty ? "Why: all conditions within the limits" : "Why: " + hour.reasons.map(\.explanation).joined(separator: " "))
            Divider()
            HStack(alignment: .lastTextBaseline) {
                TemperatureView(condition: .temperature, celsius: hour.temperatureC, size: 44)
                Spacer()
                TemperatureView(condition: .waterTemperature, celsius: water?.celsius, digits: 1, size: 28)
                Spacer()
                MetricView(title: "Waves", symbol: Condition.waves.symbol,
                           value: hour.waveHeightM.map { "\(Format.number($0, digits: 2)) m" } ?? "–", size: 28)
            }
            HStack {
                Label("Visibility \(visibilityText(hour.visibilityM))", systemImage: Condition.visibility.symbol)
                Spacer()
                Label("Ice: no data yet", systemImage: Condition.ice.symbol)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
        }
    }
}

/// A temperature with the icon and word that say whether it is air or water.
struct TemperatureView: View {
    let condition: Condition
    let celsius: Double?
    var digits = 0
    var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(condition == .temperature ? "Air" : "Water", systemImage: condition.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(celsius.map { "\(Format.number($0, digits: digits))°" } ?? "–")
                .font(.system(size: size, weight: .light))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A value with the icon and word that say what it is, matching TemperatureView.
struct MetricView: View {
    let title: String
    let symbol: String
    let value: String
    var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: size, weight: .light))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DaylightCard: View {
    let state: SunState

    var body: some View {
        Card(title: "Daylight", symbol: Condition.daylight.symbol) {
            switch state {
            case let .up(sunrise, sunset):
                sunTimes(sunrise: sunrise, sunset: sunset)
                Label("Sun is up. Rowing advised for \(Format.duration(from: .now, to: sunset)) until sunset.", systemImage: "sun.max.fill")
                    .foregroundStyle(.primary)
            case let .down(nextSunrise, nextSunset):
                sunTimes(sunrise: nextSunrise, sunset: nextSunset)
                Label("Sun is down. Rowing is advised again from sunrise at \(Format.time(nextSunrise)).", systemImage: "moon.stars.fill")
                    .foregroundStyle(.primary)
            }
        }
        .font(.subheadline)
    }

    private func sunTimes(sunrise: Date, sunset: Date) -> some View {
        HStack(spacing: 24) {
            Label(Format.time(sunrise), systemImage: "sunrise.fill")
            Label(Format.time(sunset), systemImage: "sunset.fill")
            Spacer()
        }
        .font(.title3.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .labelStyle(SunLabelStyle())
    }
}

private struct CurrentConditionsCard: View {
    let hour: ForecastHour
    let water: WaterTemperature?

    var body: some View {
        Card(title: "Current conditions", symbol: "gauge.with.dots.needle.33percent") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Condition.allCases.filter { $0 != .daylight }) { condition in
                    ConditionTile(condition: condition, light: hour.light(for: condition.reasonNames)) {
                        value(for: condition)
                    } detail: {
                        detail(for: condition)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func value(for condition: Condition) -> some View {
        switch condition {
        case .temperature: Text("\(Format.number(hour.temperatureC)) °C")
        case .wind:
            HStack(spacing: 6) {
                Text("\(Format.number(hour.windSpeedMs)) m/s")
                if let from = hour.windFromDeg {
                    Image(systemName: "location.north.fill")
                        .font(.caption)
                        .rotationEffect(.degrees(from + 180))
                        .accessibilityLabel("from \(Format.compass(from))")
                }
            }
        case .waves: Text(hour.waveHeightM.map { "\(Format.number($0, digits: 2)) m" } ?? "–")
        case .waterTemperature: Text(water.map { "\(Format.number($0.celsius, digits: 1)) °C" } ?? "–")
        case .visibility: Text(visibilityText(hour.visibilityM))
        case .cloudCover: Text("\(Format.number(hour.cloudCoverPct)) %")
        case .thunderstorm:
            switch hour.light(for: condition.reasonNames) {
            case .red: Text("High")
            case .amber: Text("Possible")
            default: Text("Low")
            }
        case .ice: Text("No data yet").foregroundStyle(.secondary)
        case .daylight: EmptyView()
        }
    }

    private func detail(for condition: Condition) -> String? {
        switch condition {
        case .wind:
            guard let gust = hour.windGustMs else { return nil }
            let from = hour.windFromDeg.map { " · from \(Format.compass($0))" } ?? ""
            return "Gusts \(Format.number(gust)) m/s\(from)"
        case .waves:
            guard let fetch = hour.fetchM else { return nil }
            return fetch < 50 ? "Wind blows off the shore" : "\(Format.number(fetch / 1000, digits: 1)) km open water upwind"
        case .waterTemperature:
            return water.map { "Measured \(Format.time($0.measuredAt))" } ?? "No lake station"
        case .visibility:
            guard let v = hour.visibilityM else { return nil }
            return v < 1000 ? "Fog" : "No fog"
        default:
            return nil
        }
    }
}

func visibilityText(_ metres: Double?) -> String {
    guard let metres else { return "–" }
    let km = metres / 1000
    return "\(Format.number(km, digits: km < 10 ? 1 : 0)) km"
}

private struct ConditionTile<Value: View>: View {
    let condition: Condition
    let light: Light?
    @ViewBuilder var value: Value
    var detail: () -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ConditionIcon(condition: condition)
                    .frame(width: 20)
                Text(condition.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let light {
                    TrafficLightDot(light: light, size: 10)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            value
                .font(.title3.weight(.semibold))
            if let detail = detail() {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Columns of the hourly table, shared by the icon header and the rows.
private enum Column {
    static let time: CGFloat = 44
    static let light: CGFloat = 14
    static let sun: CGFloat = 18
}

private struct HourlyCard: View {
    let forecast: ClubForecast

    var body: some View {
        Card(title: "Next 48 hours", symbol: "clock") {
            HourlyLegendHeader()
            ForEach(days) { group in
                DayHeader(day: group.day, sun: sunDay(on: group.day))
                ForEach(group.hours) { HourRow(hour: $0) }
            }
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let hours: [ForecastHour]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: forecast.hours) { calendar.startOfDay(for: $0.time) }
        return grouped.keys.sorted().map { DayGroup(day: $0, hours: grouped[$0]!.sorted { $0.time < $1.time }) }
    }

    private func sunDay(on day: Date) -> SunDay? {
        forecast.daylight?.first { Calendar.current.isDate($0.sunrise, inSameDayAs: day) }
    }
}

/// The icon legend over the hourly table: one icon and unit per column.
private struct HourlyLegendHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").frame(width: Column.time, alignment: .leading)
                .accessibilityLabel("Time")
            Image(systemName: "circle.fill").font(.system(size: 8)).frame(width: Column.light)
                .accessibilityLabel("Rowing light")
            column(.temperature)
            column(.wind)
            column(.waves)
            column(.visibility)
            column(.cloudCover)
            ConditionIcon(condition: .daylight).frame(width: Column.sun)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func column(_ c: Condition) -> some View {
        VStack(spacing: 1) {
            ConditionIcon(condition: c)
            Text(c.unit).font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct DayHeader: View {
    let day: Date
    let sun: SunDay?

    var body: some View {
        HStack {
            Text(Format.day(day)).font(.subheadline.weight(.semibold))
            Spacer()
            if let sun {
                Label(Format.time(sun.sunrise), systemImage: "sunrise.fill")
                Label(Format.time(sun.sunset), systemImage: "sunset.fill")
            }
        }
        .font(.caption)
        .symbolRenderingMode(.hierarchical)
        .labelStyle(SunLabelStyle())
        .padding(.top, 8)
    }
}

private struct HourRow: View {
    let hour: ForecastHour

    var body: some View {
        let dark = hour.sunUp == false
        HStack(spacing: 6) {
            Text(Format.time(hour.time))
                .frame(width: Column.time, alignment: .leading)
            TrafficLightDot(light: hour.light, size: 12).frame(width: Column.light)
            cell(Format.number(hour.temperatureC))
            cell(hour.windSpeedMs.map { "\(Format.number($0))–\(Format.number(hour.windGustMs))" } ?? "–")
            cell(Format.number(hour.waveHeightM, digits: 2))
            cell(visibilityText(hour.visibilityM).replacingOccurrences(of: " km", with: ""))
                .foregroundStyle(hour.light(for: ["fog"]).map(\.color) ?? .primary)
            cell(Format.number(hour.cloudCoverPct))
            Image(systemName: dark ? "moon.fill" : "sun.max.fill")
                .font(.caption)
                .foregroundStyle(dark ? Color.indigo : Color.orange)
                .frame(width: Column.sun)
                .accessibilityLabel(dark ? "Sun down" : "Sun up")
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(dark ? 0.6 : 1)
        .padding(.vertical, 2)
    }

    private func cell(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct LegendCard: View {
    @State private var expanded = UserDefaults.standard.string(forKey: "RWScrollTo") == "hourly"

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([Light.green, .amber, .red], id: \.self) { light in
                        HStack(alignment: .top, spacing: 10) {
                            TrafficLightDot(light: light).frame(width: 24)
                            Text(light.title).font(.subheadline)
                        }
                    }
                    Divider()
                    ForEach(Condition.allCases) { c in
                        HStack(alignment: .top, spacing: 10) {
                            ConditionIcon(condition: c).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.unit.isEmpty ? c.title : "\(c.title) (\(c.unit))").font(.subheadline.weight(.semibold))
                                Text(c.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Legend", systemImage: "info.circle").font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// Orange sun symbols, so the sunrise and sunset arrows show in light mode too.
struct SunLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(.orange)
            configuration.title
        }
    }
}
