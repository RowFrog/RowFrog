import SwiftUI

/// A card on a club page that the user can move or switch off. The rowing
/// light stays first and DWD warnings, while one is issued, right under it;
/// the forecast source and credits stay last.
enum PageCard: String, CaseIterable, Codable, Identifiable {
    case radar, conditions, lakeView, hourly, launchPoint, satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radar: tr("Rain radar")
        case .conditions: tr("Current conditions")
        case .lakeView: tr("Lake view")
        case .hourly: tr("Next 48 hours")
        case .launchPoint: tr("Launch point")
        case .satellite: tr("Satellite picture")
        }
    }

    var symbol: String {
        switch self {
        case .radar: "umbrella"
        case .conditions: "gauge.with.dots.needle.33percent"
        case .lakeView: "map"
        case .hourly: "clock"
        case .launchPoint: "mappin.and.ellipse"
        case .satellite: "globe.europe.africa"
        }
    }
}

/// The order of the cards on a club page and which are switched off.
struct PageLayout: Codable, Hashable {
    var order: [PageCard]
    var hidden: Set<PageCard> = []

    static let standard = PageLayout(order: [.radar, .conditions, .lakeView, .hourly, .launchPoint, .satellite])

    /// From a launch argument such as "hourly,radar"; cards left out follow in the standard order.
    init(list: String) {
        self.init(order: list.split(separator: ",").compactMap { PageCard(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }

    init(order: [PageCard], hidden: Set<PageCard> = []) {
        // Every card once; cards added in a later version join at the end.
        var seen = Set<PageCard>()
        self.order = (order + PageCard.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown names (from a newer version) are skipped instead of failing.
        let order = try c.decode([String].self, forKey: .order).compactMap(PageCard.init(rawValue:))
        let hidden = try c.decodeIfPresent([String].self, forKey: .hidden)?.compactMap(PageCard.init(rawValue:)) ?? []
        self.init(order: order, hidden: Set(hidden))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
    }

    private enum CodingKeys: String, CodingKey { case order, hidden }

    var visible: [PageCard] { order.filter { !hidden.contains($0) } }
}

/// Two columns for wide screens: each card goes, in order, into the column
/// that is shorter at that point, so neither ends far below the other.
struct BalancedColumns: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        let placed = arrange(subviews, width: width)
        return CGSize(width: width, height: placed.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(subviews, width: bounds.width)
        let column = columnWidth(bounds.width)
        for (subview, spot) in zip(subviews, placed.spots) {
            subview.place(at: CGPoint(x: bounds.minX + spot.x, y: bounds.minY + spot.y),
                          proposal: ProposedViewSize(width: column, height: nil))
        }
    }

    private func columnWidth(_ width: CGFloat) -> CGFloat { max(0, (width - spacing) / 2) }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (spots: [CGPoint], height: CGFloat) {
        let column = columnWidth(width)
        var heights: [CGFloat] = [0, 0]
        var spots: [CGPoint] = []
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            let i = heights[1] < heights[0] ? 1 : 0
            // An empty card (a satellite picture still loading) takes no room and no gap.
            let gap: CGFloat = heights[i] > 0 && height > 0 ? spacing : 0
            spots.append(CGPoint(x: CGFloat(i) * (column + spacing), y: heights[i] + gap))
            heights[i] += gap + height
        }
        return (spots, heights.max() ?? 0)
    }
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
                    fixedRow(tr("DWD warnings"), symbol: "exclamationmark.triangle", note: tr("right under it, while one is issued"))
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
                    Text(tr("Switched-off cards are left out of the page. The forecast source and credits stay at the end."))
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
