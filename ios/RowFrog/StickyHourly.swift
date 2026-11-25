import SwiftUI

// Split off LocationPageView.swift (owner rule: large Swift files lose a piece when touched).

/// Where the hourly table and its days are on the screen.
@Observable
final class StickyHourly {
    var hourlyFrame: CGRect = .zero
    var dayTops: [Date: CGFloat] = [:]
    /// Where the table's last line starts, in global coordinates (0 before it was measured).
    var lastRowTop: CGFloat = 0
    /// Where the header stays on the screen, in global coordinates.
    var top: CGFloat = 0
    /// The height of the tip under the card's title (0 without one): the header stays only once
    /// the tip has gone up, so it never covers the tip.
    var leadIn: CGFloat = 0

    /// Whether the header is staying at the top.
    func isShowing(at top: CGFloat) -> Bool {
        hourlyFrame.height > 0 && hourlyFrame.minY + 40 + leadIn < top && hourlyFrame.maxY > top
    }

    /// How far up the last line has pushed the header (0 or less). The header stops on the
    /// table's last line and the two leave together, so it never stands alone over the
    /// tile's rounded end with no row under it (owner's pick B, 25 Nov 2026: it showed
    /// square corners there on the iPhone).
    func push(at top: CGFloat) -> CGFloat {
        let end = lastRowTop > hourlyFrame.minY && lastRowTop < hourlyFrame.maxY ? lastRowTop : hourlyFrame.maxY
        return min(0, end - top - HourlyStickyHeader.height)
    }
}

/// Tells StickyHourly how tall the hourly card's tip is, while it shows.
struct StickyLeadIn: ViewModifier {
    let sticky: StickyHourly

    func body(content: Content) -> some View {
        content
            // The tip and the space under it, before the table's own header.
            .onGeometryChange(for: CGFloat.self) { $0.size.height + 8 } action: { sticky.leadIn = $0 }
            .onDisappear { sticky.leadIn = 0 }
    }
}

/// While the header stays, the tile ends at it: the rows scroll away under the
/// header instead of showing beside its rounded corners, as in the Weather app.
struct StickyHourlyCut: ViewModifier {
    let sticky: StickyHourly

    func body(content: Content) -> some View {
        let showing = sticky.isShowing(at: sticky.top)
        let cut = showing ? max(0, sticky.top + sticky.push(at: sticky.top) - sticky.hourlyFrame.minY) : 0
        // Rounded at the cut like the header's top, so nothing of the tile shows
        // beside the header's corners.
        let radius: CGFloat = showing ? 16 : 0
        content.mask(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius).padding(.top, cut)
        }
    }
}

/// The hourly table's header while the table is under the top of the screen.
struct StickyHourlyHeader: View {
    let sticky: StickyHourly

    var body: some View {
        let hourlyFrame = sticky.hourlyFrame, dayTops = sticky.dayTops
        GeometryReader { geo in
            let top = geo.frame(in: .global).minY
            let height = HourlyStickyHeader.height
            Color.clear
                .onAppear { sticky.top = top }
                .onChange(of: top) { _, new in sticky.top = new }
            if sticky.isShowing(at: top) {
                // The day whose header has passed under this one. Before the first, the
                // rows are the day before it (today), not that day: the header said
                // "Morgen" over today's rows (detail check 14 Nov 2026).
                let day = dayTops.filter { $0.value <= top + height }.max { $0.value < $1.value }?.key
                    ?? dayTops.keys.min().flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) }
                // At the end of the table the last rows push the header up and away,
                // instead of it vanishing while rows are still under it.
                let push = sticky.push(at: top)
                HourlyStickyHeader(day: day)
                    .frame(width: hourlyFrame.width)
                    // Cut to the tile's shape, so its square bottom corners round off
                    // with the tile's own corners as it leaves.
                    .mask(alignment: .top) {
                        RoundedRectangle(cornerRadius: 16)
                            .frame(height: hourlyFrame.height)
                            .offset(y: hourlyFrame.minY - top - push)
                    }
                    .offset(x: hourlyFrame.minX - geo.frame(in: .global).minX, y: push)
                    .transition(.opacity)
            }
        }
        // Not clipped: when the last rows push the header up, it slides on under
        // the status bar together with the tile's cut edge.
        .frame(height: HourlyStickyHeader.height)
        .allowsHitTesting(false)
    }
}
