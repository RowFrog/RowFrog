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

/// A tip and the control it points at. Plain values, so the page hands down the same value
/// on every redraw (a stored `any Tip` showed no bubble at all in the shots of 13 Nov).
struct BubbleTip: Equatable {
    let target: BubbleTarget
    let tip: ClubPageTip
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
            // Each with its own tip type, as every popover tip that works in the app.
            switch bubble.tip {
            case .topTile: content.popoverTip(TopTileTip(), arrowEdge: .top).tipDebug(target)
            case .allValues: content.popoverTip(AllValuesTip(), arrowEdge: .top).tipDebug(target)
            case .riverCurrent: content.popoverTip(RiverCurrentTip(), arrowEdge: .top).tipDebug(target)
            case .rainRadar: content.popoverTip(RainRadarTip(), arrowEdge: .top).tipDebug(target)
            case .hourView: content.popoverTip(HourViewTip(), arrowEdge: .top).tipDebug(target)
            case .source: content.popoverTip(ForecastSourceTip(), arrowEdge: .top).tipDebug(target)
            case .placeLine: content.popoverTip(PlaceLineTip(), arrowEdge: .top).tipDebug(target)
            default: content
            }
        } else {
            content
        }
    }
}

extension View {
    /// `-RWTipDebug YES`: a red frame round a control that has its bubble attached, to tell
    /// in a screenshot whether the page picked it or TipKit didn't present it.
    @ViewBuilder func tipDebug(_ target: BubbleTarget) -> some View {
        if UserDefaults.standard.bool(forKey: DefaultsKey.tipDebug) {
            overlay(alignment: .topLeading) {
                Text(verbatim: "bubble \(target)").font(.caption2.bold()).foregroundStyle(.white).background(.red)
            }
            .border(.red, width: 2)
        } else {
            self
        }
    }

    /// The control a bubble tip can point at (rule R2).
    func bubbleAnchor(_ target: BubbleTarget, active: Bool = true) -> some View {
        modifier(BubbleAnchor(target: target, active: active))
    }
}
