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

    var body: some View {
        Circle()
            .fill(light.color(stale: stale))
            .frame(width: size, height: size)
            .accessibilityLabel(light.title(stale: stale))
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
