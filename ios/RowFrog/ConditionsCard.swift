import Charts
import MapKit
import SwiftUI

/// The "Current conditions" card on a club page: small tiles, each with its
/// value, a short detail and a small graphic. Tapping a tile opens a larger
/// view with a chart that can be dragged from yesterday to the next 7 days,
/// the rowing limits and advice.
struct ConditionsCard: View {
    let forecast: ClubForecast
    let hour: ForecastHour
    @State private var open: Condition?

    var body: some View {
        let data = ConditionData(forecast: forecast, now: hour)
        Card(title: tr("Current conditions"), symbol: "gauge.with.dots.needle.33percent", legend: .conditions) {
            HStack(spacing: 10) {
                SkyIcon(sky: Sky(hour: hour), night: hour.sunUp == false).font(.system(size: 36))
                VStack(alignment: .leading, spacing: 0) {
                    Text(Sky(hour: hour).title).font(.headline)
                    Text(tr("%@ · feels like %@", Format.degrees(hour.temperatureC), Format.degrees(hour.apparentTemperatureC)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            // Pairs that belong together share a row, and both tiles of a row are as tall.
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: Condition.tileOrder.count, by: 2)), id: \.self) { i in
                    GridRow {
                        ForEach(Condition.tileOrder[i..<min(i + 2, Condition.tileOrder.count)]) { condition in
                            Button {
                                open = condition
                            } label: {
                                ConditionTile(condition: condition, data: data)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(tr("Opens a chart and more about this value"))
                        }
                    }
                }
            }
        }
        .sheet(item: $open) { condition in
            ConditionDetailView(condition: condition, data: data)
        }
        .task {
            // Screenshot hook: `-RWOpenCondition wind` opens that view.
            // Only on the page `-RWOpenClub` opens: the pages beside it would race it for the sheet.
            let page = UserDefaults.standard.string(forKey: "RWOpenClub")
            if let raw = UserDefaults.standard.string(forKey: "RWOpenCondition"), page == nil || page == forecast.clubId {
                try? await Task.sleep(for: .milliseconds(500))
                open = Condition(rawValue: raw)
            }
        }
    }
}

/// The forecast around one hour, as the tiles and larger views need it.
struct ConditionData {
    let forecast: ClubForecast
    let now: ForecastHour
    /// Yesterday to 7 days ahead when the backend sends it, else the next 48 hours.
    let timeline: [ForecastHour]

    init(forecast: ClubForecast, now: ForecastHour) {
        self.forecast = forecast
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

    /// Hours from now; negative is the past.
    func x(_ date: Date) -> Double { date.timeIntervalSince(now.time) / 3600 }

    var next24: [ForecastHour] { timeline.filter { (0..<24).contains(x($0.time)) } }
    var future: [ForecastHour] { timeline.filter { x($0.time) >= 0 } }
    var water: WaterTemperature? { forecast.waterTemperature }
    /// Without a lake station: the ice model's water temperature, worked out
    /// from the air temperatures of the last weeks. Shown marked as estimated;
    /// the rowing light's cold-water rules only use measurements.
    var estimatedWater: Double? { forecast.estimatedWaterC }

    func points(_ value: (ForecastHour) -> Double?) -> [ChartPoint] {
        timeline.compactMap { h in value(h).map { ChartPoint(x: x(h.time), y: $0) } }
    }

    /// Current DWD warnings for the place whose event contains one of these words.
    func warnings(_ words: [String]) -> [DWDWarning] {
        (forecast.warnings?.items ?? []).filter { w in
            !w.isLake && (w.expires ?? .distantFuture) > now.time && words.contains { w.event.uppercased().contains($0) }
        }
    }

    func warningNames(_ words: [String]) -> String {
        let found = warnings(words)
        guard !found.isEmpty else { return tr("None") }
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

// MARK: - Tiles

private struct ConditionTile: View {
    let condition: Condition
    let data: ConditionData
    @Environment(\.surface) private var surface

    private var hour: ForecastHour { data.now }

    var body: some View {
        Group {
            if condition == .daylight {
                sunTile
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    header(condition.title)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                        // Every graphic gets the same height, so all tiles are as tall.
                        accessory.frame(height: Self.graphicHeight)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .topLeading)
        .background(surface.tile, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    static let graphicHeight: CGFloat = 44

    private func header(_ title: String) -> some View {
        HStack(spacing: 4) {
            ConditionIcon(condition: condition).frame(width: 16)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let light = hour.light(for: condition.reasonNames) {
                TrafficLightDot(light: light, size: 8)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var value: String {
        switch condition {
        case .temperature: Format.degrees(hour.temperatureC)
        case .feelsLike: Format.degrees(hour.apparentTemperatureC)
        case .humidity: hour.humidityPct.map { "\(Format.number($0)) %" } ?? "–"
        case .wind: Format.wind(hour.windSpeedMs)
        case .waves: Format.waves(hour.waveHeightM)
        case .waterTemperature:
            if data.water == nil, let estimate = data.estimatedWater { "≈ " + Format.degrees(estimate, digits: 0) } else { Format.degrees(data.water?.celsius, digits: 1) }
        case .precipitation: (hour.precipitationMm ?? 0) >= 0.1 ? Format.rain(hour.precipitationMm) : tr("Dry")
        case .visibility: Format.distance(hour.visibilityM)
        case .cloudCover: "\(Format.number(hour.cloudCoverPct)) %"
        case .pressure: hour.pressureHpa.map { Format.number($0) } ?? "–"
        case .thunderstorm: stormLevel(hour.light(for: condition.reasonNames))
        case .uvIndex: Format.number(hour.uvIndex)
        case .ice: iceGuess.value
        case .daylight: ""
        }
    }

    private var detail: String {
        switch condition {
        case .temperature:
            let temps = data.next24.compactMap(\.temperatureC)
            guard let hi = temps.max(), let lo = temps.min() else { return "" }
            return tr("High %@ · low %@", Format.degrees(hi), Format.degrees(lo))
        case .feelsLike:
            return feelsLikeNote(hour) ?? ""
        case .humidity:
            return hour.dewPointC.map { tr("Dew point %@", Format.degrees($0)) } ?? ""
        case .wind:
            let gust = tr("Gusts %@", Format.windNumber(hour.windGustMs))
            return hour.windFromDeg.map { gust + " · " + tr("from %@", Format.compass($0)) } ?? gust
        case .waves:
            guard let fetch = hour.fetchM else { return "" }
            return fetch < 50 ? tr("Wind blows off the shore") : tr("%@ open water upwind", Format.distance(fetch))
        case .waterTemperature:
            if data.water == nil, data.estimatedWater != nil { return tr("Estimated, not measured") }
            return data.water.map { tr("Measured %@", Format.time($0.measuredAt)) } ?? tr("No lake station")
        case .precipitation:
            if (hour.precipitationMm ?? 0) >= 0.1 { return Sky(hour: hour).precipitationKind ?? "" }
            guard let wet = data.next24.first(where: { ($0.precipitationMm ?? 0) >= 0.1 }) else { return tr("Dry next 24 h") }
            return tr("%@ from %@", Sky(hour: wet).precipitationKind ?? tr("Rain"), Format.time(wet.time))
        case .visibility:
            if (hour.visibilityM ?? .infinity) < 1000 { return tr("Fog") }
            guard let fog = data.next24.first(where: { ($0.visibilityM ?? .infinity) < 1000 }) else { return tr("No fog") }
            return tr("Fog from %@", Format.time(fog.time))
        case .cloudCover:
            return hour.cloudCoverLowPct.map { tr("Low cloud %@ %%", Format.number($0)) } ?? ""
        case .pressure:
            guard let change = data.forecast.pressureChange(after: hour) else { return "hPa" }
            return "hPa · " + PressureTrend(change: change).title.lowercased()
        case .thunderstorm:
            return data.warnings(["GEWITTER"]).isEmpty ? tr("No DWD warning") : tr("DWD warning")
        case .uvIndex:
            guard let top = data.next24.filter({ $0.uvIndex != nil }).max(by: { $0.uvIndex! < $1.uvIndex! }) else { return "" }
            return tr("Max %@ · %@", Format.number(top.uvIndex), Format.day(top.time))
        case .ice:
            return iceGuess.detail
        case .daylight:
            return ""
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch condition {
        case .temperature:
            ScaleBar(fraction: ((hour.temperatureC ?? 0) + 10) / 45, colors: [.blue, .teal, .green, .orange, .red])
        case .feelsLike:
            ScaleBar(fraction: ((hour.apparentTemperatureC ?? 0) + 10) / 45, colors: [.blue, .teal, .green, .orange, .red])
        case .humidity:
            HStack(spacing: 0) {
                SymbolFill(outline: "drop", filled: "drop.fill", fraction: (hour.humidityPct ?? 0) / 100, color: .teal, size: 18)
                if let air = hour.temperatureC, let dew = hour.dewPointC {
                    DewGap(air: air, dewPoint: dew)
                }
            }
        case .wind:
            if let from = hour.windFromDeg {
                WindDial(speed: Format.windNumber(hour.windSpeedMs), fromDeg: from, unit: AppSettings.shared.windUnit.symbol)
                    .frame(width: 44, height: 44)
            }
        case .waves:
            let userLimits = AppSettings.shared.limits
            let top = userLimits.value(.waveRed) * 4 / 3
            ScaleBar(fraction: (hour.waveHeightM ?? 0) / top,
                     zones: [(0, .green), (userLimits.value(.waveAmber) / top, .orange), (userLimits.value(.waveRed) / top, .red)])
        case .waterTemperature:
            if let c = data.water?.celsius {
                ScaleBar(fraction: c / 25, zones: [(0, .red), (0.4, .orange), (0.6, .green)])
            }
        case .precipitation:
            SparkBars(values: data.future.prefix(8).map { $0.precipitationMm ?? 0 })
        case .visibility:
            // 100 m at the left to 40 km at the right, stretched at the bottom.
            ScaleBar(fraction: log10(max(hour.visibilityM ?? 40_000, 100) / 100) / log10(400),
                     zones: [(0, .red), (0.27, .orange), (0.384, .green)])
        case .cloudCover:
            HStack(spacing: 0) {
                SymbolFill(outline: "cloud", filled: "cloud.fill", fraction: (hour.cloudCoverPct ?? 0) / 100, color: .gray, size: 18)
                if let high = hour.cloudCoverHighPct, let mid = hour.cloudCoverMidPct, let low = hour.cloudCoverLowPct {
                    CloudLayers(layers: [(tr("H"), high / 100), (tr("M"), mid / 100), (tr("L"), low / 100)])
                }
            }
        case .pressure:
            PressureGauge(hpa: hour.pressureHpa, trend: data.forecast.pressureChange(after: hour).map(PressureTrend.init(change:)))
                .frame(width: 44, height: 44)
        case .thunderstorm:
            LevelSegments(level: stormRank(hour.light(for: condition.reasonNames)), colors: [.green, .orange, .red])
        case .uvIndex:
            ScaleBar(fraction: (hour.uvIndex ?? 0) / 11, colors: uvColors)
        case .ice, .daylight:
            EmptyView()
        }
    }

    /// Until the ice estimate is in the app: warm water cannot freeze over.
    private var iceGuess: (value: String, detail: String) {
        if let ice = data.forecast.ice, ice.status != "unavailable" {
            return (ice.title, ice.detail)
        }
        if let c = data.water?.celsius, c >= 8 {
            return (tr("No ice"), tr("Water too warm"))
        }
        return (tr("No data yet"), tr("Check the lake yourself"))
    }

    private var sunTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch data.forecast.sunState(at: .now) {
            case let .up(sunrise, sunset)?:
                header(tr("Sunset"))
                sunLine(Format.time(sunset), tr("Sunrise %@", Format.time(sunrise)), sunrise: sunrise, sunset: sunset)
            case let .down(sunrise, sunset)?:
                header(tr("Sunrise"))
                sunLine(Format.time(sunrise), tr("Sunset %@", Format.time(sunset)), sunrise: sunrise, sunset: sunset)
            case nil:
                header(condition.title)
                Text("–").font(.title3.weight(.semibold))
            }
        }
    }

    /// Laid out like the other tiles: value and detail on the left, the sun path on the right.
    private func sunLine(_ value: String, _ detail: String, sunrise: Date, sunset: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            SunPath(sunrise: sunrise, sunset: sunset, lineWidth: 2).frame(width: 64, height: Self.graphicHeight)
        }
    }
}

private let uvColors: [Color] = [.green, .yellow, .orange, .red, .purple]

private func stormRank(_ light: Light?) -> Int {
    switch light {
    case .red: 3
    case .amber: 2
    default: 1
    }
}

private func stormLevel(_ light: Light?) -> String {
    switch light {
    case .red: tr("High")
    case .amber: tr("Possible")
    default: tr("Low")
    }
}

/// The sun path for one day from its sunrise and sunset, with the sun now.
struct SunPath: View {
    let sunrise: Date, sunset: Date
    var lineWidth: CGFloat = 3

    var body: some View {
        let rise = clock(sunrise), down = clock(sunset)
        SunPathGraph(firstLight: rise, sunrise: rise, noon: (rise + down) / 2, sunset: down, lastLight: down,
                     now: clock(.now), lineWidth: lineWidth)
    }

    private func clock(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }
}

// MARK: - Larger views

struct ChartPoint: Identifiable {
    let x: Double
    let y: Double
    var id: Double { x }
}

struct ChartLine: Identifiable {
    enum Kind { case line, bars }
    let name: String
    let color: Color
    var kind: Kind = .line
    let points: [ChartPoint]
    var id: String { name }
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

struct ConditionDetailView: View {
    let data: ConditionData
    @Environment(\.dismiss) private var dismiss
    @State private var condition: Condition
    /// Which way the last change went, for the slide.
    @State private var forward = true
    @State private var showLimits = UserDefaults.standard.bool(forKey: "RWLimitInfo")
    /// Chart lines switched off from the legend, per view. Kept while swiping
    /// between views; a new sheet starts with every line on.
    @State private var hiddenLines: [Condition: Set<String>] = [:]
    /// Where the chart sits, so a drag on it moves the time instead of the view.
    /// Kept outside SwiftUI's state: it changes on every frame of scrolling,
    /// and only a swipe's end reads it.
    @State private var chartFrame = ChartFrame()
    /// The jump menu's titles with each view's value, worked out once.
    @State private var menuTitles: [Condition: String] = [:]

    /// The views the arrows and swipes go through: every condition, or only
    /// the values of the top tile when opened from there.
    private let order: [Condition]

    init(condition: Condition, data: ConditionData, order: [Condition] = Condition.tileOrder) {
        self.data = data
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
            .simultaneousGesture(swipe)
            .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: true))
            .navigationTitle(condition.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    jumpMenu
                }
            }
        }
    }

    private static let space = "conditionDetail"

    final class ChartFrame {
        var rect: CGRect = .zero
    }

    @ViewBuilder
    private func page(_ condition: Condition) -> some View {
        let detail = ConditionDetail(condition, data)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.compact.left").foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.value).font(.system(size: 40, weight: .light)).minimumScaleFactor(0.6).lineLimit(1)
                    Text(detail.note).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let big = detail.big { big }
                Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .contain)
            if !detail.lines.isEmpty {
                let hidden = hiddenLines[condition] ?? []
                ConditionChart(detail: detail, data: data, hidden: hidden)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: ChartFrameKey.self, value: geo.frame(in: .named(Self.space)))
                        }
                    }
                    .onPreferenceChange(ChartFrameKey.self) { chartFrame.rect = $0 }
                if detail.lines.count > 1 {
                    legend(detail, condition: condition, hidden: hidden)
                }
            }
            if let info = detail.limitInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation { showLimits.toggle() }
                    } label: {
                        Label(tr("About the limits"), systemImage: "info.circle")
                            .font(.subheadline)
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
            facts(detail)
            if condition == .waterTemperature, let water = data.water, let station = water.station, let place = station.coordinate {
                WaterStationMap(station: station, place: place)
            }
            Label(detail.rowing, systemImage: "figure.rower")
                .font(.subheadline)
            Text(detail.source).font(.caption2).foregroundStyle(.secondary)
            neighbours(of: condition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                    // grey "All cloud" line): an empty ring and struck-through name.
                    Label {
                        Text(line.name).strikethrough(off)
                    } icon: {
                        Image(systemName: off ? "circle" : "circle.fill")
                    }
                    .foregroundStyle(line.color)
                    .opacity(off ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityValue(off ? tr("Hidden") : tr("Shown"))
                .accessibilityHint(tr("Shows or hides this line in the chart"))
            }
        }
        .font(.caption2)
    }

    /// The names of the views before and after, which a swipe opens.
    private func neighbours(of condition: Condition) -> some View {
        HStack {
            Button { step(-1) } label: { Label(neighbour(of: condition, by: -1).title, systemImage: "chevron.left") }
            Spacer()
            Button { step(1) } label: {
                Label(neighbour(of: condition, by: 1).title, systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.top, 4)
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
                if chartFrame.rect.contains(value.startLocation) { return }
                step(dx < 0 ? 1 : -1)
            }
    }

    /// The symbol in the corner: a tap lists every view with its value.
    private var jumpMenu: some View {
        Menu {
            Picker(tr("Go to"), selection: Binding(get: { condition }, set: { new in
                forward = (order.firstIndex(of: new) ?? 0) > (order.firstIndex(of: condition) ?? 0)
                withAnimation(.easeInOut(duration: 0.25)) { condition = new }
            })) {
                ForEach(order) { c in
                    Label(menuTitles[c] ?? c.title, systemImage: c.symbol).tag(c)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 2) {
                ConditionIcon(condition: condition)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(.blue)
            .accessibilityLabel(tr("Go to another value"))
        }
        .task { if menuTitles.isEmpty { menuTitles = Dictionary(uniqueKeysWithValues: order.map { ($0, menuTitle($0)) }) } }
    }

    private func menuTitle(_ c: Condition) -> String {
        let value = ConditionDetail(c, data).value
        return value.isEmpty ? c.title : "\(c.title) · \(value)"
    }

    @ViewBuilder
    private func facts(_ detail: ConditionDetail) -> some View {
        if detail.twoColumnFacts {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 8) {
                ForEach(Array(detail.facts.enumerated()), id: \.offset) { _, fact in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fact.0).font(.caption).foregroundStyle(.secondary)
                        Text(fact.1).font(.subheadline.weight(.semibold))
                    }
                }
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(detail.facts.enumerated()), id: \.offset) { _, fact in
                    GridRow {
                        Text(fact.0).foregroundStyle(.secondary)
                        Text(fact.1).fontWeight(.semibold)
                    }
                }
            }
            .font(.subheadline)
        }
    }
}

private struct ChartFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Title first, icon after it: for the "next" button.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// The chart of a larger view: 24 hours visible, dragged sideways from
/// yesterday to 7 days ahead, limits as dashed lines, and one arrow per
/// 3 hours on top (rising, falling, steady; or where the wind blows to).
/// The limit names stay at the left edge while the chart slides under them.
private struct ConditionChart: View {
    let detail: ConditionDetail
    let data: ConditionData
    /// Lines switched off in the legend.
    var hidden: Set<String> = []
    /// Where the visible 24 hours start when the view opens: an hour before now.
    private static let start = -1.0
    /// The hour at the left edge of the visible 24 hours.
    @State private var scrollX = start
    /// The hour under the finger while scrubbing (hold, then slide), as in the Stocks app.
    /// Screenshot hook: `-RWChartSelect 5` shows the scrub line five hours from now.
    @State private var selectedX: Double? = UserDefaults.standard.object(forKey: "RWChartSelect") != nil
        ? UserDefaults.standard.double(forKey: "RWChartSelect") : nil

    private struct Arrow: Identifiable {
        let x: Double
        let symbol: String
        var rotation = 0.0
        var id: Double { x }
    }

    private var range: ClosedRange<Double> {
        let xs = detail.lines.flatMap { $0.points.map(\.x) }
        let lo = xs.min() ?? 0, hi = xs.max() ?? 24
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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        limitLabels(proxy: proxy, geo: geo)
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: 200)
                .sensoryFeedback(.selection, trigger: selectedX == nil)
            // Under the chart, where it covers nothing: the hint, or once dragged
            // away from now, one tap back.
            if !detail.history && abs(scrollX - Self.start) > 0.5 {
                Button {
                    withAnimation { scrollX = Self.start }
                } label: {
                    Label(tr("Back to now"), systemImage: scrollX > Self.start ? "arrow.uturn.backward" : "arrow.uturn.forward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .transition(.opacity)
            } else {
                Text(detail.chartNote ?? (detail.history ? tr("Measurements of the last days. Touch the chart to read a value.") : tr("Drag the chart: back to yesterday, forward up to 7 days. Hold, then slide to read a value.")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The point of a line nearest to an hour.
    private func nearest(_ line: ChartLine, to x: Double) -> ChartPoint? {
        line.points.min { abs($0.x - x) < abs($1.x - x) }
    }

    /// A value with as many decimals as it needs to be read: 0.19, 5.2, 14.
    private func valueText(_ y: Double) -> String {
        let digits = abs(y) < 1 ? 2 : abs(y) < 10 ? 1 : 0
        return Format.number(y, digits: digits) + (detail.unit.isEmpty ? "" : " " + detail.unit)
    }

    /// The scrub line's label: the hour and each shown line's value.
    private func callout(_ x: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.dayTime(date(x.rounded()))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(shownLines) { line in
                if let p = nearest(line, to: x) {
                    HStack(spacing: 4) {
                        if shownLines.count > 1 { Circle().fill(line.color).frame(width: 6, height: 6) }
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
            ForEach(shownLines) { line in
                ForEach(line.points) { p in
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
            if let x = selectedX {
                RuleMark(x: .value("Hour", x))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(x)
                    }
                ForEach(shownLines.filter { $0.kind == .line }) { line in
                    if let p = nearest(line, to: x) {
                        PointMark(x: .value("Hour", p.x), y: .value("Value", p.y))
                            .foregroundStyle(line.color)
                            .symbolSize(50)
                    }
                }
            }
            ForEach(arrows) { a in
                PointMark(x: .value("Hour", a.x), y: .value("Value", arrowY))
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        Image(systemName: a.symbol).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(a.rotation))
                    }
            }
        }
        .chartXScale(domain: range)
        .chartXAxis {
            AxisMarks(values: axisHours) { value in
                AxisGridLine()
                AxisValueLabel(anchor: .top) {
                    // Labels right at the visible edges would be cut in half.
                    if let x = value.as(Double.self), detail.history || (x - scrollX > 1.2 && scrollX + 24 - x > 1.2) {
                        Text(label(x))
                    }
                }
            }
        }
        // Over the values on the right; on the left a dragged chart cut it off.
        .chartYAxisLabel(position: .topTrailing) { Text(detail.unit) }
        .chartPlotStyle { $0.padding(.horizontal, 16) }
    }

    @ChartContentBuilder
    private func mark(_ line: ChartLine, _ p: ChartPoint) -> some ChartContent {
        switch line.kind {
        case .line:
            LineMark(x: .value("Hour", p.x), y: .value("Value", p.y), series: .value("Series", line.name))
                .foregroundStyle(line.color)
                .interpolationMethod(.monotone)
        case .bars:
            BarMark(x: .value("Hour", p.x), y: .value("Value", p.y), width: .fixed(5))
                .foregroundStyle(line.color.opacity(0.7))
        }
    }

    /// A limit as one dashed line; its name is drawn over the chart by `limitLabels`.
    @ChartContentBuilder
    private func limitRules(_ limit: ChartLimit) -> some ChartContent {
        RuleMark(y: .value("Limit", limit.value))
            .foregroundStyle(limit.color)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
            let visibleRight = proxy.position(forX: scrollX + 24).map { plot.minX + $0 } ?? plot.maxX
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
    private var axisHours: [Double] {
        let step = detail.history ? 24 : 6
        return stride(from: range.lowerBound.rounded(.down), through: range.upperBound, by: 1).filter { x in
            Calendar.current.component(.hour, from: date(x)) % step == 0
                && Calendar.current.component(.minute, from: date(x)) == 0
        }
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
        var facts: [(String, String)] = [(tr("Now"), Format.temperature(h.temperatureC))]
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
            big: h.temperatureC.flatMap { air in h.dewPointC.map { AnyView(DewGap(air: air, dewPoint: $0).scaleEffect(1.6).frame(width: 80, height: 60)) } },
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
                return tr("Within your own limit, but above the app's usual limit for %@: take extra care.", userLimits.boat.inSentence)
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
            big: h.windFromDeg.map { AnyView(WindDial(speed: Format.windNumber(h.windSpeedMs), fromDeg: $0, unit: w.symbol).frame(width: 100, height: 100)) },
            unit: w.symbol,
            lines: [
                ChartLine(name: tr("Wind"), color: .blue, points: d.points { $0.windSpeedMs.map(w.convert) }),
                ChartLine(name: tr("Gusts"), color: .purple, points: d.points { $0.windGustMs.map(w.convert) }),
            ],
            limits: [
                line(.windAmber, w.convert, .orange, tr("Wind: row with care")),
                line(.windRed, w.convert, .red, tr("Wind: stay ashore")),
            ],
            limitInfo: tr("Amber from %@ (Beaufort 4, the first whitecaps) and red from %@ (Beaufort 5, many whitecaps): in a single or double the boat gets hard to steer and water comes over the side. Gusts have their own limits: amber from %@ and red from %@ (46 km/h), the level at which DWD issues a strong-wind warning and the lake's warning lights start flashing. These are the app's starting values for small boats.",
                          RowingLimit.windAmber.format(5.5), RowingLimit.windRed.format(8), RowingLimit.gustAmber.format(8), RowingLimit.gustRed.format(12.8))
                + inUse([(tr("Wind"), .windAmber, .windRed), (tr("Gusts"), .gustAmber, .gustRed)]),
            windArrows: true,
            chartNote: tr("The arrows above the chart show where the wind blows to. Drag the chart: back to yesterday, forward up to 7 days. Hold, then slide to read a value."),
            facts: facts,
            rowing: advice(d, Condition.wind.reasonNames,
                           red: tr("Too windy now: stay ashore."),
                           amber: tr("Windy now: row with care and stay near the shore."),
                           later: tr("Calm enough now; the wind reaches the limit from %@."),
                           calm: tr("Calm enough for the next 24 hours.")),
            source: tr("Wind at 10 m and gusts, DWD ICON via Open-Meteo.")
        )
    }

    private static var userLimits: RowingLimits { units.limits }

    /// A limit line, marked when it is the user's own.
    private static func line(_ limit: RowingLimit, _ convert: (Double) -> Double, _ color: Color, _ label: String) -> ChartLimit {
        ChartLimit(value: convert(userLimits.value(limit)), color: color, label: userLimits.isMine(limit) ? tr("%@ (your limit)", label) : label)
    }

    /// The limits in use, after the explanation of the app's own.
    private static func inUse(_ pairs: [(String, RowingLimit, RowingLimit)]) -> String {
        let parts = pairs.map { tr("%@ amber from %@, red above %@", $0.0, $0.1.format(userLimits.value($0.1)), $0.2.format(userLimits.value($0.2))) }
        return " " + tr("In use for %@: %@. You can change them under Settings, Rowing limits.", userLimits.boat.inSentence, parts.joined(separator: "; "))
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
                line(.waveAmber, u.convert, .orange, tr("Row with care")),
                line(.waveRed, u.convert, .red, tr("Stay ashore")),
            ],
            limitInfo: tr("Amber from %@ and red from %@ wave height. A racing single sits only about 10–15 cm above the water at its side, so from about 15 cm waves start to wash in; from about 30 cm the boat fills and capsizing becomes likely. The waves are calculated from the wind and the open water upwind, not measured.",
                          Format.waves(0.15), Format.waves(0.3))
                + inUse([(tr("Waves"), .waveAmber, .waveRed)]),
            yDomain: 0...max(u.convert(userLimits.value(.waveRed) * 4 / 3), u.convert(d.timeline.compactMap(\.waveHeightM).max() ?? 0) * 1.3),
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
        let jacket = Format.temperature(userLimits.value(.lifeJacket))
        facts.append((tr("Life jacket"), userLimits.isMine(.lifeJacket) ? tr("%@ (your limit)", tr("advised below %@", jacket)) : tr("advised below %@", jacket)))
        let rowing: String
        let veryCold = Format.temperature(RowingLimits.coldWaterC)
        switch now?.celsius {
        case let c? where c < RowingLimits.coldWaterC:
            rowing = tr("Below %@ wear a life jacket, stay near the shore and row with a second boat or a safety boat nearby. Wear clothes that keep you warm when wet.", veryCold)
        case let c? where c < userLimits.value(.lifeJacket):
            rowing = tr("Below %@ a capsize can cause cold-water shock: we advise a life jacket and clothes that keep you warm when wet.", jacket)
        case let c? where c < 15:
            rowing = tr("Below %@ wear clothes that keep you warm when wet. Below %@ we advise a life jacket.", Format.temperature(15), jacket)
        case .some:
            rowing = tr("Warm enough that a capsize is not a cold-water danger.")
        case nil:
            rowing = tr("No lake station: check the water yourself. Below %@ we advise a life jacket.", jacket)
        }
        let estimate = now == nil ? d.estimatedWater : nil
        return ConditionDetail(
            value: estimate.map { "≈ " + Format.degrees($0, digits: 0) } ?? Format.degrees(now?.celsius, digits: 1),
            note: now.map { tr("Measured %@", Format.dayTime($0.measuredAt)) }
                ?? (estimate != nil ? tr("Estimated from the air temperatures of the last weeks, not measured") : tr("No lake station")),
            unit: t.symbol,
            lines: history.isEmpty ? [] : [ChartLine(name: tr("Water"), color: .cyan, points: history.map { ChartPoint(x: d.x($0.time), y: t.convert($0.celsius)) })],
            limits: [
                line(.lifeJacket, t.convert, .orange, tr("Cold-water shock: life jacket")),
                ChartLimit(value: t.convert(RowingLimits.coldWaterC), color: .red, label: tr("Very cold")),
            ],
            limitInfo: tr("Below about %@ a fall into the water causes cold-water shock: a gasp and fast breathing in the first minute. A life jacket keeps your head above water through it, so the app advises one from %@ down. A rule of thumb says the minutes you can still help yourself in the water are about the water temperature in °C, so about 10 minutes at 10 °C. That is why the advice gets stricter below %@: stay near the shore and don't row alone. Your club's own rules come first.",
                          Format.temperature(15), jacket, veryCold),
            yDomain: t.convert(0)...t.convert(max(20, (history.map(\.celsius).max() ?? 0) + 2)),
            history: true,
            facts: facts,
            rowing: rowing,
            source: tr("Gewässerkundlicher Dienst Bayern (LfU), the nearest lake station.")
        )
    }

    private static let rainWords = ["REGEN", "HAGEL", "GEWITTER", "SCHNEE"]

    private static func precipitation(_ d: ConditionData) -> ConditionDetail {
        let h = d.now
        let r = units.rainUnit
        let total = d.next24.compactMap(\.precipitationMm).reduce(0, +)
        let top = extreme(d.next24, \.precipitationMm, highest: true)
        let kinds = Set(d.next24.filter { ($0.precipitationMm ?? 0) >= 0.1 }.compactMap { Sky(hour: $0).precipitationKind })
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
        facts.append((tr("DWD warnings"), d.warningNames(rainWords)))
        facts.append((tr("Rowing light now"), light))
        let wet = (h.precipitationMm ?? 0) >= 0.1
        return ConditionDetail(
            value: wet ? Format.rain(h.precipitationMm) : tr("Dry"),
            note: wet ? (Sky(hour: h).precipitationKind ?? "") : (d.next24.first { ($0.precipitationMm ?? 0) >= 0.1 }.map { tr("Expected from %@", Format.dayTime($0.time)) } ?? tr("Dry next 24 h")),
            unit: r.symbol,
            lines: [ChartLine(name: tr("Precipitation"), color: .blue, kind: .bars, points: d.points { $0.precipitationMm.map(r.convert) })],
            limits: [ChartLimit(value: r.convert(4), color: .orange, label: tr("Heavy rain"))],
            limitInfo: tr("%@ per hour is a common line for heavy rain (the UK Met Office uses it; DWD only warns from 15 mm per hour). From there you are soaked within minutes, visibility drops and a long outing takes on water: amber. Hail always counts as red. Official DWD warnings for heavy rain or hail always make the light red or amber as well.", Format.rain(4)),
            yDomain: 0...max(r.convert(6), r.convert(d.timeline.compactMap(\.precipitationMm).max() ?? 0) * 1.2),
            facts: facts,
            rowing: advice(d, Condition.precipitation.reasonNames,
                           red: tr("Hail is forecast: stay ashore."),
                           amber: tr("Heavy rain now: you are soaked quickly and see less; keep the outing short."),
                           later: tr("Heavy rain or hail from %@: plan to be back before then."),
                           calm: tr("No heavy rain or hail in the next 24 hours.")),
            source: tr("Precipitation per hour and weather code, DWD via Open-Meteo. DWD warnings appear under DWD warnings.")
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
        facts.append((tr("DWD fog warning"), d.warningNames(["NEBEL"])))
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
            big: h.cloudCoverHighPct.flatMap { high in h.cloudCoverMidPct.flatMap { mid in h.cloudCoverLowPct.map { low in
                AnyView(CloudLayers(layers: [(tr("H"), high / 100), (tr("M"), mid / 100), (tr("L"), low / 100)]).scaleEffect(1.6).frame(width: 80, height: 60))
            } } },
            unit: "%",
            lines: [
                ChartLine(name: tr("All cloud"), color: .gray, points: d.points(\.cloudCoverPct)),
                ChartLine(name: tr("High cloud"), color: .cyan, points: d.points(\.cloudCoverHighPct)),
                ChartLine(name: tr("Middle cloud"), color: .teal, points: d.points(\.cloudCoverMidPct)),
                ChartLine(name: tr("Low cloud"), color: .indigo, points: d.points(\.cloudCoverLowPct)),
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
        let values = d.timeline.compactMap(\.pressureHpa)
        let lo = values.min() ?? 1000, hi = values.max() ?? 1030
        var facts: [(String, String)] = []
        if let now = h.pressureHpa, let next = Self.pressureNext24(now: now, hours: d.next24) {
            facts.append((tr("Next 24 h"), next))
        }
        if let low = extreme(d.future, \.pressureHpa, highest: false) {
            facts.append((tr("Lowest next 7 days"), tr("%@ hPa · %@", Format.number(low.pressureHpa), Format.dayTime(low.time))))
        }
        // The level alone says little while the pressure moves fast; the trend wins.
        let high = (h.pressureHpa ?? 1013) >= 1013
        let state: String = switch change {
        case let c? where c <= -1: high ? tr("high pressure, but falling: the weather is changing") : tr("low pressure and falling: unsettled")
        case let c? where c >= 1: high ? tr("high pressure and rising: settled") : tr("low pressure, but rising: improving")
        default: high ? tr("high pressure: mostly settled") : tr("low pressure: changeable")
        }
        facts.append((tr("Now"), state))
        let rowing: String = switch change {
        case let c? where c <= -3: tr("Falling fast: wind is likely soon.")
        case let c? where c <= -1: tr("Falling: wind and rain more likely in the next day or two.")
        case let c? where c >= 1: tr("Rising: the weather is settling.")
        default: tr("Steady: no change in the weather expected from the pressure.")
        }
        return ConditionDetail(
            value: tr("%@ hPa", Format.number(h.pressureHpa)),
            note: change.map { c in trend == .steady ? tr("Steady next 3 h") : tr("%@ %@ hPa in 3 h", PressureTrend(change: c).title, Format.number(abs(c), digits: 1)) } ?? "",
            big: AnyView(PressureGauge(hpa: h.pressureHpa, trend: trend, arrowFont: .title2.weight(.bold)).frame(width: 90, height: 90)),
            unit: "hPa",
            lines: [ChartLine(name: tr("Air pressure"), color: .purple, points: d.points(\.pressureHpa))],
            // A few hPa around the values, so the change is easy to see.
            yDomain: (lo - 4).rounded(.down)...(hi + 6).rounded(.up),
            trendStep: 0.25,
            facts: facts,
            rowing: (change ?? 0) <= -3 ? rowing : rowing + " " + tr("Falling 3 hPa or more in 3 hours often means wind soon."),
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
            let value = Format.number(lo.pressureHpa), at = Format.dayTime(lo.time)
            return last - lo.pressureHpa! >= 1 ? tr("falls to %@ hPa by %@, then rises", value, at) : tr("falls to %@ hPa by %@", value, at)
        }
        let value = Format.number(hi.pressureHpa), at = Format.dayTime(hi.time)
        return hi.pressureHpa! - last >= 1 ? tr("rises to %@ hPa by %@, then falls", value, at) : tr("rises to %@ hPa by %@", value, at)
    }

    private static func thunderstorm(_ d: ConditionData) -> ConditionDetail {
        let top = extreme(d.next24, \.capeJkg, highest: true)
        var facts: [(String, String)] = []
        if let top, (top.capeJkg ?? 0) > 0 {
            facts.append((tr("Most energy next 24 h"), tr("%@ J/kg · %@", Format.number(top.capeJkg), Format.dayTime(top.time))))
        }
        facts.append((tr("DWD warnings"), d.warningNames(["GEWITTER"])))
        return ConditionDetail(
            value: stormLevel(d.now.light(for: Condition.thunderstorm.reasonNames)),
            note: d.warnings(["GEWITTER"]).isEmpty ? tr("No DWD thunderstorm warning") : tr("DWD thunderstorm warning"),
            unit: "J/kg",
            lines: [ChartLine(name: tr("Energy for storms (CAPE)"), color: .yellow, kind: .bars, points: d.points(\.capeJkg))],
            limits: [
                ChartLimit(value: 500, color: .orange, label: tr("Possible")),
                ChartLimit(value: 1000, color: .red, label: tr("Likely")),
            ],
            limitInfo: tr("CAPE is the energy the air has for rising, in J/kg. From 500 J/kg thunderstorms are possible if something sets them off (amber); from 1000 J/kg together with rain they are likely (red). This is the app's own estimate; an official DWD thunderstorm warning always makes the light red."),
            yDomain: 0...max(1300, (d.timeline.compactMap(\.capeJkg).max() ?? 0) * 1.1),
            facts: facts,
            rowing: tr("If you hear thunder, head for the shore at once: lightning can strike 10 km ahead of a storm."),
            source: tr("Estimated from DWD forecast (CAPE); official DWD warnings appear under DWD warnings.")
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
        var facts: [(String, String)] = [(tr("Now"), h.uvIndex.map { "\(Format.number($0)) (\(uvBand($0)))" } ?? "–")]
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
        let state = d.forecast.sunState(at: .now)
        let today = days.first { Calendar.current.isDateInToday($0.sunrise) } ?? days.first
        let tomorrow = days.first { Calendar.current.isDateInTomorrow($0.sunrise) }
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
            note = tr("Sun is up. Rowing advised for %@ until sunset.", Format.duration(from: .now, to: sunset))
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
            big: today.map { AnyView(SunPath(sunrise: $0.sunrise, sunset: $0.sunset).frame(width: 120, height: 60)) },
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tr("Where it is measured"), systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
            Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon),
                                                            latitudinalMeters: 4000, longitudinalMeters: 4000)),
                interactionModes: [.pan, .zoom]) {
                Marker(station.name ?? tr("Lake station"), systemImage: "thermometer.medium", coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon))
                    .tint(.cyan)
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                if let distance = station.distanceM {
                    Text(tr("%@, %@ from the launch point", station.name ?? tr("Lake station"), Format.distance(distance)))
                } else if let name = station.name {
                    Text(name)
                }
                Spacer(minLength: 0)
                if let url = station.url {
                    Link(tr("Station page"), destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
