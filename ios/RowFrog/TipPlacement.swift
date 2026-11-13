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

/// Puts the bubble on this control when the bubble is for it. A SwiftUI popover with the tip's
/// TipView inside, shown while the page picks the tip and the control is in sight: TipKit's own
/// popoverTip stayed away when it was attached after the page appeared (shots of 13 Nov, with
/// -RWTipDebug: tip picked, anchor attached, no popover).
struct BubbleAnchor: ViewModifier {
    let target: BubbleTarget
    var active = true
    @Environment(\.bubbleTip) private var bubble
    @State private var inSight = false
    @State private var presented = false

    private var tip: ClubPageTip? {
        guard active, let bubble, bubble.target == target else { return nil }
        return bubble.tip
    }

    func body(content: Content) -> some View {
        if active {
            anchored(content)
        } else {
            // The hour rows but the first: nothing to watch.
            content
        }
    }

    private func anchored(_ content: Content) -> some View {
        content
            // In sight: inside what its scroll view shows (a control scrolled away gets no bubble).
            .onGeometryChange(for: Bool.self) { proxy in
                CGRect(origin: .zero, size: proxy.size).intersects(proxy.bounds(of: .scrollView) ?? .infinite)
            } action: { inSight = $0 }
            .onChange(of: tip != nil && inSight, initial: true) { _, show in presented = show }
            // No fixed arrow edge: iOS puts the bubble above or below, where the whole tip fits
            // (below only, the German rain tip was cut on an iPhone, 13 Nov).
            .popover(isPresented: $presented) {
                // Always a popover, also while the tip changes (else iPhone falls back to an empty sheet).
                Group {
                    if let tip { BubbleTipView(tip: tip) }
                }
                .frame(width: 320)
                // Its whole height, so a long tip (German rain tip) is not cut at the top.
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
            }
            .tipDebug(tip == nil ? nil : target)
    }
}

/// The tip inside a bubble: TipKit's view of each tip, with its own type.
private struct BubbleTipView: View {
    let tip: ClubPageTip

    var body: some View {
        switch tip {
        case .topTile: TipView(TopTileTip())
        case .allValues: TipView(AllValuesTip())
        case .riverCurrent: TipView(RiverCurrentTip())
        case .rainRadar: TipView(RainRadarTip())
        case .hourView: TipView(HourViewTip())
        case .source: TipView(ForecastSourceTip())
        case .placeLine: TipView(PlaceLineTip())
        default: EmptyView()
        }
    }
}

extension View {
    /// `-RWTipDebug YES`: a red frame round a control that has its bubble attached, to tell
    /// in a screenshot whether the page picked it or TipKit didn't present it.
    /// Same view structure either way, so the frame never replaces the control under its bubble.
    func tipDebug(_ target: BubbleTarget?) -> some View {
        let shown = target != nil && UserDefaults.standard.bool(forKey: DefaultsKey.tipDebug)
        return overlay(alignment: .topLeading) {
            Text(verbatim: "bubble \(target.map { "\($0)" } ?? "")").font(.caption2.bold()).foregroundStyle(.white).background(.red)
                .opacity(shown ? 1 : 0)
        }
        .border(shown ? Color.red : Color.clear, width: 2)
    }

    /// The control a bubble tip can point at (rule R2).
    func bubbleAnchor(_ target: BubbleTarget, active: Bool = true) -> some View {
        modifier(BubbleAnchor(target: target, active: active))
    }
}
