import SwiftUI

/// How many columns the club page's cards go into (owner's rule B, 12 Nov 2026,
/// the same on the website): the count follows the page's width as if the side
/// list were shown, so sliding the list away or back only makes the same columns
/// wider or narrower (each at most `widestCard`) and no card changes column. A
/// third column needs room for three cards of at least `narrowestCard`; the
/// buffer between `threeFrom` and `threeUntil` keeps a window resized right at
/// the edge from switching back and forth. The top tile stays full width.
enum ClubPageColumns {
    static let spacing: CGFloat = 16
    /// The page's padding on each side.
    static let padding: CGFloat = 16
    /// From this page width (padding included) the cards go into two columns.
    static let twoFrom: CGFloat = 600
    /// Three columns from this width of the cards' room (the page without its padding)…
    static let threeFrom: CGFloat = 1200
    /// …and back to two below this one: three cards of `narrowestCard` and their gaps.
    static let threeUntil: CGFloat = 1172
    static let narrowestCard: CGFloat = 380
    static let widestCard: CGFloat = 560
    /// One column keeps lines readable on wide screens (as the page did before rule B).
    static let oneColumnWidth: CGFloat = 1000
    /// How long a resize must rest before the count is worked out again.
    static let resizePause: Duration = .milliseconds(300)

    /// The count for a page `width` points wide (padding included) as if the list
    /// were shown; `current` is the count shown now, for the buffer.
    static func count(width: CGFloat, current: Int? = nil) -> Int {
        guard width >= twoFrom else { return 1 }
        let room = width - 2 * padding
        let three = current == 3 ? room >= threeUntil : room >= threeFrom
        return three ? 3 : 2
    }

    /// The widest the page gets (padding included) with this many columns.
    static func pageWidth(columns: Int) -> CGFloat {
        guard columns > 1 else { return oneColumnWidth }
        return CGFloat(columns) * widestCard + CGFloat(columns - 1) * spacing + 2 * padding
    }
}

/// Where a page's cards were last seen in its scroll view. A plain class, not
/// observed: it is written while scrolling and read only when the column count
/// changes, so that the card at the top stays at the top.
final class CardSpots {
    static let space = "clubPageScroll"
    var frames: [PageCard: CGRect] = [:]

    /// The card at the top edge of the screen (the leftmost one there), or the
    /// first one below it; nil while the page is not scrolled past its first card.
    func topCard(below edge: CGFloat) -> PageCard? {
        let shown = frames.filter { $0.value.height > 0 && $0.value.maxY > edge }
        guard frames.values.contains(where: { $0.height > 0 && $0.minY < edge }) else { return nil }
        return shown.min { a, b in
            let aCut = a.value.minY <= edge, bCut = b.value.minY <= edge
            if aCut != bCut { return aCut }
            if aCut { return a.value.minX < b.value.minX }
            return (a.value.minY, a.value.minX) < (b.value.minY, b.value.minX)
        }?.key
    }
}

extension PageCard {
    /// The id the club page gives this card, for scrolling to it.
    var scrollID: String {
        switch self {
        case .radar: "radar"
        case .conditions: "conditions"
        case .lakeView: "lakeview"
        case .hourly: "hourly"
        case .launchPoint: "launchpoint"
        case .satellite: "satellite"
        }
    }
}

private struct WidthBesideListKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// A club page's width as if the side list were shown, where the list can
    /// show (a wide iPad window); nil elsewhere. The column count follows it.
    var widthBesideList: CGFloat? {
        get { self[WidthBesideListKey.self] }
        set { self[WidthBesideListKey.self] = newValue }
    }
}

/// Columns for wide screens (ClubPageColumns): each card goes, in order, into
/// the column that is shortest at that point, so none ends far below another.
/// Then the cards marked `ColumnFiller` (the lake view and launch point maps) in
/// the shorter columns grow, so the columns end level, each card at most one
/// screen tall. A card's `ColumnSortHeight` stands in for its height in both
/// steps: the 48 hours report their folded height while opened, so opening
/// them moves no other card and changes no other card's size.
struct BalancedColumns: Layout {
    var columns: Int = 2
    var spacing: CGFloat = ClubPageColumns.spacing
    /// The tallest a growing card may get: one screen, as the satellite picture.
    var tallestCard: CGFloat = .infinity
    var widestCard: CGFloat = ClubPageColumns.widestCard

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    // The columns line up with nothing outside them. Without these, an alignment
    // query on them has SwiftUI place every card again to work it out, which
    // froze the app in the top tile grid (TopTileGrid) on the iPhone.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        nil
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        nil
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(subviews, width: bounds.width)
        let column = columnWidth(bounds.width)
        // Columns at their widest are centred.
        let used = CGFloat(count) * column + CGFloat(count - 1) * spacing
        let left = bounds.minX + max(0, (bounds.width - used) / 2)
        for (subview, spot) in zip(subviews, placed.spots) {
            subview.place(at: CGPoint(x: left + spot.origin.x, y: bounds.minY + spot.origin.y),
                          proposal: ProposedViewSize(width: column, height: spot.grown))
        }
    }

    private var count: Int { max(1, columns) }

    func columnWidth(_ width: CGFloat) -> CGFloat {
        min(widestCard, max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count)))
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (spots: [(origin: CGPoint, grown: CGFloat?)], height: CGFloat) {
        let column = columnWidth(width)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
        let sorted = zip(subviews, heights).map { $0[ColumnSortHeight.self] ?? $1 }
        let (columns, grow) = Self.balance(sorted: sorted, fillers: subviews.map { $0[ColumnFiller.self] },
                                           columns: count, spacing: spacing, tallestCard: tallestCard)

        // Placed by their real heights, so an opened table runs on below.
        var tops = [CGFloat](repeating: 0, count: count)
        var spots: [(origin: CGPoint, grown: CGFloat?)] = []
        for i in subviews.indices {
            let c = columns[i]
            let height = heights[i] + grow[i]
            let gap: CGFloat = tops[c] > 0 && height > 0 ? spacing : 0
            spots.append((CGPoint(x: CGFloat(c) * (column + spacing), y: tops[c] + gap), grow[i] > 0.5 ? height : nil))
            tops[c] += gap + height
        }
        return (spots, tops.max() ?? 0)
    }

    /// Which column each card goes into, and how much each filler grows, from
    /// the heights the cards count with (kept apart from SwiftUI for the tests).
    static func balance(sorted: [CGFloat], fillers: [Bool], columns count: Int, spacing: CGFloat,
                        tallestCard: CGFloat) -> (columns: [Int], grow: [CGFloat]) {
        // Each card into the column that is shortest at that point (the leftmost on a tie).
        var ends = [CGFloat](repeating: 0, count: count)
        var columns: [Int] = []
        for height in sorted {
            let i = ends.indices.min { ends[$0] < ends[$1] } ?? 0
            // An empty card (a satellite picture still loading) takes no room and no gap.
            ends[i] += (ends[i] > 0 && height > 0 ? spacing : 0) + height
            columns.append(i)
        }

        // The maps in each shorter column share out its difference, each up to one screen.
        var grow = [CGFloat](repeating: 0, count: sorted.count)
        let longest = ends.max() ?? 0
        for c in ends.indices where ends[c] < longest {
            var missing = longest - ends[c]
            var open = sorted.indices.filter { columns[$0] == c && fillers[$0] && sorted[$0] > 0 && sorted[$0] < tallestCard }
            while missing > 0.5, !open.isEmpty {
                let share = missing / CGFloat(open.count)
                for i in open {
                    let more = min(share, tallestCard - sorted[i] - grow[i])
                    grow[i] += more
                    missing -= more
                }
                open.removeAll { sorted[$0] + grow[$0] >= tallestCard - 0.5 }
            }
        }
        return (columns, grow)
    }
}

/// A card whose map may grow to fill its column (BalancedColumns).
struct ColumnFiller: LayoutValueKey {
    static let defaultValue = false
}

/// The height a card counts with when the columns are sorted, if not its own.
struct ColumnSortHeight: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

/// "Arrange this page": move cards by their handle, switch them off, for all
/// clubs or only this one. Dragging happens only here, never on the page,
/// so it cannot get in the way of swiping between clubs.
struct ArrangePageSheet: View {
    /// Nil in the settings, where the order is always for all clubs.
    let club: Club?
    @Environment(\.dismiss) private var dismiss
    @State private var onlyThisClub: Bool
    @State private var layout: PageLayout
    private var settings: AppSettings { .shared }

    init(club: Club?) {
        self.club = club
        let ownOrder = club.flatMap { AppSettings.shared.clubPageLayouts[$0.id] }
        _onlyThisClub = State(initialValue: ownOrder != nil)
        _layout = State(initialValue: ownOrder ?? AppSettings.shared.pageLayout)
    }

    var body: some View {
        NavigationStack {
            List {
                if let club {
                    Section {
                        Picker(tr("Apply to"), selection: $onlyThisClub) {
                            Text(tr("All clubs")).tag(false)
                            Text(tr("Only %@", club.displayName)).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: onlyThisClub) { _, only in
                            // Start from what that choice shows today.
                            layout = only ? settings.pageLayout(for: club.id) : settings.pageLayout
                        }
                    } footer: {
                        Text(onlyThisClub
                             ? tr("Only this club's page changes. Changes for all clubs no longer reach it until you reset it.")
                             : otherClubsNote)
                    }
                }
                Section {
                    if settings.launchPointInHeader {
                        fixedRow(PageCard.launchPoint.title, symbol: PageCard.launchPoint.symbol, note: tr("in the club header"))
                    }
                    fixedRow(tr("Rowing light"), symbol: "circle.fill", note: tr("always first"))
                    // In the order the page shows them: the top tile holds the
                    // current conditions, the warnings come under it (owner 14 Nov 2026).
                    if settings.combinedTopTile {
                        fixedRow(PageCard.conditions.title, symbol: PageCard.conditions.symbol, note: tr("in the top tile"))
                    }
                    fixedRow(tr("Warnings"), symbol: "exclamationmark.triangle", note: tr("right under it, while one is issued"))
                    ForEach(movable) { card in
                        Toggle(isOn: Binding(
                            get: { !layout.hidden.contains(card) },
                            set: { on in if on { layout.hidden.remove(card) } else { layout.hidden.insert(card) } }
                        )) {
                            Label(card.title, systemImage: card.symbol)
                                .foregroundStyle(layout.hidden.contains(card) ? .secondary : .primary)
                        }
                    }
                    .onMove(perform: move)
                } header: {
                    Text(tr("Drag the handles to change the order"))
                } footer: {
                    Text(tr("Switched-off cards are left out of the page. The forecast source and credits stay at the end.") + " "
                         + tr("The rain radar card starts switched off: the rain tile in Current conditions shows the radar."))
                }
                Section {
                    if onlyThisClub {
                        // Setting onlyThisClub reloads the order for all clubs.
                        Button(tr("Use the order for all clubs")) { onlyThisClub = false }
                    } else {
                        Button(tr("Reset to the standard order"), role: .destructive) { layout = .standard }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(tr("Arrange page"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { save(); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        // The iPad's form sheet was too short: the note and the reset button sat
        // below its edge (detail check 14 Nov 2026, B1.3).
        .presentationSizing(.page)
    }

    /// The cards that can be moved here: not those shown elsewhere on the page for now.
    private var movable: [PageCard] {
        layout.order.filter { !settings.cardsElsewhere.contains($0) }
    }

    /// Moves within the list shown; a card left out of it keeps its place in the
    /// saved order, for when it is a card of its own again.
    private func move(from: IndexSet, to: Int) {
        var cards = movable
        cards.move(fromOffsets: from, toOffset: to)
        for (place, card) in layout.order.enumerated() where settings.cardsElsewhere.contains(card) {
            cards.insert(card, at: min(place, cards.count))
        }
        layout.order = cards
    }

    private var otherClubsNote: String {
        let own = settings.clubPageLayouts.keys.filter { $0 != club?.id }.count
        return own == 0
            ? tr("Every club page uses this order.")
            : tr("Every club page uses this order, except %@ with their own.", "\(own)")
    }

    private func fixedRow(_ title: String, symbol: String, note: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(note).font(.caption).foregroundStyle(.secondary)
            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
        }
        .moveDisabled(true)
    }

    private func save() {
        if let club, onlyThisClub {
            settings.clubPageLayouts[club.id] = layout
        } else {
            settings.pageLayout = layout
            // Chosen on this club's page for all clubs: the club follows them again.
            if let club { settings.clubPageLayouts[club.id] = nil }
        }
    }
}
