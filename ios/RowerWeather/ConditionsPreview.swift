import Charts
import SwiftUI

// Screenshot hook `-RWConditionsPreview YES`: a proposal, not in the app yet,
// for a compact "Current conditions" card in which every value can be tapped
// to open a larger view with a chart and more information. All numbers are
// sample values for a calm October evening at Starnberger See.

/// The day's sun path as in the Weather app: bright above the horizon, faint
/// below, twilight marked on the horizon, and the sun's position now.
/// Times are hours of the day.
struct SunPathGraph: View {
    let firstLight: Double, sunrise: Double, noon: Double, sunset: Double, lastLight: Double, now: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            // Sun height through the day, 0 at sunrise and sunset; scaled so
            // noon touches the top and midnight the bottom.
            let height = { (t: Double) -> Double in cos(2 * .pi * (t - noon) / 24) - cos(2 * .pi * (sunset - noon) / 24) }
            let top = height(noon), bottom = height(noon + 12)
            let inset = lineWidth * 2 + 2
            let y = { (t: Double) -> CGFloat in CGFloat((top - height(t)) / (top - bottom)) * (size.height - 2 * inset) + inset }
            let x = { (t: Double) -> CGFloat in CGFloat(t / 24) * size.width }
            var path = Path()
            for step in 0...96 {
                let t = Double(step) / 4
                step == 0 ? path.move(to: CGPoint(x: x(t), y: y(t))) : path.addLine(to: CGPoint(x: x(t), y: y(t)))
            }
            let horizon = y(sunrise)
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
                layer.stroke(path, with: .color(.orange), lineWidth: lineWidth)
            }
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)))
                layer.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: max(1, lineWidth - 1))
            }
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: horizon)); $0.addLine(to: CGPoint(x: size.width, y: horizon)) },
                           with: .color(.secondary), lineWidth: 1)
            for (a, b) in [(firstLight, sunrise), (sunset, lastLight)] {
                context.fill(Path(CGRect(x: x(a), y: horizon - 2, width: x(b) - x(a), height: 4)), with: .color(.orange.opacity(0.35)))
            }
            let r = lineWidth * 2 + 1
            let sun = CGRect(x: x(now) - r, y: y(now) - r, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: sun), with: .color(.yellow))
            context.stroke(Path(ellipseIn: sun), with: .color(.orange), lineWidth: 1.5)
        }
    }
}

/// A compass dial for the wind as in the Weather app: ticks, N E S W, an
/// arrow across the dial pointing where the wind blows to, the speed inside.
struct WindDial: View {
    let speed: String
    let fromDeg: Double
    var unit = "m/s"

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let compact = side < 90
            ZStack {
                Canvas { context, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) / 2
                    for i in 0..<(compact ? 36 : 72) {
                        let a = Double(i) / Double(compact ? 36 : 72) * 2 * .pi
                        let long = i % (compact ? 9 : 18) == 0
                        let inner = r - (long ? side * 0.08 : side * 0.045)
                        var tick = Path()
                        tick.move(to: CGPoint(x: c.x + inner * sin(a), y: c.y - inner * cos(a)))
                        tick.addLine(to: CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)))
                        context.stroke(tick, with: .color(.secondary.opacity(long ? 0.9 : 0.4)), lineWidth: long ? 2 : 1)
                    }
                }
                if !compact {
                    ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { i, letter in
                        let angle = Double(i) * .pi / 2
                        Text(letter)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .offset(x: side * 0.35 * sin(angle), y: -side * 0.35 * cos(angle))
                    }
                }
                Capsule().fill(Color.primary).frame(width: compact ? 2 : 3, height: side * 0.86)
                    .overlay(alignment: .top) {
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: compact ? 8 : 12)).offset(y: -4)
                    }
                    .rotationEffect(.degrees(fromDeg + 180))
                Circle().fill(Color(.secondarySystemGroupedBackground)).frame(width: side * 0.44, height: side * 0.44)
                VStack(spacing: -2) {
                    Text(speed).font(compact ? .caption.weight(.semibold) : .title2.weight(.semibold))
                    if !compact { Text(unit).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Wind \(speed) \(unit) from \(Format.compass(fromDeg))")
    }
}

struct ConditionsPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Current conditions: proposal").font(.largeTitle.bold()).padding(.top, 24)
                Text("A compact card on the club page. Every tile can be tapped and opens a larger view from the bottom, like in the Weather app. Sample values.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                optionHeader("Sun tile S1: across both columns")
                CompactConditionsMock(wideSun: true)
                optionHeader("Sun tile S2: one column, next to ice cover")
                CompactConditionsMock(wideSun: false)
                optionHeader("Other graphics for humidity and cloud cover")
                GraphicOptionsMock()
                Text("Larger views when a tile is tapped").font(.title2.bold()).padding(.top, 8)
                Text("Charts can be dragged sideways: back to yesterday and forward up to 7 days. Arrows above a chart show where the value rises, falls or stays the same in each 6 hours. ⓘ explains the limits.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(DetailMock.all) { DetailMockView(detail: $0) }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: true))
    }

    private func optionHeader(_ text: String) -> some View {
        Text(text).font(.headline).padding(.top, 4)
    }
}

/// One small tile of the compact card: icon, title and chevron on top, the
/// value with a short detail below and a small graphic on the right.
private func compactTile(_ symbol: String, _ title: String, _ value: String, _ detail: String,
                         @ViewBuilder accessory: () -> some View = { EmptyView() }) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
            Image(systemName: symbol).symbolRenderingMode(.hierarchical).frame(width: 16)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            accessory()
        }
    }
    .padding(8)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
}

private func compactTile(_ condition: Condition, _ value: String, _ detail: String,
                         @ViewBuilder accessory: () -> some View = { EmptyView() }) -> some View {
    compactTile(condition.symbol, condition.title, value, detail, accessory: accessory)
}

private let uvColors: [Color] = [.green, .yellow, .orange, .red, .purple]
private let sunNow = SunPathGraph(firstLight: 7.12, sunrise: 7.67, noon: 12.98, sunset: 18.3, lastLight: 18.85, now: 19.75, lineWidth: 2)

/// The proposed compact card: two columns of small tiles, each with a chevron
/// that says it opens, and each with a small graphic. The sun tile comes in
/// two options: across both columns (S1) or in one column (S2).
private struct CompactConditionsMock: View {
    let wideSun: Bool

    var body: some View {
        Card(title: "Current conditions", symbol: "gauge.with.dots.needle.33percent") {
            HStack(spacing: 10) {
                SkyIcon(sky: .cloudy).font(.system(size: 32))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cloudy").font(.headline)
                    Text("11° · feels like 9°").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            LazyVGrid(columns: columns, spacing: 8) {
                compactTile(.temperature, "11°", "High 14° · low 6°") {
                    ScaleBar(fraction: 5.0 / 8, colors: [.blue, .orange])
                }
                compactTile(.feelsLike, "9°", "Wind chill") {
                    ScaleBar(fraction: 3.0 / 8, colors: [.blue, .orange])
                }
                compactTile(.humidity, "80 %", "Dew point 8°") {
                    Gauge(value: 0.8) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(.teal).scaleEffect(0.6).frame(width: 36, height: 36)
                }
                compactTile(.wind, "2 m/s", "Gusts 4 · from E") {
                    WindDial(speed: "2", fromDeg: 90).frame(width: 44, height: 44)
                }
                compactTile(.waves, "0.01 m", "Wind off the shore") {
                    ScaleBar(fraction: 0.02, zones: [(0.4, .orange), (0.7, .red)])
                }
                compactTile(.waterTemperature, "15.6°", "Measured 19:30") {
                    ScaleBar(fraction: 15.6 / 25, zones: [(0, .red), (0.4, .orange), (0.6, .green)])
                }
                compactTile(.precipitation, "Dry", "Rain from 23:00") {
                    SparkBars(values: [0, 0, 0, 0.2, 0.6, 0.9, 0.4, 0.1])
                }
                compactTile(.visibility, "32 km", "Fog from 04:00") {
                    ScaleBar(fraction: 1, zones: [(0, .red), (0.05, .orange), (0.1, .green)])
                }
                compactTile(.cloudCover, "100 %", "Low cloud 70 %") {
                    Gauge(value: 1.0) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(.gray).scaleEffect(0.6).frame(width: 36, height: 36)
                }
                compactTile(.pressure, "1023", "hPa · steady") {
                    PressureGauge(hpa: 1023, trend: .steady).frame(width: 44, height: 44)
                }
                compactTile(.thunderstorm, "Low", "No DWD warning") {
                    LevelSegments(level: 1, colors: [.green, .orange, .red])
                }
                compactTile(DetailMock.uvSymbol, "UV index", "0", "Max 2 tomorrow") {
                    ScaleBar(fraction: 0, colors: uvColors)
                }
                if !wideSun {
                    compactTile(.ice, "No ice", "Water too warm")
                    narrowSunTile
                }
            }
            if wideSun {
                wideSunTile
                compactTile(.ice, "No ice", "Water too warm")
            }
        }
    }

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)] }

    private var sunHeader: some View {
        HStack(spacing: 4) {
            ConditionIcon(condition: .daylight).frame(width: 16)
            Text("Sunset")
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// S1: across both columns so the sun path has room, as in the Weather app.
    private var wideSunTile: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                sunHeader.fixedSize()
                Text("18:18").font(.title3.weight(.semibold))
                Text("Sunrise 07:40").font(.caption2).foregroundStyle(.secondary)
            }
            sunNow.frame(height: 50)
        }
        .padding(8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    /// S2: one column, the sun path below the time.
    private var narrowSunTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            sunHeader
            HStack(alignment: .firstTextBaseline) {
                Text("18:18").font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Text("Sunrise 07:40").font(.caption2).foregroundStyle(.secondary)
            }
            sunNow.frame(height: 28)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Other small graphics that could replace the rings for humidity and cloud
/// cover, shown as tiles with the same sample values.
private struct GraphicOptionsMock: View {
    var body: some View {
        Card {
            Text("Humidity").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                compactTile(Condition.humidity.symbol, "H1 Ring (now)", "80 %", "Dew point 8°") {
                    Gauge(value: 0.8) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(.teal).scaleEffect(0.6).frame(width: 36, height: 36)
                }
                compactTile(Condition.humidity.symbol, "H2 Filling drop", "80 %", "Dew point 8°") {
                    SymbolFill(outline: "drop", filled: "drop.fill", fraction: 0.8, color: .teal)
                }
                compactTile(Condition.humidity.symbol, "H3 Mist gap", "80 %", "Dew point 8°") {
                    DewGap(air: 11, dewPoint: 8)
                }
                compactTile(Condition.humidity.symbol, "H4 Scale", "80 %", "Dew point 8°") {
                    ScaleBar(fraction: 0.8, colors: [.yellow, .teal, .blue])
                }
            }
            Text("H3 shows air and dew point as two dots: when they meet, mist forms, so it also warns of fog.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Cloud cover").font(.subheadline.weight(.semibold)).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                compactTile(Condition.cloudCover.symbol, "C1 Ring (now)", "100 %", "Low cloud 70 %") {
                    Gauge(value: 1.0) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(.gray).scaleEffect(0.6).frame(width: 36, height: 36)
                }
                compactTile(Condition.cloudCover.symbol, "C2 Sky in eighths", "6/8", "Mostly cloudy") {
                    OktaDisc(eighths: 6)
                }
                compactTile(Condition.cloudCover.symbol, "C3 Layers", "100 %", "Low cloud 70 %") {
                    CloudLayers(layers: [("H", 0.9), ("M", 0.4), ("L", 0.7)])
                }
                compactTile(Condition.cloudCover.symbol, "C4 Filling cloud", "100 %", "Low cloud 70 %") {
                    SymbolFill(outline: "cloud", filled: "cloud.fill", fraction: 1, color: .gray)
                }
            }
            Text("C2 is the weather map symbol: the sky in eighths. C3 shows high, middle and low cloud; low cloud matters most for visibility.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// An SF Symbol outline filled from the bottom up to a share.
struct SymbolFill: View {
    let outline: String, filled: String
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Image(systemName: outline)
            Image(systemName: filled)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: 30 * fraction)
                }
        }
        .font(.system(size: 26))
        .foregroundStyle(color)
        .frame(width: 36, height: 30)
    }
}

/// Air temperature and dew point as two dots with the gap between them.
struct DewGap: View {
    let air: Double, dewPoint: Double

    var body: some View {
        let gap = air - dewPoint
        let width = 46.0
        // 0–8 degrees of gap across the bar; mist when the dots touch.
        let offset = min(gap, 8) / 8 * (width - 12)
        VStack(spacing: 3) {
            Text("\(Int(gap.rounded()))°").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 4)
                Circle().fill(Color.teal).frame(width: 10, height: 10)
                Circle().fill(Color.orange).frame(width: 10, height: 10).offset(x: offset)
            }
            .frame(width: width)
        }
        .frame(width: 46, height: 36)
    }
}

/// The sky in eighths (oktas) as on weather maps.
struct OktaDisc: View {
    let eighths: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary, lineWidth: 2)
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                var pie = Path()
                pie.move(to: c)
                pie.addArc(center: c, radius: size.width / 2 - 1, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * Double(eighths) / 8), clockwise: false)
                pie.closeSubpath()
                context.fill(pie, with: .color(.gray))
            }
        }
        .frame(width: 30, height: 30)
        .frame(width: 46, height: 36)
    }
}

/// High, middle and low cloud as three short bars.
struct CloudLayers: View {
    let layers: [(String, Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                HStack(spacing: 3) {
                    Text(layer.0).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).frame(width: 8)
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(width: 34, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.gray).frame(width: 34 * layer.1, height: 6)
                        }
                }
            }
        }
        .frame(width: 46, height: 36)
    }
}

/// One proposed larger view, opened by tapping a tile.
struct DetailMock: Identifiable {
    enum Kind { case line, bars }
    struct Series {
        let name: String
        let color: Color
        var kind: Kind = .line
        /// The value at an hour from now (negative is the past).
        let value: (Int) -> Double

        /// 24 hourly sample values from 20:00, repeated for the other days.
        init(name: String, values: [Double], color: Color, kind: Kind = .line) {
            self.name = name
            self.color = color
            self.kind = kind
            value = { values[(($0 % 24) + 24) % 24] }
        }

        init(name: String, color: Color, value: @escaping (Int) -> Double) {
            self.name = name
            self.color = color
            self.value = value
        }
    }

    static let uvSymbol = "sun.max.trianglebadge.exclamationmark"

    let symbol: String
    let title: String
    let value: String
    let note: String
    var big: AnyView? = nil
    let unit: String
    let series: [Series]
    /// Rowing limits drawn across the chart: value, colour, label.
    var limits: [(Double, Color, String)] = []
    /// Why the limits are where they are, shown when ⓘ is tapped.
    var limitInfo: String? = nil
    var yDomain: ClosedRange<Double>? = nil
    var logScale = false
    /// Change in 6 hours that counts as rising or falling; nil for no arrows.
    var trendStep: Double? = nil
    /// The chart shows the past 7 days instead of the forecast.
    var history = false
    let facts: [(String, String)]
    var twoColumnFacts = false
    let rowing: String
    let source: String

    var id: String { title }
}

private struct DetailMockView: View {
    let detail: DetailMock
    // Hour 0 is now, 20:00 on a Monday.
    private let start = 20

    private var hours: ClosedRange<Int> { detail.history ? -23...0 : -24...167 }

    private var domain: ClosedRange<Double> {
        if let d = detail.yDomain { return d }
        let values = detail.series.flatMap { s in hours.map(s.value) } + detail.limits.map(\.0)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(hi - lo, 0.1)
        let bottom = lo >= 0 ? 0 : lo - span * 0.1
        return bottom...(hi + span * (detail.trendStep == nil ? 0.1 : 0.3))
    }

    /// Where the trend arrows sit: near the top of the chart.
    private var arrowY: Double {
        let d = domain
        if detail.logScale { return exp(log(d.upperBound) - 0.08 * (log(d.upperBound) - log(d.lowerBound))) }
        return d.upperBound - 0.08 * (d.upperBound - d.lowerBound)
    }

    private struct Trend: Identifiable {
        let mid: Int
        let symbol: String
        var id: Int { mid }
    }

    private var trends: [Trend] {
        guard let step = detail.trendStep, let s = detail.series.first else { return [] }
        return stride(from: hours.lowerBound, to: hours.upperBound - 5, by: 6).map { h in
            let change = s.value(h + 6) - s.value(h)
            return Trend(mid: h + 3, symbol: change > step ? "arrow.up" : change < -step ? "arrow.down" : "equal")
        }
    }

    var body: some View {
        Card {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap").foregroundStyle(.blue)
                Text("Tap on “\(detail.title)” opens:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: detail.symbol).symbolRenderingMode(.hierarchical).font(.title).foregroundStyle(.blue).frame(width: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.title).font(.headline)
                    Text(detail.value).font(.system(size: 34, weight: .light))
                    Text(detail.note).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let big = detail.big { big }
            }
            if !detail.series.isEmpty {
                scrolling(scaled(chart))
                    .frame(height: 160)
                if detail.series.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(detail.series, id: \.name) { s in
                            Label(s.name, systemImage: "circle.fill").foregroundStyle(s.color)
                        }
                    }
                    .font(.caption2)
                }
                if !detail.history {
                    HStack {
                        Text("‹ Yesterday")
                        Spacer()
                        Text("Drag the chart")
                        Spacer()
                        Text("Next 7 days ›")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            if let info = detail.limitInfo {
                LimitInfo(text: info)
            }
            facts
            Label(detail.rowing, systemImage: "figure.rower")
                .font(.subheadline)
            Text(detail.source).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(detail.series, id: \.name) { s in
                ForEach(Array(hours), id: \.self) { h in
                    mark(s, h)
                }
            }
            ForEach(Array(detail.limits.enumerated()), id: \.offset) { _, limit in
                limitRules(limit)
            }
            RuleMark(x: .value("Now", 0)).foregroundStyle(.secondary.opacity(0.4))
            ForEach(trends) { t in
                PointMark(x: .value("Hour", t.mid), y: .value(detail.unit, arrowY))
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        Image(systemName: t.symbol).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: hours.lowerBound...hours.upperBound)
        .chartXAxis {
            AxisMarks(values: axisHours) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let h = value.as(Int.self) { Text(label(h)) }
                }
            }
        }
        .chartYAxisLabel(detail.unit)
    }

    @ChartContentBuilder
    private func mark(_ s: DetailMock.Series, _ h: Int) -> some ChartContent {
        switch s.kind {
        case .line:
            LineMark(x: .value("Hour", h), y: .value(detail.unit, s.value(h)), series: .value("Series", s.name))
                .foregroundStyle(s.color)
                .interpolationMethod(.catmullRom)
        case .bars:
            BarMark(x: .value("Hour", h), y: .value(detail.unit, s.value(h)))
                .foregroundStyle(s.color.opacity(0.7))
        }
    }

    /// A limit line in day-long pieces, so its label shows again each day
    /// when the chart is dragged.
    @ChartContentBuilder
    private func limitRules(_ limit: (Double, Color, String)) -> some ChartContent {
        ForEach(Array(stride(from: detail.history ? hours.lowerBound : 0 - 24, to: hours.upperBound, by: 24)), id: \.self) { from in
            RuleMark(xStart: .value("Hour", max(from, hours.lowerBound)), xEnd: .value("Hour", min(from + 24, hours.upperBound)), y: .value("Limit", limit.0))
                .foregroundStyle(limit.1)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text(limit.2).font(.caption2).foregroundStyle(limit.1)
                }
        }
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
                .chartScrollPosition(initialX: 0)
        }
    }

    private var axisHours: [Int] {
        if detail.history { return [-23, -10, 0] }
        // Every 6 hours on the clock (00, 06, 12, 18), and now.
        return Array(stride(from: -20, through: hours.upperBound, by: 6)).filter { abs($0) >= 3 } + [0]
    }

    private func label(_ h: Int) -> String {
        if h == 0 { return "Now" }
        if detail.history { return h == -23 ? "7 days ago" : "3 days ago" }
        let clock = ((start + h) % 24 + 24) % 24
        if clock == 0 {
            let day = Int((Double(start + h) / 24).rounded(.down))
            return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Mon"][day + 1]
        }
        return String(format: "%02d:00", clock)
    }

    @ViewBuilder
    private var facts: some View {
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

/// The ⓘ button under a chart and, in this preview, the explanation it opens.
private struct LimitInfo: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("About the limits", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.footnote)
                Text("In the app this only shows after tapping ⓘ.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

extension DetailMock {
    private static let air: [Double] = [11, 10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 7, 8, 10, 11, 12, 13, 14, 14, 13, 12, 11, 10, 10]
    private static let feels: [Double] = [9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 5, 6, 8, 10, 11, 12, 13, 13, 12, 10, 9, 8, 8]
    private static let pressure: [Double] = [1023, 1023, 1023, 1022.8, 1022.5, 1022.1, 1021.8, 1021.5, 1021.2, 1021, 1020.6, 1020.2, 1019.8, 1019.4, 1019, 1018.6, 1018.3, 1018, 1017.7, 1017.4, 1017.2, 1017, 1016.8, 1016.6]

    private static func d(_ c: Condition) -> (String, String) { (c.symbol, c.title) }

    static let all: [DetailMock] = [
        DetailMock(
            symbol: d(.temperature).0, title: d(.temperature).1, value: "11°", note: "Cloudy · high 14°, low 6° today", unit: "°C",
            series: [Series(name: "Air", values: air, color: .orange), Series(name: "Feels like", values: feels, color: .blue)],
            trendStep: 1,
            facts: [("Now", "11 °C"), ("Tonight", "lowest 6 °C at 05:00"), ("Tomorrow", "highest 14 °C at 14:00"), ("Yesterday", "highest 13 °C")],
            rowing: "Under 5 °C dress in layers and keep a dry set in the boathouse.",
            source: "Deutscher Wetterdienst (DWD) via Open-Meteo, 2 m above ground."
        ),
        DetailMock(
            symbol: d(.feelsLike).0, title: d(.feelsLike).1, value: "9°", note: "2° colder than the air: wind chill", unit: "°C",
            series: [Series(name: "Air", values: air, color: .orange), Series(name: "Feels like", values: feels, color: .blue)],
            trendStep: 1,
            facts: [("Why", "Wind 2 m/s, gusts 4 m/s"), ("Humidity", "80 %"), ("Sun", "down"), ("On the water", "feels about 1° colder again from the boat's speed")],
            rowing: "Feels colder than 5 °C: gloves or pogies and a hat.",
            source: "Apparent temperature from air temperature, wind, humidity and sun (DWD via Open-Meteo)."
        ),
        DetailMock(
            symbol: d(.humidity).0, title: d(.humidity).1, value: "80 %", note: "Dew point 8° · 3° below the air", unit: "%",
            series: [Series(name: "Humidity", values: [80, 82, 85, 87, 89, 91, 93, 94, 95, 96, 96, 94, 90, 84, 78, 72, 68, 65, 64, 66, 70, 74, 77, 79], color: .teal)],
            trendStep: 5,
            facts: [("Dew point", "8 °C"), ("Air minus dew point", "3° (mist forms near 0–1°)"), ("Morning mist", "likely 04:00–08:00")],
            rowing: "When air and dew point meet, mist forms over the water: check visibility before going out early.",
            source: "Relative humidity and dew point, DWD via Open-Meteo."
        ),
        DetailMock(
            symbol: d(.wind).0, title: d(.wind).1, value: "2 m/s", note: "Gusts 4 m/s · from the east (90°)",
            big: AnyView(WindDial(speed: "2", fromDeg: 90).frame(width: 100, height: 100)), unit: "m/s",
            series: [
                Series(name: "Wind", values: [2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 5, 5, 4, 4, 3, 3, 2, 2, 2], color: .blue),
                Series(name: "Gusts", values: [4, 4, 3, 3, 3, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9, 9, 8, 8, 7, 6, 5, 4, 4, 4], color: .purple),
            ],
            limits: [(5.5, .orange, "Wind: row with care"), (8, .red, "Wind: stay ashore")],
            limitInfo: "Amber from 5.5 m/s (Beaufort 4, the first whitecaps) and red from 8 m/s (Beaufort 5, many whitecaps): in a single or double the boat gets hard to steer and water comes over the side. Gusts have their own limits: amber from 8 m/s and red from 12.8 m/s (46 km/h), the level at which DWD issues a strong-wind warning and the lake's warning lights start flashing. These are the app's starting values for small boats and can be tuned with rowers.",
            yDomain: 0...14, trendStep: 1,
            facts: [("Beaufort", "2 · light breeze"), ("Direction", "E, along the lake"), ("Open water upwind", "0.1 km"), ("Strongest gust", "9 m/s at 15:00")],
            rowing: "Calm now; gusts reach the amber limit tomorrow afternoon.",
            source: "Wind at 10 m and gusts, DWD ICON via Open-Meteo."
        ),
        DetailMock(
            symbol: d(.waves).0, title: d(.waves).1, value: "0.01 m", note: "Wind blows off the shore", unit: "m",
            series: [Series(name: "Waves", values: [0.01, 0.01, 0.01, 0.01, 0, 0, 0, 0.01, 0.01, 0.02, 0.04, 0.05, 0.08, 0.1, 0.14, 0.16, 0.15, 0.12, 0.1, 0.07, 0.05, 0.03, 0.02, 0.01], color: .blue)],
            limits: [(0.15, .orange, "Row with care"), (0.3, .red, "Stay ashore")],
            limitInfo: "Amber from 0.15 m and red from 0.30 m wave height. A racing single sits only about 10–15 cm above the water at its side, so from about 15 cm waves start to wash in; from about 30 cm the boat fills and capsizing becomes likely. The waves are calculated from the wind and the open water upwind, not measured.",
            yDomain: 0...0.4, trendStep: 0.03,
            facts: [("Open water upwind", "0.1 km (wind off the shore)"), ("Highest", "0.16 m at 15:00"), ("Period", "about 1 s, short and steep")],
            rowing: "Flat now; around 15:00 the waves just reach the amber limit.",
            source: "Calculated by the app from wind and the lake's shape (fetch), not measured."
        ),
        DetailMock(
            symbol: d(.waterTemperature).0, title: d(.waterTemperature).1, value: "15.6°", note: "Measured 19:30 · Starnberg station", unit: "°C",
            series: [Series(name: "Last 7 days", values: [17.2, 17.0, 16.9, 16.8, 16.6, 16.5, 16.4, 16.3, 16.3, 16.2, 16.1, 16.0, 16.0, 15.9, 15.9, 15.8, 15.8, 15.7, 15.7, 15.7, 15.6, 15.6, 15.6, 15.6], color: .cyan)],
            limits: [(15, .orange, "Cold-water shock"), (10, .red, "Cold water")],
            limitInfo: "Below about 15 °C a fall into the water causes cold-water shock: a gasp and fast breathing in the first minute. A rule of thumb says the minutes you can still help yourself in the water are about the water temperature in °C, so about 10 minutes at 10 °C. That is why the light turns amber below 15 °C and the advice gets stricter below 10 °C. Your club's own rules come first.",
            yDomain: 0...20, history: true,
            facts: [("Trend", "−1.6° in 7 days"), ("Station", "Starnberg (GKD 16663002)"), ("Depth", "surface"), ("Life jacket", "advised below 10 °C")],
            rowing: "Below 15 °C wear clothes that keep you warm when wet. Below 10 °C we advise wearing a life jacket and rowing with a second boat or a safety boat nearby.",
            source: "Gewässerkundlicher Dienst Bayern (LfU). The chart shows the last 7 days."
        ),
        DetailMock(
            symbol: d(.precipitation).0, title: d(.precipitation).1, value: "Dry", note: "Rain expected from 23:00", unit: "mm",
            series: [Series(name: "Rain", values: [0, 0, 0, 0.2, 0.6, 0.9, 0.4, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.1, 0.3], color: .blue, kind: .bars)],
            limits: [(4, .orange, "Heavy rain")],
            limitInfo: "4 mm per hour is a common line for heavy rain (the UK Met Office uses it; DWD only warns from 15 mm per hour). From there you are soaked within minutes, visibility drops and a long outing takes on water. Hail always counts as red. This limit is still a proposal: the traffic light does not use rain yet.",
            yDomain: 0...6,
            facts: [("Next 24 h", "2.6 mm in total"), ("Kind", "rain, no hail or snow"), ("Heaviest", "0.9 mm at 01:00")],
            rowing: "Light rain only; hail would come with a thunderstorm warning.",
            source: "Precipitation per hour and weather code, DWD via Open-Meteo."
        ),
        DetailMock(
            symbol: d(.visibility).0, title: d(.visibility).1, value: "32 km", note: "Clear now · fog expected 04:00–07:00", unit: "km",
            series: [Series(name: "Visibility", values: [32, 30, 25, 20, 15, 10, 6, 3, 0.9, 0.4, 0.3, 0.7, 1.6, 4, 10, 20, 30, 35, 40, 40, 38, 35, 30, 28], color: .gray)],
            limits: [(5, .secondary, "Mist"), (1, .orange, "Fog: row with care"), (0.5, .red, "Stay ashore")],
            limitInfo: "Fog means visibility under 1 km (the WMO definition): amber. Under 500 m you see another boat or a passenger ship only about 2 minutes ahead at rowing speed, and you lose sight of the shore: red. Mist (1–5 km) has no limit, but the app mentions it because it often thickens into fog. The scale is stretched at the bottom so short distances are easy to read.",
            yDomain: 0.1...80, logScale: true, trendStep: 2,
            facts: [("Fog", "04:00–07:00, thickest 0.3 km at 06:00"), ("Mist", "08:00–09:00, 1.6–4 km"), ("Rowing possible", "from about 08:00 by visibility (sunrise 07:40)")],
            rowing: "Fog tomorrow morning: wait until about 08:00, when it has lifted to mist.",
            source: "Visibility, DWD via Open-Meteo."
        ),
        DetailMock(
            symbol: d(.cloudCover).0, title: d(.cloudCover).1, value: "100 %", note: "Low cloud 70 %", unit: "%",
            series: [
                Series(name: "All cloud", values: [100, 100, 95, 90, 90, 85, 80, 80, 75, 70, 60, 55, 50, 45, 40, 40, 45, 50, 60, 70, 80, 90, 95, 100], color: .gray),
                Series(name: "Low cloud", values: [70, 70, 65, 60, 60, 55, 50, 50, 40, 30, 20, 15, 10, 10, 5, 5, 10, 15, 20, 30, 40, 55, 65, 70], color: .indigo),
            ],
            yDomain: 0...130, trendStep: 10,
            facts: [("Sunny spells", "tomorrow 11:00–15:00"), ("Low cloud", "fog-like on the hills")],
            rowing: "No effect on the rowing light; low cloud often comes with poor visibility.",
            source: "Cloud cover, DWD via Open-Meteo."
        ),
        DetailMock(
            symbol: d(.pressure).0, title: d(.pressure).1, value: "1023 hPa", note: "Steady over the next 3 hours",
            big: AnyView(PressureGauge(hpa: 1023, trend: .steady).frame(width: 90, height: 90)), unit: "hPa",
            series: [Series(name: "Pressure", color: .purple) { h in
                if h < 0 { return 1023 + 0.08 * Double(h) }
                if h < 24 { return pressure[h] }
                if h < 72 { return 1016.6 - 0.12 * Double(h - 23) }
                return 1010.8 + 0.1 * Double(h - 71)
            }],
            yDomain: 1005...1030, trendStep: 0.5,
            facts: [("Next 24 h", "falling 6 hPa"), ("Next days", "down to 1011 hPa on Wednesday, then rising"), ("High pressure", "above 1013 hPa: mostly settled")],
            rowing: "Falling slowly: settled now, wind and rain more likely in 1–2 days. Falling 3 hPa or more in 3 hours often means wind soon.",
            source: "Air pressure at sea level, DWD via Open-Meteo."
        ),
        DetailMock(
            symbol: d(.thunderstorm).0, title: d(.thunderstorm).1, value: "Low", note: "No DWD thunderstorm warning", unit: "J/kg",
            series: [Series(name: "Energy for storms (CAPE)", values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 40, 80, 120, 150, 120, 60, 20, 0, 0, 0, 0, 0, 0], color: .yellow, kind: .bars)],
            limits: [(500, .orange, "Possible"), (1000, .red, "Likely")],
            limitInfo: "CAPE is the energy the air has for rising, in J/kg. From 500 J/kg thunderstorms are possible if something sets them off (amber); from 1000 J/kg together with rain they are likely (red). This is the app's own estimate; an official DWD thunderstorm warning always makes the light red.",
            yDomain: 0...1300,
            facts: [("Highest risk", "low, tomorrow 15:00"), ("DWD warnings", "none for Starnberg")],
            rowing: "If you hear thunder, head for the shore at once: lightning can strike 10 km ahead of a storm.",
            source: "Estimated from DWD forecast (CAPE); official DWD warnings appear under DWD warnings."
        ),
        DetailMock(
            symbol: uvSymbol, title: "UV index", value: "0", note: "Night · highest tomorrow 2 at 13:00", unit: "UV",
            series: [Series(name: "UV index", values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.1, 0.5, 1.0, 1.6, 2.0, 2.1, 1.8, 1.2, 0.6, 0.2, 0, 0], color: .orange, kind: .bars)],
            limits: [(3, .orange, "Moderate: protect"), (6, .red, "High"), (8, .purple, "Very high")],
            limitInfo: "These are the WHO UV bands: 0–2 low, 3–5 moderate, 6–7 high, 8–10 very high, 11 and more extreme. From 3 the WHO advises sun protection. On the water the surface reflects extra UV and outings are long, so the app gives its advice from 3.",
            yDomain: 0...10,
            facts: [("Highest tomorrow", "2 (low) at 13:00"), ("Protection needed", "not tomorrow"), ("If the cloud clears", "up to 3 at 13:00"), ("Sunshine tomorrow", "about 4 h"), ("Low sun, glare", "08:00–09:00 and 17:15–18:15"), ("Hot (feels 25° +)", "not this week")],
            twoColumnFacts: true,
            rowing: "From UV 3: sunscreen SPF 30 or more, also on neck, ears and the backs of the knees, a cap and sunglasses. When it feels 25 °C or more, drink before and during the outing.",
            source: "UV index forecast via Open-Meteo; bands from the WHO. Glare times calculated by the app from the sun's height."
        ),
        DetailMock(
            symbol: d(.ice).0, title: d(.ice).1, value: "No ice", note: "Water 15.6 °C, too warm for ice", unit: "",
            series: [],
            facts: [("Mon", "no ice"), ("Tue", "no ice"), ("Wed", "no ice"), ("Thu", "no ice"),
                    ("Fri", "no ice"), ("Sat", "no ice"), ("Sun", "no ice"), ("Basis", "measured water temperature")],
            twoColumnFacts: true,
            rowing: "Never go onto the ice because of this app. Never row between ice floes; thin ice cuts hulls.",
            source: "Estimated by the app from water temperature and frost (the ice thread's model, PR #11)."
        ),
        DetailMock(
            symbol: d(.daylight).0, title: d(.daylight).1, value: "Sunset 18:18", note: "Sun is down · sunrise 07:40",
            big: AnyView(sunNow.frame(width: 120, height: 60)),
            unit: "",
            series: [],
            facts: [("First light", "07:07"), ("Last light", "18:51"), ("Sunrise", "07:40"), ("Sunset", "18:18"),
                    ("Daylight", "10 h 38 min"), ("Change", "3 min shorter than yesterday"),
                    ("Tomorrow sunrise", "07:41"), ("Tomorrow sunset", "18:16")],
            twoColumnFacts: true,
            rowing: "Rowing is advised from sunrise to sunset; in twilight carry lights.",
            source: "Calculated by the app from the launch point's position."
        ),
    ]
}

/// A small horizontal scale with a dot at the current value, for the compact
/// tiles: either a colour gradient (temperatures) or coloured zones that start
/// at a share of the scale (limits for waves, water, visibility).
struct ScaleBar: View {
    let fraction: Double
    var colors: [Color] = []
    var zones: [(Double, Color)] = []

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                if zones.isEmpty {
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(zones.enumerated()), id: \.offset) { i, zone in
                            let end = i + 1 < zones.count ? zones[i + 1].0 : 1
                            Rectangle().fill(zone.1.opacity(0.6)).frame(width: max(0, (end - zone.0) * w))
                        }
                    }
                    .padding(.leading, zones[0].0 * w)
                    .background(Color.secondary.opacity(0.25))
                    .clipShape(Capsule())
                }
                Circle()
                    .fill(Color.primary)
                    .overlay(Circle().stroke(Color(.tertiarySystemGroupedBackground), lineWidth: 2))
                    .frame(width: 10, height: 10)
                    .offset(x: min(max(0, fraction), 1) * (w - 10))
            }
            .frame(height: 10)
            .frame(maxHeight: .infinity)
        }
        .frame(width: 46, height: 36)
    }
}

/// Tiny bars for the next hours, e.g. rain per hour.
struct SparkBars: View {
    let values: [Double]

    var body: some View {
        let top = max(values.max() ?? 1, 0.1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 1)
                    .fill(v > 0 ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: max(2, 28 * v / top))
            }
        }
        .frame(width: 46, height: 36, alignment: .bottom)
    }
}

/// Three steps (low, possible, high) with the current one lit.
struct LevelSegments: View {
    let level: Int
    let colors: [Color]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<colors.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < level ? colors[i] : Color.secondary.opacity(0.25))
                    .frame(width: 10, height: CGFloat(10 + i * 8))
            }
        }
        .frame(width: 46, height: 36, alignment: .bottom)
    }
}
