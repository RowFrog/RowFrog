// The large widgets' day bars and how tightly the large widgets are packed,
// split off WidgetLayouts.swift (14 Nov 2026) when the fit steps came in.

import SwiftUI
import WidgetKit

extension RowingWidgetView {
    /// The good rowing times as one bar per day: green, amber (striped with marks)
    /// and red (an outline with marks), past hours faint, and the first good stretch.
    /// All bars share one clock axis, from the earliest first hour to the latest last
    /// hour of the days shown, so an hour sits at the same place every day and today's
    /// bar does not stretch as the day ends; a tick marks now (owner's pick B, 15 Nov 2026).
    func dayBars(_ count: Int, header: Bool, big: Bool, fit: WidgetFit = .regular) -> some View {
        let days = snapshot.days(count)
        let axisStart = days.map(\.firstHour).min() ?? 0
        let axisEnd = days.map { $0.firstHour + $0.slots }.max() ?? 0
        let texts = days.map { dayText($0) }
        return VStack(alignment: .leading, spacing: big ? fit.dayGap : 4) {
            if header {
                Label(tr("Good to row"), systemImage: "figure.rower")
                    .font(.caption.weight(.semibold))
                if axisEnd - axisStart >= 3 {
                    // The clock above the bars: every third hour.
                    HStack(spacing: 8) {
                        Color.clear.frame(width: big ? 64 : 54, height: 1)
                        GeometryReader { geometry in
                            ForEach(Array(stride(from: axisStart, to: axisEnd, by: 3)), id: \.self) { hour in
                                Text(String(format: "%02d", hour))
                                    .fixedSize()
                                    .offset(x: geometry.size.width * Double(hour - axisStart) / Double(axisEnd - axisStart))
                            }
                        }
                        ZStack {
                            ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                                Text(text).font(.caption.monospacedDigit()).hidden()
                            }
                        }
                        .fixedSize()
                        .frame(height: 1)
                    }
                    .font(.system(size: 9).monospacedDigit())
                    .opacity(0.7)
                    .frame(height: 10)
                    .padding(.bottom, -(big ? fit.dayGap : 4) / 2)
                    .accessibilityHidden(true)
                }
            }
            if days.isEmpty {
                Text(snapshot.noWindowsText).font(.caption).opacity(0.85)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                HStack(spacing: 8) {
                    Text(day.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: big ? 64 : 54, alignment: .leading)
                    HStack(spacing: 2) {
                        slots(day.firstHour - axisStart) { Color.clear }
                        slots(day.earlier) { segment(.green, past: true) }
                        ForEach(Array(day.lights.enumerated()), id: \.offset) { index, light in
                            segment(light, past: day.past[index])
                        }
                        // Not forecast yet: room kept, a faint dashed outline.
                        slots(day.missing) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .opacity(0.35)
                        }
                        slots(axisEnd - day.firstHour - day.slots) { Color.clear }
                    }
                    .frame(height: big ? 10 : 8)
                    .overlay(alignment: .leading) {
                        if let now = day.now, axisEnd > axisStart, !snapshot.isStale {
                            nowTick(at: (now - Double(axisStart)) / Double(axisEnd - axisStart), big: big)
                        }
                    }
                    .accessibilityHidden(true)
                    // Every text takes the widest one's room, so all bars end in line.
                    ZStack(alignment: .leading) {
                        ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                            Text(text).hidden()
                        }
                        Text(texts[index])
                            .opacity(day.good == nil ? 0.75 : 1)
                    }
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func dayText(_ day: WidgetDay) -> String {
        day.good ?? (snapshot.isStale ? "–" : day.missing > 0 ? tr("Not known yet") : tr("Not good"))
    }

    /// `count` equal slots of the bar (none when `count` is 0 or less).
    private func slots<Slot: View>(_ count: Int, @ViewBuilder _ slot: @escaping () -> Slot) -> some View {
        ForEach(0..<max(count, 0), id: \.self) { _ in slot() }
    }

    /// A small upright line at `fraction` of the bar's width: now.
    private func nowTick(at fraction: Double, big: Bool) -> some View {
        GeometryReader { geometry in
            Capsule()
                .fill(plain ? Color.primary : Color.white)
                .frame(width: 2, height: (big ? 10 : 8) + 6)
                .offset(x: geometry.size.width * min(max(fraction, 0), 1) - 1, y: -3)
        }
    }

    @ViewBuilder
    private func segment(_ light: Light, past: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let faint = plain ? Color.secondary.opacity(0.25) : Color.white.opacity(0.22)
        if past {
            shape.fill(faint)
        } else if snapshot.isStale {
            // Out of date: grey, not even amber or red, as the hours row.
            shape.fill(Color.gray)
        } else if showMarks && light == .red {
            shape.strokeBorder(Light.red.color, lineWidth: 1.5)
        } else if showMarks && light == .amber {
            shape.fill(Light.amber.color)
                .overlay(Stripes().stroke(Color.black.opacity(0.35), lineWidth: 1.5))
                .clipShape(shape)
        } else {
            shape.fill(light.color(stale: snapshot.isStale))
        }
    }
}

/// How tightly the large and extra large widgets are packed (WidgetLayouts' ViewThatFits steps).
struct WidgetFit: Equatable {
    /// Gap between the widget's parts (head, rules, hours, days).
    let gap: CGFloat
    /// Gap between the lines under the hours.
    let rowGap: CGFloat
    /// Height of the weather symbol row.
    let skyHeight: CGFloat
    /// Gap between the day bars.
    let dayGap: CGFloat
    /// How many days the bars show.
    let days: Int
    /// The step's number, for the widget gallery's badge.
    let step: Int

    static let regular = WidgetFit(gap: 10, rowGap: 5, skyHeight: 26, dayGap: 8, days: 3, step: 1)
    static let tight = WidgetFit(gap: 6, rowGap: 3, skyHeight: 22, dayGap: 6, days: 3, step: 2)
    static let tightTwoDays = WidgetFit(gap: 6, rowGap: 3, skyHeight: 22, dayGap: 6, days: 2, step: 3)
}

extension EnvironmentValues {
    /// The widget gallery (`-RWWidgetGallery YES`) shows which fit step a widget landed on.
    @Entry var showsWidgetFitStep = false
}

/// A small "Step N" in the bottom right corner, in the widget gallery only.
struct FitStepBadge: ViewModifier {
    let step: Int
    @Environment(\.showsWidgetFitStep) private var shows

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if shows {
                Text("Step \(step)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("widget-fit-step-\(step)")
            }
        }
    }
}
