import XCTest
@testable import RowFrog

/// A launch point suggested from the Location sheet: what is sent, and the
/// lines the accept workflow (scripts/accept_launch_point.py) reads.
final class LaunchPointSuggestionTests: XCTestCase {
    private func club(verified: Bool = false, id: String = "ruderclub-musterstadt") -> Club {
        Club(id: id, name: "Ruderclub Musterstadt", shortName: "RCM", address: "", website: nil,
             launchPoint: Coordinate(lat: 47.9, lon: 11.3), launchPointVerified: verified)
    }

    func testOnlyTheClubAndThePointAreSent() throws {
        let suggestion = LaunchPointSuggestion(club: club(), point: Coordinate(lat: 47.912346, lon: 11.300012))
        let request = try suggestion.request(api: APIClient(baseURL: URL(string: "https://api.rowfrog.com/v1")!))
        XCTAssertEqual(request.url?.absoluteString, "https://api.rowfrog.com/v1/suggestions")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["name", "kind", "club", "lat", "lon"])
        XCTAssertEqual(body["kind"] as? String, "launchPoint")
        XCTAssertEqual(body["club"] as? String, "ruderclub-musterstadt")
        XCTAssertEqual(body["lat"] as? Double, 47.912346)
    }

    func testTheGitHubFallbackHasTheLinesTheWorkflowReads() throws {
        let suggestion = LaunchPointSuggestion(club: club(), point: Coordinate(lat: 47.912346, lon: 11.3))
        let items = try XCTUnwrap(URLComponents(url: XCTUnwrap(suggestion.issueURL), resolvingAgainstBaseURL: false)?.queryItems)
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("- Club id: `ruderclub-musterstadt`"))
        XCTAssertTrue(body.contains("- Launch point: 47.912346, 11.300000"))
        XCTAssertEqual(items.first { $0.name == "labels" }?.value, "launch point suggestion")
    }

    func testOfferedOnlyForClubsThatHaveNotConfirmedTheirLaunchPoint() {
        XCTAssertTrue(LaunchPointSuggestion.isOffered(for: club()))
        XCTAssertFalse(LaunchPointSuggestion.isOffered(for: club(verified: true)))
        XCTAssertFalse(LaunchPointSuggestion.isOffered(for: club(id: OwnPlace.idPrefix + "x")))
    }

    func testSentClubsAreRemembered() {
        let saved = UserDefaults.standard.object(forKey: LaunchPointSuggestion.sentKey)
        defer { UserDefaults.standard.set(saved, forKey: LaunchPointSuggestion.sentKey) }
        UserDefaults.standard.removeObject(forKey: LaunchPointSuggestion.sentKey)
        XCTAssertFalse(LaunchPointSuggestion.wasSent(forID: "a"))
        LaunchPointSuggestion.markSent(forID: "a")
        LaunchPointSuggestion.markSent(forID: "a")
        XCTAssertTrue(LaunchPointSuggestion.wasSent(forID: "a"))
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: LaunchPointSuggestion.sentKey), ["a"])
    }
}
