import MapKit
import SwiftUI
import UIKit

// Pins, lines and the loupe the lake map draws for routes and river sections.
// Split off LakeMapScreen.swift on 6 Nov 2026 (large-file rule), unchanged.

/// One end of a river section's stretch.
final class SectionEndPin: MKPointAnnotation {
    var isBarrier = false
}

final class RoutePin: MKPointAnnotation {
    var isStart = false
    var isSelected = false
    /// Its index in the route's waypoints.
    var index = 0
}

/// The route around a turning point while it is dragged.
final class DragLine: MKPolyline {}

/// A round magnifier above the finger that shows the map under a dragged
/// point, with cross hairs where the point will land.
final class Loupe: UIView {
    static let size: CGFloat = 116
    private let map = MKMapView()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isUserInteractionEnabled = false
        layer.cornerRadius = Self.size / 2
        layer.borderWidth = 3
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        map.frame = bounds
        map.layer.cornerRadius = Self.size / 2
        map.clipsToBounds = true
        map.isUserInteractionEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        addSubview(map)
        let cross = CAShapeLayer()
        let path = UIBezierPath()
        let c = Self.size / 2
        for (from, to) in [(CGPoint(x: c - 14, y: c), CGPoint(x: c - 5, y: c)), (CGPoint(x: c + 5, y: c), CGPoint(x: c + 14, y: c)),
                           (CGPoint(x: c, y: c - 14), CGPoint(x: c, y: c - 5)), (CGPoint(x: c, y: c + 5), CGPoint(x: c, y: c + 14))] {
            path.move(to: from)
            path.addLine(to: to)
        }
        path.append(UIBezierPath(ovalIn: CGRect(x: c - 3, y: c - 3, width: 6, height: 6)))
        cross.path = path.cgPath
        cross.strokeColor = UIColor.systemOrange.cgColor
        cross.fillColor = UIColor.systemOrange.cgColor
        cross.lineWidth = 2.5
        layer.addSublayer(cross)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `coordinate` magnified, above the finger, or below it near the top.
    func show(at coordinate: CLLocationCoordinate2D, finger: CGPoint, on host: MKMapView) {
        if superview !== host {
            map.preferredConfiguration = host.preferredConfiguration
            host.addSubview(self)
        }
        let span = MKCoordinateSpan(latitudeDelta: max(host.region.span.latitudeDelta / 8, 0.0008),
                                    longitudeDelta: max(host.region.span.longitudeDelta / 8, 0.0008))
        map.setRegion(MKCoordinateRegion(center: coordinate, span: span), animated: false)
        let half = Self.size / 2, gap: CGFloat = 70
        var y = finger.y - gap - half
        if y - half < host.safeAreaInsets.top + 8 { y = finger.y + gap + half }
        let x = min(max(finger.x, half + 8), host.bounds.width - half - 8)
        center = CGPoint(x: x, y: y)
    }

    func hide() { removeFromSuperview() }
}

/// An imported row's track as it was rowed.
final class RowedTrackLine: MKPolyline {}

/// One stretch of a planned route in the colour of its conditions; the casing
/// is a wider white line under it.
final class RouteLine: MKPolyline {
    var light: Light = .green
    var casing = false

    /// Room for the line drawn beside its points (about 2 km).
    override var boundingMapRect: MKMapRect { super.boundingMapRect.insetBy(dx: -20_000, dy: -20_000) }
}

/// Draws a route stretch a few points to the right of the way the boat goes,
/// so where a route is rowed out and back both trips show side by side, each
/// in the colour of the time the boat is there.
final class RouteLineRenderer: MKOverlayRenderer {
    /// Screen points between the line's middle and the route.
    static let offset: CGFloat = 3.5

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let line = overlay as? RouteLine, line.pointCount > 1 else { return }
        let points = UnsafeBufferPointer(start: line.points(), count: line.pointCount).map { point(for: $0) }
        let path = CGMutablePath()
        path.addLines(between: Self.shifted(points, by: Self.offset / zoomScale))
        context.addPath(path)
        context.setStrokeColor((line.casing ? UIColor(white: 1, alpha: 0.9) : UIColor(line.light.color)).cgColor)
        context.setLineWidth((line.casing ? 9 : 5) / zoomScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    /// The points moved `distance` to the right of the direction of travel, with y running down.
    static func shifted(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let normals = zip(points, points.dropFirst()).map { a, b -> CGVector in
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(hypot(dx, dy), .ulpOfOne)
            return CGVector(dx: -dy / length, dy: dx / length)
        }
        return points.indices.map { i in
            let before = i > 0 ? normals[i - 1] : normals[0]
            let after = i < normals.count ? normals[i] : normals[normals.count - 1]
            var n = CGVector(dx: before.dx + after.dx, dy: before.dy + after.dy)
            let length = hypot(n.dx, n.dy)
            n = length > 0.01 ? CGVector(dx: n.dx / length, dy: n.dy / length) : after
            return CGPoint(x: points[i].x + n.dx * distance, y: points[i].y + n.dy * distance)
        }
    }
}
