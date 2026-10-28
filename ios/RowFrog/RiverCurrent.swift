import Charts
import SwiftUI

/// The river at a river club (backend: the forecast's "river" block, see
/// backend/rowfrog/river.py): the nearest gauge's water level and the current.
/// On river clubs the Current tile takes the ice tile's place.
struct RiverConditions: Codable, Hashable {
    /// Missing where no federal gauge is on the club's river nearby.
    let gauge: RiverGauge?
    /// Missing without a gauge or when its last reading is too old.
    let now: RiverReading?
    var limits: CurrentLimits? = nil
    var attribution: String? = nil
}

struct RiverGauge: Codable, Hashable {
    let name: String
    let water: String
    var riverKm: Double? = nil
    let lat: Double
    let lon: Double
    let distanceKm: Double
    /// Mean water, mean high water and the level at which shipping stops, in cm at the gauge.
    var meanCm: Double? = nil
    var meanHighCm: Double? = nil
    var shippingStopsCm: Double? = nil
    /// Mean discharge in m³/s.
    var meanDischarge: Double? = nil
}

struct CurrentLimits: Codable, Hashable {
    let currentAmberMs: Double
    let currentRedMs: Double
}

struct RiverReading: Codable, Hashable {
    let time: Date
    let levelCm: Double?
    /// "rising", "falling", "steady" or "".
    let trend: String
    /// "normal", "raised", "high", "shipping_stopped" or "" without the gauge's marks.
    let state: String
    let discharge: Double?
    /// Mid-river, measured at the gauge or estimated from the discharge.
    let speedMs: Double?
    let speedMeasured: Bool
    let light: Light
    let history: [RiverLevel]

    var stateTitle: String {
        switch state {
        case "normal": tr("Normal water")
        case "raised": tr("Raised water")
        case "high": tr("High water")
        case "shipping_stopped": tr("Shipping stopped")
        default: tr("Water level")
        }
    }

    var trendTitle: String? {
        switch trend {
        case "rising": tr("rising")
        case "falling": tr("falling")
        case "steady": tr("steady")
        default: nil
        }
    }

    var trendSymbol: String {
        switch trend {
        case "rising": "arrow.up.right"
        case "falling": "arrow.down.right"
        default: "arrow.right"
        }
    }
}

struct RiverLevel: Codable, Hashable {
    let time: Date
    let levelCm: Double
}

enum RiverFormat {
    /// "1.3 m/s" (always m/s: flow speeds are given so on rivers).
    static func speed(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return Format.number(ms, digits: 1) + " m/s"
    }

    /// "3.20 m" for a gauge level in cm.
    static func level(_ cm: Double?) -> String {
        guard let cm else { return "–" }
        return Format.number(cm / 100, digits: 2) + " m"
    }

    /// Time per 500 m over ground at a still-water pace, with the current
    /// helping (downstream) or against (upstream); nil when the boat cannot make way.
    static func pace(_ secondsPer500: Double, current: Double, downstream: Bool) -> Double? {
        let speed = 500 / secondsPer500 + (downstream ? current : -current)
        return speed > 0.2 ? 500 / speed : nil
    }
}

/// The tile in Current conditions, in the ice tile's place.
struct CurrentTile: View {
    let river: RiverConditions
    @Environment(\.surface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: CurrentTile.symbol).symbolRenderingMode(.hierarchical).frame(width: 16)
                Text(tr("Current")).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let light = river.now?.light, light > .green {
                    TrafficLightDot(light: light, size: 8)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if let now = river.now, let level = now.levelCm {
                    LevelBar(levelCm: level, gauge: river.gauge).frame(width: 44, height: 44)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .topLeading)
        .background(surface.tile, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    static let symbol = "arrow.right.circle"

    private var value: String {
        guard let now = river.now else { return river.gauge == nil ? tr("No gauge") : tr("No reading") }
        if now.state == "shipping_stopped" { return tr("Shipping stopped") }
        if let speed = now.speedMs { return (now.speedMeasured ? "" : "≈ ") + RiverFormat.speed(speed) }
        return now.stateTitle
    }

    private var detail: String {
        guard let now = river.now else {
            return river.gauge == nil ? tr("Check the river yourself") : tr("Gauge %@", river.gauge?.name ?? "")
        }
        let level = RiverFormat.level(now.levelCm)
        return [level, now.trendTitle].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The level between mean water and the shipping mark: a vertical bar like a gauge board.
struct LevelBar: View {
    let levelCm: Double
    let gauge: RiverGauge?

    var body: some View {
        let low = (gauge?.meanCm ?? levelCm) - 100
        let top = gauge?.shippingStopsCm ?? gauge?.meanHighCm.map { $0 + 100 } ?? levelCm + 100
        let fraction = max(0, min(1, (levelCm - low) / max(top - low, 1)))
        let color: Color = gauge?.shippingStopsCm.map { levelCm >= $0 } == true ? .red
            : gauge?.meanHighCm.map { levelCm >= $0 } == true ? .orange : .teal
        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.secondary.opacity(0.2)).frame(width: 10)
                Capsule().fill(color).frame(width: 10, height: max(10, geo.size.height * fraction))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// Opened from the Current tile: speed, level and its last two days, and how
/// the current changes a crew's pace.
struct CurrentDetailView: View {
    let river: RiverConditions
    @Environment(\.dismiss) private var dismiss
    @AppStorage("RWRoutePace") private var pace = 150.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let now = river.now {
                        summary(now)
                        if now.history.count > 1 { chart(now) }
                        if let speed = now.speedMs { paceTable(speed) }
                    } else {
                        Text(river.gauge == nil
                             ? tr("No federal gauge measures this river near the club. Check the water level and current yourself, and ask your club when the river runs high.")
                             : tr("The gauge has sent no recent reading. Check the water level and current yourself."))
                            .foregroundStyle(.secondary)
                    }
                    notes
                }
                .padding()
            }
            .navigationTitle(tr("Current"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
            }
        }
    }

    private func summary(_ now: RiverReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(now.speedMs.map { (now.speedMeasured ? "" : "≈ ") + RiverFormat.speed($0) } ?? now.stateTitle)
                    .font(.largeTitle.weight(.semibold))
                if now.light > .green { TrafficLightDot(light: now.light, size: 14) }
            }
            if now.speedMs != nil {
                Text(now.speedMeasured ? tr("Flow speed measured at the gauge") : tr("Estimated mid-river; near the bank the water is slower"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label {
                Text([now.stateTitle, RiverFormat.level(now.levelCm), now.trendTitle].compactMap { $0 }.joined(separator: " · "))
            } icon: {
                Image(systemName: now.trendSymbol)
            }
            .font(.headline)
            if now.state == "shipping_stopped" {
                Label(tr("Above the shipping mark: even motor ships stay in. Do not row."), systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
            } else if now.state == "high" {
                Label(tr("High water: strong current, flotsam and flooded banks. Only experienced crews, with care."), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func chart(_ now: RiverReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Water level, last two days")).font(.headline)
            Chart {
                ForEach(now.history, id: \.time) { h in
                    LineMark(x: .value(tr("Time"), h.time), y: .value(tr("Level"), h.levelCm / 100))
                        .foregroundStyle(.teal)
                }
                if let mean = river.gauge?.meanCm {
                    RuleMark(y: .value(tr("Mean water"), mean / 100))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) { Text(tr("Mean water")).font(.caption2).foregroundStyle(.secondary) }
                }
                if let stop = river.gauge?.shippingStopsCm {
                    RuleMark(y: .value(tr("Shipping stops"), stop / 100))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) { Text(tr("Shipping stops")).font(.caption2).foregroundStyle(.red) }
                }
            }
            .chartYAxisLabel("m")
            .frame(height: 180)
        }
    }

    private func paceTable(_ current: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Your pace %@ /500 m on this current", Format.pace(pace))).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text(tr("Upstream"))
                    Text(RiverFormat.pace(pace, current: current, downstream: false).map { Format.pace($0) + " /500 m" } ?? tr("No headway"))
                        .fontWeight(.semibold)
                }
                GridRow {
                    Text(tr("Downstream"))
                    Text(RiverFormat.pace(pace, current: current, downstream: true).map { Format.pace($0) + " /500 m" } ?? "–")
                        .fontWeight(.semibold)
                }
            }
            Text(tr("Over ground. The route planner on the river view uses the same current."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let g = river.gauge {
                let km = g.riverKm.map { " · " + tr("river km %@", Format.number($0, digits: 1)) } ?? ""
                Text(tr("Gauge %@ (%@)", g.name, g.water) + km + " · " + tr("%@ km from the club", Format.number(g.distanceKm, digits: 1)))
                if let time = river.now?.time { Text(tr("Reading %@", Format.dayTime(time))) }
            }
            if let limits = river.limits {
                Text(tr("Current amber from %@, red above %@. Shipping stopped is red, high water amber.",
                        RiverFormat.speed(limits.currentAmberMs), RiverFormat.speed(limits.currentRedMs)))
            }
            Text(tr("Data: %@", river.attribution ?? "WSV PEGELONLINE"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
