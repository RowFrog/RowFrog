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
