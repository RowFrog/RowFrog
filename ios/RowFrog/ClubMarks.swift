import MapKit
import SwiftUI
import UIKit

/// One scheme for a club's marks on every map and picture. Colour says which
/// club (blue: the page's club; grey: other clubs), the symbol what the point
/// is (house or rower: the club; oars: its launch point).
///
/// Zoomed out a club has one pin, at its forecast point: the launch point once
/// set (confirmed by the club or checked by hand), else the club's own point.
/// Zoomed in until the club's place (`clubhouse`) is `splitAt` points away on
/// screen, the club's pin moves there; under `joinAt` it goes back. A club
/// with a launch point set then gets oars on the launch point; one without
/// keeps its single pin, now on its place.
///
/// The club's place follows the map apps where it can (owner's option A,
/// 6 Nov 2026): the club's own place in Apple Maps, so our pin covers Apple's
/// label and the club shows once, as in the Maps app. Only when a clubhouse
/// checked by hand lies more than `onPlaceWithin` from that place (the map
/// app's place is then often an entrance by the road) does the pin keep to
/// the checked clubhouse.
enum ClubMarks {
    static let launchSymbol = "oar.2.crossed"
    /// Closer than this, the club's place counts as its forecast point itself.
    static let sameSpot: CLLocationDistance = 30
    /// Up to this far from the clubhouse checked by hand, the pin stands on
    /// the club's place in the map app instead.
    static let onPlaceWithin: CLLocationDistance = 80
    /// Screen points between the two before the pin moves, and before it moves back.
    static let splitAt: CGFloat = 48
    static let joinAt: CGFloat = 40

    /// Whether two pins this far apart on screen show apart, with some room
    /// between splitting and joining so they don't flicker.
    static func shouldSplit(apart: CGFloat, now: Bool) -> Bool {
        apart >= (now ? joinAt : splitAt)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Where the club's pin stands once zoomed in, when that is apart from its
    /// forecast point: the club's place in the map app (`place`), unless a
    /// clubhouse checked by hand lies more than `onPlaceWithin` from it; with
    /// no map-app place, the checked clubhouse. Nil keeps the pin where it is.
    static func clubhouse(of club: Club, place: CLLocationCoordinate2D? = nil) -> CLLocationCoordinate2D? {
        let checked = club.clubhouse.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let spot: CLLocationCoordinate2D?
        if let checked, let place {
            spot = distance(checked, place) <= onPlaceWithin ? place : checked
        } else {
            spot = place ?? checked
        }
        guard let spot else { return nil }
        let forecastPoint = CLLocationCoordinate2D(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
        return distance(spot, forecastPoint) >= sameSpot ? spot : nil
    }

    /// Whether the club's launch point gets oars once its pin has moved: only
    /// a launch point that is set; otherwise the forecast point is the club itself.
    static func showsOars(for club: Club) -> Bool { club.hasLaunchPoint }

    static func showsOars(forID id: String?) -> Bool { club(forID: id).map(showsOars) ?? false }

    /// The loaded clubs by id, for maps that only know a club's id (lake map,
    /// satellite picture, radar and weather maps). Set when the club list loads.
    private static var clubs: [String: Club] = [:]

    static func register(_ list: [Club]) {
        clubs = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func club(forID id: String?) -> Club? {
        id.flatMap { clubs[$0] }
    }

    static func clubhouse(forID id: String?) -> CLLocationCoordinate2D? {
        guard let club = club(forID: id) else { return nil }
        return clubhouse(of: club, place: ClubPlaces.savedLocation(forID: club.id))
    }

    /// Looks up the Apple Maps places of these clubs (a lake's few clubs), so
    /// their pins can move onto them when zoomed in.
    @MainActor static func lookUpPlaces(forIDs ids: [String]) async {
        for id in ids {
            guard let club = club(forID: id), !club.isOwnPlace, !ClubPlaces.lookedUpRecently(forID: id) else { continue }
            _ = await ClubPlaces.shared.place(for: club)
        }
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
        /// False for a club with no launch point set: its pin only moves.
        let withOars: Bool
        var split = false
    }
    private var pairs: [Pair] = []
    /// Pins whose clubhouse wasn't known yet; tried again on every update.
    private var waiting: [(pin: MKPointAnnotation, clubID: String?, isOwn: Bool)] = []

    /// Follows a club's pin, standing on its launch point; it splits once its clubhouse is known.
    func track(_ pin: MKPointAnnotation, clubID: String?, isOwn: Bool) {
        waiting.append((pin, clubID, isOwn))
    }

    @MainActor func update(_ map: MKMapView) {
        guard map.bounds.width > 0 else { return }
        waiting.removeAll { entry in
            guard let clubhouse = ClubMarks.clubhouse(forID: entry.clubID) else { return false }
            let oars = LaunchOarsPin()
            oars.coordinate = entry.pin.coordinate
            oars.title = entry.isOwn ? tr("Launch point") : nil
            oars.isOwn = entry.isOwn
            pairs.append(Pair(pin: entry.pin, launch: entry.pin.coordinate, clubhouse: clubhouse, oars: oars,
                              withOars: ClubMarks.showsOars(forID: entry.clubID)))
            return true
        }
        for index in pairs.indices {
            let pair = pairs[index]
            let a = map.convert(pair.launch, toPointTo: map), b = map.convert(pair.clubhouse, toPointTo: map)
            let apart = hypot(a.x - b.x, a.y - b.y)
            let now = ClubMarks.shouldSplit(apart: apart, now: pair.split)
            guard now != pair.split else { continue }
            pairs[index].split = now
            UIView.animate(withDuration: 0.25) { pair.pin.coordinate = now ? pair.clubhouse : pair.launch }
            guard pair.withOars else { continue }
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
