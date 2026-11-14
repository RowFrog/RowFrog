import XCTest
@testable import RowFrog

/// The app's route links read the same on the website (web/tests/routelink.test.mjs reads this payload shape).
final class RouteLinkTests: XCTestCase {
    private func payload(_ url: URL) throws -> [String: Any] {
        let text = url.absoluteString
        XCTAssertTrue(text.hasPrefix(RouteLink.base))
        var value = String(text.dropFirst(RouteLink.base.count))
        XCTAssertNil(value.range(of: "[^A-Za-z0-9_-]", options: .regularExpression), "URL-safe")
        value = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        let data = try XCTUnwrap(Data(base64Encoded: value))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testLinkCarriesNameWaterWayBackAndRoundedPointsButNoTrack() throws {
        let route = Route(name: "Rund um die Roseninsel – ÄÖÜ", lakeId: "starnberger-see",
                          points: [Coordinate(lat: 47.9312345, lon: 11.3123456), Coordinate(lat: 47.94, lon: 11.32)],
                          outAndBack: true, track: [Coordinate(lat: 1, lon: 2)])
        let json = try payload(XCTUnwrap(RouteLink.url(for: [route])))
        XCTAssertEqual(json["v"] as? Int, 1)
        let item = try XCTUnwrap((json["routes"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["name"] as? String, route.name)
        XCTAssertEqual(item["lake"] as? String, "starnberger-see")
        XCTAssertEqual(item["back"] as? Bool, true)
        XCTAssertEqual(item["p"] as? [[Double]], [[47.93123, 11.31235], [47.94, 11.32]])
        XCTAssertEqual(Set(item.keys), ["name", "lake", "back", "p"])
    }

    func testNoRoutesNoLink() {
        XCTAssertNil(RouteLink.url(for: []))
    }
}
