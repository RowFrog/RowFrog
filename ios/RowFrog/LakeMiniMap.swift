import MapKit
import SwiftUI

/// The small lake map of the lake view tile and the waves page: the lake on a
/// still picture of Apple's muted map, coloured by one layer at one hour, with
/// the wind's arrows. On the water they are the lake's own; on land, fainter,
/// the wind map's, as in the lake view a tap opens (owner's pick B, 17 Nov 2026,
/// decision 0047). The map is a picture taken once per lake, size and
/// appearance and kept while the app runs, so scrolling a club page stays as
/// light as with the lake alone. Until it is there, or without a connection,
/// the lake stands on a plain box as before.
struct LakeMiniMap: View {
    let view: LakeView
    let hour: LakeHour
    var clubID: String?
    var layer: LakeLayer = .light
    /// Rounded on its own (the tile); 0 where the card around it clips (the waves page).
    var cornerRadius: CGFloat = 12
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var base: UIImage?

    /// The map pictures, by lake, size and appearance.
    private static let pictures = NSCache<NSString, UIImage>()
    /// Screen points between the arrows: closer than on the big map, as the map is small.
    static let arrowSpacing: CGFloat = 40
    /// The foot of the map kept free for Apple's logo in the map picture, so neither
    /// the lake nor arrows lie over it (owner, 20 Nov 2026, as on the website).
    static let logoStrip: CGFloat = 26
    /// The arrows' length against the big map's.
    static let arrowScale: CGFloat = 0.6

    var body: some View {
        GeometryReader { geometry in
            let frame = LakeMiniFrame(grid: view.grid, size: geometry.size, bottom: Self.logoStrip)
            let key = "\(view.lakeId)|\(Int(geometry.size.width))x\(Int(geometry.size.height))|\(colorScheme == .dark ? "dark" : "light")" as NSString
            let land = ModelMapStore.shared.landWind(at: view.grid.centre, time: hour.time)
            ZStack(alignment: .topLeading) {
                if let base {
                    Image(uiImage: base).resizable()
                } else {
                    Color.secondary.opacity(0.1)
                }
                lake(frame, land: land)
                if let club = view.clubs.first(where: { $0.id == clubID }) {
                    ClubMarkIcon(color: .blue, symbol: LocationStore.markSymbol(for: club.id))
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(frame.point(lon: club.launchPoint.lon, lat: club.launchPoint.lat))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: key) { await loadBase(frame, key: key) }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task { await ModelMapStore.shared.loadLandWind(at: view.grid.centre) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Map of %@ coloured by the rowing light", view.name))
    }

    /// The lake's colours, shore and arrows, the wind map's arrows on land and the other clubs.
    private func lake(_ frame: LakeMiniFrame, land: LandWind?) -> some View {
        let image = LakeRaster.image(view, hour: hour, layer: layer)
        let coldShore = view.coldShore
        let dark = colorScheme == .dark
        return Canvas { ctx, size in
            let rings = view.outline.filter { $0.count > 2 }.map { ring in ring.map { frame.point(lon: $0[0], lat: $0[1]) } }
            var shore = Path()
            for ring in rings {
                shore.addLines(ring)
                shore.closeSubpath()
            }
            let even = FillStyle(eoFill: true)
            ctx.fill(shore, with: .color(.blue.opacity(0.2)), style: even)
            if let image {
                var water = ctx
                water.clip(to: shore, style: even)
                water.opacity = 0.85
                water.draw(Image(decorative: image, scale: 1).interpolation(.high), in: frame.rect(of: view.grid))
                // The whole lake is red (dark, a warning): stripes over the greyed squares;
                // amber (sunrise or sunset, a warning): fainter stripes wider apart.
                if layer == .light, let light = hour.lakeWide.stripes {
                    let red = light == .red, fall = view.stripesFall
                    var lines = Path()
                    for x in stride(from: -size.height, to: size.width, by: red ? 8 : 14) {
                        lines.move(to: CGPoint(x: x, y: fall ? 0 : size.height))
                        lines.addLine(to: CGPoint(x: x + size.height, y: fall ? size.height : 0))
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
            // The wind as in the lake view, only smaller (owner, 20 Nov 2026): every arrow, on the
            // water and on land, on one grid; the lake's wind on the water, the wind map's on land,
            // faded in over the first kilometre; dark with a light edge, light on the dark map's land.
            let samples = zip(view.points, hour.wind).compactMap { point, wind -> WindArrows.Sample? in
                guard let from = wind.fromDeg else { return nil }
                return WindArrows.Sample(point: frame.point(lon: point.lon, lat: point.lat), towardDeg: from + 180, speedMs: wind.speedMs ?? 0)
            }
            if !samples.isEmpty {
                let water = shore.cgPath
                let blend = CGFloat(WindArrows.blendM * MKMapPointsPerMeterAtLatitude(view.grid.centre.lat)) * frame.pointsPerMapPoint
                var onLand: ((CGPoint) -> (towardDeg: Double, speedMs: Double)?)?
                if let land { onLand = { land.at(frame.mapPoint($0)) } }
                let grid = WindArrows.arrows(in: CGRect(x: 0, y: 0, width: size.width, height: max(size.height - Self.logoStrip, 0)), spacing: Self.arrowSpacing, water: water,
                                             from: samples, land: onLand, shore: WindArrows.Shore(rings: rings), blend: blend)
                for light in [false, true] {
                    var arrows = Path()
                    for arrow in grid where (dark && (arrow.ashore || image == nil)) == light {
                        arrows.addPath(LakeArrow.path(at: arrow.at, towardDeg: arrow.towardDeg, length: WindArrows.length(arrow.speedMs) * Self.arrowScale))
                    }
                    let (edge, core) = light ? (Color.black.opacity(0.6), Color.white) : (Color.white.opacity(0.7), Color(white: 0.1).opacity(0.75))
                    ctx.stroke(arrows, with: .color(edge), style: StrokeStyle(lineWidth: light ? 2.2 : 2.5, lineCap: .round, lineJoin: .round))
                    ctx.stroke(arrows, with: .color(core), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
            // The other clubs on the lake; the page's own has its mark on top.
            for club in view.clubs where club.id != clubID {
                let at = frame.point(lon: club.launchPoint.lon, lat: club.launchPoint.lat)
                let dot = Path(ellipseIn: CGRect(x: at.x - 3, y: at.y - 3, width: 6, height: 6))
                ctx.fill(dot, with: .color(.white))
                ctx.stroke(dot, with: .color(.blue), lineWidth: 1.5)
            }
        }
    }

    /// Apple's muted map for the frame, without places of interest, as under the lake view.
    @MainActor private func loadBase(_ frame: LakeMiniFrame, key: NSString) async {
        if let kept = Self.pictures.object(forKey: key) {
            base = kept
            return
        }
        base = nil
        guard frame.size.width > 1, frame.size.height > 1 else { return }
        let options = MKMapSnapshotter.Options()
        options.mapRect = frame.shown
        options.size = frame.size
        options.scale = displayScale
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let map = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = map
        if let snapshot = try? await MKMapSnapshotter(options: options).start() {
            Self.pictures.setObject(snapshot.image, forKey: key)
            base = snapshot.image
        }
    }
}

/// The part of the map a small lake map shows: the lake's grid with `padding`
/// around it, widened to the view's shape, in Apple's map points, so the lake's
/// colours and arrows land where the map picture has the shore.
struct LakeMiniFrame {
    /// The map points shown.
    let shown: MKMapRect
    let size: CGSize

    /// `bottom`: the strip kept free at the foot, where Apple's map picture has its
    /// logo; the lake is centred in the room above it.
    init(grid: LakeGrid, size: CGSize, padding: CGFloat = 8, bottom: CGFloat = 8) {
        self.size = size
        let lake = Self.mapRect(of: grid)
        let w = Double(max(size.width - 2 * padding, 1)), h = Double(max(size.height - padding - bottom, 1))
        let scale = min(w / max(lake.width, 1), h / max(lake.height, 1))
        let width = Double(max(size.width, 1)) / scale, height = Double(max(size.height, 1)) / scale
        // The lake's middle at the middle of the room between `padding` and `bottom`.
        let middle = Double(padding) + h / 2
        shown = MKMapRect(x: lake.midX - width / 2, y: lake.midY - middle / scale, width: width, height: height)
    }

    /// The grid's corners in map points.
    static func mapRect(of grid: LakeGrid) -> MKMapRect {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: grid.north, longitude: grid.westEdge))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: grid.southEdge, longitude: grid.east))
        return MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
    }

    /// Screen points per map point.
    var pointsPerMapPoint: CGFloat { shown.width > 0 ? size.width / CGFloat(shown.width) : 0 }

    func point(_ p: MKMapPoint) -> CGPoint {
        CGPoint(x: CGFloat(p.x - shown.minX) * pointsPerMapPoint, y: CGFloat(p.y - shown.minY) * pointsPerMapPoint)
    }

    func point(lon: Double, lat: Double) -> CGPoint {
        point(MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon)))
    }

    func mapPoint(_ p: CGPoint) -> MKMapPoint {
        let k = pointsPerMapPoint > 0 ? 1 / Double(pointsPerMapPoint) : 0
        return MKMapPoint(x: shown.minX + Double(p.x) * k, y: shown.minY + Double(p.y) * k)
    }

    /// Where the lake's cell picture goes: over the whole grid.
    func rect(of grid: LakeGrid) -> CGRect {
        let r = Self.mapRect(of: grid)
        let a = point(MKMapPoint(x: r.minX, y: r.minY)), b = point(MKMapPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
}
