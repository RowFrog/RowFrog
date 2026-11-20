import SwiftUI

// Split off LocationPageView.swift (owner's large-file rule, 4 Nov 2026): the
// top tile's wind and value views, unchanged except for the "Nearby" mark.

/// Wind now as mean–gust with an arrow pointing where the wind blows.
struct WindView: View {
    let hour: ForecastHour
    var size: CGFloat
    /// The worst wind within 1 km sets the light, so it shows instead of the launch point's.
    var nearby = false
    /// The light's colour while the wind sets it: the number and its unit "m/s" take it (owner,
    /// 20 Nov 2026: a unit takes its value's colour), the direction stays grey.
    @Environment(\.causeTint) private var tint

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(tr("Wind"), systemImage: Condition.wind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let wind = hour.shownWind
                Text(wind.speed.map { "\(Format.windNumber($0))–\(Format.windNumber(wind.gust))" } ?? "–")
                    .valueFont(size: size)
                    .causeTinted()
                if let from = hour.windFromDeg {
                    Image(systemName: "arrow.up")
                        .scaledSystemFont(size: size * 0.6, weight: .semibold, relativeTo: .title2, maxGrowth: 1.35)
                        .rotationEffect(.degrees(from + 180))
                }
            }
            // As wide as its longest direction ("from NW"), so the column keeps one
            // width whatever the wind does and the line never wraps.
            ZStack(alignment: .leading) {
                ForEach(0..<8, id: \.self) { step in
                    Text(unitLine(from: Double(step) * 45)).hidden()
                }
                unitText(from: hour.windFromDeg)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func unitLine(from degrees: Double?) -> String {
        AppSettings.shared.windUnit.symbol + rest(from: degrees)
    }

    /// The unit line as shown: the unit in the light's colour while the wind sets it.
    private func unitText(from degrees: Double?) -> Text {
        let unit = Text(AppSettings.shared.windUnit.symbol)
        return Text("\(tint.map { unit.foregroundStyle($0) } ?? unit)\(rest(from: degrees))")
    }

    private func rest(from degrees: Double?) -> String {
        if nearby { return " · " + tr("Nearby") }
        return degrees.map { " · " + tr("from %@", Format.compass($0)) } ?? ""
    }
}

/// A value with the icon and word that say what it is, matching TemperatureView.
struct MetricView: View {
    let title: String
    let symbol: String
    let value: String
    var size: CGFloat
    /// A grey line under the value, as the tiles have.
    var caption: String? = nil
    /// A symbol in front of the caption, such as the radar's.
    var mark: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            // Two lines rather than cut off, should a value outgrow its column.
            Text(value)
                .valueFont(size: size)
                .causeTinted()
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .alignmentGuide(.metricValue) { $0[.firstTextBaseline] }
            if let caption, !caption.isEmpty {
                Group {
                    if let mark { Text("\(Image(systemName: mark)) \(caption)") } else { Text(caption) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .greyLine()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
