import MapKit
import SwiftUI
import UIKit

/// One scheme for a club's marks on every map and picture. Colour says which
/// club (blue: the page's club; grey: other clubs), the symbol what the point
/// is (house or rower: the club; oars: its launch point).
///
/// Zoomed out a club has one pin, at its launch point, which is where the
/// forecast is for. Once the club has a confirmed launch point and its
/// clubhouse (its Apple Maps place) lies apart from it, zooming in until the
/// two are `splitAt` points apart on screen moves the club's pin to the
/// clubhouse and puts oars on the launch point; under `joinAt` they join again.
/// A club with no launch point set yet keeps its one pin.
enum ClubMarks {
    static let launchSymbol = "oar.2.crossed"
    /// Closer than this, the clubhouse counts as the launch point itself.
    static let sameSpot: CLLocationDistance = 30
    /// Screen points between the pins before they split, and before they join again.
    static let splitAt: CGFloat = 48
    static let joinAt: CGFloat = 40

    /// Whether two pins this far apart on screen show apart, with some room
    /// between splitting and joining so they don't flicker.
    static func shouldSplit(apart: CGFloat, now: Bool) -> Bool {
        apart >= (now ? joinAt : splitAt)
    }

    /// The club's Apple Maps place as its clubhouse: only for a confirmed launch
    /// point, and only when it isn't at the launch point.
    static func clubhouse(of place: MKMapItem?, launch: CLLocationCoordinate2D, verified: Bool) -> CLLocationCoordinate2D? {
        guard verified, let location = place?.placemark.location else { return nil }
        let distance = location.distance(from: CLLocation(latitude: launch.latitude, longitude: launch.longitude))
        return distance >= sameSpot ? location.coordinate : nil
    }
}

/// A club's launch point once its own pin has moved to the clubhouse.
final class LaunchOarsPin: MKPointAnnotation {
    var isOwn = true
}

/// Splits and joins the clubs' pins on a UIKit map as it zooms (lake map,
/// rain radar, weather maps). The map's delegate calls `update` as the visible
/// region changes and asks `view(for:)` for the oars.
final class ClubPinSplitter {
    private struct Pair {
        let pin: MKPointAnnotation
        let launch: CLLocationCoordinate2D
        let clubhouse: CLLocationCoordinate2D
        let oars: LaunchOarsPin
        var split = false
    }
    private var pairs: [Pair] = []

    /// Follows a club's pin, standing on its launch point, when its clubhouse is known.
    func track(_ pin: MKPointAnnotation, clubID: String?, isOwn: Bool) {
        guard let clubhouse = ClubPlaces.clubhouse(forID: clubID) else { return }
        let oars = LaunchOarsPin()
        oars.coordinate = pin.coordinate
        oars.title = isOwn ? tr("Launch point") : nil
        oars.isOwn = isOwn
        pairs.append(Pair(pin: pin, launch: pin.coordinate, clubhouse: clubhouse, oars: oars))
    }

    @MainActor func update(_ map: MKMapView) {
        guard map.bounds.width > 0 else { return }
        for index in pairs.indices {
            let pair = pairs[index]
            let a = map.convert(pair.launch, toPointTo: map), b = map.convert(pair.clubhouse, toPointTo: map)
            let apart = hypot(a.x - b.x, a.y - b.y)
            let now = ClubMarks.shouldSplit(apart: apart, now: pair.split)
            guard now != pair.split else { continue }
            pairs[index].split = now
            UIView.animate(withDuration: 0.25) { pair.pin.coordinate = now ? pair.clubhouse : pair.launch }
            if now { map.addAnnotation(pair.oars) } else { map.removeAnnotation(pair.oars) }
        }
    }

    /// The oars' pin, coloured like its club's.
    @MainActor static func view(for oars: LaunchOarsPin) -> MKAnnotationView {
        let view = MKMarkerAnnotationView(annotation: oars, reuseIdentifier: nil)
        view.glyphImage = UIImage(systemName: ClubMarks.launchSymbol)
        view.markerTintColor = oars.isOwn ? .systemBlue : .systemGray
        view.displayPriority = .required
        // Under the club's pin where the two still touch.
        view.zPriority = .min
        return view
    }
}

/// A club's pin on the lake map: the page's club or another club on the lake.
final class ClubPin: MKPointAnnotation {
    var isOwn = false
    var clubID: String?
}

/// A club mark as the maps draw it, for the legends: a white rower in a coloured circle.
struct ClubMarkIcon: View {
    let color: Color
    var symbol = "figure.rower"

    /// The legend line for the page's club, as its mark is drawn on this map.
    static func pageClubText(_ clubID: String?) -> String {
        LocationStore.markSymbol(for: clubID) == "house.fill" ? tr("Your home base, the club of this page") : tr("The club of this page")
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
    }
}
