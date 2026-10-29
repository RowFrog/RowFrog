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
    @MainActor private var store: LakeViewStore { .shared }
    @State private var showingMap = false

    var body: some View {
        Group {
            if let view = store.views[lakeID] {
                card(view)
            } else if !store.failed.contains(lakeID) {
                Card(title: water.viewTitle, symbol: "map") {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showingMap) {
            if let view = store.views[lakeID] {
                LakeMapScreen(view: view, clubID: clubID)
            }
        }
    }

    /// Screenshot hook: `-RWOpenLakeView YES` opens the full lake view once it has loaded.
    @MainActor private func load() async {
        store.noteWater(waterC, lake: lakeID)
        store.noteCurrent(currentMs, lake: lakeID)
        await store.load(lakeID)
        // Only on the page `-RWOpenClub` opens: clubs on the same lake would race it for the sheet.
        let page = UserDefaults.standard.string(forKey: "RWOpenClub")
        if UserDefaults.standard.bool(forKey: "RWOpenLakeView"), store.views[lakeID] != nil, page == nil || page == clubID {
            showingMap = true
        }
    }

    private func card(_ view: LakeView) -> some View {
        let index = view.hourIndex()
        let hour = view.hours.isEmpty ? nil : view.hours[index]
        let aspect = LakeProjection.aspect(of: view.grid)
        return Card(title: view.water.viewTitle + " · " + view.name, symbol: "map") {
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
            Text(tr("Now, %@", Format.time(hour.time)))
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
            MapBoatNote()
            if view.zones.count > 1 {
                ForEach(Array(zip(view.zones.indices, view.zones)), id: \.0) { i, zone in
                    if i < hour.zones.count {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                TrafficLightDot(light: hour.zones[i].light, size: 10, stale: view.isStale)
                                Text(LakeZoneName.title(zone)).font(.subheadline.weight(.semibold))
                            }
                            Text(tr("Waves up to %@", Format.waves(hour.zones[i].maxWaveM)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 16)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let wind = view.windSummary(for: hour) {
                Label(wind, systemImage: Condition.wind.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if view.sample {
                Label(tr("Sample wind"), systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 2) {
                Text(tr("Open lake view"))
                Image(systemName: "chevron.right")
            }
            .font(.subheadline)
            .foregroundStyle(.tint)
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

/// The lake drawn by itself, coloured by the light of each part, with wind arrows.
struct LakeMiniMap: View {
    let view: LakeView
    let hour: LakeHour
    var clubID: String?
    var layer: LakeLayer = .light

    var body: some View {
        let image = LakeRaster.image(view, hour: hour, layer: layer)
        let coldShore = view.coldShore
        Canvas { ctx, size in
            let p = LakeProjection(grid: view.grid, size: size)
            let shore = p.outline(view.outline)
            let even = FillStyle(eoFill: true)
            ctx.fill(shore, with: .color(.blue.opacity(0.2)), style: even)
            if let image {
                var water = ctx
                water.clip(to: shore, style: even)
                water.opacity = 0.85
                water.draw(Image(decorative: image, scale: 1).interpolation(.high), in: p.imageRect)
                // The whole lake is red (dark, a warning): stripes over the greyed squares;
                // amber (sunrise or sunset, a warning): fainter stripes wider apart.
                if layer == .light, let light = hour.lakeWide.stripes {
                    let red = light == .red
                    var lines = Path()
                    for x in stride(from: -size.height, to: size.width, by: red ? 8 : 14) {
                        lines.move(to: CGPoint(x: x, y: size.height))
                        lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }
                    water.opacity = 1
                    water.stroke(lines, with: .color(red ? .red.opacity(0.55) : .orange.opacity(0.75)), lineWidth: red ? 1.5 : 1.2)
                }
            }
            // Cold water: the shore turns blue, the squares keep their colours.
            if let cold = coldShore {
                ctx.stroke(shore, with: .color(cold.color), lineWidth: cold.tileWidth)
            } else {
                ctx.stroke(shore, with: .color(.blue.opacity(0.4)), lineWidth: 0.7)
            }
            for (point, wind) in zip(view.points, hour.wind) {
                guard let from = wind.fromDeg else { continue }
                let at = p.point(lon: point.lon, lat: point.lat)
                ctx.stroke(LakeArrow.path(at: at, towardDeg: from + 180, length: 12), with: .color(.primary.opacity(0.55)), lineWidth: 1.2)
            }
            for club in view.clubs {
                let at = p.point(lon: club.launchPoint.lon, lat: club.launchPoint.lat)
                let own = club.id == clubID
                let r: CGFloat = own ? 4.5 : 3
                let dot = Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(dot, with: .color(own ? .blue : .white))
                ctx.stroke(dot, with: .color(own ? .white : .blue), lineWidth: 1.5)
            }
        }
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(tr("Map of %@ coloured by the rowing light", view.name))
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
