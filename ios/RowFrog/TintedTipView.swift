import SwiftUI
import TipKit

/// A tip in a page: a box tinted with the tip blue, so it reads as a tip in light
/// and dark and over a frosted tile shows no solid block (owner's pick C,
/// 12 Nov 2026, docs/decisions/0023). The website draws the same (.tip in style.css).
struct TintedTipView<T: Tip>: View {
    let tip: T
    @Environment(\.colorScheme) private var scheme

    init(_ tip: T) { self.tip = tip }

    /// The blue's share: a touch more in dark mode, where the tile behind is dark.
    static func tint(dark: Bool) -> Double { dark ? 0.22 : 0.14 }

    var body: some View {
        TipView(tip)
            .tipBackground(Color.blue.opacity(Self.tint(dark: scheme == .dark)))
    }
}
