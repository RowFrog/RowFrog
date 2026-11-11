import SwiftUI

extension Light {
    var color: Color {
        switch self {
        case .green: .green
        case .amber: .orange
        case .red: .red
        }
    }

    var title: String {
        switch self {
        case .green: tr("Good to row")
        case .amber: tr("Row with care")
        case .red: tr("Stay ashore")
        }
    }
}

extension Light {
    /// With an out-of-date forecast a green light turns grey: it can no longer
    /// say the water is good. Amber and red stay, as they still warn.
    func color(stale: Bool) -> Color { stale && self == .green ? .gray : color }

    func title(stale: Bool) -> String { stale && self == .green ? tr("Forecast out of date") : title }
}

struct TrafficLightDot: View {
    let light: Light
    var size: CGFloat = 14
    var stale = false
    /// An hour in which the light changes: left half the light it starts with, right half
    /// the one it ends with (owner's pick D, 6 Nov 2026).
    var halves: DotHalves? = nil
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    var body: some View {
        Group {
            if let halves, !stale {
                ZStack {
                    Circle().fill(halves.start.color(stale: false))
                    Circle().fill(halves.end.color(stale: false))
                        .mask(HStack(spacing: 0) { Color.clear; Color.black })
                    if withoutColor {
                        // Settings › Accessibility › Display & Text Size › Differentiate Without Colour:
                        // a gap between the halves, so the change shows without its colours.
                        Rectangle().fill(.background).frame(width: max(1, size / 10))
                    }
                }
                .clipShape(Circle())
            } else {
                Circle().fill(light.color(stale: stale))
            }
        }
        .overlay {
            // The same setting: a mark in the dot for amber and red, where it is big enough to read.
            if withoutColor, !stale, size >= 12, let mark = (halves.map { max($0.start, $0.end) } ?? light).mark {
                Image(systemName: mark)
                    .font(.system(size: size * 0.5, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(halves.map { tr("%@, then %@", $0.start.title, $0.end.title) } ?? light.title(stale: stale))
    }
}

extension Light {
    /// The mark in the dot when colours are not to be relied on: none for green.
    var mark: String? {
        switch self {
        case .green: nil
        case .amber: "exclamationmark"
        case .red: "xmark"
        }
    }
}

extension ColdWaterKit {
    /// The badge's blue: its own colour, so it never reads as a warning light.
    static let color = Color(red: 0.18, green: 0.5, blue: 0.82)
    /// The deeper blue for very cold water: dark navy on light backgrounds,
    /// a lighter blue on dark ones, where the navy would vanish.
    static let deep = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.47, green: 0.64, blue: 0.94, alpha: 1)
        : UIColor(red: 0.11, green: 0.3, blue: 0.55, alpha: 1) })
}

/// The blue cold-water badge under the rowing light: what to bring, not a warning.
struct ColdWaterBadge: View {
    let kit: ColdWaterKit
    /// Estimated water, not measured: the badge says so.
    var estimated = false

    var body: some View {
        Label(estimated ? "≈ " + kit.title : kit.title, systemImage: ColdWaterKit.symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(ColdWaterKit.color.opacity(0.18), in: Capsule())
            .foregroundStyle(ColdWaterKit.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(estimated ? tr("Estimated: %@", kit.explanation) : kit.explanation)
    }
}

/// Just the symbol, for the list row and the widget.
struct ColdWaterGlyph: View {
    let kit: ColdWaterKit
    var body: some View {
        Image(systemName: ColdWaterKit.symbol)
            .foregroundStyle(ColdWaterKit.color)
            .accessibilityLabel(kit.title)
    }
}

extension Light {
    /// The colour a value takes while it sets the light: amber or red, never green,
    /// so a coloured value always means "this is why" (owner's pick C1/T2, 5 Nov 2026).
    var causeTint: Color? { self == .green ? nil : color }
}

extension EnvironmentValues {
    /// The light colour of the value shown inside, while that value sets the light.
    @Entry var causeTint: Color? = nil
}

extension View {
    /// Colours a value in the light it sets, if it sets one (see `Light.causeTint`).
    func causeTinted() -> some View { modifier(CauseTinted()) }
}

private struct CauseTinted: ViewModifier {
    @Environment(\.causeTint) private var tint

    func body(content: Content) -> some View {
        if let tint { content.foregroundStyle(tint) } else { content }
    }
}

extension Condition {
    /// The light this value sets in an hour, if amber or red (see `Light.causeTint`).
    /// Screenshot hook: `-RWSampleCause wind,thunderstorm` makes those values amber.
    func cause(in hour: ForecastHour) -> Light? {
        if Self.sampleCauses.contains(rawValue) { return .amber }
        return hour.light(for: reasonNames).flatMap { $0 == .green ? nil : $0 }
    }

    /// Read once: launch arguments do not change while the app runs.
    private static let sampleCauses: Set<String> =
        Set((UserDefaults.standard.string(forKey: "RWSampleCause") ?? "").split(separator: ",").map(String.init))
}

extension ColdWaterKit {
    /// The water value's colour while the Life jacket badge shows: the cold-water blue on the
    /// number, and the wash and rim on its open tile (owner's pick W2, 5 Nov 2026). Blue never
    /// means the light. For W0 (no blue) return nil here; for W1 (number only) see `causeHighlight`.
    static func valueTint(waterC: Double?, limits: RowingLimits) -> Color? {
        ColdWaterKit(waterC: waterC, limits: limits) == nil ? nil : color
    }
}
