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

/// A basin with the water in it, from the drained mark (empty) to full.
struct BasinGauge: View {
    let levelM: Double
    let level: LakeLevel

    var body: some View {
        let low = level.drainedBelowM - 2
        let fraction = max(0, min(1, (levelM - low) / max(level.fullM - low, 0.1)))
        let color: Color = levelM < level.drainedBelowM ? .red : levelM < level.loweredBelowM ? .orange : .teal
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                Path { p in
                    p.move(to: CGPoint(x: 2, y: 4))
                    p.addLine(to: CGPoint(x: w * 0.3, y: h - 4))
                    p.addLine(to: CGPoint(x: w * 0.7, y: h - 4))
                    p.addLine(to: CGPoint(x: w - 2, y: 4))
                }
                .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                Rectangle()
                    .fill(color)
                    .frame(width: w * (0.4 + 0.5 * fraction), height: max(3, (h - 10) * fraction))
                    .padding(.bottom, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
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
                ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { dismiss() } }
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
