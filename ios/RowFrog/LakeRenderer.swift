import MapKit
import SwiftUI

/// The area of the lake's grid, as one map overlay.
final class LakeOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    /// The lake's grid; `boundingMapRect` is the whole world, as the wind arrows cover the map.
    let lakeRect: MKMapRect
    /// What the map shows when it opens: the whole lake, or on a river the 10 km around the club.
    let openRect: MKMapRect
    let boundingMapRect = MKMapRect.world
    /// Shore and islands in map points, for clipping.
    let rings: [[MKMapPoint]]
    /// The water in map points, to tell arrows on it from those on land.
    let water: CGPath
    /// The shore in map points, and how far from it the land's wind fades in.
    let shore: WindArrows.Shore
    let blend: CGFloat
    /// The whole-lake stripes cross the lake's long side (see LakeView.stripesFall).
    let stripesFall: Bool

    init(view: LakeView, focus: CLLocationCoordinate2D? = nil) {
        let g = view.grid
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: g.north, longitude: g.westEdge))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: g.southEdge, longitude: g.east))
        let whole = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        lakeRect = whole
        if let focus {
            let side = 10_000 * MKMapPointsPerMeterAtLatitude(focus.latitude)
            let centre = MKMapPoint(focus)
            let around = MKMapRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
            let both = around.intersection(whole)
            openRect = both.isNull || both.isEmpty ? whole : both
        } else {
            openRect = whole
        }
        coordinate = CLLocationCoordinate2D(latitude: (g.north + g.southEdge) / 2, longitude: (g.westEdge + g.east) / 2)
        rings = view.outline.map { ring in ring.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])) } }
        let water = CGMutablePath()
        for ring in rings where ring.count > 2 {
            water.addLines(between: ring.map { CGPoint(x: $0.x, y: $0.y) })
            water.closeSubpath()
        }
        self.water = water
        shore = WindArrows.Shore(rings: rings.map { $0.map { CGPoint(x: $0.x, y: $0.y) } })
        blend = CGFloat(WindArrows.blendM * MKMapPointsPerMeterAtLatitude(coordinate.latitude))
        stripesFall = view.stripesFall
    }
}

/// Draws the cell picture smoothly scaled over the grid, clipped to the shore,
/// and the wind arrows over the whole map.
final class LakeRenderer: MKOverlayRenderer {
    /// Screen points between arrows: more arrows as the map zooms in, fewer out.
    static let arrowSpacing = WindArrows.spacing

    /// Arrow length on screen: longer in stronger wind.
    static func arrowLength(_ speedMs: Double) -> CGFloat { WindArrows.length(speedMs) }

    private let lock = NSLock()
    private var image: CGImage?
    private var arrows: [WindArrows.Sample] = []
    private var land: LandWind?
    /// Stripes over the water while the whole lake is red or amber (see LakeWide.stripes).
    private var stripes: Light?
    /// A blue shore while the water is cold.
    private var coldShore: ColdShore?
    /// Whether the map under the arrows is dark: Apple's satellite pictures or the map in dark mode.
    private var darkBase = false

    func setDarkBase(_ dark: Bool) {
        lock.lock()
        let changed = darkBase != dark
        darkBase = dark
        lock.unlock()
        if changed { setNeedsDisplay() }
    }

    func setColdShore(_ shore: ColdShore?) {
        lock.lock()
        let changed = coldShore != shore
        coldShore = shore
        lock.unlock()
        if changed { setNeedsDisplay() }
    }

    func update(image: CGImage?, arrows: [WindArrows.Sample], land: LandWind?, stripes: Light?) {
        lock.lock()
        self.image = image
        self.arrows = arrows
        self.land = land
        self.stripes = stripes
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let lake = overlay as? LakeOverlay else { return }
        lock.lock()
        let image = self.image, arrows = self.arrows, land = self.land, stripes = self.stripes, coldShore = self.coldShore
        let darkBase = self.darkBase
        lock.unlock()

        let shore = CGMutablePath()
        for ring in lake.rings where ring.count > 2 {
            shore.addLines(between: ring.map { point(for: $0) })
            shore.closeSubpath()
        }
        if let image {
            let rect = self.rect(for: lake.lakeRect)
            context.saveGState()
            context.addPath(shore)
            context.clip(using: .evenOdd)
            context.interpolationQuality = .high
            context.setAlpha(0.72)
            // CGContext draws images bottom up; the overlay's points run top down.
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        }
        if let stripes {
            // Amber stripes are wider apart and fainter than red ones.
            let red = stripes == .red
            context.saveGState()
            context.addPath(shore)
            context.clip(using: .evenOdd)
            // Lines x + y = k * gap (or x - y where they fall), so the stripes run on across the map's tiles.
            let tile = self.rect(for: mapRect), gap = (red ? 14 : 24) / zoomScale
            let lines = CGMutablePath()
            if lake.stripesFall {
                var k = ((tile.minX - tile.maxY) / gap).rounded(.down)
                while k * gap <= tile.maxX - tile.minY {
                    lines.move(to: CGPoint(x: k * gap + tile.minY, y: tile.minY))
                    lines.addLine(to: CGPoint(x: k * gap + tile.maxY, y: tile.maxY))
                    k += 1
                }
            } else {
                var k = ((tile.minX + tile.minY) / gap).rounded(.down)
                while k * gap <= tile.maxX + tile.maxY {
                    lines.move(to: CGPoint(x: k * gap - tile.minY, y: tile.minY))
                    lines.addLine(to: CGPoint(x: k * gap - tile.maxY, y: tile.maxY))
                    k += 1
                }
            }
            context.addPath(lines)
            let color = red ? UIColor.systemRed.withAlphaComponent(0.55) : UIColor.systemOrange.withAlphaComponent(0.75)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth((red ? 3 : 2.5) / zoomScale)
            context.strokePath()
            context.restoreGState()
        }
        context.addPath(shore)
        // Cold water: the shore turns blue and thicker, the squares keep their colours.
        context.setStrokeColor(coldShore.map { UIColor($0.color) }?.cgColor ?? UIColor.systemBlue.withAlphaComponent(0.45).cgColor)
        context.setLineWidth((coldShore?.mapWidth ?? 1) / zoomScale)
        context.strokePath()

        // Arrows on an even grid over the whole map, as on the weather map, fixed
        // to the map so the tiles agree; the grid gets finer as the map zooms in.
        // On land the wind is the wind map's own forecast, faded in from the
        // lake's over the first kilometre.
        // As on the Sentinel pictures, each arrow stands out from what lies under
        // it: dark with a light edge over the lake's colours and a light map, white
        // with a dark edge over Apple's satellite pictures and the map in dark mode.
        let margin = Double(WindArrows.length(15) / zoomScale)
        let area = mapRect.insetBy(dx: -margin, dy: -margin)
        var onLand: ((CGPoint) -> (towardDeg: Double, speedMs: Double)?)?
        if let land {
            onLand = { p in land.at(MKMapPoint(x: Double(p.x), y: Double(p.y))) }
        }
        let grid = WindArrows.arrows(in: CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height),
                                     spacing: WindArrows.spacing / zoomScale, water: lake.water, from: arrows,
                                     land: onLand, shore: lake.shore, blend: lake.blend)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // Light arrows where a dark map shows through: on land, and on the water
        // when no colours are drawn over it.
        func isLight(_ arrow: WindArrows.Arrow) -> Bool { darkBase && (arrow.ashore || image == nil) }
        for light in [false, true] {
            let paths = grid.filter { isLight($0) == light }.map {
                LakeArrow.path(at: point(for: MKMapPoint(x: $0.at.x, y: $0.at.y)), towardDeg: $0.towardDeg,
                               length: WindArrows.length($0.speedMs) / zoomScale).cgPath
            }
            guard !paths.isEmpty else { continue }
            let (edge, core) = light
                ? (UIColor(white: 0, alpha: 0.6), UIColor.white)
                : (UIColor(white: 1, alpha: 0.7), UIColor(white: 0.1, alpha: 0.75))
            for (color, width) in [(edge, CGFloat(light ? 3.5 : 4)), (core, CGFloat(2))] {
                paths.forEach { context.addPath($0) }
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(width / zoomScale)
                context.strokePath()
            }
        }
    }
}
