import MapKit
import SwiftUI
import UIKit

/// One scheme for a club's marks on every map and picture. Colour says which
/// club (blue: the page's club; grey: other clubs), the symbol what the point
/// is (house or rower: the club; oars: its launch point).
///
/// Zoomed out a club has one pin, at its launch point, which is where the
/// forecast is for. Once the club's launch point is set (confirmed by the club
/// or checked by hand) and its clubhouse lies apart from it, zooming in until the
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

    /// Where the club's pin stands once split: the clubhouse the owner checked
    /// by hand, else the club's place in Apple Maps (the one Open in Maps shows).
    /// Only for a club whose launch point is set, and only when it lies apart from it.
    static func clubhouse(of club: Club, place: CLLocationCoordinate2D? = nil) -> CLLocationCoordinate2D? {
        guard club.hasLaunchPoint else { return nil }
        let house = club.clubhouse.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } ?? place
        guard let house else { return nil }
        let launch = CLLocation(latitude: club.launchPoint.lat, longitude: club.launchPoint.lon)
        let distance = CLLocation(latitude: house.latitude, longitude: house.longitude).distance(from: launch)
        return distance >= sameSpot ? house : nil
    }

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

    /// Looks up the Apple Maps places of these clubs that have a launch point set
    /// but no clubhouse checked by hand (a lake's few clubs), so their pins can split.
    @MainActor static func lookUpPlaces(forIDs ids: [String]) async {
        for id in ids {
            guard let club = club(forID: id), club.hasLaunchPoint, club.clubhouse == nil, !club.isOwnPlace else { continue }
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
            pairs.append(Pair(pin: entry.pin, launch: entry.pin.coordinate, clubhouse: clubhouse, oars: oars))
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
