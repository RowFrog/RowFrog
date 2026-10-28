import SwiftUI

/// Two columns for wide screens: each card goes, in order, into the column
/// that is shorter at that point, so neither ends far below the other. Then
/// the cards marked `ColumnFiller` (the lake view and launch point maps) in the
/// shorter column grow, so both columns end level, each card at most one
/// screen tall. A card's `ColumnSortHeight` stands in for its height in both
/// steps: the 48 hours report their folded height while opened, so opening
/// them moves no other card and changes no other card's size.
struct BalancedColumns: Layout {
    var spacing: CGFloat = 16
    /// The tallest a growing card may get: one screen, as the satellite picture.
    var tallestCard: CGFloat = .infinity

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(subviews, width: bounds.width)
        let column = columnWidth(bounds.width)
        for (subview, spot) in zip(subviews, placed.spots) {
            subview.place(at: CGPoint(x: bounds.minX + spot.origin.x, y: bounds.minY + spot.origin.y),
                          proposal: ProposedViewSize(width: column, height: spot.grown))
        }
    }

    private func columnWidth(_ width: CGFloat) -> CGFloat { max(0, (width - spacing) / 2) }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (spots: [(origin: CGPoint, grown: CGFloat?)], height: CGFloat) {
        let column = columnWidth(width)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
        let sorted = zip(subviews, heights).map { $0[ColumnSortHeight.self] ?? $1 }

        // Each card into the column that is shorter at that point.
        var ends: [CGFloat] = [0, 0]
        var columns: [Int] = []
        for height in sorted {
            let i = ends[1] < ends[0] ? 1 : 0
            // An empty card (a satellite picture still loading) takes no room and no gap.
            ends[i] += (ends[i] > 0 && height > 0 ? spacing : 0) + height
            columns.append(i)
        }

        // The maps in the shorter column share out the difference, each up to one screen.
        var grow = [CGFloat](repeating: 0, count: subviews.count)
        let shorter = ends[0] <= ends[1] ? 0 : 1
        var missing = abs(ends[0] - ends[1])
        var open = subviews.indices.filter { columns[$0] == shorter && subviews[$0][ColumnFiller.self] && sorted[$0] > 0 && sorted[$0] < tallestCard }
        while missing > 0.5, !open.isEmpty {
            let share = missing / CGFloat(open.count)
            for i in open {
                let more = min(share, tallestCard - sorted[i] - grow[i])
                grow[i] += more
                missing -= more
            }
            open.removeAll { sorted[$0] + grow[$0] >= tallestCard - 0.5 }
        }

        // Placed by their real heights, so an opened table runs on below.
        var tops: [CGFloat] = [0, 0]
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
                    fixedRow(tr("Rowing light"), symbol: "circle.fill", note: tr("always first"))
                    fixedRow(tr("Warnings"), symbol: "exclamationmark.triangle", note: tr("right under it, while one is issued"))
                    ForEach(layout.order) { card in
                        Toggle(isOn: Binding(
                            get: { !layout.hidden.contains(card) },
                            set: { on in if on { layout.hidden.remove(card) } else { layout.hidden.insert(card) } }
                        )) {
                            Label(card.title, systemImage: card.symbol)
                                .foregroundStyle(layout.hidden.contains(card) ? .secondary : .primary)
                        }
                    }
                    .onMove { layout.order.move(fromOffsets: $0, toOffset: $1) }
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
