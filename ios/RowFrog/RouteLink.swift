import Foundation

/// Saved routes as a link that the website opens and saves in that browser, so routes planned in the app can
/// be used in a browser too, or sent to a clubmate (owner, 14 Nov 2026). The website's routelink.js reads and
/// writes the same links:
///   https://rowfrog.com/app/#/routes/add?r=<base64url of {"v":1,"routes":[{"name","lake","back","p":[[lat,lon],…]}]}>
/// Points are rounded to 5 decimals (about 1 m); an imported row's track and date stay on the device.
enum RouteLink {
    static let base = "https://rowfrog.com/app/#/routes/add?r="

    private struct Payload: Encodable {
        let v = 1
        let routes: [Item]
    }

    private struct Item: Encodable {
        let name: String
        let lake: String
        let back: Bool
        let p: [[Double]]
    }

    private static func round(_ x: Double) -> Double { (x * 1e5).rounded() / 1e5 }

    /// The link for these routes; nil when there are none.
    static func url(for routes: [Route]) -> URL? {
        guard !routes.isEmpty else { return nil }
        let payload = Payload(routes: routes.map {
            Item(name: $0.name, lake: $0.lakeId, back: $0.outAndBack, p: $0.points.map { [round($0.lat), round($0.lon)] })
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { return nil }
        let value = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: base + value)
    }
}
