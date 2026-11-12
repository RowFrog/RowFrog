import SwiftUI

// Moved out of LocationPageView.swift unchanged (large-file split).

/// Which part of the legend a card's ⓘ opens; `.all` in the settings.
enum LegendPart: String {
    case lights, conditions, hourly, all
}

/// The legend, or the part of it one card needs.
struct LegendSheet: View {
    let part: LegendPart
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if part == .lights || part == .all { lights }
                    if part == .all { Divider() }
                    if part == .conditions || part == .all { symbols; conditionIcons(Condition.tileOrder) }
                    if part == .all { Divider() }
                    if part == .hourly || part == .all { columns }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
        .presentationDetents(part == .all ? [.large] : [.medium, .large])
    }

    private var title: String {
        switch part {
        case .lights: tr("Rowing light")
        case .conditions: tr("Weather symbols")
        case .hourly: tr("The columns")
        case .all: tr("Legend")
        }
    }

    private var lights: some View {
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
        }
    }

    private var symbols: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
    }

    private func conditionIcons(_ conditions: [Condition]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(conditions) { c in
                HStack(alignment: .top, spacing: 10) {
                    ConditionIcon(condition: c).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.unit.isEmpty ? c.title : "\(c.title) (\(c.unit))").font(.subheadline.weight(.semibold))
                        Text(c.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The hourly table's columns from left to right.
    private var columns: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock").frame(width: 24)
                Text(tr("Time; the hour starts here.")).font(.subheadline)
            }
            HStack(alignment: .top, spacing: 10) {
                TrafficLightDot(light: .green, size: 12).frame(width: 24)
                Text(tr("Rowing light for your boat in that hour.")).font(.subheadline)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cloud.sun").frame(width: 24)
                Text(tr("Weather symbol; it also shows how cloudy it is.")).font(.subheadline)
            }
            conditionIcons([.temperature, .feelsLike, .wind, .waves, .precipitation, .visibility])
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "moon.stars.fill").frame(width: 24)
                Text(tr("Night line: the hours between sunset and sunrise in one line, with the night's lowest temperature and feels-like, strongest wind and gusts, highest waves, all its rain and its poorest visibility. Tap it to see each hour.")).font(.subheadline)
            }
            Text(tr("Hours after sunset are dimmed. Tap an hour to see all its values.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
