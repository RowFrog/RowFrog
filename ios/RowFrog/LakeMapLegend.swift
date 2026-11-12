import SwiftUI

// Split off LakeMapScreen.swift (owner's large-file rule, 4 Nov 2026): the lake
// map's legend sheet, unchanged except that its stripes now run the way the
// lake's own stripes do (owner, 12 Nov 2026).

/// What each symbol and colour on the lake map means, listing only what is on
/// the map right now (layer, whole-lake stripes, route, boat, spot).
struct LakeMapLegend: View {
    let layer: LakeLayer
    let stripes: Light?
    let routeMode: Bool
    let hasRoute: Bool
    let boat: Bool
    let spot: Bool
    let hasWind: Bool
    var track = false
    var clubID: String? = nil
    var coldShore: ColdShore? = nil
    /// Whether this lake's stripes fall from top left to bottom right (`LakeView.stripesFall`),
    /// so the legend's stripes run the same way as the map's.
    var stripesFall = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(layer.title) {
                    LakeLegend(layer: layer, clubID: clubID).padding(.vertical, 4)
                    MapBoatNote(clubID: clubID)
                    if stripes == .red {
                        row(StripeSwatch(color: .red, fall: stripesFall),
                            tr("Grey squares with red stripes: the whole lake is red (official warning or darkness), see the panel."))
                    } else if stripes == .amber {
                        row(StripeSwatch(color: .orange, fall: stripesFall),
                            tr("Amber stripes: the whole lake is amber (the last hour before sunset, official warning), see the panel. The squares keep their own colours."))
                    }
                }
                Section(tr("On the map")) {
                    row(ClubMarkIcon(color: .blue, symbol: LocationStore.markSymbol(for: clubID)), ClubMarkIcon.pageClubText(clubID))
                    row(ClubMarkIcon(color: .gray), tr("Other clubs on the lake"))
                    row(ClubMarkIcon(color: .blue, symbol: ClubMarks.launchSymbol), tr("Zoomed in: the club's pin moves to the club's own place in the map app, and oars mark the launch point the forecast is for"))
                    if let coldShore {
                        row(Capsule().fill(coldShore.color).frame(width: 18, height: 4),
                            tr("Blue shore: the water is cold. Bring a life jacket; light blue below %@, deeper blue below %@.",
                               Format.temperature(AppSettings.shared.limits(at: clubID).value(.lifeJacket)), Format.temperature(RowingLimits.coldWaterC)))
                    }
                    if hasWind {
                        row(Image(systemName: "arrow.up.right").fontWeight(.bold),
                            tr("Wind: points where the wind blows to; longer arrows mean stronger wind. Between the forecast points the wind is estimated from the nearest ones. On land the arrows show the weather map's wind forecast for each place."))
                    }
                    if spot { row(Image(systemName: "scope"), tr("The spot you tapped")) }
                }
                if routeMode {
                    Section(tr("Route")) {
                        row(Image(systemName: "circle.fill").foregroundStyle(.blue), tr("Start at your club"))
                        row(Image(systemName: "circle").fontWeight(.bold), tr("Turning point: tap to select, hold and drag to move"))
                        if hasRoute {
                            row(HStack(spacing: 2) { ForEach([Light.green, .amber, .red], id: \.self) { Capsule().fill($0.color).frame(width: 8, height: 4) } },
                                tr("The route in the light the boat meets there; out and back run side by side"))
                        }
                        if boat { row(ClubMarkIcon(color: .indigo), tr("Where the boat is at the time shown")) }
                        if track { row(Image(systemName: "scribble.variable").foregroundStyle(.secondary), tr("Dashed: the track as you rowed it (imported row)")) }
                    }
                }
            }
            .navigationTitle(tr("Legend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ symbol: some View, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            symbol.frame(width: 28)
            Text(text).font(.subheadline)
        }
    }
}

/// A few stripes in a small square, running like the lake's stripes on the map:
/// bottom left to top right, or top left to bottom right where they fall.
struct StripeSwatch: View {
    let color: Color
    var fall = false

    var body: some View {
        Canvas { ctx, size in
            var lines = Path()
            for k in stride(from: -size.height, to: size.width, by: size.width / 3) {
                lines.move(to: CGPoint(x: k, y: fall ? 0 : size.height))
                lines.addLine(to: CGPoint(x: k + size.height, y: fall ? size.height : 0))
            }
            ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3))
            ctx.stroke(lines, with: .color(color), lineWidth: 1.6)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
