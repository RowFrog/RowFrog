import Charts
import MapKit
import SwiftUI
import TipKit

/// The "Current conditions" card on a club page: small tiles, each with its
/// value, a short detail and a small graphic. Tapping a tile opens a larger
/// view with a chart that can be dragged from yesterday to the next 7 days,
/// the rowing limits and advice.
struct ConditionsCard: View {
    let forecast: ClubForecast
    let hour: ForecastHour
    /// The club, for the weather maps in the larger views.
    var club: Club?

    var body: some View {
        let data = ConditionData(forecast: forecast, now: hour, radar: club.flatMap { RadarStore.shared.radar(at: $0.launchPoint) })
        Card(title: tr("Current conditions"), symbol: "gauge.with.dots.needle.33percent", legend: .conditions) {
            HStack(spacing: 10) {
                SkyIcon(sky: data.sky, night: hour.sunUp == false).scaledSystemFont(size: 36, relativeTo: .largeTitle, maxGrowth: 1.35)
                VStack(alignment: .leading, spacing: 0) {
                    Text(data.sky.title).font(.headline)
                    Text(tr("%@ · feels like %@", Format.degrees(hour.temperatureC), Format.degrees(hour.apparentTemperatureC)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ConditionTiles(forecast: forecast, hour: hour, club: club)
        }
    }
}

/// The tiles of Current conditions, two by two, each opening its chart: in their own
/// card, or inside the top tile when that is opened.
struct ConditionTiles: View {
    let forecast: ClubForecast
    let hour: ForecastHour
    var club: Club?
    @State private var open: Condition?
    @State private var showingCurrent = false
    @State private var showingLevel = false

    /// The values in tile order, as the larger views swipe through them: on a river or a
    /// lowered lake without ice, whose place the current or water level tile takes.
    static func order(_ forecast: ClubForecast) -> [Condition] {
        forecast.river == nil && forecast.waterLevel?.isLowered != true ? Condition.tileOrder : Condition.tileOrder.filter { $0 != .ice }
    }

    var body: some View {
        let data = ConditionData(forecast: forecast, now: hour, radar: club.flatMap { RadarStore.shared.radar(at: $0.launchPoint) },
                                 radarStatus: club.flatMap { RadarStore.shared.status(at: $0.launchPoint) })
        // Pairs that belong together share a row, and all tiles are as tall as the tallest.
        ConditionTileGrid(spacing: 8) {
            ForEach(Condition.tileOrder) { condition in
                tile(condition, data: data)
            }
        }
        .detailCover(item: $open) { condition in
            ConditionDetailView(condition: condition, data: data, order: Self.order(forecast), club: club)
        }
        .detailCover(isPresented: $showingCurrent) {
            if let river = forecast.river { CurrentDetailView(river: river) }
        }
        .detailCover(isPresented: $showingLevel) {
            if let level = forecast.waterLevel { WaterLevelDetailView(level: level) }
        }
        .task {
            // Screenshot hook: `-RWOpenCondition wind` opens that view.
            // Only on the page `-RWOpenClub` opens: the pages beside it would race it for the sheet.
            let page = UserDefaults.standard.string(forKey: DefaultsKey.openClub)
            if let raw = UserDefaults.standard.string(forKey: DefaultsKey.openCondition), page == nil || page == forecast.clubId {
                try? await Task.sleep(for: .milliseconds(500))
                open = Condition(rawValue: raw)
            }
        }
    }

    /// One tile: on a river the Current tile takes the ice tile's place, on a lake let
    /// down for the winter the Water level tile.
    @ViewBuilder private func tile(_ condition: Condition, data: ConditionData) -> some View {
        if condition == .ice, let river = forecast.river {
            Button {
                showingCurrent = true
                RiverCurrentTip().invalidate(reason: .actionPerformed)
            } label: {
                CurrentTile(river: river)
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Opens the water level and current"))
        } else if condition == .ice, let level = forecast.waterLevel, level.isLowered {
            Button {
                showingLevel = true
                WaterLevelTip().invalidate(reason: .actionPerformed)
            } label: {
                WaterLevelTile(level: level)
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Opens the lake's water level"))
        } else {
            Button {
                open = condition
            } label: {
                ConditionTile(condition: condition, data: data)
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Opens a chart and more about this value"))
            .accessibilityIdentifier("condition-\(condition.rawValue)")
        }
    }
}

extension View {
    /// The tile that sets the light gets a faint wash and a thin rim in the light's colour
    /// (owner's pick T2, 5 Nov 2026); the cold-water tile the same in blue (W2). To go back
    /// to T1 (coloured value only), make this return `self`; for W1, skip it for blue.
    @ViewBuilder func causeHighlight(_ tint: Color?) -> some View {
        if let tint {
            background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.55), lineWidth: 1.5))
        } else {
            self
        }
    }
}

/// A value the closed top tile hides, as one line under its sun line while it counts for
/// the rowing light (the "smart peek"): with its tile's own title, value and short line,
/// so it reads the same as the tile it stands for, in either language.
struct TilePeekLine: View {
    let condition: Condition
    let data: ConditionData

    var body: some View {
        let tile = ConditionTile(condition: condition, data: data)
        let light = condition.cause(in: data.now)
        // One text size, as the sun line above; the value takes the colour of the light it
        // sets, as the reason lines do, so no dot is needed (owner's pick P3, 5 Nov 2026).
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(condition.title, systemImage: condition.symbol)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(tile.value)
                .fontWeight(.semibold)
                .foregroundStyle(light?.causeTint ?? .primary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(verbatim: "·")
                tile.detailLine
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .font(.subheadline)
        .symbolRenderingMode(.hierarchical)
        .accessibilityElement(children: .combine)
        .accessibilityValue(light?.title ?? "")
    }
}

/// The forecast around one hour, as the tiles and larger views need it.
struct ConditionData {
    let forecast: ClubForecast
    let now: ForecastHour
    /// Yesterday to 7 days ahead when the backend sends it, else the next 48 hours.
    let timeline: [ForecastHour]
    /// DWD's radar at the launch point, read while the club page is open.
    let radar: RainRadar?
    /// Why there is no radar: still loading, or it could not be read; the rain tile marks it.
    let radarStatus: RadarStatus?

    /// The limits of the boat in use at the club.
    var limits: RowingLimits { AppSettings.shared.limits(at: forecast.clubId) }

    init(forecast: ClubForecast, now: ForecastHour, radar: RainRadar? = nil, radarStatus: RadarStatus? = nil) {
        self.forecast = forecast
        self.radar = radar
        self.radarStatus = radarStatus
        let outlook = forecast.outlook ?? []
        timeline = (outlook.isEmpty ? forecast.hours : outlook).sorted { $0.time < $1.time }
        // The rowing hours have no UV index; the outlook has it for the same hour.
        var now = now
        if let same = timeline.first(where: { $0.time == now.time }) {
            now.uvIndex = now.uvIndex ?? same.uvIndex
            now.cloudCoverMidPct = now.cloudCoverMidPct ?? same.cloudCoverMidPct
            now.cloudCoverHighPct = now.cloudCoverHighPct ?? same.cloudCoverHighPct
        }
        self.now = now
    }

    /// Hours from the shown hour (now, or the hour picked in the 48 hours); negative is earlier.
    func x(_ date: Date) -> Double { date.timeIntervalSince(now.time) / 3600 }

    /// Whether the shown hour is the current one, not one picked further on.
    var isNow: Bool { now.time <= .now && Date.now.timeIntervalSince(now.time) < 3600 }

    /// The moment the card is about: the clock now, or the picked hour.
    var moment: Date { isNow ? .now : now.time }

    /// "Now", or the picked hour: "Tomorrow 15:00".
    var nowLabel: String { isNow ? tr("Now") : Format.dayTime(now.time) }

    var next24: [ForecastHour] { timeline.filter { (0..<24).contains(x($0.time)) } }
    /// The radar from the shown moment on, while its nowcast still reaches at
    /// least half an hour ahead; rain then comes from the radar, later from the forecast.
    var radarAhead: RainRadar? { radar?.ahead(of: moment) }
    /// The radar's words for rain from the shown moment on, while it reaches.
    var rainOutlook: RainOutlook? { radarAhead.map { RainOutlook(radar: $0, hours: timeline) } }

    /// The first forecast hour with rain that is still to come after the radar's
    /// two hours (or after the shown moment without radar), and when that rain
    /// starts: the hour's own start, but never before the radar's end (owner's
    /// pick, 15 Nov 2026: "Regen ab 13:55" after a dry radar). The backend puts
    /// each hour's rain under the hour it fell (decision 0043), so the 13:00 row
    /// is 13:00 to 14:00. Without radar a start in the running hour stays at the
    /// hour's start; the lines then say "this hour" rather than a time already past.
    var forecastRain: (hour: ForecastHour, from: Date)? {
        let radarEnd = radarAhead?.end
        guard let wet = next24.first(where: { $0.isWet && $0.time.addingTimeInterval(3600) > (radarEnd ?? moment) }) else { return nil }
        return (wet, radarEnd.map { max(wet.time, $0) } ?? wet.time)
    }

    /// Drizzle and the like whose amount stays under 0.1 mm: named, with how little it is.
    private func trace(_ kind: String) -> (value: String, detail: String, fromRadar: Bool) {
        (kind, AppSettings.shared.rainUnit == .millimeters ? tr("Under %@", Format.rain(0.1)) : tr("Barely measurable"), false)
    }

    /// What the forecast names for the shown hour when its amount stays under
    /// 0.1 mm, which the radar cannot see either.
    var traceNow: String? { (now.precipitationMm ?? 0) < 0.1 ? Sky(hour: now).precipitationKind : nil }
    var future: [ForecastHour] { timeline.filter { x($0.time) >= 0 } }

    /// The line under the waves value: where the wind comes from over the lake.
    var wavesDetail: String {
        guard let fetch = now.fetchM else { return "" }
        return fetch < 50 ? tr("Wind blows off the shore") : tr("%@ open water upwind", Format.distance(fetch))
    }

    /// The line under the visibility value: fog now, or when it comes.
    var visibilityDetail: String {
        if (now.visibilityM ?? .infinity) < 1000 { return tr("Fog") }
        guard let fog = next24.first(where: { ($0.visibilityM ?? .infinity) < 1000 }) else { return tr("No fog") }
        return tr("Fog from %@", Format.time(fog.time))
    }

    /// What falls at the shown moment and what comes next, as the rain tile
    /// and the top tile both show it: the radar for two hours, then the forecast.
    var rainLines: (value: String, detail: String, fromRadar: Bool) {
        func later() -> String {
            guard let wet = forecastRain else { return tr("Dry next 24 h") }
            let kind = Sky(hour: wet.hour).precipitationKind ?? tr("Rain")
            // An hour that has begun has no start to name (owner's pick, 15 Nov 2026).
            return wet.from <= moment ? tr("%@ this hour", kind) : tr("%@ from %@", kind, Format.time(wet.from))
        }
        if let outlook = rainOutlook {
            // The radar's dry wins over the forecast's rain, but not over its drizzle under 0.1 mm, which it cannot see.
            let trace = outlook.now == nil ? traceNow : nil
            let value = outlook.now ?? trace ?? tr("Dry")
            // While it rains, what comes next.
            if let next = outlook.next { return (value, next.text, next.fromRadar) }
            if let trace { return self.trace(trace) }
            return (value, later(), false)
        }
        if (now.precipitationMm ?? 0) >= 0.1 { return (Format.rain(now.precipitationMm), Sky(hour: now).precipitationKind ?? "", false) }
        if let trace = traceNow { return self.trace(trace) }
        return (tr("Dry"), later(), false)
    }

    /// The sky word and symbol for the shown moment, matched to the rain tile:
    /// while the radar covers the moment it decides whether anything falls, so
    /// the headline never says "Rain" over a "Dry" rain tile, or the other way
    /// round. The forecast still names how cloudy it is and what falls.
    var sky: Sky {
        let model = Sky(hour: now)
        guard let ahead = radarAhead else { return model }
        let wet = model.precipitationKind != nil
        if ahead.rainingNow {
            if wet { return model }
            if (now.temperatureC ?? 10) <= 0 { return .snow }
            return (ahead.steps.first?.mmPerHour ?? 0) >= 10 ? .heavyRain : .rain
        }
        // Drizzle under 0.1 mm stays: the radar cannot see it, and the rain tile names it.
        return wet && traceNow == nil ? Sky(code: nil, cloudCoverPct: now.cloudCoverPct, precipitationMm: 0) : model
    }
    var water: WaterTemperature? { forecast.waterTemperature }
    /// Without a station: the satellite reading carried forward, else the ice
    /// model's water temperature, worked out from the air temperatures of the
    /// last weeks. Shown marked as estimated; the rowing light's cold-water
    /// rules only use measurements.
    var estimatedWater: Double? { forecast.estimatedWaterC }
    /// The satellite reading behind `estimatedWater`, when there is one.
    var satelliteWater: SatelliteWaterReading? { water == nil ? forecast.waterEstimate?.reading : nil }

    func points(_ value: (ForecastHour) -> Double?) -> [ChartPoint] {
        timeline.compactMap { h in value(h).map { ChartPoint(x: x(h.time), y: $0) } }
    }

    /// Current DWD warnings for the place whose event contains one of these words.
    func warnings(_ words: [String]) -> [DWDWarning] {
        (forecast.warnings?.items ?? []).filter { w in
            !w.isLake && (w.expires ?? .distantFuture) > now.time && words.contains { w.event.uppercased().contains($0) }
        }
    }

    /// False outside Germany, where DWD's warnings do not reach (see Warnings.localChecked).
    var warningsChecked: Bool { forecast.warnings?.localChecked ?? true }

    func warningNames(_ words: [String]) -> String {
        guard warningsChecked else { return tr("Not checked here") }
        let found = warnings(words)
        // "None" alone is the rain value ("Kein Niederschlag"): the warnings say "Keine".
        guard !found.isEmpty else { return tr("None", key: "Warning: none") }
        let german = AppSettings.shared.resolvedLanguage == .german
        return found.map { german ? $0.event : ($0.english?.event ?? $0.event) }.joined(separator: ", ")
    }

    /// The first run of hours in which `test` holds, as start and end.
    func firstRun(in hours: [ForecastHour], where test: (ForecastHour) -> Bool) -> (start: Date, end: Date)? {
        guard let i = hours.firstIndex(where: test) else { return nil }
        var j = i
        while j + 1 < hours.count && test(hours[j + 1]) { j += 1 }
        return (hours[i].time, hours[j].time.addingTimeInterval(3600))
    }

    func span(_ run: (start: Date, end: Date)) -> String {
        "\(Format.dayTime(run.start))–\(Format.time(run.end))"
    }
}

/// Clothing advice from the feels-like temperature, shared by the air and
/// feels-like views so they never disagree.
func clothingAdvice(feelsLike: Double?) -> String {
    guard let feels = feelsLike else { return tr("Dress in layers you can take off.") }
    if feels < 5 {
        return tr("Feels colder than %@: dress in layers, wear gloves or pogies and a hat, and keep a dry set in the boathouse.", Format.temperature(5))
    }
    if feels >= 25 {
        return tr("Feels %@ or more: drink before and during the outing and protect yourself from the sun.", Format.temperature(25))
    }
    return tr("Dress in layers you can take off.")
}

// MARK: - Larger views

struct ChartPoint: Identifiable {
    let x: Double
    let y: Double
    var id: Double { x }
}

struct ChartLine: Identifiable {
    /// `area`: a soft filled area behind the lines (the cloud chart's "All", owner's pick A, 14 Nov 2026).
    enum Kind { case line, bars, area }
    let name: String
    let color: Color
    var kind: Kind = .line
    let points: [ChartPoint]
    /// Dashed, for a forecast after measurements.
    var dashed = false
    /// Bars only: their width, and the hours where they stand in for the
    /// other bars (the radar's quarter hours over the forecast's hours).
    var barWidth: CGFloat = 5
    var covers: ClosedRange<Double>? = nil
    /// Bars only: hours past each point's x where the bar is drawn. A rain bar
    /// stands for the hour from its time on (decision 0043), so it is drawn in
    /// the middle of that hour; scrubbing and the values still read the point's x.
    var drawOffset: Double = 0
    var id: String { name }
}

/// The cloud chart's colours, light and dark mode (mock-up option A, same numbers on the website).
enum CloudColours {
    static let all = adaptive(0xC7C7CC, 0x636366)
    static let high = adaptive(0x8EC9FF, 0xA8D8FF)
    static let mid = adaptive(0x2F80ED, 0x4C9BFF)
    static let low = adaptive(0x1B2F8A, 0x7D8CFF)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

struct ChartLimit {
    let value: Double
    let color: Color
    let label: String
}

/// What a larger view shows; values in the user's units.
struct ConditionDetail {
    var value: String
    var note: String
    var big: AnyView? = nil
    var unit: String = ""
    var lines: [ChartLine] = []
    var limits: [ChartLimit] = []
    /// Why the limits are where they are, behind ⓘ.
    var limitInfo: String? = nil
    var yDomain: ClosedRange<Double>? = nil
    var logScale = false
    /// Change in 3 hours that counts as rising or falling; nil for no arrows.
    var trendStep: Double? = nil
    /// Arrows with the wind direction instead of the trend.
    var windArrows = false
    /// The chart shows past measurements only and does not scroll.
    var history = false
    var chartNote: String? = nil
    var facts: [(String, String)] = []
    var twoColumnFacts = false
    var rowing: String
    var source: String
}

extension View {
    /// A value's view: a sheet on the iPhone, full screen on the iPad, where a
    /// sheet was too small to show the chart and the map together.
    @ViewBuilder
    func detailCover<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        if Orientation.isPad {
            fullScreenCover(item: item) { content($0).diagnosisNamed("value detail") }
        } else {
            sheet(item: item) { content($0).diagnosisNamed("value detail") }
        }
    }

    @ViewBuilder
    func detailCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        if Orientation.isPad {
            fullScreenCover(isPresented: isPresented) { content().diagnosisNamed("value detail") }
        } else {
            sheet(isPresented: isPresented) { content().diagnosisNamed("value detail") }
        }
    }
}

struct ConditionDetailView: View {
    let data: ConditionData
    @Environment(\.dismiss) private var dismiss
    @State private var condition: Condition
    /// Which way the last change went, for the slide.
    @State private var forward = true
    @State private var showLimits = UserDefaults.standard.bool(forKey: DefaultsKey.limitInfo)
    /// Chart lines switched off from the legend, per view. Kept while swiping
    /// between views; a new sheet starts with every line on.
    @State private var hiddenLines: [Condition: Set<String>] = [:]
    /// Where the chart sits, so a drag on it moves the time instead of the view.
    /// Kept outside SwiftUI's state: it changes on every frame of scrolling,
    /// and only a swipe's end reads it.
    @State private var chartFrame = ChartFrame()
    /// The jump menu's titles with each view's value, worked out once.
    @State private var menuTitles: [Condition: String] = [:]
    @AppStorage(Tutorial.seenKey) private var tourSeen = false
    private let scrubTip = ChartScrubTip()
    @State private var showScrubTip = false
    private let mapTip = WeatherMapTip()
    @State private var showMapTip = false
    /// The hour of the chart's blue line and of the map, kept while swiping.
    @State private var time = DetailTime()
    /// Compact height: a phone on its side, where the map sits beside the chart.
    @Environment(\.verticalSizeClass) private var verticalSize
    /// The view's size: the iPad shows it full screen, with the map beside the chart in landscape.
    @State private var size: CGSize = .zero

    /// The map beside the chart: a phone on its side, or a wide screen (iPad in landscape).
    private var sideBySide: Bool {
        verticalSize == .compact || (size.width > size.height && size.width >= 900)
    }

    /// The views the arrows and swipes go through: every condition, or only
    /// the values of the top tile when opened from there.
    private let order: [Condition]
    /// The club, for the weather maps.
    private let club: Club?

    init(condition: Condition, data: ConditionData, order: [Condition] = Condition.tileOrder, club: Club? = nil) {
        self.data = data
        self.club = club
        self.order = order.contains(condition) ? order : Condition.tileOrder
        _condition = State(initialValue: condition)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                page(condition)
                    .id(condition)
                    .transition(.push(from: forward ? .trailing : .leading))
                    .padding()
            }
            .coordinateSpace(name: Self.space)
            .accessibilityIdentifier("condition-detail")
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .simultaneousGesture(swipe)
            // The views before and after float over the page, as the club page's bar.
            .safeAreaInset(edge: .bottom) { neighbours(of: condition) }
            // The new view's map card reports its own hours.
            .onChange(of: condition) { time.mapHours = nil }
            .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: DefaultsKey.scrollPage), ready: true))
            .tipVisibility(scrubTip, $showScrubTip)
            .tipVisibility(mapTip, $showMapTip)
            // The chain's link tip follows once the map tip is closed.
            .onChange(of: showMapTip) { was, now in if was && !now { MapLinkTip.mapTipClosed = true } }
            .navigationTitle(condition.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            // The title is the menu to jump to another value, as Apple's title menus
            // (owner's pick A, 12 Nov 2026); the X takes the top left.
            .toolbarTitleMenu { jumpPicker }
            .task { if menuTitles.isEmpty { menuTitles = Dictionary(uniqueKeysWithValues: order.map { ($0, menuTitle($0)) }) } }
        }
    }

    private static let space = "conditionDetail"
    /// The map card under the chart in portrait. Every page puts it at the same
    /// height: a header of at least `headerHeight`, the chart, then one line for
    /// the legend and "Back to now" (owner, 13 Nov 2026): chart bottom to map top
    /// 6 + 20 + 14 = 40 pt, more only at larger text, equally on every page.
    static let mapHeight: CGFloat = 200
    /// As tall as the largest graphic (the wind dial and the pressure gauge, 90 pt).
    static let headerHeight: CGFloat = 90

    final class ChartFrame {
        var rect: CGRect = .zero
        /// The map card, whose slider is dragged sideways too.
        var map: CGRect = .zero
    }

    /// The map a view shows: the rain forecast for rain, else the value's own.
    private func mapLayer(_ condition: Condition) -> WeatherMapLayer? {
        condition == .precipitation ? .rain : WeatherMapLayer(condition: condition)
    }

    @ViewBuilder
    private func page(_ condition: Condition) -> some View {
        let detail = ConditionDetail(condition, data)
        // The big number is the value at the chart's blue line; past
        // measurements (water) keep the measured value.
        let shown = detail.history || detail.lines.isEmpty ? data : data.at(time.hour)
        let head = shown.now.time == data.now.time ? detail : ConditionDetail(condition, shown)
        let hidden = hiddenLines[condition] ?? []
        let layer = detail.history || detail.lines.isEmpty ? nil : mapLayer(condition)
        // Waves have no weather map: the lake view's waves take its place (owner, 13 Nov 2026).
        let lakeMap = condition == .waves && !detail.history && !detail.lines.isEmpty
        VStack(alignment: .leading, spacing: 14) {
            if let club, layer != nil || lakeMap, sideBySide {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        top(condition, detail, head: head, shown: shown, hidden: hidden)
                    }
                    .frame(maxWidth: .infinity)
                    // As tall as the chart beside it on the iPad.
                    mapSlot(detail, layer: layer, club: club, hidden: hidden, height: verticalSize == .compact ? 230 : 300)
                        .frame(maxWidth: .infinity)
                }
            } else {
                top(condition, detail, head: head, shown: shown, hidden: hidden)
                if let club, layer != nil || lakeMap {
                    // After the chart's tip, so one tip shows at a time.
                    if mapTipShown && layer != nil {
                        TintedTipView(mapTip)
                    }
                    mapSlot(detail, layer: layer, club: club, hidden: hidden, height: Self.mapHeight)
                }
            }
            if let info = detail.limitInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation { showLimits.toggle() }
                    } label: {
                        Label(tr("About the limits"), systemImage: "info.circle")
                            .font(.subheadline)
                            .tapArea(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 12))
                    }
                    if showLimits {
                        Text(info)
                            .font(.footnote)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            ConditionFacts(facts: detail.facts, twoColumns: detail.twoColumnFacts)
            if condition == .waterTemperature, let water = data.water, let station = water.station, let place = station.coordinate {
                WaterStationMap(station: station, place: place)
            }
            Label(detail.rowing, systemImage: "figure.rower")
                .font(.subheadline)
            Text(detail.source).font(.caption2).foregroundStyle(.secondary)
            DetailUnitRow(condition: condition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The big number and the chart with its legend.
    @ViewBuilder
    private func top(_ condition: Condition, _ detail: ConditionDetail, head: ConditionDetail, shown: ConditionData, hidden: Set<String>) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(head.value).valueFont(size: 40).minimumScaleFactor(0.6).lineLimit(1)
                    .contentTransition(.numericText())
                // Two lines kept free (the hidden text), so scrubbing never makes the chart jump.
                ZStack(alignment: .topLeading) {
                    Text(verbatim: " \n ").hidden()
                    Text(Self.unbroken(shown.now.time == data.now.time ? head.note : [Format.dayTime(shown.now.time), head.note].filter { !$0.isEmpty }.joined(separator: " · ")))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            Spacer(minLength: 0)
            // The tile's graphic, larger, where the value has no bigger one of its own.
            if let big = head.big {
                big
            } else if condition != .ice {
                // Scaling does not change the space a view takes, so it gets its scaled size.
                let width: CGFloat = condition == .humidity || condition == .cloudCover ? 78 : 46
                ConditionGraphic(condition: condition, data: shown)
                    .frame(width: width, height: ConditionTile.graphicHeight)
                    .scaleEffect(1.6)
                    .frame(width: width * 1.6, height: ConditionTile.graphicHeight * 1.6)
            }
        }
        .frame(minHeight: Self.headerHeight)
        .accessibilityElement(children: .contain)
        if !detail.lines.isEmpty {
            if tourSeen && showScrubTip {
                TintedTipView(scrubTip)
            }
            ConditionChart(detail: detail, data: data, time: time, hidden: hidden,
                           legend: detail.lines.count > 1 ? AnyView(legend(detail, condition: condition, hidden: hidden)) : nil)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ChartFrameKey.self, value: geo.frame(in: .named(Self.space)))
                    }
                }
                .onPreferenceChange(ChartFrameKey.self) { chartFrame.rect = $0 }
        }
    }

    /// A note that breaks only between its parts ("Gusts 3 m/s · from SW"), never
    /// inside one, so the break does not move with each digit or wind direction.
    /// Sentences (ice, water forecast) still break where they need to.
    static func unbroken(_ note: String) -> String {
        note.components(separatedBy: " · ")
            .map { $0.count > 24 ? $0 : $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: " · ")
    }

    /// The weather map tip, above the map card in portrait once the chart's tip is closed.
    private var mapTipShown: Bool {
        tourSeen && showMapTip && !showScrubTip && !sideBySide
    }

    /// The weather map, or for waves the lake view's waves.
    @ViewBuilder
    private func mapSlot(_ detail: ConditionDetail, layer: WeatherMapLayer?, club: Club, hidden: Set<String>, height: CGFloat) -> some View {
        if let layer {
            mapCard(detail, layer: layer, club: club, hidden: hidden, height: height)
        } else {
            DetailLakeCard(lakeID: data.forecast.lakeId, clubID: club.id, data: data, time: time, height: height)
        }
    }

    /// The weather map under (or beside) the chart, with the slim chart for its full-screen view.
    private func mapCard(_ detail: ConditionDetail, layer: WeatherMapLayer, club: Club, hidden: Set<String>, height: CGFloat) -> some View {
        DetailMapCard(layer: layer, club: club, data: data, time: time,
                      slimChart: AnyView(ConditionChart(detail: detail, data: data, time: time, hidden: hidden, compact: true)),
                      height: height, symbol: condition.symbol)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: MapCardFrameKey.self, value: geo.frame(in: .named(Self.space)))
                }
            }
            .onPreferenceChange(MapCardFrameKey.self) { chartFrame.map = $0 }
    }

    /// The chart's lines; a tap switches one off or on again. One stays on.
    private func legend(_ detail: ConditionDetail, condition: Condition, hidden: Set<String>) -> some View {
        HStack(spacing: 12) {
            ForEach(detail.lines) { line in
                let off = hidden.contains(line.name)
                Button {
                    var set = hidden
                    if off {
                        set.remove(line.name)
                    } else if detail.lines.count - set.count > 1 {
                        set.insert(line.name)
                    }
                    withAnimation(.easeInOut(duration: 0.2)) { hiddenLines[condition] = set }
                } label: {
                    // A hidden line keeps its colour (a grey entry would look like the
                    // grey "All" cloud line): an empty ring and struck-through name.
                    Label {
                        Text(line.name).strikethrough(off)
                    } icon: {
                        // The dashed forecast gets a dashed dot, so it reads apart
                        // from the measured line of the same colour.
                        Image(systemName: line.dashed ? (off ? "circle.dashed" : "circle.dashed.inset.filled") : (off ? "circle" : "circle.fill"))
                    }
                    .foregroundStyle(line.color)
                    .opacity(off ? 0.45 : 1)
                    // 44 pt tall to tap, and half the gap to the next entry.
                    .tapArea(EdgeInsets(top: 14, leading: 6, bottom: 14, trailing: 6))
                }
                .buttonStyle(.plain)
                .accessibilityValue(off ? tr("Hidden") : tr("Shown"))
                .accessibilityHint(tr("Shows or hides this line in the chart"))
            }
        }
        .font(.caption2)
    }

    /// The views before and after, which a swipe opens too: two glass buttons
    /// floating at the bottom, 44 pt tall, as the club page's bar. Each shows the
    /// arrow and the neighbour's own symbol at a fixed width, so the buttons keep
    /// their size while swiping; VoiceOver reads the neighbour's name (owner's pick
    /// V2, 12 Nov 2026, decision 0027).
    private func neighbours(of condition: Condition) -> some View {
        HStack(spacing: 12) {
            neighbourButton(condition, by: -1)
            Spacer(minLength: 0)
            neighbourButton(condition, by: 1)
        }
        .tint(.primary)
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    /// Width of a neighbour button: arrow and symbol side by side.
    static let neighbourWidth: CGFloat = 76

    private func neighbourButton(_ condition: Condition, by offset: Int) -> some View {
        let next = neighbour(of: condition, by: offset)
        let arrow = Image(systemName: offset < 0 ? "chevron.left" : "chevron.right").font(.subheadline.weight(.semibold))
        let symbol = ConditionIcon(condition: next).font(.title3)
        return Button { step(offset) } label: {
            HStack(spacing: 8) {
                if offset < 0 { arrow; symbol } else { symbol; arrow }
            }
            .frame(width: Self.neighbourWidth, height: 44)
            .contentShape(Capsule())
        }
        .floatingControl(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(next.title)
        .accessibilityAddTraits(.isButton)
    }

    private func neighbour(of condition: Condition, by offset: Int) -> Condition {
        let i = order.firstIndex(of: condition) ?? 0
        return order[(i + offset + order.count) % order.count]
    }

    private func step(_ offset: Int) {
        forward = offset > 0
        withAnimation(.easeInOut(duration: 0.25)) { condition = neighbour(of: condition, by: offset) }
    }

    /// A sideways swipe outside the chart opens the next or previous view.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .named(Self.space))
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 2 else { return }
                // A chart that can't be dragged ignores it too, so a drag on any chart never changes the view.
                if chartFrame.rect.contains(value.startLocation) || chartFrame.map.contains(value.startLocation) { return }
                step(dx < 0 ? 1 : -1)
            }
    }

    /// The title's menu: every view with its value.
    private var jumpPicker: some View {
        Picker(tr("Go to"), selection: Binding(get: { condition }, set: { new in
            forward = (order.firstIndex(of: new) ?? 0) > (order.firstIndex(of: condition) ?? 0)
            withAnimation(.easeInOut(duration: 0.25)) { condition = new }
        })) {
            ForEach(order) { c in
                Label(menuTitles[c] ?? c.title, systemImage: c.symbol).tag(c)
            }
        }
        .pickerStyle(.inline)
    }

    private func menuTitle(_ c: Condition) -> String {
        let value = ConditionDetail(c, data).value
        return value.isEmpty ? c.title : "\(c.title) · \(value)"
    }
}

private struct MapCardFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct ChartFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// The chart of a larger view: 24 hours visible, dragged sideways from
/// yesterday to 7 days ahead, limits as dashed lines, and one arrow per
/// 3 hours on top (rising, falling, steady; or where the wind blows to).
/// The limit names stay at the left edge while the chart slides under them.
///
/// A blue line marks the hour of the big number above the chart. Hold, then
/// slide moves it, and it stays where the finger lets go. A green badge at
/// the bottom shows the map's hour (with a chain while linked, outlined under
/// a dashed line while not), and a thin green band the hours that have maps.
private struct ConditionChart: View {
    let detail: ConditionDetail
    let data: ConditionData
    let time: DetailTime
    /// Lines switched off in the legend.
    var hidden: Set<String> = []
    /// Slim, without the line underneath: the time bar of the full-screen map.
    var compact = false
    /// The chart's lines to switch off and on, left in the line under the chart.
    var legend: AnyView? = nil
    /// The line under the chart: 20 pt, growing with the text size.
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let start = DetailTime.start
    /// The hour at the left edge of the visible 24 hours.
    @State private var scrollX: Double
    /// The hour under the finger while scrubbing (hold, then slide), as in the Stocks app.
    /// Screenshot hook: `-RWChartSelect 5` shows the scrub line five hours from now.
    @State private var selectedX: Double? = UserDefaults.standard.object(forKey: DefaultsKey.chartSelect) != nil
        ? UserDefaults.standard.double(forKey: DefaultsKey.chartSelect) : nil

    init(detail: ConditionDetail, data: ConditionData, time: DetailTime, hidden: Set<String> = [], compact: Bool = false, legend: AnyView? = nil) {
        self.detail = detail
        self.data = data
        self.time = time
        self.hidden = hidden
        self.compact = compact
        self.legend = legend
        _scrollX = State(initialValue: detail.history ? Self.start : time.scrollX)
    }

    /// The map's colour on the chart (strip of map hours, marker line, badge): teal, owner's pick
    /// 14 Nov 2026. Green read as the rowing light, grey as "no forecast".
    static let mapGreen = Color(.systemTeal)

    /// The blue line and the map's marker. The map's badge sits at the bottom and
    /// shows the link: linked, a filled pill with a chain that the blue line ends
    /// on; unlinked, an outlined badge under a dashed full-height green line, so
    /// both show even at the same hour.
    @ViewBuilder
    private func lines(plot: CGRect, mapX: Double?, onScreen: (Double) -> CGFloat?) -> some View {
        let green = Self.mapGreen
        let badgeTop = plot.maxY - 17
        let joined = time.linked && mapX != nil
        ZStack(alignment: .topLeading) {
            if let x = markerX, let px = onScreen(x) {
                Rectangle().fill(Color.blue)
                    .frame(width: 1.5, height: max((joined ? badgeTop : plot.maxY) - plot.minY, 0))
                    .offset(x: px - 0.75, y: plot.minY)
            }
            if let m = mapX, let px = onScreen(m) {
                if !joined {
                    Path { path in
                        path.move(to: CGPoint(x: px, y: plot.minY))
                        path.addLine(to: CGPoint(x: px, y: badgeTop))
                    }
                    .stroke(green, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                Group {
                    if joined {
                        HStack(spacing: 1) {
                            Image(systemName: "link")
                            Image(systemName: "map.fill")
                        }
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 15)
                        .background(green, in: Capsule())
                    } else {
                        Image(systemName: "map.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(green)
                            .frame(width: 17, height: 15)
                            .background(Color(.systemBackground), in: Capsule())
                            .overlay(Capsule().strokeBorder(green, lineWidth: 1.5))
                    }
                }
                .fixedSize()
                .frame(width: 25, height: 15)
                .offset(x: px - 12.5, y: badgeTop)
                .opacity(time.mapOutOfRange ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The persistent blue line; past measurements only show it while touched,
    /// or at the picked hour when the detail was opened from the 48 hours.
    private var markerX: Double? {
        if let x = selectedX { return x.rounded() }
        if detail.history { return data.isNow ? nil : 0 }
        return time.hour
    }

    private struct Arrow: Identifiable {
        let x: Double
        let symbol: String
        var rotation = 0.0
        var id: Double { x }
    }

    private var range: ClosedRange<Double> {
        let xs = detail.lines.flatMap { $0.points.map(\.x) }
        var lo = xs.min() ?? 0, hi = xs.max() ?? 24
        // Measurements end now; opened at a later hour, the chart reaches on to
        // it, so its blue line sits inside the chart after the last measurement.
        if detail.history, !data.isNow { hi = max(hi, 0); lo = min(lo, 0) }
        return lo...max(hi, lo + 1)
    }

    private var domain: ClosedRange<Double> {
        if let d = detail.yDomain { return d }
        let values = detail.lines.flatMap { $0.points.map(\.y) } + detail.limits.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(hi - lo, 0.1)
        let bottom = lo >= 0 && detail.trendStep == nil ? 0 : lo - span * 0.1
        let room = detail.trendStep == nil && !detail.windArrows ? 0.1 : 0.3
        return bottom...(hi + span * room)
    }

    private var arrowY: Double {
        let d = domain
        if detail.logScale { return exp(log(d.upperBound) - 0.08 * (log(d.upperBound) - log(d.lowerBound))) }
        return d.upperBound - 0.08 * (d.upperBound - d.lowerBound)
    }

    private var arrows: [Arrow] {
        if detail.windArrows {
            return data.timeline.compactMap { h in
                let x = data.x(h.time)
                guard x.truncatingRemainder(dividingBy: 3) == 0, let from = h.windFromDeg else { return nil }
                return Arrow(x: x + 1, symbol: "arrow.down", rotation: from)
            }
        }
        guard let step = detail.trendStep, let points = detail.lines.first?.points, points.count > 3 else { return [] }
        return stride(from: 0, to: points.count - 3, by: 3).compactMap { i in
            guard points[i].x.truncatingRemainder(dividingBy: 1) == 0 else { return nil }
            let change = points[i + 3].y - points[i].y
            return Arrow(x: points[i].x + 1.5, symbol: change > step ? "arrow.up" : change < -step ? "arrow.down" : "equal")
        }
    }

    private var shownLines: [ChartLine] { detail.lines.filter { !hidden.contains($0.name) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            scrolling(scaled(chart))
                .chartXSelection(value: $selectedX)
                .onChange(of: selectedX != nil) { _, on in if on { ChartScrubTip().invalidate(reason: .actionPerformed) } }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        markers(proxy: proxy, geo: geo)
                        limitLabels(proxy: proxy, geo: geo)
                        scrubLabel(proxy: proxy, geo: geo)
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: compact ? 100 : 200)
                .sensoryFeedback(.selection, trigger: selectedX == nil)
                .onChange(of: selectedX) { _, x in
                    if let x, !detail.history { time.setChart(x) }
                }
                .onChange(of: scrollX) { _, x in
                    if !detail.history { time.scrollX = x }
                }
                // Moved from the map (play, slider, linking again): keep the line in view.
                .onChange(of: time.hour) { _, x in
                    guard !detail.history, selectedX == nil, x < scrollX + 0.5 || x > scrollX + 23.5 else { return }
                    // Without animation: the green band and the lines on top follow
                    // the chart's place at once, and an animated scroll left them
                    // stretching past the chart's edge and shrinking back.
                    scrollX = min(max(x - 8, range.lowerBound), range.upperBound - 24)
                }
            // One line under the chart, the same height on every page so the map
            // card below never moves: the legend at the left, and once dragged or
            // scrubbed away from the opened hour, one tap back at the right. How to
            // drag and read the chart is a one-time tip (ChartScrubTip, owner 13 Nov 2026).
            if !compact {
                let away = !detail.history && (abs(scrollX - Self.start) > 0.5 || time.hour != 0)
                HStack(spacing: 8) {
                    legend
                    Spacer(minLength: 0)
                    if away {
                        Button {
                            withAnimation { time.back() }
                            scrollX = Self.start
                        } label: {
                            let label = data.isNow ? tr("Back to now") : tr("Back to %@", Format.dayTime(data.now.time))
                            let symbol = (time.hour != 0 ? time.hour : scrollX - Self.start) > 0 ? "arrow.uturn.backward" : "arrow.uturn.forward"
                            // Beside a long legend (cloud), only the arrow.
                            ViewThatFits(in: .horizontal) {
                                Label(label, systemImage: symbol)
                                Image(systemName: symbol).accessibilityLabel(label)
                            }
                            .font(.caption.weight(.semibold))
                            .tapArea(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 0))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .transition(.opacity)
                    }
                }
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Past measurements have no map below: their note (what the dashed line is) stays.
                if detail.history {
                    Text(detail.chartNote ?? tr("Measurements of the last days. Touch the chart to read a value."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The point of a line nearest to an hour.
    private func nearest(_ line: ChartLine, to x: Double) -> ChartPoint? {
        line.points.min { abs($0.x - x) < abs($1.x - x) }
    }

    /// The point a line has at an hour, or nil where the line doesn't reach:
    /// measurements end now and a forecast starts there, so only one of them
    /// answers. A dashed forecast starts on the last measurement, which then
    /// speaks for both.
    private func value(_ line: ChartLine, at x: Double) -> ChartPoint? {
        guard let first = line.points.first, let last = line.points.last else { return nil }
        let start = line.dashed && line.points.count > 1 ? first.x + 0.5 : first.x - 0.75
        guard x >= start, x <= last.x + 0.75 else { return nil }
        return nearest(line, to: x)
    }

    /// A value with as many decimals as it needs to be read: 0.19, 5.2, 14.
    private func valueText(_ y: Double) -> String {
        // Beaufort is drawn without steps (`chartValue`) but read as whole forces.
        if detail.unit == SpeedUnit.beaufort.symbol { return "\(Int(y.rounded())) \(detail.unit)" }
        let digits = abs(y) < 1 ? 2 : abs(y) < 10 ? 1 : 0
        return Format.number(y, digits: digits) + (detail.unit.isEmpty ? "" : " " + detail.unit)
    }

    /// The scrub line's label: the hour and each shown line's value.
    private func callout(_ x: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.dayTime(date(x.rounded()))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(shownLines) { line in
                if let p = value(line, at: x) {
                    HStack(spacing: 4) {
                        if shownLines.count > 1 {
                            if line.dashed {
                                Circle().strokeBorder(line.color, lineWidth: 1.5).frame(width: 6, height: 6)
                            } else {
                                Circle().fill(line.color).frame(width: 6, height: 6)
                            }
                        }
                        Text(valueText(p.y)).font(.caption.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var chart: some View {
        Chart {
            // First, so switching a line off in the legend leaves the arrows where
            // they are: the chart matches marks by their place, and arrows after
            // the lines were taken for new ones, faded out and in again.
            ForEach(arrows) { a in
                PointMark(x: .value("Hour", a.x), y: .value("Value", arrowY))
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        Image(systemName: a.symbol).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(a.rotation))
                    }
            }
            ForEach(shownLines) { line in
                ForEach(drawn(line)) { p in
                    mark(line, p)
                }
            }
            ForEach(Array(detail.limits.enumerated()), id: \.offset) { _, limit in
                limitRules(limit)
            }
            RuleMark(x: .value("Hour", 0.0)).foregroundStyle(.secondary.opacity(0.5))
            // A dot where each line meets now, as in the Weather app: it marks
            // the present and shows what can be held and slid.
            if !detail.history {
                ForEach(shownLines.filter { $0.kind == .line }) { line in
                    if let p = nearest(line, to: 0), abs(p.x) < 0.75 {
                        PointMark(x: .value("Hour", p.x), y: .value("Value", p.y))
                            .foregroundStyle(line.color)
                            .symbolSize(60)
                        PointMark(x: .value("Hour", p.x), y: .value("Value", p.y))
                            .foregroundStyle(.background)
                            .symbolSize(18)
                    }
                }
            }
            // The blue line and the touched value's label are drawn over the
            // chart (`markers`, `scrubLabel`): a label inside a scrolling chart
            // was cut off at its edge and left only a dark bar.
            if let x = markerX {
                ForEach(shownLines.filter { $0.kind == .line }) { line in
                    if let p = value(line, at: x) {
                        PointMark(x: .value("Hour", p.x), y: .value("Value", p.y))
                            .foregroundStyle(line.color)
                            .symbolSize(50)
                    }
                }
            }
        }
        .chartXScale(domain: range)
        .chartXAxis {
            AxisMarks(values: axisHours) { value in
                AxisGridLine()
                AxisValueLabel(anchor: .top) {
                    // Labels right at the visible edges would be cut in half; one next to "Now" gives way to it.
                    if let x = value.as(Double.self), detail.history ? labelled(x) : (x - scrollX > 1.2 && scrollX + 24 - x > 1.2 && !(showsNow && abs(x) < 2.5)) {
                        Text(label(x))
                    }
                }
            }
            // "Now" under the start of a forecast, on the app and the website (owner, 14 Nov 2026).
            // At the left edge it starts at the line instead of centring on it, so it is never cut.
            AxisMarks(values: showsNow ? [0.0] : []) { _ in
                AxisValueLabel(anchor: -scrollX < 1.2 ? .topLeading : .top) { Text(tr("Now")) }
            }
        }
        // Over the values on the right; on the left a dragged chart cut it off.
        .chartYAxisLabel(position: .topTrailing) { Text(detail.unit) }
        // Room at the edges for the scrolling forecast; a history keeps its
        // lines within the plot, where the padding pushed them under the
        // axis numbers on the right.
        .chartPlotStyle { $0.padding(.horizontal, detail.history ? 0 : 16) }
        .accessibilityChartDescriptor(description)
        // Axis labels stop growing at the largest standard text size: larger,
        // the days ran into each other.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The shown lines for VoiceOver: "Describe chart" and the audio graph.
    private var description: ChartDescription {
        let shown = detail.lines.filter { !hidden.contains($0.name) && !$0.points.isEmpty }
        return ChartDescription(
            title: shown.map(\.name).joined(separator: ", "),
            unit: detail.unit,
            series: shown.map { line in
                .init(name: line.name, points: line.points.map { (date($0.x), $0.y) }, continuous: line.kind != .bars)
            },
            summary: [detail.value, detail.note].filter { !$0.isEmpty }.joined(separator: ". "),
            digits: detail.unit == SpeedUnit.beaufort.symbol ? 0 : 1)
    }

    /// A line's points, without bars where another shown line's bars stand in for them.
    private func drawn(_ line: ChartLine) -> [ChartPoint] {
        let covered = shownLines.filter { $0.id != line.id }.compactMap(\.covers)
        guard line.kind == .bars, !covered.isEmpty else { return line.points }
        return line.points.filter { p in !covered.contains { range in range.contains(p.x) } }
    }

    @ChartContentBuilder
    private func mark(_ line: ChartLine, _ p: ChartPoint) -> some ChartContent {
        switch line.kind {
        case .line:
            LineMark(x: .value("Hour", p.x), y: .value("Value", p.y), series: .value("Series", line.name))
                .foregroundStyle(line.color)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: line.dashed ? [5, 4] : []))
                .interpolationMethod(.monotone)
        case .bars:
            BarMark(x: .value("Hour", p.x + line.drawOffset), y: .value("Value", p.y), width: .fixed(line.barWidth))
                .foregroundStyle(line.color.opacity(0.7))
        case .area:
            AreaMark(x: .value("Hour", p.x), y: .value("Value", p.y), series: .value("Series", line.name))
                .foregroundStyle(line.color.opacity(0.55))
                .interpolationMethod(.monotone)
        }
    }

    /// A limit as one dashed line; its name is drawn over the chart by `limitLabels`.
    @ChartContentBuilder
    private func limitRules(_ limit: ChartLimit) -> some ChartContent {
        // From the first hour to the last only: across the plot's side padding
        // the dashes ran through the axis numbers on the right.
        RuleMark(xStart: .value("Hour", range.lowerBound), xEnd: .value("Hour", range.upperBound), y: .value("Limit", limit.value))
            .foregroundStyle(limit.color)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    /// The blue line at the big number's hour, the green marker at the map's
    /// hour and the green band of hours with maps, drawn over the chart.
    @ViewBuilder
    private func markers(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotFrame = proxy.plotFrame {
            let plot = geo[plotFrame]
            let left = max(plot.minX, 0)
            let visibleRight = rightEdge(proxy: proxy, plot: plot)
            let right = min(plot.maxX, visibleRight, geo.size.width)
            let onScreen = { (x: Double) -> CGFloat? in
                guard let p = proxy.position(forX: x) else { return nil }
                let px = plot.minX + p
                return px >= left - 1 && px <= right + 1 ? px : nil
            }
            let green = Self.mapGreen
            let mapX = detail.history ? nil : time.mapFrameHour
            ZStack(alignment: .topLeading) {
                if !detail.history, let hours = time.mapHours, let first = hours.first, let last = hours.last,
                   let a = proxy.position(forX: first), let b = proxy.position(forX: last) {
                    let from = max(plot.minX + a, left), to = min(plot.minX + b, right)
                    if to > from {
                        Capsule().fill(green.opacity(0.8))
                            .frame(width: to - from, height: 3)
                            .offset(x: from, y: plot.maxY - 3)
                    }
                }
                lines(plot: plot, mapX: mapX, onScreen: onScreen)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Placed from the chart's current scroll, so never animated on their own.
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
        }
    }

    /// One name per limit, just above its line, on the side away from "now":
    /// at the right edge of a forecast (now sits at the left) and at the left
    /// edge of a history (now sits at the right), so names never cover it.
    /// Names that would touch are moved apart, and a name whose line is off
    /// the chart is left out.
    @ViewBuilder
    private func limitLabels(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotFrame = proxy.plotFrame {
            let plot = geo[plotFrame]
            // A chart that scrolls reports its whole plot, which starts off screen
            // once dragged; the names stay at the visible left edge instead.
            let left = max(plot.minX, 0)
            let visibleRight = rightEdge(proxy: proxy, plot: plot)
            let right = min(plot.maxX, visibleRight, geo.size.width)
            let trailing = !detail.history
            let placed = Self.spread(detail.limits.compactMap { limit -> (limit: ChartLimit, y: CGFloat)? in
                guard let y = proxy.position(forY: limit.value), y >= 0, y <= plot.height else { return nil }
                return (limit, plot.minY + y - Self.labelHeight / 2 - 2)
            }, top: plot.minY)
            ForEach(Array(placed.enumerated()), id: \.offset) { _, item in
                Text(item.limit.label)
                    .font(.caption2)
                    .foregroundStyle(item.limit.color)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(height: Self.labelHeight)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
                    .padding(.leading, trailing ? 0 : left + 4)
                    .padding(.trailing, trailing ? max(geo.size.width - right, 0) + 4 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: trailing ? .topTrailing : .topLeading)
                    .offset(y: item.y - Self.labelHeight / 2)
            }
        }
    }

    static let labelHeight: CGFloat = 15

    /// The right edge of what is on screen: the visible 24 hours of a forecast;
    /// a history's whole plot, which reaches on into the water forecast.
    private func rightEdge(proxy: ChartProxy, plot: CGRect) -> CGFloat {
        if detail.history { return plot.maxX }
        return proxy.position(forX: scrollX + 24).map { plot.minX + $0 } ?? plot.maxX
    }

    /// While touched, the hour and values at the top of the plot, beside the
    /// blue line on the side with more room, so it never covers the line or
    /// runs past the visible edge (the big number above changes as well).
    @ViewBuilder
    private func scrubLabel(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let x = selectedX, let plotFrame = proxy.plotFrame, let p = proxy.position(forX: x.rounded()) {
            let plot = geo[plotFrame]
            let left = max(plot.minX, 0)
            let visibleRight = rightEdge(proxy: proxy, plot: plot)
            let right = min(plot.maxX, visibleRight, geo.size.width)
            let px = plot.minX + p
            let before = px > (left + right) / 2
            callout(x)
                .fixedSize()
                .padding(.leading, before ? 0 : px + 6)
                .padding(.trailing, before ? max(geo.size.width - px, 0) + 6 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: before ? .topTrailing : .topLeading)
                .offset(y: plot.minY + 2)
                .transaction { $0.animation = nil }
        }
    }

    /// Moves names down so no two overlap, keeping their order from top to bottom.
    static func spread(_ items: [(limit: ChartLimit, y: CGFloat)], top: CGFloat) -> [(limit: ChartLimit, y: CGFloat)] {
        var result: [(limit: ChartLimit, y: CGFloat)] = []
        var next = top + labelHeight / 2
        for item in items.sorted(by: { $0.y < $1.y }) {
            let y = max(item.y, next)
            result.append((item.limit, y))
            next = y + labelHeight + 1
        }
        return result
    }

    @ViewBuilder
    private func scaled(_ chart: some View) -> some View {
        if detail.logScale {
            chart.chartYScale(domain: domain, type: .log)
        } else {
            chart.chartYScale(domain: domain)
        }
    }

    @ViewBuilder
    private func scrolling(_ chart: some View) -> some View {
        if detail.history {
            chart
        } else {
            chart
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 24)
                .chartScrollPosition(x: $scrollX)
        }
    }

    /// Every 6 hours on the clock (00, 06, 12, 18); daily for past measurements.
    /// The forecast's "Now" label: while the hour now is in view.
    private var showsNow: Bool {
        !detail.history && data.isNow && range.contains(0) && scrollX <= 0.3 && scrollX + 24 >= 1.2
    }

    private var axisHours: [Double] {
        let step = detail.history ? 24 : 6
        return stride(from: range.lowerBound.rounded(.down), through: range.upperBound, by: 1).filter { x in
            Calendar.current.component(.hour, from: date(x)) % step == 0
                && Calendar.current.component(.minute, from: date(x)) == 0
        }
    }

    /// Past measurements show many days: only every second or third gets its
    /// name, so the names don't run into each other, fewer with larger text.
    private func labelled(_ x: Double) -> Bool {
        let days = axisHours
        guard let i = days.firstIndex(of: x) else { return false }
        let most = typeSize >= .xLarge ? 5 : 7
        let step = max(1, Int((Double(days.count) / Double(most)).rounded(.up)))
        return (days.count - 1 - i) % step == 0
    }

    private func date(_ x: Double) -> Date { data.now.time.addingTimeInterval(x * 3600) }

    private func label(_ x: Double) -> String {
        let d = date(x)
        if Calendar.current.component(.hour, from: d) == 0 {
            return d.formatted(.dateTime.weekday(.abbreviated).locale(Format.locale))
        }
        return Format.time(d)
    }
}

// MARK: - Contents of the larger views

extension ConditionDetail {
    private static var units: AppSettings { .shared }

    /// A change of `value` (in metric) in the user's unit, for trend steps.
    private static func step(_ convert: (Double) -> Double, _ value: Double) -> Double {
        convert(value) - convert(0)
    }

    init(_ condition: Condition, _ d: ConditionData) {
        switch condition {
        case .temperature: self = Self.temperature(d)
        case .feelsLike: self = Self.feelsLike(d)
        case .humidity: self = Self.humidity(d)
        case .wind: self = Self.wind(d)
        case .waves: self = Self.waves(d)
        case .waterTemperature: self = Self.water(d)
        case .precipitation: self = Self.precipitation(d)
        case .visibility: self = Self.visibility(d)
        case .cloudCover: self = Self.cloud(d)
        case .pressure: self = Self.pressure(d)
        case .thunderstorm: self = Self.thunderstorm(d)
        case .uvIndex: self = Self.uv(d)
        case .ice: self = Self.ice(d)
        case .daylight: self = Self.daylight(d)
        }
    }

    private static func temperatureLines(_ d: ConditionData) -> [ChartLine] {
        let t = units.temperatureUnit
        return [
            ChartLine(name: tr("Air"), color: .orange, points: d.points { $0.temperatureC.map(t.convert) }),
            ChartLine(name: tr("Feels like"), color: .blue, points: d.points { $0.apparentTemperatureC.map(t.convert) }),
        ]
    }

    private static func extreme(_ hours: [ForecastHour], _ value: (ForecastHour) -> Double?, highest: Bool) -> ForecastHour? {
        let known = hours.filter { value($0) != nil }
        return highest ? known.max { value($0)! < value($1)! } : known.min { value($0)! < value($1)! }
    }

    private static func temperature(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        var facts: [(String, String)] = [(d.nowLabel, Format.temperature(h.temperatureC))]
        if let lo = extreme(d.next24, \.temperatureC, highest: false) {
            facts.append((tr("Lowest next 24 h"), tr("%@ · %@", Format.temperature(lo.temperatureC), Format.dayTime(lo.time))))
        }
        if let hi = extreme(d.next24, \.temperatureC, highest: true) {
            facts.append((tr("Highest next 24 h"), tr("%@ · %@", Format.temperature(hi.temperatureC), Format.dayTime(hi.time))))
        }
        let past = d.timeline.filter { d.x($0.time) < 0 }
        if let hi = extreme(past, \.temperatureC, highest: true) {
            facts.append((tr("Last 24 h"), tr("highest %@", Format.temperature(hi.temperatureC))))
        }
        return ConditionDetail(
            value: Format.degrees(h.temperatureC),
            note: tr("%@ · feels like %@", Sky(hour: h).title, Format.degrees(h.apparentTemperatureC)),
            unit: units.temperatureUnit.symbol,
            lines: temperatureLines(d),
            trendStep: step(units.temperatureUnit.convert, 0.5),
            facts: facts,
            rowing: clothingAdvice(feelsLike: h.apparentTemperatureC),
            source: tr("Deutscher Wetterdienst (DWD) via Open-Meteo, 2 m above ground.")
        )
    }

    private static func feelsLike(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        var facts: [(String, String)] = []
        if let feels = h.apparentTemperatureC, let air = h.temperatureC {
            let diff = units.temperatureUnit.convert(feels) - units.temperatureUnit.convert(air)
            facts.append((tr("Compared with the air"), tr("%@° %@", Format.number(abs(diff)), diff < 0 ? tr("colder") : tr("warmer"))))
        }
        facts.append((tr("Wind"), Format.windRange(h.windSpeedMs, h.windGustMs)))
        facts.append((tr("Humidity"), h.humidityPct.map { "\(Format.number($0)) %" } ?? "–"))
        facts.append((tr("Sun"), h.sunUp == false ? tr("down") : tr("up")))
        facts.append((tr("On the water"), tr("the boat's speed adds wind chill")))
        return ConditionDetail(
            value: Format.degrees(h.apparentTemperatureC),
            note: feelsLikeNote(h) ?? "",
            unit: units.temperatureUnit.symbol,
            lines: temperatureLines(d),
            trendStep: step(units.temperatureUnit.convert, 0.5),
            facts: facts,
            rowing: clothingAdvice(feelsLike: h.apparentTemperatureC),
            source: tr("Apparent temperature from air temperature, wind, humidity and sun (DWD via Open-Meteo).")
        )
    }

    /// Air and dew point within 1 °C: mist forms.
    private static func misty(_ h: ForecastHour) -> Bool {
        guard let air = h.temperatureC, let dew = h.dewPointC else { return false }
        return air - dew <= 1
    }

    private static func humidity(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let mist = d.firstRun(in: d.next24, where: misty)
        var shownGap: Double?
        if let air = h.temperatureC, let dew = h.dewPointC {
            shownGap = step(units.temperatureUnit.convert, air - dew)
        }
        return ConditionDetail(
            value: h.humidityPct.map { "\(Format.number($0)) %" } ?? "–",
            note: tr("Dew point %@", Format.degrees(h.dewPointC)),
            unit: "%",
            lines: [ChartLine(name: tr("Humidity"), color: .teal, points: d.points(\.humidityPct))],
            yDomain: 0...130,
            trendStep: 2.5,
            facts: [
                (tr("Dew point"), Format.temperature(h.dewPointC)),
                (tr("Air minus dew point"), tr("%@° (mist forms near 0–1°)", Format.number(shownGap))),
                (tr("Mist likely"), mist.map(d.span) ?? tr("not in the next 24 h")),
            ],
            rowing: mist == nil
                ? tr("No mist expected from the humidity in the next 24 hours.")
                : tr("When air and dew point meet, mist forms over the water: check visibility before going out early."),
            source: tr("Relative humidity and dew point, DWD via Open-Meteo.")
        )
    }

    /// Rowing advice from the light of these reasons now and in the next 24 hours.
    private static func advice(_ d: ConditionData, _ names: Set<String>, red: String, amber: String, later: String, calm: String) -> String {
        switch d.now.light(for: names) {
        case .red: return red
        case .amber: return amber
        default:
            if (d.now.notes ?? []).contains(where: { names.contains($0.condition) }) {
                return tr("Within your own limit, but above the app's usual limit for %@: take extra care.", d.limits.boat.inSentence)
            }
            if let next = d.next24.first(where: { $0.light(for: names) != nil }) {
                return tr(later, Format.dayTime(next.time))
            }
            return calm
        }
    }

    private static func wind(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let w = units.windUnit
        let gust = extreme(d.next24, \.windGustMs, highest: true)
        var facts: [(String, String)] = [(tr("Beaufort"), h.windSpeedMs.map { "\(SpeedUnit.beaufort($0))" } ?? "–")]
        if let from = h.windFromDeg { facts.append((tr("From"), "\(Format.compass(from)) (\(Format.number(from))°)")) }
        if let fetch = h.fetchM { facts.append((tr("Open water upwind"), Format.distance(fetch))) }
        if let gust { facts.append((tr("Strongest gust next 24 h"), tr("%@ · %@", Format.wind(gust.windGustMs), Format.dayTime(gust.time)))) }
        return ConditionDetail(
            value: Format.wind(h.windSpeedMs),
            note: tr("Gusts %@", Format.wind(h.windGustMs)) + (h.windFromDeg.map { " · " + tr("from %@", Format.compass($0)) } ?? ""),
            big: h.windFromDeg.map { AnyView(WindDial(speed: Format.windNumber(h.windSpeedMs), fromDeg: $0, unit: w.symbol).frame(width: 90, height: 90)) },
            unit: w.symbol,
            lines: [
                ChartLine(name: tr("Wind"), color: .blue, points: d.points { $0.windSpeedMs.map(w.chartValue) }),
                ChartLine(name: tr("Gusts"), color: .purple, points: d.points { $0.windGustMs.map(w.chartValue) }),
            ],
            limits: [
                line(d.limits, .windAmber, w.chartValue, .orange, tr("Wind: row with care")),
                line(d.limits, .windRed, w.chartValue, .red, tr("Wind: stay ashore")),
            ],
            limitInfo: tr("Amber from %@ (Beaufort 4, the first whitecaps) and red from %@ (Beaufort 5, many whitecaps): in a single or double the boat gets hard to steer and water comes over the side. Gusts have their own limits: amber from %@ and red from %@ (46 km/h), the level at which DWD issues a strong-wind warning and the lake's warning lights start flashing. These are the app's starting values for small boats.",
                          RowingLimit.windAmber.format(5.5), RowingLimit.windRed.format(8), RowingLimit.gustAmber.format(8), RowingLimit.gustRed.format(12.8))
                + inUse(d.limits, [(tr("Wind"), .windAmber, .windRed), (tr("Gusts"), .gustAmber, .gustRed)]),
            windArrows: true,
            facts: facts,
            rowing: advice(d, Condition.wind.reasonNames,
                           red: tr("Too windy now: stay ashore."),
                           amber: tr("Windy now: row with care and stay near the shore."),
                           later: tr("Calm enough now; the wind reaches the limit from %@."),
                           calm: tr("Calm enough for the next 24 hours.")),
            source: tr("Wind at 10 m and gusts, DWD ICON via Open-Meteo.")
        )
    }

    /// A limit line, marked when it is the user's own.
    private static func line(_ limits: RowingLimits, _ limit: RowingLimit, _ convert: (Double) -> Double, _ color: Color, _ label: String) -> ChartLimit {
        ChartLimit(value: convert(limits.value(limit)), color: color, label: limits.isMine(limit) ? tr("%@ (your limit)", label) : label)
    }

    /// The limits in use, after the explanation of the app's own.
    private static func inUse(_ limits: RowingLimits, _ pairs: [(String, RowingLimit, RowingLimit)]) -> String {
        let parts = pairs.map { tr("%@ amber from %@, red above %@", $0.0, $0.1.format(limits.value($0.1)), $0.2.format(limits.value($0.2))) }
        return " " + tr("In use for %@: %@. You can change them under Settings, Boats and limits.", limits.boat.inSentence, parts.joined(separator: "; "))
    }

    private static func waves(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let u = units.waveUnit
        let top = extreme(d.next24, \.waveHeightM, highest: true)
        var facts: [(String, String)] = []
        if let fetch = h.fetchM {
            facts.append((tr("Open water upwind"), fetch < 50 ? tr("none, the wind blows off the shore") : Format.distance(fetch)))
        }
        if let top { facts.append((tr("Highest next 24 h"), tr("%@ · %@", Format.waves(top.waveHeightM), Format.dayTime(top.time)))) }
        return ConditionDetail(
            value: Format.waves(h.waveHeightM),
            note: (h.fetchM ?? 100) < 50 ? tr("Wind blows off the shore") : tr("At the launch point"),
            unit: u.symbol,
            lines: [ChartLine(name: tr("Waves"), color: .blue, points: d.points { $0.waveHeightM.map(u.convert) })],
            limits: [
                line(d.limits, .waveAmber, u.convert, .orange, tr("Row with care")),
                line(d.limits, .waveRed, u.convert, .red, tr("Stay ashore")),
            ],
            limitInfo: tr("Amber from %@ and red from %@ wave height. A racing single sits only about 10–15 cm above the water at its side, so from about 15 cm waves start to wash in; from about 30 cm the boat fills and capsizing becomes likely. The waves are calculated from the wind and the open water upwind, not measured.",
                          Format.waves(0.15), Format.waves(0.3))
                + inUse(d.limits, [(tr("Waves"), .waveAmber, .waveRed)]),
            yDomain: 0...max(u.convert(d.limits.value(.waveRed) * 4 / 3), u.convert(d.timeline.compactMap(\.waveHeightM).max() ?? 0) * 1.3),
            trendStep: step(u.convert, 0.015),
            facts: facts,
            rowing: advice(d, ["waves"],
                           red: tr("Waves are too high now: stay ashore."),
                           amber: tr("Waves now: row with care; small boats take on water."),
                           later: tr("Flat enough now; the waves reach the limit from %@."),
                           calm: tr("Flat enough for the next 24 hours.")),
            source: tr("Calculated by the app from wind and the lake's shape (fetch), not measured.")
        )
    }

    private static func water(_ d: ConditionData) -> ConditionDetail {
        let t = units.temperatureUnit
        let now = d.water
        let history = now?.history ?? []
        var facts: [(String, String)] = []
        if let first = history.first, let last = history.last, history.count > 1 {
            let change = step(t.convert, last.celsius - first.celsius)
            facts.append((tr("Trend"), tr("%@° since %@", (change >= 0 ? "+" : "−") + Format.number(abs(change), digits: 1), Format.day(first.time))))
        }
        let jacket = Format.temperature(d.limits.value(.lifeJacket))
        facts.append((tr("Life jacket"), d.limits.isMine(.lifeJacket) ? tr("%@ (your limit)", tr("advised below %@", jacket)) : tr("advised below %@", jacket)))
        let rowing: String
        let veryCold = Format.temperature(RowingLimits.coldWaterC)
        switch now?.celsius {
        case let c? where c < RowingLimits.coldWaterC:
            rowing = tr("Below %@ wear a life jacket, stay near the shore and row with a second boat or a safety boat nearby. Wear clothes that keep you warm when wet.", veryCold)
        case let c? where c < d.limits.value(.lifeJacket):
            rowing = tr("Below %@ a capsize can cause cold-water shock: we advise a life jacket and clothes that keep you warm when wet.", jacket)
        case let c? where c < 15:
            rowing = tr("Below %@ wear clothes that keep you warm when wet. Below %@ we advise a life jacket.", Format.temperature(15), jacket)
        case .some:
            rowing = tr("Warm enough that a capsize is not a cold-water danger.")
        case nil:
            rowing = tr("No lake station: check the water yourself. Below %@ we advise a life jacket.", jacket)
        }
        let estimate = now == nil ? d.estimatedWater : nil
        let satellite = d.satelliteWater
        // Today's water carried on with the forecast air, dashed after the
        // measurements; a picked later hour reads its value from it.
        let forecastDays = (d.forecast.waterForecast ?? []).compactMap { day in day.day.map { ($0, day.celsius) } }
        let ahead = forecastDays.filter { $0.0 > .now }
        var forecastPoints: [ChartPoint] = []
        if !ahead.isEmpty {
            if let last = history.last { forecastPoints.append(ChartPoint(x: d.x(last.time), y: t.convert(last.celsius))) }
            else if let today = forecastDays.first { forecastPoints.append(ChartPoint(x: d.x(.now), y: t.convert(today.1))) }
            forecastPoints += ahead.map { ChartPoint(x: d.x($0.0), y: t.convert($0.1)) }
        }
        let picked = d.isNow ? nil : d.forecast.waterForecastC(on: d.now.time).flatMap { c in
            Calendar.current.isDateInToday(d.now.time) ? nil : c
        }
        if let picked {
            facts.insert((tr("Forecast %@", Format.day(d.now.time)), Format.temperature(picked, digits: 1)), at: 0)
        }
        if let satellite {
            facts.append((tr("Satellite"), tr("%@, %@: %@", satellite.satelliteName, satellite.when, Format.temperature(satellite.celsius, digits: 1))))
        }
        let source: String
        if let satellite {
            source = satellite.source == "landsat"
                ? tr("Landsat surface temperature (U.S. Geological Survey, via Microsoft Planetary Computer), carried forward to today with the air temperatures.")
                : tr("Copernicus Land Monitoring Service, Lake Surface Water Temperature (Sentinel-3), carried forward to today with the air temperatures.")
        } else if now == nil, estimate != nil {
            source = tr("Calculated by the app from the air temperatures of the last weeks, not measured.")
        } else if let now {
            source = tr("%@, the nearest station on this water.", (now.station ?? WaterStation()).operatorName)
        } else {
            source = tr("No station measures the water of this lake, and no satellite has seen it clearly in the last 30 days.")
        }
        var lines: [ChartLine] = history.isEmpty ? [] : [ChartLine(name: tr("Measurement"), color: .cyan, points: history.map { ChartPoint(x: d.x($0.time), y: t.convert($0.celsius)) })]
        if forecastPoints.count > 1 {
            lines.append(ChartLine(name: tr("Forecast"), color: .cyan, points: forecastPoints, dashed: true))
        }
        // Fitted to the readings and the forecast, with room around them, the
        // life-jacket and very-cold lines always in view.
        let readings = history.map(\.celsius) + forecastDays.map { $0.1 } + [estimate].compactMap { $0 }
        let limitValues = [d.limits.value(.lifeJacket), RowingLimits.coldWaterC]
        let lowest = ((readings + limitValues).min() ?? 0) - 2, highest = ((readings + limitValues).max() ?? 20) + 2
        let yDomain = t.convert(lowest.rounded(.down))...t.convert(highest.rounded(.up))
        if let picked {
            return ConditionDetail(
                value: "≈ " + Format.degrees(picked, digits: 1),
                note: tr("Forecast for %@, from today's water and the forecast air temperatures", Format.day(d.now.time)),
                unit: t.symbol,
                lines: lines,
                limits: [
                    line(d.limits, .lifeJacket, t.convert, ColdWaterKit.color, tr("Cold-water shock: life jacket")),
                    ChartLimit(value: t.convert(RowingLimits.coldWaterC), color: ColdWaterKit.deep, label: tr("Very cold")),
                ],
                yDomain: yDomain,
                history: true,
                chartNote: tr("Measurements of the last days; dashed, the forecast from the air temperatures. Touch the chart to read a value."),
                facts: facts,
                rowing: rowing,
                source: source
            )
        }
        return ConditionDetail(
            value: estimate.map { "≈ " + Format.degrees($0, digits: 0) } ?? Format.degrees(now?.celsius, digits: 1),
            note: now.map { tr("Measured %@", Format.dayTime($0.measuredAt)) }
                ?? (satellite.map { tr("Estimated from %@ (%@) and the air temperatures since, not measured", $0.satelliteName, $0.when) }
                    ?? (estimate != nil ? tr("Estimated from the air temperatures of the last weeks, not measured") : tr("No lake station"))),
            unit: t.symbol,
            lines: lines,
            limits: [
                line(d.limits, .lifeJacket, t.convert, ColdWaterKit.color, tr("Cold-water shock: life jacket")),
                ChartLimit(value: t.convert(RowingLimits.coldWaterC), color: ColdWaterKit.deep, label: tr("Very cold")),
            ],
            limitInfo: tr("Below about %@ a fall into the water causes cold-water shock: a gasp and fast breathing in the first minute. A life jacket keeps your head above water through it, so the app advises one from %@ down. A rule of thumb says the minutes you can still help yourself in the water are about the water temperature in °C, so about 10 minutes at 10 °C. That is why the advice gets stricter below %@: stay near the shore and don't row alone. Your club's own rules come first.",
                          Format.temperature(15), jacket, veryCold)
                + " " + tr("Cold water does not change the rowing light: the blue life-jacket badge under it shows what to bring. Below %@ the app's wind and gust limits are %@ lower, and below %@ small boats get an amber warning.",
                           veryCold, Format.wind(RowingLimits.coldWindMarginMs), Format.temperature(RowingLimits.freezingWaterC)),
            yDomain: yDomain,
            history: true,
            chartNote: forecastPoints.count > 1 ? tr("Measurements of the last days; dashed, the forecast from the air temperatures. Touch the chart to read a value.") : nil,
            facts: facts,
            rowing: rowing,
            source: source
        )
    }

    private static let rainWords = ["REGEN", "HAGEL", "GEWITTER", "SCHNEE"]

    private static func precipitation(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let r = units.rainUnit
        let total = d.next24.compactMap(\.precipitationMm).reduce(0, +)
        let top = extreme(d.next24, \.precipitationMm, highest: true)
        let kinds = Set(d.next24.filter(\.isWet).compactMap { Sky(hour: $0).precipitationKind })
        let light: String = switch d.now.light(for: Condition.precipitation.reasonNames) {
        case .red: tr("red: hail")
        case .amber: tr("amber: heavy rain")
        default: tr("green: under %@ per hour", Format.rain(4))
        }
        var facts: [(String, String)] = [(tr("Next 24 h"), tr("%@ in total", Format.rain(total)))]
        facts.append((tr("Kind"), kinds.isEmpty ? tr("dry") : kinds.sorted().joined(separator: ", ")))
        if let top, (top.precipitationMm ?? 0) >= 0.1 {
            facts.append((tr("Heaviest"), tr("%@ · %@", Format.rain(top.precipitationMm), Format.dayTime(top.time))))
        }
        // The label names the warning, the value says "Keine" (owner's pick C, 14 Nov 2026).
        facts.append((tr("Official rain warning"), d.warningNames(rainWords)))
        facts.append((tr("Rowing light now"), light))
        let wet = (h.precipitationMm ?? 0) >= 0.1
        var value = wet ? Format.rain(h.precipitationMm) : (d.traceNow ?? tr("Dry"))
        var note = wet ? (Sky(hour: h).precipitationKind ?? "") : d.traceNow != nil ? d.rainLines.detail
            : (d.forecastRain.map { $0.from <= d.moment ? tr("Expected this hour") : tr("Expected from %@", Format.dayTime($0.from)) } ?? tr("Dry next 24 h"))
        var lines = [ChartLine(name: tr("Precipitation"), color: .blue, kind: .bars, points: d.points { $0.precipitationMm.map(r.convert) }, drawOffset: 0.5)]
        var source = tr("Precipitation per hour and weather code, DWD via Open-Meteo. Official warnings appear under the warnings.")
        // The next two hours from DWD's radar, in quarter hours, in front of the forecast's hours.
        if let ahead = d.radarAhead, let outlook = d.rainOutlook {
            value = ahead.rainingNow ? Format.rain(ahead.steps.first?.mmPerHour) : (d.traceNow ?? tr("Dry"))
            if let now = outlook.now, let next = outlook.next {
                note = next.fromRadar ? tr("Radar: %@ · %@", now, next.text) : tr("Radar: %@", now) + " · " + next.text
            } else {
                note = tr("Radar: %@", outlook.summary)
            }
            facts.insert((tr("Radar, next 2 h"), outlook.summary), at: 0)
        }
        if let radar = d.radar, let first = radar.steps.first {
            let points = radar.steps.map { ChartPoint(x: d.x($0.time), y: r.convert($0.mmPerHour)) }
            lines[0] = ChartLine(name: tr("Forecast"), color: .blue, kind: .bars, points: lines[0].points, drawOffset: 0.5)
            // First in the legend, as it comes first on the chart. It hides the forecast hours whose
            // middle (where their bar stands) lies under the radar.
            lines.insert(ChartLine(name: tr("Radar"), color: .indigo, kind: .bars, points: points, barWidth: 2.5,
                                   covers: (d.x(first.time) - 0.5)...(d.x(radar.end) - 0.5)), at: 0)
            source += " " + tr("Radar: Deutscher Wetterdienst (DWD), CC BY 4.0")
        }
        let highest = max(d.timeline.compactMap(\.precipitationMm).max() ?? 0, d.radar?.peak ?? 0)
        return ConditionDetail(
            value: value,
            note: note,
            unit: r.symbol,
            lines: lines,
            limits: [ChartLimit(value: r.convert(4), color: .orange, label: tr("Heavy rain"))],
            limitInfo: tr("%@ per hour is a common line for heavy rain (the UK Met Office uses it; DWD only warns from 15 mm per hour). From there you are soaked within minutes, visibility drops and a long outing takes on water: amber. Hail always counts as red. Official warnings for heavy rain or hail always make the light red or amber as well.", Format.rain(4)),
            yDomain: 0...max(r.convert(6), r.convert(highest) * 1.2),
            facts: facts,
            rowing: advice(d, Condition.precipitation.reasonNames,
                           red: tr("Hail is forecast: stay ashore."),
                           amber: tr("Heavy rain now: you are soaked quickly and see less; keep the outing short."),
                           later: tr("Heavy rain or hail from %@: plan to be back before then."),
                           calm: tr("No heavy rain or hail in the next 24 hours.")),
            source: source
        )
    }

    private static func visibility(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let u = units.distanceUnit
        let fogHours: (ForecastHour) -> Bool = { ($0.visibilityM ?? .infinity) < 1000 }
        let fog = d.firstRun(in: d.next24, where: fogHours)
        let thickest = extreme(d.next24.filter(fogHours), \.visibilityM, highest: false)
        let mist = d.firstRun(in: d.next24) { (1000..<5000).contains($0.visibilityM ?? .infinity) }
        var facts: [(String, String)] = []
        if let fog {
            facts.append((tr("Fog"), d.span(fog) + (thickest.map { " · " + tr("thickest %@", Format.distance($0.visibilityM)) } ?? "")))
            let clear = d.future.first { $0.time >= fog.end && ($0.visibilityM ?? .infinity) >= 1000 && $0.sunUp != false }
            facts.append((tr("Rowing possible"), clear.map { tr("from about %@ by visibility", Format.dayTime($0.time)) } ?? tr("not in the forecast")))
        } else {
            facts.append((tr("Fog"), tr("not in the next 24 h")))
        }
        facts.append((tr("Mist"), mist.map(d.span) ?? tr("not in the next 24 h")))
        facts.append((tr("Official fog warning"), d.warningNames(["NEBEL"])))
        facts.append((tr("Lake view"), tr("fog shows as a banner over the whole lake")))
        return ConditionDetail(
            value: Format.distance(h.visibilityM),
            note: fogHours(h) ? tr("Fog now") : (fog.map { tr("Fog expected %@", d.span($0)) } ?? tr("No fog in the next 24 h")),
            unit: u.symbol,
            lines: [ChartLine(name: tr("Visibility"), color: .gray, points: d.points { $0.visibilityM.map { u.convert(max($0, 50)) } })],
            limits: [
                ChartLimit(value: u.convert(5000), color: .secondary, label: tr("Mist")),
                ChartLimit(value: u.convert(1000), color: .orange, label: tr("Fog: row with care")),
                ChartLimit(value: u.convert(500), color: .red, label: tr("Stay ashore")),
            ],
            limitInfo: tr("Fog means visibility under %@ (the WMO definition): amber. Under %@ you see another boat or a passenger ship only about 2 minutes ahead at rowing speed, and you lose sight of the shore: red. Mist (up to %@) has no limit, but the app mentions it because it often thickens into fog. The scale is stretched at the bottom so short distances are easy to read.",
                          Format.distance(1000), Format.distance(500), Format.distance(5000)),
            yDomain: u.convert(50)...u.convert(80_000),
            logScale: true,
            trendStep: 1,
            facts: facts,
            rowing: advice(d, ["fog"],
                           red: tr("Thick fog now: stay ashore."),
                           amber: tr("Fog now: row with care, close to the shore, and carry a light."),
                           later: tr("Clear now; fog from %@."),
                           calm: tr("No fog in the next 24 hours.")),
            source: tr("Visibility, DWD via Open-Meteo.")
        )
    }

    private static func cloud(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let sunny = d.firstRun(in: d.next24) { ($0.cloudCoverPct ?? 100) < 40 && $0.sunUp == true }
        let pct: (Double?) -> String = { $0.map { "\(Format.number($0)) %" } ?? "–" }
        return ConditionDetail(
            value: pct(h.cloudCoverPct),
            note: tr("Low cloud %@ %%", Format.number(h.cloudCoverLowPct)),
            unit: "%",
            lines: [
                // Owner's pick A (14 Nov 2026, "for now"; the colour thread may change the palette):
                // all cloud a grey area behind, the layers one blue from light (high) to dark (low), like the sky.
                ChartLine(name: tr("All", key: "Cloud line: All"), color: CloudColours.all, kind: .area, points: d.points(\.cloudCoverPct)),
                ChartLine(name: tr("High", key: "Cloud line: High"), color: CloudColours.high, points: d.points(\.cloudCoverHighPct)),
                ChartLine(name: tr("Mid", key: "Cloud line: Mid"), color: CloudColours.mid, points: d.points(\.cloudCoverMidPct)),
                ChartLine(name: tr("Low", key: "Cloud line: Low"), color: CloudColours.low, points: d.points(\.cloudCoverLowPct)),
            ].filter { !$0.points.isEmpty },
            yDomain: 0...130,
            trendStep: 5,
            facts: [
                (tr("Sunny spells"), sunny.map(d.span) ?? tr("not in the next 24 h")),
                (tr("High cloud"), pct(h.cloudCoverHighPct)),
                (tr("Middle cloud"), pct(h.cloudCoverMidPct)),
                (tr("Low cloud"), pct(h.cloudCoverLowPct)),
            ],
            rowing: tr("No effect on the rowing light; low cloud often comes with poor visibility."),
            source: tr("Cloud cover, DWD via Open-Meteo.")
        )
    }

    private static func pressure(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let change = d.forecast.pressureChange(after: h)
        let trend = change.map(PressureTrend.init(change:))
        let p = units.pressureUnit
        let values = d.timeline.compactMap(\.pressureHpa)
        let lo = values.min() ?? 1000, hi = values.max() ?? 1030
        var facts: [(String, String)] = []
        if let now = h.pressureHpa, let next = Self.pressureNext24(now: now, hours: d.next24) {
            facts.append((tr("Next 24 h"), next))
        }
        if let low = extreme(d.future, \.pressureHpa, highest: false) {
            facts.append((tr("Lowest next 7 days"), tr("%@ · %@", Format.pressure(low.pressureHpa), Format.dayTime(low.time))))
        }
        // The level alone says little while the pressure moves fast; the trend wins.
        let high = (h.pressureHpa ?? 1013) >= 1013
        let state: String = switch change {
        case let c? where c <= -1: high ? tr("high pressure, but falling: the weather is changing") : tr("low pressure and falling: unsettled")
        case let c? where c >= 1: high ? tr("high pressure and rising: settled") : tr("low pressure, but rising: improving")
        default: high ? tr("high pressure: mostly settled") : tr("low pressure: changeable")
        }
        facts.append((d.nowLabel, state))
        let rowing: String = switch change {
        case let c? where c <= -3: tr("Falling fast: wind is likely soon.")
        case let c? where c <= -1: tr("Falling: wind and rain more likely in the next day or two.")
        case let c? where c >= 1: tr("Rising: the weather is settling.")
        default: tr("Steady: no change in the weather expected from the pressure.")
        }
        return ConditionDetail(
            value: Format.pressure(h.pressureHpa),
            note: change.map { c in trend == .steady ? tr("Steady next 3 h") : tr("%@ %@ in 3 h", PressureTrend(change: c).title, Format.pressureChange(abs(c))) } ?? "",
            big: AnyView(PressureGauge(hpa: h.pressureHpa, trend: trend, arrowFont: .title2.weight(.bold)).frame(width: 90, height: 90)),
            unit: p.symbol,
            lines: [ChartLine(name: tr("Air pressure"), color: .purple, points: d.points { $0.pressureHpa.map(p.convert) })],
            // A few hPa around the values, so the change is easy to see.
            yDomain: p.convert((lo - 4).rounded(.down))...p.convert((hi + 6).rounded(.up)),
            trendStep: p.convert(0.25),
            facts: facts,
            rowing: (change ?? 0) <= -3 ? rowing : rowing + " " + tr("Falling %@ or more in 3 hours often means wind soon.", Format.pressureChange(3)),
            source: tr("Air pressure at sea level, DWD via Open-Meteo.")
        )
    }

    /// The pressure over the next 24 hours by its biggest move, so a dip
    /// that recovers by then is not called steady.
    static func pressureNext24(now: Double, hours: [ForecastHour]) -> String? {
        let known = hours.filter { $0.pressureHpa != nil }
        guard let lo = known.min(by: { $0.pressureHpa! < $1.pressureHpa! }),
              let hi = known.max(by: { $0.pressureHpa! < $1.pressureHpa! }),
              let last = known.last?.pressureHpa else { return nil }
        let fall = now - lo.pressureHpa!, rise = hi.pressureHpa! - now
        if max(fall, rise) < 1 { return tr("steady") }
        if fall >= rise {
            let value = Format.pressure(lo.pressureHpa), at = Format.dayTime(lo.time)
            return last - lo.pressureHpa! >= 1 ? tr("falls to %@ by %@, then rises", value, at) : tr("falls to %@ by %@", value, at)
        }
        let value = Format.pressure(hi.pressureHpa), at = Format.dayTime(hi.time)
        return hi.pressureHpa! - last >= 1 ? tr("rises to %@ by %@, then falls", value, at) : tr("rises to %@ by %@", value, at)
    }

    private static func thunderstorm(_ d: ConditionData) -> ConditionDetail {
        let top = extreme(d.next24, \.capeJkg, highest: true)
        var facts: [(String, String)] = []
        if let top, (top.capeJkg ?? 0) > 0 {
            facts.append((tr("Most energy next 24 h"), tr("%@ J/kg · %@", Format.number(top.capeJkg), Format.dayTime(top.time))))
        }
        facts.append((tr("Official thunderstorm warning"), d.warningNames(["GEWITTER"])))
        return ConditionDetail(
            value: stormLevel(d.now.light(for: Condition.thunderstorm.reasonNames)),
            note: !d.warningsChecked ? tr("Warnings not checked")
                : d.warnings(["GEWITTER"]).isEmpty ? tr("No official thunderstorm warning") : tr("Official thunderstorm warning"),
            unit: "J/kg",
            lines: [ChartLine(name: tr("Energy for storms (CAPE)"), color: .yellow, kind: .bars, points: d.points(\.capeJkg))],
            limits: [
                ChartLimit(value: 500, color: .orange, label: tr("Possible")),
                ChartLimit(value: 1000, color: .red, label: tr("Likely")),
            ],
            limitInfo: tr("CAPE is the energy the air has for rising, in J/kg. From 500 J/kg thunderstorms are possible if something sets them off (amber); from 1000 J/kg together with rain they are likely (red). This is the app's own estimate; an official thunderstorm warning always makes the light red."),
            yDomain: 0...max(1300, (d.timeline.compactMap(\.capeJkg).max() ?? 0) * 1.1),
            facts: facts,
            rowing: tr("If you hear thunder, head for the shore at once: lightning can strike 10 km ahead of a storm."),
            source: tr("Estimated from the forecast (CAPE); official warnings appear under the warnings.")
        )
    }

    private static func uvBand(_ uv: Double) -> String {
        switch uv.rounded() {
        case ..<3: tr("low")
        case ..<6: tr("moderate")
        case ..<8: tr("high")
        case ..<11: tr("very high")
        default: tr("extreme")
        }
    }

    private static func uv(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let top = extreme(d.next24, \.uvIndex, highest: true)
        let protect = d.firstRun(in: d.next24) { ($0.uvIndex ?? 0).rounded() >= 3 }
        let hot = d.future.first { ($0.apparentTemperatureC ?? 0) >= 25 }
        var facts: [(String, String)] = [(d.nowLabel, h.uvIndex.map { "\(Format.number($0)) (\(uvBand($0)))" } ?? "–")]
        if let top, let uv = top.uvIndex {
            facts.append((tr("Highest next 24 h"), tr("%@ (%@) · %@", Format.number(uv), uvBand(uv), Format.dayTime(top.time))))
        }
        facts.append((tr("Protection needed"), protect.map(d.span) ?? tr("not in the next 24 h")))
        if let days = d.forecast.daylight?.sorted(by: { $0.sunrise < $1.sunrise }),
           let day = days.first(where: { $0.sunset > .now }) {
            let hour: TimeInterval = 3600
            facts.append((tr("Low sun, glare"), "\(Format.time(day.sunrise))–\(Format.time(day.sunrise + hour)), \(Format.time(day.sunset - hour))–\(Format.time(day.sunset))"))
        }
        facts.append((tr("Feels %@ or more", Format.temperature(25)), hot.map { Format.dayTime($0.time) } ?? tr("not this week")))
        return ConditionDetail(
            value: Format.number(h.uvIndex),
            note: h.uvIndex.map(uvBand) ?? tr("No UV forecast"),
            unit: tr("UV"),
            lines: [ChartLine(name: tr("UV index"), color: .orange, kind: .bars, points: d.points(\.uvIndex))],
            limits: [
                ChartLimit(value: 3, color: .orange, label: tr("Moderate: protect")),
                ChartLimit(value: 6, color: .red, label: tr("High")),
                ChartLimit(value: 8, color: .purple, label: tr("Very high")),
            ],
            limitInfo: tr("These are the WHO UV bands: 0–2 low, 3–5 moderate, 6–7 high, 8–10 very high, 11 and more extreme. From 3 the WHO advises sun protection. On the water the surface reflects extra UV and outings are long, so the app gives its advice from 3. UV does not change the rowing light."),
            yDomain: 0...max(10, (d.timeline.compactMap(\.uvIndex).max() ?? 0) + 1),
            facts: facts,
            twoColumnFacts: true,
            rowing: protect == nil
                ? tr("No sun protection needed for UV in the next 24 hours; sunglasses still help against glare.")
                : tr("From UV 3: sunscreen SPF 30 or more, also on neck, ears and the backs of the knees, a cap and sunglasses. When it feels %@ or more, drink before and during the outing.", Format.temperature(25)),
            source: tr("UV index forecast via Open-Meteo; bands from the WHO. Glare times calculated by the app from sunrise and sunset.")
        )
    }

    private static func ice(_ d: ConditionData) -> ConditionDetail {
        if IceSeason.isOff(d.forecast.ice) {
            return ConditionDetail(
                value: tr("Off season"),
                note: tr("Ice estimates run from November to April. There is no ice estimate at this time of year."),
                facts: [(tr("Water"), Format.temperature(d.forecast.ice?.waterTemperatureC ?? d.water?.celsius, digits: 1))],
                rowing: tr("Never go onto the ice because of this app. Never row between ice floes; thin ice cuts hulls."),
                source: Condition.ice.explanation
            )
        }
        if let ice = d.forecast.ice, ice.status != "unavailable" {
            var facts: [(String, String)] = [(tr("Water"), Format.temperature(ice.waterTemperatureC ?? d.water?.celsius, digits: 1))]
            if let cm = ice.thicknessCm, cm > 0 { facts.append((tr("Ice"), tr("About %@ cm, estimated", Format.number(cm)))) }
            if let satellite = ice.satellite { facts.append((tr("Satellite"), satellite.summary)) }
            return ConditionDetail(
                value: ice.title,
                note: ice.detail,
                facts: facts,
                rowing: tr("Never go onto the ice because of this app. Never row between ice floes; thin ice cuts hulls."),
                source: Condition.ice.explanation
            )
        }
        let warm = (d.water?.celsius ?? 0) >= 8
        return ConditionDetail(
            value: warm ? tr("No ice") : tr("No data yet"),
            note: warm ? tr("Water %@, too warm for ice", Format.temperature(d.water?.celsius, digits: 1)) : tr("Check the lake yourself"),
            facts: [(tr("Water"), Format.temperature(d.water?.celsius, digits: 1)), (tr("Basis"), tr("measured water temperature"))],
            rowing: tr("Never go onto the ice because of this app. Never row between ice floes; thin ice cuts hulls."),
            source: tr("An ice estimate from water temperature and frost is being built; until then check the lake yourself in winter.")
        )
    }

    private static func daylight(_ d: ConditionData) -> ConditionDetail {
        let days = (d.forecast.daylight ?? []).sorted { $0.sunrise < $1.sunrise }
        let moment = d.moment
        let state = d.forecast.sunState(at: moment)
        let calendar = Calendar.current
        let today = days.first { calendar.isDate($0.sunrise, inSameDayAs: moment) } ?? days.first
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: moment).flatMap { next in days.first { calendar.isDate($0.sunrise, inSameDayAs: next) } }
        var facts: [(String, String)] = []
        if let today {
            facts += [(tr("Sunrise"), Format.time(today.sunrise)), (tr("Sunset"), Format.time(today.sunset)),
                      (tr("Daylight"), Format.duration(from: today.sunrise, to: today.sunset))]
            if let tomorrow {
                let change = Int((tomorrow.sunset.timeIntervalSince(tomorrow.sunrise) - today.sunset.timeIntervalSince(today.sunrise)) / 60)
                facts.append((tr("Tomorrow"), change < 0 ? tr("%@ min shorter", "\(-change)") : tr("%@ min longer", "\(change)")))
                facts += [(tr("Tomorrow sunrise"), Format.time(tomorrow.sunrise)), (tr("Tomorrow sunset"), Format.time(tomorrow.sunset))]
            }
        }
        let value: String, note: String
        switch state {
        case let .up(_, sunset)?:
            value = tr("Sunset %@", Format.time(sunset))
            note = tr("Sun is up. Rowing advised for %@ until sunset.", Format.timeLeft(from: moment, to: sunset))
        case let .down(sunrise, _)?:
            value = tr("Sunrise %@", Format.time(sunrise))
            note = tr("Sun is down. Rowing is advised again from sunrise at %@.", Format.time(sunrise))
        case nil:
            value = "–"
            note = ""
        }
        return ConditionDetail(
            value: value,
            note: note,
            big: today.map { AnyView(SunPath(sunrise: $0.sunrise, sunset: $0.sunset, at: moment).frame(width: 120, height: 60)) },
            facts: facts,
            twoColumnFacts: true,
            rowing: tr("Rowing is advised from sunrise to sunset; in twilight carry lights."),
            source: tr("Calculated by the app from the launch point's position.")
        )
    }
}

/// Where the water temperature is measured, with the distance from the
/// launch point and a link to the station's page.
struct WaterStationMap: View {
    let station: WaterStation
    let place: Coordinate
    /// The live map after a tap; a still picture until then.
    @State private var live = false
    @State private var address: String?

    private var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon) }
    private var region: MKCoordinateRegion { MKCoordinateRegion(center: coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tr("Where it is measured"), systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
            Group {
                if live {
                    Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
                        Marker(station.name ?? tr("Lake station"), systemImage: "thermometer.medium", coordinate: coordinate)
                            .tint(.cyan)
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                } else {
                    Button { live = true } label: {
                        LaunchPointSnapshot(coordinate: coordinate, region: region, symbol: "thermometer.medium", tint: .cyan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr("Shows a map you can move"))
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let distance = station.distanceM {
                        Text(tr("%@, %@ from the launch point", station.name ?? tr("Lake station"), Format.distance(distance)))
                    } else if let name = station.name {
                        Text(name)
                    }
                    if let address {
                        Label(address, systemImage: "mappin")
                            .labelStyle(.titleAndIcon)
                    }
                }
                Spacer(minLength: 0)
                if let url = station.url {
                    Link(tr("Station page"), destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task(id: place) { address = await StationAddress.near(place) }
    }
}

/// The street or place nearest a station, as the phone's maps know it
/// ("Seepromenade, Starnberg"); stations have coordinates but no address.
/// Asked once per station and app run.
@MainActor
enum StationAddress {
    private static var known: [Coordinate: String] = [:]

    static func near(_ place: Coordinate) async -> String? {
        if let known = known[place] { return known }
        let location = CLLocation(latitude: place.lat, longitude: place.lon)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: AppSettings.shared.locale).first else { return nil }
        let parts = [mark.thoroughfare ?? mark.name, mark.locality].compactMap { $0 }
        // A place's name is often its town too.
        let unique = parts.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let text = unique.isEmpty ? nil : unique.joined(separator: ", ")
        known[place] = text
        return text
    }
}

/// At the bottom of a larger view, as in the Weather app: the unit of its
/// value, the same setting as in Settings > Units, so every screen follows.
private struct DetailUnitRow: View {
    let condition: Condition

    var body: some View {
        let settings = AppSettings.shared
        if [.temperature, .feelsLike, .waterTemperature, .wind, .waves, .precipitation, .visibility, .pressure].contains(condition) {
            row(settings)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func row(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        switch condition {
        case .temperature, .feelsLike, .waterTemperature:
            UnitRow(condition: condition, title: tr("Units"), selection: $settings.temperatureUnit)
        case .wind: UnitRow(condition: condition, title: tr("Units"), selection: $settings.windUnit)
        case .waves: UnitRow(condition: condition, title: tr("Units"), selection: $settings.waveUnit)
        case .precipitation: UnitRow(condition: condition, title: tr("Units"), selection: $settings.rainUnit)
        case .visibility: UnitRow(condition: condition, title: tr("Units"), selection: $settings.distanceUnit)
        case .pressure: UnitRow(condition: condition, title: tr("Units"), selection: $settings.pressureUnit)
        default: EmptyView()
        }
    }
}
