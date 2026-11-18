import SwiftUI

/// The lake view tile on a club page: a small map of the lake coloured by the
/// conditions this hour, and which part of the lake is calmer. Tapping it
/// opens the full lake view.
struct LakeViewCard: View {
    let lakeID: String
    /// The club whose page this is; its launch point is marked.
    let clubID: String
    /// The club's water, measured or estimated: the shore turns blue when it is cold.
    var waterC: Double? = nil
    /// Lake, river or canal, for the title while the view loads.
    var water: WaterKind = .lake
    /// The river's current at the club's gauge, for the route planner.
    var currentMs: Double? = nil
    /// The club's sunrise and sunset, so "now" on the lake goes by this minute's daylight.
    var daylight: [SunDay]? = nil
    @MainActor private var store: LakeViewStore { .shared }
    @State private var showingMap = false

    var body: some View {
        Group {
            if let view = store.views[lakeID, club: clubID] {
                card(view)
            } else if !store.failed(lakeID) {
                Card(title: water.viewTitle, symbol: "map") {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showingMap) {
            if let view = store.views[lakeID, club: clubID] {
                LakeMapScreen(view: view, clubID: clubID)
            }
        }
    }

    /// Screenshot hook: `-RWOpenLakeView YES` opens the full lake view once it has loaded.
    @MainActor private func load() async {
        store.noteWater(waterC, lake: lakeID)
        store.noteCurrent(currentMs, lake: lakeID)
        store.noteDaylight(daylight, lake: lakeID)
        await store.load(lakeID)
        // Only on the page `-RWOpenClub` opens: clubs on the same lake would race it for the sheet.
        let page = UserDefaults.standard.string(forKey: DefaultsKey.openClub)
        if UserDefaults.standard.bool(forKey: DefaultsKey.openLakeView), store.views[lakeID, club: clubID] != nil, page == nil || page == clubID {
            showingMap = true
        }
    }

    private func card(_ view: LakeView) -> some View {
        let index = view.hourIndex()
        let hour = view.hours.isEmpty ? nil : view.hours[index]
        let aspect = LakeProjection.aspect(of: view.grid)
        return Card(title: view.water.viewTitle + " · " + view.name, symbol: "map", opens: { showingMap = true }) {
            Button { showingMap = true } label: {
                if let hour {
                    if aspect >= 1.3 {
                        HStack(alignment: .top, spacing: 14) {
                            LakeMiniMap(view: view, hour: hour, clubID: clubID)
                                // Taller when the club page's columns need it filled (BalancedColumns).
                                .frame(width: 120)
                                .frame(minHeight: min(320, max(170, 120 * aspect)), idealHeight: min(320, max(170, 120 * aspect)), maxHeight: .infinity)
                            summary(view, hour)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            LakeMiniMap(view: view, hour: hour, clubID: clubID)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 180, idealHeight: 180, maxHeight: .infinity)
                            summary(view, hour)
                        }
                    }
                } else {
                    Text(tr("No forecast")).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(view.water.opensHint)
        }
    }

    private func summary(_ view: LakeView, _ hour: LakeHour) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The running hour; its start time read like a wrong clock (decision 0039).
            Text(tr("Now"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(view.headline(for: hour))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if view.isStale {
                Label(tr("Forecast out of date: from %@. Check the conditions yourself.", Format.dayTime(view.generatedAt)), systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if hour.lakeWide.light > .green {
                LakeWideBanner(lakeWide: hour.lakeWide, water: water)
            }
            MapBoatNote(clubID: clubID)
            // A small table like the 48-hour one, wind with its direction, also for a
            // lake or stretch in one part; the old wind line under it went (owner's H1, 12 Nov 2026).
            if !view.zones.isEmpty {
                LakeZoneTable(view: view, hour: hour)
            }
            if view.sample {
                Label(tr("Sample wind"), systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            // No "Open lake view" link: the whole tile opens it, and the › in its
            // title row says so, as on the value tiles (owner, 13 Nov 2026).
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What holds for the whole lake (or river stretch) this hour, such as a DWD storm warning or darkness.
struct LakeWideBanner: View {
    let lakeWide: LakeWide
    var water: WaterKind = .lake

    private var reasons: String { lakeWide.reasons.map(\.label).joined(separator: ", ") }

    var body: some View {
        Label {
            Text(water == .lake ? tr("Whole lake: %@", reasons) : tr("Whole stretch: %@", reasons))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: lakeWide.reasons.first?.symbol ?? "exclamationmark.triangle.fill")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(lakeWide.light.color)
    }
}

/// Fits the lake into a rectangle, north up, in an equirectangular projection.
struct LakeProjection {
    let grid: LakeGrid
    let scale: CGFloat
    let origin: CGPoint
    private let k: Double

    static func aspect(of grid: LakeGrid) -> CGFloat {
        let k = cos((grid.north + grid.southEdge) / 2 * .pi / 180)
        return CGFloat((grid.north - grid.southEdge) / ((grid.east - grid.westEdge) * k))
    }

    init(grid: LakeGrid, size: CGSize, padding: CGFloat = 6) {
        self.grid = grid
        k = cos((grid.north + grid.southEdge) / 2 * .pi / 180)
        let w = (grid.east - grid.westEdge) * k, h = grid.north - grid.southEdge
        scale = min((size.width - 2 * padding) / w, (size.height - 2 * padding) / h)
        origin = CGPoint(x: (size.width - w * scale) / 2, y: (size.height - h * scale) / 2)
    }

    func point(lon: Double, lat: Double) -> CGPoint {
        CGPoint(x: origin.x + (lon - grid.westEdge) * k * scale, y: origin.y + (grid.north - lat) * scale)
    }

    var imageRect: CGRect {
        let a = point(lon: grid.westEdge, lat: grid.north), b = point(lon: grid.east, lat: grid.southEdge)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    func outline(_ rings: [[[Double]]]) -> Path {
        var path = Path()
        for ring in rings where ring.count > 2 {
            path.move(to: point(lon: ring[0][0], lat: ring[0][1]))
            for p in ring.dropFirst() { path.addLine(to: point(lon: p[0], lat: p[1])) }
            path.closeSubpath()
        }
        return path
    }
}

enum LakeArrow {
    /// An arrow centred on `at`, pointing where the wind blows to (0 = north, clockwise).
    static func path(at: CGPoint, towardDeg: Double, length: CGFloat) -> Path {
        let r = towardDeg * .pi / 180
        let dx = CGFloat(sin(r)), dy = CGFloat(-cos(r))
        let tail = CGPoint(x: at.x - dx * length / 2, y: at.y - dy * length / 2)
        let tip = CGPoint(x: at.x + dx * length / 2, y: at.y + dy * length / 2)
        let head = length * 0.35
        var path = Path()
        path.move(to: tail)
        path.addLine(to: tip)
        for side in [-1.0, 1.0] {
            let a = r + .pi + side * 0.5
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + CGFloat(sin(a)) * head, y: tip.y - CGFloat(cos(a)) * head))
        }
        return path
    }
}

extension ColdShore {
    var color: Color {
        self == .cool ? Color(red: 0.36, green: 0.66, blue: 0.95) : Color(red: 0.08, green: 0.33, blue: 0.76)
    }
}
