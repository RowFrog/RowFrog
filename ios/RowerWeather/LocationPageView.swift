import SwiftUI
import TipKit

/// One full-screen location page: rowing light now, daylight, current
/// conditions, the hourly forecast, the launch point on a map, the icon
/// legend, and the credits.
struct LocationPageView: View {
    let club: Club
    let lake: Lake?
    let isHome: Bool
    let forecasts: ForecastStore
    @Environment(\.surface) private var surface
    @AppStorage(Tutorial.seenKey) private var tourSeen = false
    @State private var showHourlyTip = false
    @State private var showLaunchPointTip = false
    @State private var showConditionsTip = false
    @State private var showLakeViewTip = false
    @State private var showRainRadarTip = false
    @State private var showSatelliteTip = false
    @State private var showSourceTip = false
    private let conditionsTip = ConditionsExtrasTip()
    private let lakeViewTip = LakeViewTip()
    private let rainRadarTip = RainRadarTip()
    private let satelliteTip = SatellitePictureTip()
    private let sourceTip = ForecastSourceTip()
    private let hourlyTip = HourlyTip()
    private let launchPointTip = LaunchPointTip()

    var body: some View {
        let forecast = forecasts.forecasts[club.id]
        GeometryReader { geometry in
            // Wide screens (an unfolded iPhone Duo, an iPhone on its side) put the
            // cards below the rowing light in two columns; phones upright keep one.
            let twoColumns = geometry.size.width >= Self.twoColumnWidth
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if let forecast, let now = forecast.current() {
                            NowCard(hour: now, water: forecast.waterTemperature, stale: forecast.isStale())
                            VStack(spacing: 16) {
                                if tourSeen && showRainRadarTip {
                                    TipView(rainRadarTip)
                                }
                                RainRadarCard(point: club.launchPoint)
                            }
                            .id("radar")
                            if let warnings = forecast.warnings {
                                WarningsCard(warnings: warnings, lakeName: lake?.name, town: club.town, checkedAt: forecast.generatedAt)
                                    .id("warnings")
                            }
                            if twoColumns {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(spacing: 16) {
                                        conditionCards(forecast, now: now)
                                        sourceLine(forecast)
                                        LegendCard()
                                    }
                                    VStack(spacing: 16) {
                                        forecastCards(forecast)
                                    }
                                }
                            } else {
                                conditionCards(forecast, now: now)
                                forecastCards(forecast)
                                sourceLine(forecast)
                                LegendCard()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(forecast.attribution, id: \.self) { Text(tr($0)) }
                                if club.isOwnPlace {
                                    Text(tr("Your own place, kept on this iPhone. No waves, water temperature or warnings here."))
                                } else if !club.launchPointVerified {
                                    switch club.source {
                                    case "drv":
                                        Text(tr("Club data: Deutscher Ruderverband e.V. (rudern.de). Launch point geocoded with © OpenStreetMap contributors, ODbL"))
                                    case "oerv":
                                        Text(tr("Club data: Österreichischer Ruderverband (rudern.at). Launch point geocoded with © OpenStreetMap contributors, ODbL"))
                                    case "swissrowing":
                                        Text(tr("Club data: Swiss Rowing (swissrowing.ch). Launch point geocoded with © OpenStreetMap contributors, ODbL"))
                                    default:
                                        Text(tr("Launch point from © OpenStreetMap contributors, ODbL"))
                                    }
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(surface.hasPicture ? 12 : 0)
                            .background(surface.label, in: RoundedRectangle(cornerRadius: 12))
                        } else if forecasts.failed.contains(club.id) {
                            ContentUnavailableView {
                                Label(tr("No forecast"), systemImage: "icloud.slash")
                            } description: {
                                Text(tr("Could not load the forecast. Pull to retry."))
                            }
                        } else {
                            ProgressView().padding(.top, 40)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                    .frame(maxWidth: Self.maxContentWidth)
                    .frame(maxWidth: .infinity)
                }
                .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: forecast != nil))
                .refreshable { await forecasts.load(club.id, force: true) }
                .tipVisibility(conditionsTip, $showConditionsTip)
                .tipVisibility(lakeViewTip, $showLakeViewTip)
                .tipVisibility(rainRadarTip, $showRainRadarTip)
                .tipVisibility(satelliteTip, $showSatelliteTip)
                .tipVisibility(sourceTip, $showSourceTip)
                .tipVisibility(hourlyTip, $showHourlyTip)
                .tipVisibility(launchPointTip, $showLaunchPointTip)
                .task {
                    await forecasts.load(club.id)
                    // Screenshot hook: `-RWScrollTo hourly` (or `warnings`, `conditions`, `radar`, `launchpoint`, `lakeview`, `satellite`, `source`) scrolls to that card.
                    if let target = UserDefaults.standard.string(forKey: "RWScrollTo") {
                        // The lake view loads after the forecast and pushes the cards below it down,
                        // so for cards below it scroll again once it has settled.
                        let waits = ["lakeview", "satellite", "radar", "source"].contains(target) ? [2500, 3000, 3000] : [300]
                        for wait in waits {
                            try? await Task.sleep(for: .milliseconds(wait))
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceLine(_ forecast: ClubForecast) -> some View {
        if let source = forecast.forecastSource {
            VStack(spacing: 16) {
                if tourSeen && showSourceTip {
                    TipView(sourceTip)
                }
                ForecastSourceLine(
                    source: source,
                    choices: forecast.modelChoices ?? [],
                    selected: AppSettings.shared.pickedModel(for: club.id),
                    pickedModelMissing: forecasts.pickedModelMissing.contains(club.id)
                ) { model in
                    AppSettings.shared.pickedModels[club.id] = model
                    await forecasts.load(club.id, force: true)
                }
            }
            .id("source")
        }
    }

    /// From this width (in points) the page shows two columns of cards.
    static let twoColumnWidth: CGFloat = 600
    /// Keeps lines readable on very wide screens.
    static let maxContentWidth: CGFloat = 1000

    @ViewBuilder
    private func conditionCards(_ forecast: ClubForecast, now: ForecastHour) -> some View {
        if let sun = forecast.sunState(at: .now) {
            DaylightCard(state: sun)
        }
        VStack(spacing: 16) {
            if tourSeen && showConditionsTip {
                TipView(conditionsTip)
            }
            ConditionsCard(forecast: forecast, hour: now)
        }
        .id("conditions")
        // The satellite card further down is empty until its picture has loaded, and an
        // empty view never runs its own .task, so this always-shown card loads it.
        .task(id: forecast.lakeId) { await SatellitePictureStore.shared.load(forecast.lakeId) }
        if lake?.hasOutline != false {
            VStack(spacing: 16) {
                if tourSeen && showLakeViewTip {
                    TipView(lakeViewTip)
                }
                LakeViewCard(lakeID: forecast.lakeId, clubID: club.id)
            }
            .id("lakeview")
            VStack(spacing: 16) {
                if tourSeen && showSatelliteTip {
                    TipView(satelliteTip)
                }
                SatellitePictureCard(lakeID: forecast.lakeId)
            }
            .id("satellite")
        }
    }

    @ViewBuilder
    private func forecastCards(_ forecast: ClubForecast) -> some View {
        // Each tip sits above its card and scrolls with it.
        VStack(spacing: 16) {
            if tourSeen && showHourlyTip {
                TipView(hourlyTip)
            }
            HourlyCard(forecast: forecast, stale: forecast.isStale())
        }
        .id("hourly")
        VStack(spacing: 16) {
            if tourSeen && showLaunchPointTip {
                TipView(launchPointTip)
            }
            LaunchPointMapCard(club: club)
        }
        .id("launchpoint")
    }

    private var header: some View {
        VStack(spacing: 4) {
            if isHome {
                Label(tr("Home base"), systemImage: "house.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(club.displayName)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text([lake?.name, club.town].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            if !club.launchPointVerified {
                Label(tr("Launch point not yet confirmed"), systemImage: "mappin.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let forecast = forecasts.forecasts[club.id] {
                let updated = forecast.generatedAt
                if forecast.isStale() {
                    // Old data must not look current: say so plainly, with the day.
                    Label(tr("Forecast out of date: from %@. Pull down to refresh, and check the conditions yourself.", Format.dayTime(updated)), systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else if forecasts.failed.contains(club.id) {
                    Label(tr("Could not update. Showing data from %@.", Format.time(updated)), systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(tr("Updated %@ · Pull down to refresh", Format.time(updated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, surface.hasPicture ? 16 : 0)
        .padding(.vertical, surface.hasPicture ? 10 : 0)
        .background(surface.label, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 24)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content
    @Environment(\.surface) private var surface

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
        .cardBackground(surface)
    }
}

private struct NowCard: View {
    let hour: ForecastHour
    let water: WaterTemperature?
    var stale = false

    var body: some View {
        Card {
            HStack(spacing: 14) {
                TrafficLightDot(light: hour.light, size: 36, stale: stale)
                VStack(alignment: .leading, spacing: 0) {
                    Text(hour.light.title(stale: stale)).font(.title2.bold())
                    Text(tr("For %@", AppSettings.shared.selectedBoat.inSentence))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    SkyIcon(sky: Sky(hour: hour), night: hour.sunUp == false).font(.system(size: 34))
                    Text(Sky(hour: hour).title).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if stale {
                    Label(tr("The forecast is more than 3 hours old. Check the conditions yourself before you go out."), systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if hour.reasons.isEmpty {
                    Label(tr("All conditions are within the limits."), systemImage: "checkmark.circle")
                } else {
                    ForEach(hour.reasons, id: \.self) { reason in
                        Label(reason.explanation, systemImage: reason.symbol)
                            .foregroundStyle(reason.light == .red ? Color.red : Color.orange)
                    }
                }
                ForEach(hour.notes ?? [], id: \.self) { note in
                    Label(note.noteText, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                if let steadier = SteadierBoat.suggestion(for: hour, water: water?.celsius) {
                    Label(steadier.light == .green
                          ? tr("A steadier boat helps: %@ would be green now.", steadier.boat.title)
                          : tr("A steadier boat helps: %@ would only need care now.", steadier.boat.title),
                          systemImage: "figure.rower")
                        .foregroundStyle(.tint)
                }
            }
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(hour.reasons.isEmpty ? tr("Why: all conditions within the limits") : tr("Why: %@", hour.reasons.map(\.explanation).joined(separator: " ")))
            AdviceOnlyNote()
            Divider()
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    TemperatureView(condition: .temperature, celsius: hour.temperatureC, size: 44)
                    if let feels = hour.apparentTemperatureC {
                        Label(tr("Feels like %@", Format.degrees(feels)), systemImage: Condition.feelsLike.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(tr("Feels like %@", Format.temperature(feels)) + ". " + (feelsLikeNote(hour) ?? ""))
                    }
                }
                Spacer()
                TemperatureView(condition: .waterTemperature, celsius: water?.celsius, digits: 1, size: 28)
                Spacer()
                MetricView(title: tr("Waves"), symbol: Condition.waves.symbol, value: Format.waves(hour.waveHeightM), size: 28)
            }
            HStack(alignment: .top) {
                MetricView(title: tr("Visibility"), symbol: Condition.visibility.symbol, value: Format.distance(hour.visibilityM), size: 17)
                Spacer()
                MetricView(title: tr("Rain, hail"), symbol: Condition.precipitation.symbol, value: precipitationText(hour) ?? tr("None"), size: 17)
                Spacer()
                MetricView(title: tr("Ice"), symbol: Condition.ice.symbol, value: tr("No data"), size: 17)
                    .foregroundStyle(.secondary)
            }
            .symbolRenderingMode(.hierarchical)
        }
    }
}

/// The reminder that the light is advice and the rower decides, wherever a
/// decision to go out is made from the app.
struct AdviceOnlyNote: View {
    var body: some View {
        Label(tr("Advice only. You decide whether to go out. When in doubt, ask experienced rowers or stay ashore."), systemImage: "person.fill.questionmark")
            .font(.caption)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
            .fixedSize(horizontal: false, vertical: true)
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
            Label(condition == .temperature ? tr("Air") : tr("Water"), systemImage: condition.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Format.degrees(celsius, digits: digits))
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
        Card(title: tr("Daylight"), symbol: Condition.daylight.symbol) {
            switch state {
            case let .up(sunrise, sunset):
                sunTimes(sunrise: sunrise, sunset: sunset)
                Label(tr("Sun is up. Rowing advised for %@ until sunset.", Format.duration(from: .now, to: sunset)), systemImage: "sun.max.fill")
                    .foregroundStyle(.primary)
            case let .down(nextSunrise, nextSunset):
                sunTimes(sunrise: nextSunrise, sunset: nextSunset)
                Label(tr("Sun is down. Rowing is advised again from sunrise at %@.", Format.time(nextSunrise)), systemImage: "moon.stars.fill")
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

/// A small dial like the Weather app's pressure gauge: an arc from 960 to
/// 1060 hPa with a mark at the current value and the trend arrow inside.
struct PressureGauge: View {
    let hpa: Double?
    let trend: PressureTrend?
    private let range = 960.0...1060.0
    private let sweep = 0.75  // share of the circle the arc covers

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))
            if let hpa {
                let share = (min(max(hpa, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
                Circle()
                    .trim(from: max(0, share * sweep - 0.012), to: min(sweep, share * sweep + 0.012))
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
            }
            Image(systemName: trend?.symbol ?? "minus")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(4)
        .accessibilityElement()
        .accessibilityLabel(tr("Pressure %@ hectopascal, %@", hpa.map { Format.number($0) } ?? "–", trend?.title ?? "–"))
    }
}

/// Columns of the hourly table, shared by the icon header and the rows.
private enum Column {
    /// Wider for "10:00 PM" than for "22:00".
    static var time: CGFloat { AppSettings.shared.timeFormat.usesAMPM ? 64 : 44 }
    static let light: CGFloat = 14
    static let sky: CGFloat = 24
}

private struct HourlyCard: View {
    let forecast: ClubForecast
    var stale = false

    var body: some View {
        Card(title: tr("Next 48 hours"), symbol: "clock") {
            HourlyLegendHeader()
            ForEach(days) { group in
                DayHeader(day: group.day, sun: sunDay(on: group.day))
                ForEach(group.hours) { HourRow(hour: $0, stale: stale) }
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
                .accessibilityLabel(tr("Time"))
            Image(systemName: "circle.fill").font(.system(size: 8)).frame(width: Column.light)
                .accessibilityLabel(tr("Rowing light"))
            Image(systemName: "cloud.sun").frame(width: Column.sky)
                .accessibilityLabel(tr("Weather"))
            column(.temperature)
            column(.wind)
            column(.waves)
            column(.precipitation)
            column(.visibility)
            column(.cloudCover)
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
    var stale = false

    var body: some View {
        let dark = hour.sunUp == false
        HStack(spacing: 6) {
            Text(Format.time(hour.time))
                .frame(width: Column.time, alignment: .leading)
            TrafficLightDot(light: hour.light, size: 12, stale: stale).frame(width: Column.light)
            SkyIcon(sky: Sky(hour: hour), night: dark)
                .font(.callout)
                .frame(width: Column.sky)
            cell(Format.degrees(hour.temperatureC).replacingOccurrences(of: "°", with: ""))
            cell(hour.windSpeedMs.map { "\(Format.windNumber($0))–\(Format.windNumber(hour.windGustMs))" } ?? "–")
            cell(Format.wavesNumber(hour.waveHeightM))
            cell(Format.rainNumber(hour.precipitationMm))
                .foregroundStyle((hour.precipitationMm ?? 0) >= 0.1 ? Color.blue : .primary)
            cell(Format.distanceNumber(hour.visibilityM))
                .foregroundStyle(hour.light(for: ["fog"]).map(\.color) ?? .primary)
            cell(Format.number(hour.cloudCoverPct))
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
        || UserDefaults.standard.integer(forKey: "RWScrollPage") > 0

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
                    HStack(alignment: .top, spacing: 10) {
                        TrafficLightDot(light: .green, stale: true).frame(width: 24)
                        Text(tr("Forecast out of date: more than 3 hours old. Amber and red still show.")).font(.subheadline)
                    }
                    AdviceOnlyNote()
                    Divider()
                    Text(tr("Weather symbols")).font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(Sky.allCases, id: \.self) { sky in
                            HStack(spacing: 8) {
                                SkyIcon(sky: sky).frame(width: 24)
                                Text(sky.title).font(.caption)
                            }
                        }
                    }
                    Text(tr("At night the sun becomes a moon and the row is dimmed.")).font(.caption).foregroundStyle(.secondary)
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
                Label(tr("Legend"), systemImage: "info.circle").font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// Screenshot hook: `-RWScrollPage n` scrolls the page down by n screens
/// (less a little overlap), stopping at the bottom, so a series of screenshots
/// covers the whole page.
struct ScreenshotScroll: ViewModifier {
    let page: Int
    let ready: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), page > 0 {
            content.modifier(PagedScroll(page: page, ready: ready))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct PagedScroll: ViewModifier {
    let page: Int
    let ready: Bool
    @State private var position = ScrollPosition(edge: .top)
    @State private var size: (content: CGFloat, container: CGFloat) = (0, 0)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentSize.height, $0.containerSize.height] } action: { _, new in
                size = (new[0], new[1])
            }
            .task(id: ready) {
                guard ready else { return }
                // Wait for the page to be laid out, then scroll twice in case the
                // first request lands before the scroll view is ready.
                for _ in 0..<50 where size.content <= size.container {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                try? await Task.sleep(for: .seconds(1))
                for _ in 0..<2 {
                    // Bars cover about 150 points of the screen; overlap pages by a few rows.
                    // On a phone on its side that would leave little, so move at least 70 %.
                    let target = CGFloat(page) * max(size.container - 260, size.container * 0.7)
                    if target < size.content - size.container {
                        position.scrollTo(y: target)
                    } else {
                        position.scrollTo(edge: .bottom)
                    }
                    try? await Task.sleep(for: .seconds(1))
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
