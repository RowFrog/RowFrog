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
                CompactConditionsMock()
                Text("Larger views when a tile is tapped").font(.title2.bold()).padding(.top, 8)
                ForEach(DetailMock.all) { DetailMockView(detail: $0) }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .modifier(ScreenshotScroll(page: UserDefaults.standard.integer(forKey: "RWScrollPage"), ready: true))
    }
}

/// The proposed compact card: two columns of small tiles, each with a chevron
/// that says it opens; wind, air pressure and sunset carry small graphics.
private struct CompactConditionsMock: View {
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tile(.temperature, "11°", "High 14° · low 6°") {
                    ScaleBar(fraction: 5.0 / 8, colors: [.blue, .orange])
                }
                tile(.feelsLike, "9°", "Wind chill") {
                    ScaleBar(fraction: 3.0 / 8, colors: [.blue, .orange])
                }
                tile(.humidity, "80 %", "Dew point 8°") {
                    Gauge(value: 0.8) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(.teal).scaleEffect(0.6).frame(width: 36, height: 36)
                }
                tile(.wind, "2 m/s", "Gusts 4 · from E") {
                    WindDial(speed: "2", fromDeg: 90).frame(width: 44, height: 44)
                }
                tile(.waves, "0.01 m", "Wind off the shore") {
                    ScaleBar(fraction: 0.02, zones: [(0.4, .orange), (0.7, .red)])
                }
                tile(.waterTemperature, "15.6°", "Measured 19:30") {
                    ScaleBar(fraction: 15.6 / 25, zones: [(0, .red), (0.4, .orange), (0.6, .green)])
                }
                tile(.precipitation, "Dry", "Rain from 23:00") {
                    SparkBars(values: [0, 0, 0, 0.2, 0.6, 0.9, 0.4, 0.1])
                }
                tile(.visibility, "32 km", "No fog") {
                    ScaleBar(fraction: 1, zones: [(0, .red), (0.05, .orange), (0.1, .green)])
                }
                tile(.cloudCover, "100 %", "Low cloud 70 %") {
                    Gauge(value: 1.0) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(.gray).scaleEffect(0.6).frame(width: 36, height: 36)
                }
                tile(.pressure, "1023", "hPa · steady") {
                    PressureGauge(hpa: 1023, trend: .steady).frame(width: 44, height: 44)
                }
                tile(.thunderstorm, "Low", "No DWD warning") {
                    LevelSegments(level: 1, colors: [.green, .orange, .red])
                }
                tile(.ice, "–", "No data yet")
            }
            sunsetTile
        }
    }

    private func tile(_ condition: Condition, _ value: String, _ detail: String,
                      @ViewBuilder accessory: () -> some View = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ConditionIcon(condition: condition).frame(width: 16)
                Text(condition.title).lineLimit(1).minimumScaleFactor(0.8)
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

    /// Full width so the sun path has room, as the Weather app's sunset tile.
    private var sunsetTile: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    ConditionIcon(condition: .daylight).frame(width: 16)
                    Text("Sunset")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("18:18").font(.title3.weight(.semibold))
                Text("Sunrise 07:40").font(.caption2).foregroundStyle(.secondary)
            }
            SunPathGraph(firstLight: 7.12, sunrise: 7.67, noon: 12.98, sunset: 18.3, lastLight: 18.85, now: 19.75, lineWidth: 2)
                .frame(height: 50)
        }
        .padding(8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One proposed larger view, opened by tapping a tile.
struct DetailMock: Identifiable {
    enum Kind { case line, bars }
    struct Series { let name: String; let values: [Double]; let color: Color; var kind: Kind = .line }

    let condition: Condition
    let value: String
    let note: String
    var big: AnyView? = nil
    let unit: String
    let series: [Series]
    /// Rowing limits drawn across the chart: value, colour, label.
    var limits: [(Double, Color, String)] = []
    let facts: [(String, String)]
    let rowing: String
    let source: String

    var id: Condition { condition }
}

private struct DetailMockView: View {
    let detail: DetailMock
    // The chart starts at 20:00 and runs 24 hours.
    private let start = 20

    var body: some View {
        Card {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap").foregroundStyle(.blue)
                Text("Tap on “\(detail.condition.title)” opens:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 12) {
                ConditionIcon(condition: detail.condition).font(.title).foregroundStyle(.blue).frame(width: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.condition.title).font(.headline)
                    Text(detail.value).font(.system(size: 34, weight: .light))
                    Text(detail.note).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let big = detail.big { big }
            }
            if !detail.series.isEmpty {
                Chart {
                    ForEach(detail.series, id: \.name) { s in
                        ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                            switch s.kind {
                            case .line:
                                LineMark(x: .value("Hour", i), y: .value(detail.unit, v), series: .value("Series", s.name))
                                    .foregroundStyle(s.color)
                                    .interpolationMethod(.catmullRom)
                            case .bars:
                                BarMark(x: .value("Hour", i), y: .value(detail.unit, v))
                                    .foregroundStyle(s.color.opacity(0.7))
                            }
                        }
                    }
                    ForEach(Array(detail.limits.enumerated()), id: \.offset) { _, limit in
                        RuleMark(y: .value("Limit", limit.0))
                            .foregroundStyle(limit.1)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text(limit.2).font(.caption2).foregroundStyle(limit.1)
                            }
                    }
                    RuleMark(x: .value("Now", 0)).foregroundStyle(.secondary.opacity(0.4))
                }
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let i = value.as(Int.self) {
                                Text(i == 0 ? "Now" : String(format: "%02d:00", (start + i) % 24))
                            }
                        }
                    }
                }
                .chartYAxisLabel(detail.unit)
                .frame(height: 140)
                if detail.series.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(detail.series, id: \.name) { s in
                            Label(s.name, systemImage: "circle.fill").foregroundStyle(s.color)
                        }
                    }
                    .font(.caption2)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(detail.facts.enumerated()), id: \.offset) { _, fact in
                    GridRow {
                        Text(fact.0).foregroundStyle(.secondary)
                        Text(fact.1).fontWeight(.semibold)
                    }
                }
            }
            .font(.subheadline)
            Label(detail.rowing, systemImage: "figure.rower")
                .font(.subheadline)
            Text(detail.source).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

extension DetailMock {
    // 24 hourly sample values from 20:00.
    private static func curve(_ values: [Double]) -> [Double] { values }

    static let all: [DetailMock] = [
        DetailMock(
            condition: .temperature, value: "11°", note: "Cloudy · high 14°, low 6° today", unit: "°C",
            series: [
                Series(name: "Air", values: [11, 10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 7, 8, 10, 11, 12, 13, 14, 14, 13, 12, 11, 10, 10], color: .orange),
                Series(name: "Feels like", values: [9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 5, 6, 8, 10, 11, 12, 13, 13, 12, 10, 9, 8, 8], color: .blue),
            ],
            facts: [("Now", "11 °C"), ("Tonight", "lowest 6 °C at 05:00"), ("Tomorrow", "highest 14 °C at 14:00"), ("Yesterday", "highest 13 °C")],
            rowing: "Under 5 °C dress in layers and keep a dry set in the boathouse.",
            source: "Deutscher Wetterdienst (DWD) via Open-Meteo, 2 m above ground."
        ),
        DetailMock(
            condition: .feelsLike, value: "9°", note: "2° colder than the air: wind chill", unit: "°C",
            series: [
                Series(name: "Air", values: [11, 10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 7, 8, 10, 11, 12, 13, 14, 14, 13, 12, 11, 10, 10], color: .orange),
                Series(name: "Feels like", values: [9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 5, 6, 8, 10, 11, 12, 13, 13, 12, 10, 9, 8, 8], color: .blue),
            ],
            facts: [("Why", "Wind 2 m/s, gusts 4 m/s"), ("Humidity", "80 %"), ("Sun", "down"), ("On the water", "feels about 1° colder again from the boat's speed")],
            rowing: "Feels colder than 5 °C: gloves or pogies and a hat.",
            source: "Apparent temperature from air temperature, wind, humidity and sun (DWD via Open-Meteo)."
        ),
        DetailMock(
            condition: .humidity, value: "80 %", note: "Dew point 8° · 3° below the air", unit: "%",
            series: [Series(name: "Humidity", values: [80, 82, 85, 87, 89, 91, 93, 94, 95, 96, 96, 94, 90, 84, 78, 72, 68, 65, 64, 66, 70, 74, 77, 79], color: .teal)],
            facts: [("Dew point", "8 °C"), ("Air minus dew point", "3° (mist forms near 0–1°)"), ("Morning mist", "likely 04:00–08:00")],
            rowing: "When air and dew point meet, mist forms over the water: check visibility before going out early.",
            source: "Relative humidity and dew point, DWD via Open-Meteo."
        ),
        DetailMock(
            condition: .wind, value: "2 m/s", note: "Gusts 4 m/s · from the east (90°)",
            big: AnyView(WindDial(speed: "2", fromDeg: 90).frame(width: 100, height: 100)), unit: "m/s",
            series: [
                Series(name: "Wind", values: [2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 5, 5, 4, 4, 3, 3, 2, 2, 2], color: .blue),
                Series(name: "Gusts", values: [4, 4, 3, 3, 3, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9, 9, 8, 8, 7, 6, 5, 4, 4, 4], color: .purple),
            ],
            limits: [(6, .orange, "Row with care"), (9, .red, "Stay ashore")],
            facts: [("Beaufort", "2 · light breeze"), ("Direction", "E, along the lake"), ("Open water upwind", "0.1 km"), ("Strongest gust", "9 m/s at 15:00")],
            rowing: "Calm now; gusts reach the amber limit tomorrow afternoon.",
            source: "Wind at 10 m and gusts, DWD ICON via Open-Meteo. Limits from the app's settings."
        ),
        DetailMock(
            condition: .waves, value: "0.01 m", note: "Wind blows off the shore", unit: "m",
            series: [Series(name: "Waves", values: [0.01, 0.01, 0.01, 0.01, 0, 0, 0, 0.01, 0.01, 0.02, 0.04, 0.05, 0.08, 0.1, 0.14, 0.16, 0.15, 0.12, 0.1, 0.07, 0.05, 0.03, 0.02, 0.01], color: .blue)],
            limits: [(0.2, .orange, "Row with care"), (0.35, .red, "Stay ashore")],
            facts: [("Open water upwind", "0.1 km (wind off the shore)"), ("Highest", "0.16 m at 15:00"), ("Period", "about 1 s, short and steep")],
            rowing: "Flat water at the launch point; more chop mid-lake when the wind turns west.",
            source: "Calculated by the app from wind and the lake's shape (fetch), not measured."
        ),
        DetailMock(
            condition: .waterTemperature, value: "15.6°", note: "Measured 19:30 · Starnberg station", unit: "°C",
            series: [Series(name: "Last 7 days", values: [17.2, 17.0, 16.9, 16.8, 16.6, 16.5, 16.4, 16.3, 16.3, 16.2, 16.1, 16.0, 16.0, 15.9, 15.9, 15.8, 15.8, 15.7, 15.7, 15.7, 15.6, 15.6, 15.6, 15.6], color: .cyan)],
            limits: [(15, .orange, "Cool water"), (10, .red, "Cold water")],
            facts: [("Trend", "−1.6° in 7 days"), ("Station", "Starnberg (GKD 16663002)"), ("Depth", "surface")],
            rowing: "Below 15 °C capsizing gets serious fast; below 10 °C row only with a safety boat.",
            source: "Gewässerkundlicher Dienst Bayern (LfU). Chart shows the last 7 days instead of the next 24 hours."
        ),
        DetailMock(
            condition: .precipitation, value: "Dry", note: "Rain expected from 23:00", unit: "mm",
            series: [Series(name: "Rain", values: [0, 0, 0, 0.2, 0.6, 0.9, 0.4, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.1, 0.3], color: .blue, kind: .bars)],
            limits: [(4, .orange, "Heavy rain")],
            facts: [("Next 24 h", "2.6 mm in total"), ("Kind", "rain, no hail or snow"), ("Heaviest", "0.9 mm at 01:00")],
            rowing: "Light rain only; hail would come with a thunderstorm warning.",
            source: "Precipitation per hour and weather code, DWD via Open-Meteo."
        ),
        DetailMock(
            condition: .visibility, value: "32 km", note: "No fog", unit: "km",
            series: [Series(name: "Visibility", values: [32, 30, 25, 20, 15, 10, 6, 3, 1.5, 0.8, 1.2, 4, 10, 20, 30, 35, 40, 40, 38, 35, 30, 28, 25, 24], color: .gray)],
            limits: [(1, .orange, "Fog: care"), (0.5, .red, "Stay ashore")],
            facts: [("Fog", "possible 05:00–07:00"), ("Lowest", "0.8 km at 05:00")],
            rowing: "Early outings tomorrow may meet fog; wait until it lifts.",
            source: "Visibility, DWD via Open-Meteo."
        ),
        DetailMock(
            condition: .cloudCover, value: "100 %", note: "Low cloud 70 %", unit: "%",
            series: [
                Series(name: "All cloud", values: [100, 100, 95, 90, 90, 85, 80, 80, 75, 70, 60, 55, 50, 45, 40, 40, 45, 50, 60, 70, 80, 90, 95, 100], color: .gray),
                Series(name: "Low cloud", values: [70, 70, 65, 60, 60, 55, 50, 50, 40, 30, 20, 15, 10, 10, 5, 5, 10, 15, 20, 30, 40, 55, 65, 70], color: .indigo),
            ],
            facts: [("Sunny spells", "tomorrow 11:00–15:00"), ("Low cloud", "fog-like on the hills")],
            rowing: "No effect on the rowing light; low cloud often comes with poor visibility.",
            source: "Cloud cover, DWD via Open-Meteo."
        ),
        DetailMock(
            condition: .pressure, value: "1023 hPa", note: "Steady over the next 3 hours",
            big: AnyView(PressureGauge(hpa: 1023, trend: .steady).frame(width: 90, height: 90)), unit: "hPa",
            series: [Series(name: "Pressure", values: [1023, 1023, 1023, 1022.8, 1022.5, 1022.1, 1021.8, 1021.5, 1021.2, 1021, 1020.6, 1020.2, 1019.8, 1019.4, 1019, 1018.6, 1018.3, 1018, 1017.7, 1017.4, 1017.2, 1017, 1016.8, 1016.6], color: .purple)],
            facts: [("Next 24 h", "falling 6 hPa"), ("High pressure", "above 1013 hPa: mostly settled")],
            rowing: "Falling slowly: settled now, wind and rain more likely in 1–2 days. Falling 3 hPa or more in 3 hours often means wind soon.",
            source: "Air pressure at sea level, DWD via Open-Meteo."
        ),
        DetailMock(
            condition: .thunderstorm, value: "Low", note: "No DWD thunderstorm warning", unit: "J/kg",
            series: [Series(name: "Energy for storms (CAPE)", values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 40, 80, 120, 150, 120, 60, 20, 0, 0, 0, 0, 0, 0], color: .yellow, kind: .bars)],
            limits: [(300, .orange, "Possible"), (800, .red, "High")],
            facts: [("Highest risk", "low, tomorrow 15:00"), ("DWD warnings", "none for Starnberg")],
            rowing: "If you hear thunder, head for the shore at once: lightning can strike 10 km ahead of a storm.",
            source: "Estimated from DWD forecast (CAPE); official DWD warnings appear under DWD warnings."
        ),
        DetailMock(
            condition: .ice, value: "No data yet", note: "Planned for winter", unit: "",
            series: [],
            facts: [("Planned", "ice cover from satellite (Copernicus) and water temperature"), ("Until then", "check the lake yourself")],
            rowing: "Never row between ice floes; thin ice cuts hulls.",
            source: "Not available yet."
        ),
        DetailMock(
            condition: .daylight, value: "Sunset 18:18", note: "Sun is down · sunrise 07:40",
            big: AnyView(SunPathGraph(firstLight: 7.12, sunrise: 7.67, noon: 12.98, sunset: 18.3, lastLight: 18.85, now: 19.75, lineWidth: 2).frame(width: 120, height: 60)),
            unit: "",
            series: [],
            facts: [("First light", "07:07"), ("Sunrise", "07:40"), ("Sunset", "18:18"), ("Last light", "18:51"), ("Daylight", "10 h 38 min, 3 min shorter than yesterday"), ("Tomorrow", "sunrise 07:41, sunset 18:16")],
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
