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
        case .green: "Good to row"
        case .amber: "Row with care"
        case .red: "Stay ashore"
        }
    }
}

struct TrafficLightDot: View {
    let light: Light
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(light.color)
            .frame(width: size, height: size)
            .accessibilityLabel(light.title)
    }
}
