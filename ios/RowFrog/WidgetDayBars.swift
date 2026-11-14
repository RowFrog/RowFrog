// The large widgets' day bars and how tightly the large widgets are packed,
// split off WidgetLayouts.swift (14 Nov 2026) when the fit steps came in.

import SwiftUI
import WidgetKit

extension RowingWidgetView {
    /// The good rowing times as one bar per day: green, amber (striped with marks)
    /// and red (an outline with marks), past hours faint, and the first good stretch.
    func dayBars(_ count: Int, header: Bool, big: Bool, fit: WidgetFit = .regular) -> some View {
        let days = snapshot.days(count)
        return VStack(alignment: .leading, spacing: big ? fit.dayGap : 4) {
            if header {
                Label(tr("Good to row"), systemImage: "figure.rower")
                    .font(.caption.weight(.semibold))
            }
            if days.isEmpty {
                Text(snapshot.noWindowsText).font(.caption).opacity(0.85)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                HStack(spacing: 8) {
                    Text(day.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: big ? 64 : 54, alignment: .leading)
                    HStack(spacing: 2) {
                        ForEach(Array(day.lights.enumerated()), id: \.offset) { index, light in
                            segment(light, past: day.past[index])
                        }
                        // Not forecast yet: room kept, a faint dashed outline.
                        ForEach(0..<day.missing, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .opacity(0.35)
                        }
                    }
                    .frame(height: big ? 10 : 8)
                    .accessibilityHidden(true)
                    Text(day.good ?? (snapshot.isStale ? "–" : day.missing > 0 ? tr("Not known yet") : tr("Not good")))
                        .font(.caption.monospacedDigit())
                        .opacity(day.good == nil ? 0.75 : 1)
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
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
