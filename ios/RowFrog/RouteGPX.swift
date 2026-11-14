import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A saved route as a GPX file, for other apps and devices (CrewNerd, Garmin, Strava) and as a backup
/// (owner, 14 Nov 2026). One track with the turning points, and the way back when the route is rowed out
/// and back, so the file shows the whole outing. The website's routegpx.js writes the same file.
enum RouteGPX {
    static func text(_ route: Route) -> String {
        var points = route.points
        if route.outAndBack { points += route.points.reversed().dropFirst() }
        let rows = points.map { String(format: "      <trkpt lat=\"%.5f\" lon=\"%.5f\"/>", locale: Locale(identifier: "en_US_POSIX"), $0.lat, $0.lon) }
        let name = escape(route.name)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Row Frog" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(name)</name></metadata>
          <trk>
            <name>\(name)</name>
            <type>rowing</type>
            <trkseg>
        \(rows.joined(separator: "\n"))
            </trkseg>
          </trk>
        </gpx>

        """
    }

    /// "Rund um die Roseninsel.gpx": the route's name without characters file systems refuse.
    static func fileName(_ route: Route) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let base = route.name.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "Route" : String(base.prefix(80))) + ".gpx"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// The GPX file for the share sheet ("Export GPX").
struct RouteGPXFile: Transferable {
    let route: Route

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: TrackFile.gpx) { Data(RouteGPX.text($0.route).utf8) }
            .suggestedFileName { RouteGPX.fileName($0.route) }
    }
}
