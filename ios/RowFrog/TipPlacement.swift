import SwiftUI
import TipKit

// Where a tip sits (owner's placement rules, 12 Nov 2026; the website does the same):
// R1, a tip about a whole card sits inside that card, under its title (`cardTip`);
// R2, a tip about one control is a bubble on that control (`bubbleTip` + `bubbleAnchor`).
// The page decides which tip shows (ClubPageTip) and hands it down; the card puts it in place.

extension EnvironmentValues {
    /// The tip for the card below, shown inside it under its title. Card clears it for its content.
    @Entry var cardTip: AnyView? = nil
    /// The tip shown as a bubble on one control of the view below.
    @Entry var bubbleTip: BubbleTip? = nil
}

/// A tip and the control it points at.
struct BubbleTip {
    let target: BubbleTarget
    let tip: any Tip
}

/// The controls a bubble can point at.
enum BubbleTarget {
    /// The top tile's values (Tap a value, rain, river current).
    case values
    /// "All values" under the top tile.
    case allValues
    /// The first hour of the 48 hours (One hour in full).
    case hours
    /// The header's place line (lake and town), which opens the launch point.
    case place
    /// The forecast source line at the page's end.
    case source
}

/// Puts the bubble on this control when the bubble is for it.
struct BubbleAnchor: ViewModifier {
    let target: BubbleTarget
    var active = true
    @Environment(\.bubbleTip) private var bubble

    func body(content: Content) -> some View {
        if active, let bubble, bubble.target == target {
            content.popoverTip(bubble.tip, arrowEdge: .top)
        } else {
            content
        }
    }
}

extension View {
    /// The control a bubble tip can point at (rule R2).
    func bubbleAnchor(_ target: BubbleTarget, active: Bool = true) -> some View {
        modifier(BubbleAnchor(target: target, active: active))
    }
}
