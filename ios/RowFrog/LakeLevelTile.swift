import Charts
import SwiftUI

/// The tile in Current conditions, in the ice tile's place while a lake is
/// lowered on purpose (Forggensee in winter).
struct WaterLevelTile: View {
    let level: LakeLevel
    @Environment(\.surface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: LakeLevel.symbol).symbolRenderingMode(.hierarchical).frame(width: 16)
                Text(tr("Water level")).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let light = level.now?.light, light > .green {
                    TrafficLightDot(light: light, size: 8)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(level.now?.stateTitle ?? tr("No reading")).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if let now = level.now {
                    BasinGauge(levelM: now.levelM, level: level).frame(width: 44, height: 44)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .topLeading)
        .background(surface.tile, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var detail: String {
        guard let now = level.now else { return tr("Gauge %@", level.gauge) }
        return [tr("%@ below full", LakeLevelFormat.metres(now.belowFullM)), now.trendTitle].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A basin with the water in it, from 2 m under the drained mark (empty) to full,
/// with the marks drawn in: the full mark as a dashed line across, the lowered
/// (amber) and drained (red) marks as short lines on its right side. The water
/// follows the basin's sloping sides. Before, it was a box standing out over them,
/// and without the marks 1.1 m below full read as nearly full (owner, 12 Nov 2026).
struct BasinGauge: View {
    let levelM: Double
    let level: LakeLevel

    var body: some View {
        let shape = BasinShape(level: level)
        let fraction = shape.fraction(levelM)
        let color: Color = levelM < level.drainedBelowM ? .red : levelM < level.loweredBelowM ? .orange : .teal
        return GeometryReader { geo in
            let k = min(geo.size.width, geo.size.height) / BasinShape.size
            let point = { (p: CGPoint) in CGPoint(x: p.x * k, y: p.y * k) }
            ZStack {
                Path { p in p.addLines(BasinShape.water(fraction).map(point)); p.closeSubpath() }
                    .fill(color)
                Path { p in p.addLines(BasinShape.walls.map(point)) }
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                Path { p in p.addLines(BasinShape.mark(1, wholeWidth: true).map(point)) }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                Path { p in p.addLines(BasinShape.mark(shape.fraction(level.loweredBelowM)).map(point)) }
                    .stroke(Color.orange, lineWidth: 1.5)
                Path { p in p.addLines(BasinShape.mark(shape.fraction(level.drainedBelowM)).map(point)) }
                    .stroke(Color.red, lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The basin's drawing in a 44 x 44 box (the website's lakelevel.js `basinShape` copies it).
struct BasinShape {
    let level: LakeLevel
    static let size: CGFloat = 44
    /// The rim and the floor of the basin's sides.
    static let rimY: CGFloat = 4, floorY: CGFloat = 40
    /// Where the sides meet the rim and the floor on the left; the right mirrors them.
    static let rimX: CGFloat = 2, floorX: CGFloat = 13.2
    /// The water's height when full, and its bottom, inside the sides.
    static let fullY: CGFloat = 9, emptyY: CGFloat = 38.5

    static let walls = [CGPoint(x: rimX, y: rimY), CGPoint(x: floorX, y: floorY),
                        CGPoint(x: size - floorX, y: floorY), CGPoint(x: size - rimX, y: rimY)]

    /// How full, 0 at 2 m under the drained mark, 1 at the full mark.
    func fraction(_ levelM: Double) -> Double {
        let low = level.drainedBelowM - 2
        return max(0, min(1, (levelM - low) / max(level.fullM - low, 0.1)))
    }

    static func y(_ fraction: Double) -> CGFloat { emptyY - (emptyY - fullY) * fraction }

    /// The inside of the left side at height y (1.5 in from its line).
    static func leftX(_ y: CGFloat) -> CGFloat { rimX + (floorX - rimX) * (y - rimY) / (floorY - rimY) + 1.5 }

    /// The water: from the floor up to its height, between the sides.
    static func water(_ fraction: Double) -> [CGPoint] {
        let top = min(y(fraction), emptyY - 2)
        return [CGPoint(x: leftX(emptyY), y: emptyY), CGPoint(x: size - leftX(emptyY), y: emptyY),
                CGPoint(x: size - leftX(top), y: top), CGPoint(x: leftX(top), y: top)]
    }

    /// A mark at a level: right across, or a short line on the right side.
    static func mark(_ fraction: Double, wholeWidth: Bool = false) -> [CGPoint] {
        let at = y(fraction)
        let right = size - leftX(at) + 1
        return [CGPoint(x: wholeWidth ? leftX(at) - 1 : right - 7, y: at), CGPoint(x: right, y: at)]
    }
}

enum LakeLevelFormat {
    /// "4.2 m".
    static func metres(_ m: Double) -> String { Format.number(m, digits: 1) + " m" }

    /// "776.40 m" above sea level.
    static func height(_ m: Double) -> String { Format.number(m, digits: 2) + " m" }
}

/// Opened from the Water level tile: the level, its last week and the marks.
struct WaterLevelDetailView: View {
    let level: LakeLevel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let now = level.now {
                        summary(now)
                        if now.history.count > 1 { chart(now) }
                    } else {
                        Text(tr("The gauge has sent no recent reading. Ask your club whether there is enough water to row."))
                            .foregroundStyle(.secondary)
                    }
                    Text(tr("The lake is let down every winter, for flood protection and power: from mid-November, lowest in February, full again by about the end of May."))
                        .font(.callout)
                    notes
                }
                .padding()
            }
            .navigationTitle(tr("Water level"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
    }

    private func summary(_ now: LakeLevelReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(now.stateTitle).font(.largeTitle.weight(.semibold))
                if now.light > .green { TrafficLightDot(light: now.light, size: 14) }
            }
            Text([LakeLevelFormat.height(now.levelM), tr("%@ below full", LakeLevelFormat.metres(now.belowFullM)), now.trendTitle]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.headline)
            if now.state == "drained" {
                Label(tr("Too little water at the club to row."), systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
            } else if now.state == "lowered" {
                Label(tr("Lowered: shallows, sandbanks and a long way to the water. Check the landing stage first."), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func chart(_ now: LakeLevelReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Water level, last week")).font(.headline)
            Chart {
                ForEach(now.history, id: \.time) { h in
                    LineMark(x: .value(tr("Time"), h.time), y: .value(tr("Level"), h.levelM))
                        .foregroundStyle(.teal)
                }
                RuleMark(y: .value(tr("Full"), level.fullM))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) { Text(tr("Full")).font(.caption2).foregroundStyle(.secondary) }
                RuleMark(y: .value(tr("Drained"), level.drainedBelowM))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) { Text(tr("Drained")).font(.caption2).foregroundStyle(.red) }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel("m")
            .frame(height: 180)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityChartDescriptor(ChartDescription(
                title: tr("Water level, last week"), unit: "m",
                series: [.init(name: tr("Level"), points: now.history.map { ($0.time, $0.levelM) })],
                summary: LakeLevelFormat.height(now.levelM), digits: 2))
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Gauge %@", level.gauge))
            if let time = level.now?.time { Text(tr("Reading %@", Format.dayTime(time))) }
            Text(tr("Amber below %@, red below %@.", LakeLevelFormat.height(level.loweredBelowM), LakeLevelFormat.height(level.drainedBelowM)))
            Text(tr("Data: %@", level.attribution ?? "GKD Bayern"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
